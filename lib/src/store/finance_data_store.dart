import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../budgets/budget_calculator.dart';
import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/fund.dart';
import '../domain/goal.dart';
import '../domain/goal_funding.dart';
import '../domain/reservation.dart';
import '../domain/scheduled_transaction.dart';
import '../domain/scheduled_occurrence_authority.dart';
import '../domain/sync_metadata.dart';
import '../domain/transaction.dart';
import '../domain/user_preferences.dart';
import '../goals/goal_calculator.dart';
import '../notifications/notification_scheduler.dart';
import '../persistence/finance_record_repository.dart';
import '../persistence/local_finance_data_set_repository.dart';
import '../persistence/scheduled_notification_state_repository.dart';

class AuthoritativeRestoreLocalInstallException implements Exception {
  const AuthoritativeRestoreLocalInstallException(this.cause);

  final Object cause;
}

class FinanceDataValidationException implements Exception {
  const FinanceDataValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A transient in-app notification emitted when an active Budget crosses from
/// comfortably funded to its configured low-remaining threshold.
class BudgetLowAlert {
  const BudgetLowAlert({
    required this.budgetId,
    required this.budgetName,
    required this.remainingMinor,
    required this.periodStart,
  });

  final String budgetId;
  final String budgetName;
  final int remainingMinor;
  final DateTime periodStart;
}

class FinanceDataStore extends ChangeNotifier {
  factory FinanceDataStore({
    required FinanceDataSet dataSet,
    LocalFinanceDataSetRepository? localRepository,
    FinanceRecordRepository? remoteRepository,
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler(),
    bool preferRemoteOnFirstSync = false,
    String? userId,
    String deviceId = 'local',
    ScheduledNotificationStateRepository? notificationStateRepository,
  }) {
    return FinanceDataStore._(
      dataSet,
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      notificationScheduler: notificationScheduler,
      preferRemoteOnFirstSync: preferRemoteOnFirstSync,
      userId: userId,
      deviceId: deviceId,
      notificationStateRepository:
          notificationStateRepository ??
          InMemoryScheduledNotificationStateRepository(),
    );
  }

  FinanceDataStore._(
    this._dataSet, {
    this.localRepository,
    this.remoteRepository,
    this.notificationScheduler = const NoopNotificationScheduler(),
    this.preferRemoteOnFirstSync = false,
    this.userId,
    this.deviceId = 'local',
    required this.notificationStateRepository,
  });

  factory FinanceDataStore.empty({
    LocalFinanceDataSetRepository? localRepository,
    FinanceRecordRepository? remoteRepository,
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler(),
    String? userId,
    String deviceId = 'local',
    ScheduledNotificationStateRepository? notificationStateRepository,
  }) {
    return FinanceDataStore(
      dataSet: const FinanceDataSet(
        accounts: [],
        categories: [],
        transactions: [],
        scheduledTransactions: [],
        budgets: [],
        preferences: UserPreferences(),
      ),
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      notificationScheduler: notificationScheduler,
      userId: userId,
      deviceId: deviceId,
      notificationStateRepository: notificationStateRepository,
    );
  }

  static Future<FinanceDataStore> load({
    LocalFinanceDataSetRepository localRepository =
        const LocalFinanceDataSetRepository(),
    FinanceRecordRepository? remoteRepository,
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler(),
    String? userId,
    String deviceId = 'local',
    ScheduledNotificationStateRepository? notificationStateRepository,
  }) async {
    final localData = await localRepository.load();
    final store = FinanceDataStore(
      dataSet:
          localData ??
          const FinanceDataSet(
            accounts: [],
            categories: [],
            transactions: [],
            scheduledTransactions: [],
            budgets: [],
            preferences: UserPreferences(),
          ),
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      notificationScheduler: notificationScheduler,
      userId: userId,
      deviceId: deviceId,
      notificationStateRepository: notificationStateRepository,
    );
    await store.migrateLegacyGoalsToAccounts();
    return store;
  }

  FinanceDataSet _dataSet;
  final LocalFinanceDataSetRepository? localRepository;
  FinanceRecordRepository? remoteRepository;
  final NotificationScheduler notificationScheduler;
  bool preferRemoteOnFirstSync;
  String? userId;
  bool _authoritativeRestoreInProgress = false;

  bool get hasRemoteSync => remoteRepository != null && userId != null;
  final String deviceId;
  final ScheduledNotificationStateRepository notificationStateRepository;
  final ValueNotifier<BudgetLowAlert?> budgetLowAlertNotifier =
      ValueNotifier<BudgetLowAlert?>(null);
  final List<BudgetLowAlert> _pendingBudgetLowAlerts = [];

  FinanceDataSet get dataSet => _dataSet;
  List<AccountRecord> get accounts => _dataSet.accounts;
  List<CategoryRecord> get categories => _dataSet.categories;
  List<TransactionRecord> get transactions => _dataSet.transactions;
  List<ScheduledTransactionRecord> get scheduledTransactions =>
      _dataSet.scheduledTransactions;
  List<BudgetRecord> get budgets => _dataSet.budgets;
  List<GoalRecord> get goals => _dataSet.goals;
  List<GoalContributionRecord> get goalContributions =>
      _dataSet.goalContributions;
  List<GoalFundingEventRecord> get goalFundingEvents =>
      _dataSet.goalFundingEvents;
  List<FundRecord> get funds => _dataSet.funds;
  List<ReservationOperationRecord> get reservationOperations =>
      _dataSet.reservationOperations;
  UserPreferences get preferences => _dataSet.preferences;

  List<AccountRecord> get activeAccountsInDisplayOrder {
    final groupOrder = accountGroupDisplayOrderIndexes;
    return accounts
        .where((account) => account.isVisible && !account.isInternalGoalAccount)
        .toList(growable: false)
      ..sort(
        (a, b) => compareAccountDisplayOrder(a, b, groupOrder: groupOrder),
      );
  }

  List<AccountGroup> get accountGroupsInDisplayOrder {
    final remaining = {
      for (final group in AccountGroup.values) group.name: group,
    };
    final ordered = <AccountGroup>[];
    for (final groupName in preferences.accountGroupOrderNames) {
      final group = remaining.remove(groupName);
      if (group != null) ordered.add(group);
    }
    ordered.addAll(
      remaining.values.toList()..sort((a, b) => a.index.compareTo(b.index)),
    );
    return ordered;
  }

  Map<AccountGroup, int> get accountGroupDisplayOrderIndexes {
    final groups = accountGroupsInDisplayOrder;
    return {
      for (var index = 0; index < groups.length; index += 1)
        groups[index]: index,
    };
  }

  String accountGroupLabel(AccountGroup group) {
    final override = preferences.accountGroupLabelOverrides[group.name]?.trim();
    if (override != null && override.isNotEmpty) return override;
    return group.defaultLabel;
  }

  int balanceForAccount(String accountId) {
    return _dataSet.balanceForAccount(accountId);
  }

  int clearedBalanceForAccount(String accountId, {DateTime? asOf}) =>
      _dataSet.clearedBalanceForAccount(accountId, asOf: asOf);

  int pendingEffectForAccount(String accountId, {DateTime? asOf}) =>
      _dataSet.pendingEffectForAccount(accountId, asOf: asOf);

  int reservedForAccount(String accountId, {DateTime? asOf}) =>
      _dataSet.reservedForAccount(accountId, asOf: asOf);

  int availableToSpendForAccount(String accountId, {DateTime? asOf}) =>
      _dataSet.availableToSpendForAccount(accountId, asOf: asOf);

  int creditUsedMinorForAccount(String accountId) {
    final account = accountById(accountId);
    if (account.type != AccountType.creditCard) return 0;
    return balanceForAccount(accountId).isNegative
        ? balanceForAccount(accountId).abs()
        : 0;
  }

  int? creditAvailableMinorForAccount(String accountId) {
    final account = accountById(accountId);
    final creditLimit = account.creditLimitMinor;
    if (account.type != AccountType.creditCard || creditLimit == null) {
      return null;
    }
    return creditLimit - creditUsedMinorForAccount(accountId);
  }

  int creditAvailableMinorForGroup(AccountGroup group) {
    if (group != AccountGroup.creditCards) return 0;
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              account.type == AccountType.creditCard,
        )
        .fold(0, (total, account) {
          final limit = account.creditLimitMinor ?? 0;
          return total + limit - creditUsedMinorForAccount(account.id);
        });
  }

  int creditLimitMinorForGroup(AccountGroup group) {
    if (group != AccountGroup.creditCards) return 0;
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              account.type == AccountType.creditCard,
        )
        .fold(0, (total, account) => total + (account.creditLimitMinor ?? 0));
  }

  int creditUsedMinorForGroup(AccountGroup group) {
    if (group != AccountGroup.creditCards) return 0;
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              account.type == AccountType.creditCard,
        )
        .fold(0, (total, account) {
          return total + creditUsedMinorForAccount(account.id);
        });
  }

  int remainingLoanMinorForAccount(String accountId) {
    final account = accountById(accountId);
    if (account.type != AccountType.loan) return 0;
    return balanceForAccount(accountId).abs();
  }

  int? loanPaidDownMinorForAccount(String accountId) {
    final account = accountById(accountId);
    final originalAmount = account.originalLoanAmountMinor;
    if (account.type != AccountType.loan || originalAmount == null) {
      return null;
    }
    final remaining = remainingLoanMinorForAccount(accountId);
    final paidDown = originalAmount - remaining;
    if (paidDown < 0) return 0;
    if (paidDown > originalAmount) return originalAmount;
    return paidDown;
  }

  int originalLoanAmountMinorForGroup(AccountGroup group) {
    if (group != AccountGroup.loans) return 0;
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              account.type == AccountType.loan,
        )
        .fold(
          0,
          (total, account) => total + (account.originalLoanAmountMinor ?? 0),
        );
  }

  int remainingLoanMinorForGroup(AccountGroup group) {
    if (group != AccountGroup.loans) return 0;
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              account.type == AccountType.loan &&
              account.originalLoanAmountMinor != null,
        )
        .fold(0, (total, account) {
          return total + remainingLoanMinorForAccount(account.id);
        });
  }

  int get totalAssetsMinor {
    return accounts
        .where((account) => account.isVisible && account.includeInNetWorth)
        .map((account) => balanceForAccount(account.id))
        .where((balance) => balance > 0)
        .fold(0, (total, balance) => total + balance);
  }

  int get totalLiabilitiesMinor {
    return accounts
        .where((account) => account.isVisible && account.includeInNetWorth)
        .map((account) => balanceForAccount(account.id))
        .where((balance) => balance < 0)
        .fold(0, (total, balance) => total + balance);
  }

  int get fundedGoalAssetsMinor {
    final visibleGoalIds = {
      for (final goal in goals)
        if (!goal.isDeleted &&
            !goal.requiresFundingMigration &&
            !goal.isAccountBacked &&
            !goal.usesReservationModel)
          goal.id,
    };
    return goalFundingEvents
        .where((event) => event.isActive)
        .expand((event) => event.allocations)
        .where((allocation) => visibleGoalIds.contains(allocation.goalId))
        .fold<int>(
          0,
          (total, allocation) => total + allocation.amountMinor.abs(),
        );
  }

  int get netWorthMinor =>
      totalAssetsMinor + totalLiabilitiesMinor + fundedGoalAssetsMinor;

  int get openingNetWorthMinor {
    return accounts
        .where((account) => account.isVisible && account.includeInNetWorth)
        .fold(0, (total, account) => total + account.openingBalanceMinor);
  }

  int get netWorthLedgerChangeMinor => netWorthMinor - openingNetWorthMinor;

  List<GoalRecord> get activeGoals {
    return goals.where((goal) => goal.isActive).toList(growable: false);
  }

  List<GoalRecord> get inactiveGoals {
    return goals
        .where((goal) => goal.isCompleted || goal.isArchived)
        .toList(growable: false);
  }

  List<GoalContributionRecord> activeContributionsForGoal(String goalId) {
    return goalContributions
        .where(
          (contribution) =>
              contribution.goalId == goalId && contribution.isActive,
        )
        .toList(growable: false);
  }

  int currentGoalAmountMinor(String goalId) {
    final goal = goalById(goalId);
    if (goal.usesReservationModel) {
      return reservationAmountMinor(
        containerType: ReservationContainerType.goal,
        containerId: goal.id,
      );
    }
    final accountId = goal.accountId;
    if (accountId != null &&
        accounts.any(
          (account) => account.id == accountId && !account.isDeleted,
        )) {
      return balanceForAccount(accountId);
    }
    return const GoalCalculator().currentAmountMinor(
      goal,
      goalContributions,
      goalFundingEvents,
    );
  }

  List<
    ({ReservationContainerType type, String id, String name, int amountMinor})
  >
  reservationBreakdownForAccount(String accountId, {DateTime? asOf}) {
    final result =
        <
          ({
            ReservationContainerType type,
            String id,
            String name,
            int amountMinor,
          })
        >[];
    for (final fund in funds.where(
      (fund) => !fund.isDeleted && fund.fundingAccountId == accountId,
    )) {
      final amount = reservationAmountMinor(
        containerType: ReservationContainerType.fund,
        containerId: fund.id,
        asOf: asOf,
      );
      if (amount > 0) {
        result.add((
          type: ReservationContainerType.fund,
          id: fund.id,
          name: fund.name,
          amountMinor: amount,
        ));
      }
    }
    for (final goal in goals.where(
      (goal) =>
          !goal.isDeleted &&
          goal.usesReservationModel &&
          goal.reservationFundingAccountId == accountId,
    )) {
      final amount = reservationAmountMinor(
        containerType: ReservationContainerType.goal,
        containerId: goal.id,
        asOf: asOf,
      );
      if (amount > 0) {
        result.add((
          type: ReservationContainerType.goal,
          id: goal.id,
          name: goal.name,
          amountMinor: amount,
        ));
      }
    }
    result.sort((left, right) => right.amountMinor.compareTo(left.amountMinor));
    return result;
  }

  /// A Goal is usable when its linked hidden account still exists. The account
  /// is intentionally not an ordinary Accounts-page item, so visibility in
  /// the main account UI must never be used as a health signal here.
  bool hasUsableGoalAccount(String goalId) {
    final goal = goalById(goalId);
    if (goal.usesReservationModel) {
      final fundingAccountId = goal.reservationFundingAccountId;
      return fundingAccountId != null &&
          accounts.any(
            (account) =>
                account.id == fundingAccountId &&
                account.isVisible &&
                _isReservationFundingAccount(account),
          );
    }
    final accountId = goal.accountId;
    return accountId != null &&
        accounts.any(
          (account) =>
              account.id == accountId &&
              !account.isDeleted &&
              account.goalId == goal.id,
        );
  }

  GoalProgressMetrics goalMetrics(String goalId, {DateTime? now}) {
    final goal = goalById(goalId);
    return const GoalCalculator().calculate(
      goal,
      goalContributions,
      fundingEvents: goalFundingEvents,
      currentAmountMinorOverride:
          goal.isAccountBacked || goal.usesReservationModel
          ? currentGoalAmountMinor(goalId)
          : null,
      now: now,
    );
  }

  int reservedForGoalsMinorForAccount(
    String accountId, {
    String? excludingGoalId,
  }) {
    final reservableGoals = {
      for (final goal in goals)
        if (!goal.isDeleted &&
            !goal.reservationsReleased &&
            goal.id != excludingGoalId)
          goal.id: goal,
    };
    var reserved = 0;
    for (final goal in reservableGoals.values) {
      if (goal.fundingMethod == GoalFundingMethod.accountFunded &&
          goal.requiresFundingMigration &&
          goal.defaultFundingAccountId == accountId) {
        reserved += goal.startingAmountMinor.abs();
      }
    }
    for (final contribution in goalContributions) {
      if (!contribution.isActive ||
          contribution.goalId == excludingGoalId ||
          contribution.fundingMethod != GoalFundingMethod.accountFunded ||
          !contribution.isLegacyReservation ||
          contribution.sourceAccountId != accountId ||
          !reservableGoals.containsKey(contribution.goalId)) {
        continue;
      }
      reserved += contribution.amountMinor.abs();
    }
    return reserved;
  }

  int availableAfterGoalsMinorForAccount(
    String accountId, {
    String? excludingGoalId,
  }) {
    return balanceForAccount(accountId) -
        reservedForGoalsMinorForAccount(
          accountId,
          excludingGoalId: excludingGoalId,
        );
  }

  int get availableCashMinor {
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              (account.group == AccountGroup.banking ||
                  account.group == AccountGroup.cash),
        )
        .map((account) => balanceForAccount(account.id))
        .fold(0, (total, balance) => total + balance);
  }

  int incomeThisMonthMinor({DateTime? now}) {
    return _totalThisMonth(type: TransactionType.income, now: now);
  }

  int expensesThisMonthMinor({DateTime? now}) {
    return _totalThisMonth(type: TransactionType.expense, now: now);
  }

  int scheduledDueOrOverdueCount({DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final today = DateTime(anchor.year, anchor.month, anchor.day);
    return scheduledTransactions
        .where((item) => isScheduledDueOrOverdue(item, today))
        .length;
  }

  List<ScheduledAlertOccurrence> activeScheduledAlerts({DateTime? now}) {
    if (!preferences.notificationsEnabled) return const [];
    final anchor = now ?? DateTime.now();
    const planner = ScheduledNotificationPlanner();
    final alerts = <ScheduledAlertOccurrence>[];
    for (final schedule in scheduledTransactions) {
      if (schedule.isDeleted ||
          !schedule.hasAlert ||
          !hasActionableScheduledAccounts(schedule)) {
        continue;
      }
      final unresolved = <String, ({DateTime date, int amount})>{};
      for (final state in occurrenceAuthorityFor(schedule).values) {
        if (state.status != ScheduledOccurrenceStatus.pending) continue;
        unresolved[scheduledDayKey(state.scheduledDate)] = (
          date: state.scheduledDate,
          amount: state.plannedAmountMinor,
        );
      }
      final effectiveDate = effectiveNextActionableDate(schedule);
      if (effectiveDate != null) {
        final nextDateKey = scheduledDayKey(effectiveDate);
        unresolved.putIfAbsent(
          nextDateKey,
          () => (date: effectiveDate, amount: schedule.amountMinor),
        );
      }
      for (final occurrence in unresolved.values) {
        final alertDateTime = planner.alertDateTimeForOccurrence(
          schedule,
          occurrence.date,
        );
        if (alertDateTime.isAfter(anchor)) continue;
        alerts.add(
          ScheduledAlertOccurrence(
            scheduledTransaction: schedule,
            occurrenceDate: occurrence.date,
            plannedAmountMinor: occurrence.amount,
            alertDateTime: alertDateTime,
          ),
        );
      }
    }
    alerts.sort((left, right) {
      final byAlert = left.alertDateTime.compareTo(right.alertDateTime);
      if (byAlert != 0) return byAlert;
      final byDate = left.occurrenceDate.compareTo(right.occurrenceDate);
      if (byDate != 0) return byDate;
      return left.scheduledTransaction.id.compareTo(
        right.scheduledTransaction.id,
      );
    });
    return alerts;
  }

  int scheduledActiveAlertCount({DateTime? now}) =>
      activeScheduledAlerts(now: now).length;

  DateTime? nextScheduledAlertDateTime({DateTime? now}) {
    if (!preferences.notificationsEnabled) return null;
    final anchor = now ?? DateTime.now();
    const planner = ScheduledNotificationPlanner();
    DateTime? next;
    for (final schedule in scheduledTransactions) {
      if (schedule.isDeleted ||
          schedule.lastAction != ScheduledAction.none ||
          !schedule.hasAlert ||
          !hasActionableScheduledAccounts(schedule)) {
        continue;
      }
      final effectiveDate = effectiveNextActionableDate(schedule);
      if (effectiveDate == null) continue;
      final candidate = planner.alertDateTimeForOccurrence(
        schedule,
        effectiveDate,
      );
      if (!candidate.isAfter(anchor)) continue;
      if (next == null || candidate.isBefore(next)) next = candidate;
    }
    return next;
  }

  bool hasActionableScheduledAccounts(
    ScheduledTransactionRecord scheduledTransaction,
  ) {
    final sourceExists = accounts.any(
      (account) =>
          account.id == scheduledTransaction.accountId && account.isVisible,
    );
    if (!sourceExists) return false;
    if (scheduledTransaction.type != TransactionType.transfer) return true;
    final destinationId = scheduledTransaction.transferAccountId;
    return destinationId != null &&
        destinationId != scheduledTransaction.accountId &&
        accounts.any(
          (account) => account.id == destinationId && account.isVisible,
        );
  }

  DateTime? nextActionableScheduledDate(
    ScheduledTransactionRecord scheduledTransaction, {
    DateTime? now,
  }) {
    if (scheduledTransaction.isDeleted ||
        scheduledTransaction.lastAction != ScheduledAction.none ||
        !hasActionableScheduledAccounts(scheduledTransaction)) {
      return null;
    }
    return effectiveNextActionableDate(scheduledTransaction);
  }

  List<ScheduledTransactionRecord> actionableScheduledTransactions({
    DateTime? now,
  }) {
    final result = <ScheduledTransactionRecord>[];
    for (final scheduledTransaction in scheduledTransactions) {
      final actionableDate = nextActionableScheduledDate(
        scheduledTransaction,
        now: now,
      );
      if (actionableDate == null) continue;
      result.add(
        isSameScheduledDay(actionableDate, scheduledTransaction.nextDate)
            ? scheduledTransaction
            : scheduledTransaction.copyWith(
                nextDate: actionableDate,
                sync: scheduledTransaction.sync,
              ),
      );
    }
    result.sort((left, right) => left.nextDate.compareTo(right.nextDate));
    return result;
  }

  /// Returns the earliest unresolved scheduled payment transfer whose
  /// destination is [creditCardAccountId]. The schedule relationship is
  /// identified by stable account IDs; payee/display text is intentionally
  /// not considered.
  DateTime? nextCreditCardPaymentDueDate(
    String creditCardAccountId, {
    DateTime? now,
  }) {
    final account = accounts
        .where(
          (item) =>
              item.id == creditCardAccountId &&
              item.type == AccountType.creditCard &&
              item.isVisible,
        )
        .firstOrNull;
    if (account == null) return null;

    DateTime? earliest;
    for (final scheduledTransaction in scheduledTransactions) {
      if (scheduledTransaction.type != TransactionType.transfer ||
          scheduledTransaction.transferAccountId != creditCardAccountId) {
        continue;
      }
      final candidate = nextActionableScheduledDate(
        scheduledTransaction,
        now: now,
      );
      if (candidate != null &&
          (earliest == null || candidate.isBefore(earliest))) {
        earliest = candidate;
      }
    }
    return earliest;
  }

  Future<void> resetScheduledHistory({DateTime? now}) async {
    final anchor = now ?? DateTime.now();
    final updatedSchedules = <ScheduledTransactionRecord>[];
    for (final scheduledTransaction in scheduledTransactions) {
      var nextDate = scheduledTransaction.nextDate;
      var lastAction = scheduledTransaction.lastAction;
      if (!scheduledTransaction.isDeleted &&
          scheduledTransaction.frequency != RecurrenceFrequency.once) {
        nextDate =
            firstUnresolvedScheduledDate(scheduledTransaction, today: anchor) ??
            nextDate;
        lastAction = ScheduledAction.none;
      }
      final resetSync = _touchAfterCurrent(scheduledTransaction.sync);
      var reset = scheduledTransaction.copyWith(
        nextDate: nextDate,
        lastAction: lastAction,
        occurrences: const [],
        occurrenceStates: const {},
        scheduledNotificationIds: const [],
        sync: resetSync,
        clearLastReminderScheduledAt: true,
      );
      reset = await _applyScheduledNotificationState(reset);
      reset = reset.copyWith(sync: resetSync);
      updatedSchedules.add(reset);
    }

    final updatedTransactions = <TransactionRecord>[];
    final linkageClearedTransactions = <TransactionRecord>[];
    for (final transaction in transactions) {
      if (transaction.scheduledTransactionId == null &&
          transaction.scheduledOccurrenceDate == null &&
          transaction.scheduledPlannedAmountMinor == null) {
        updatedTransactions.add(transaction);
        continue;
      }
      final reset = transaction.copyWith(
        clearScheduledTransaction: true,
        sync: _touchAfterCurrent(transaction.sync),
      );
      updatedTransactions.add(reset);
      linkageClearedTransactions.add(reset);
    }

    _dataSet = _dataSet.copyWith(
      scheduledTransactions: updatedSchedules,
      transactions: updatedTransactions,
    );
    notifyListeners();
    await localRepository?.save(_dataSet);

    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote != null && currentUserId != null) {
      try {
        for (final scheduledTransaction in updatedSchedules) {
          await remote.saveScheduledTransaction(
            userId: currentUserId,
            scheduledTransaction: scheduledTransaction,
          );
        }
        for (final transaction in linkageClearedTransactions) {
          await remote.saveTransaction(
            userId: currentUserId,
            transaction: transaction,
          );
        }
      } on Exception catch (error) {
        debugPrint(
          'Remote scheduled-history reset failed; local reset retained: $error',
        );
      }
    }
    await refreshScheduledNotificationBadge(now: anchor);
  }

  SyncMetadata _touchAfterCurrent(SyncMetadata sync) {
    final currentTime = DateTime.now().toUtc();
    final timestamp = currentTime.isAfter(sync.updatedAt)
        ? currentTime
        : sync.updatedAt.add(const Duration(microseconds: 1));
    return sync.touched(now: timestamp, deviceId: deviceId);
  }

  int _totalThisMonth({required TransactionType type, DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final periodStart = DateTime(anchor.year, anchor.month);
    final periodEnd = DateTime(anchor.year, anchor.month + 1);
    return transactions
        .where((transaction) {
          return !transaction.isDeleted &&
              transaction.type == type &&
              !transaction.date.isBefore(periodStart) &&
              transaction.date.isBefore(periodEnd);
        })
        .fold(0, (total, transaction) => total + transaction.amountMinor.abs());
  }

  int spentThisMonthForBudget(BudgetRecord budget, {DateTime? now}) {
    return budgetPeriodResult(budget, date: now).spentMinor;
  }

  BudgetPeriodResult budgetPeriodResult(BudgetRecord budget, {DateTime? date}) {
    final requestedDate = date ?? DateTime.now();
    final effectiveDate =
        budget.isArchived &&
            requestedDate.isAfter(budget.sync.updatedAt.toLocal())
        ? budget.sync.updatedAt.toLocal()
        : requestedDate;
    return const BudgetCalculator().calculate(
      budget: budget,
      transactions: transactions,
      categories: categories,
      date: effectiveDate,
    );
  }

  List<BudgetPeriodResult> budgetHistoryThrough(
    BudgetRecord budget, {
    DateTime? date,
  }) {
    final requestedDate = date ?? DateTime.now();
    final effectiveDate =
        budget.isArchived &&
            requestedDate.isAfter(budget.sync.updatedAt.toLocal())
        ? budget.sync.updatedAt.toLocal()
        : requestedDate;
    return const BudgetCalculator().historyThrough(
      budget: budget,
      transactions: transactions,
      categories: categories,
      date: effectiveDate,
    );
  }

  AccountRecord accountById(String id) {
    return accounts.firstWhere((account) => account.id == id);
  }

  CategoryRecord categoryById(String id) {
    return categories.firstWhere((category) => category.id == id);
  }

  BudgetRecord budgetById(String id) {
    return budgets.firstWhere((budget) => budget.id == id);
  }

  Future<void> replaceDataSet(
    FinanceDataSet dataSet, {
    bool persistLocal = true,
  }) async {
    final previousSchedules = scheduledTransactions;
    // Old local data and backups may still carry notification bookkeeping in
    // the schedule record. Treat it only as device-local migration input so
    // reconciliation can cancel those requests before the fields are removed
    // from semantic storage.
    for (final schedule in dataSet.scheduledTransactions) {
      if (schedule.scheduledNotificationIds.isEmpty &&
          schedule.lastReminderScheduledAt == null) {
        continue;
      }
      await notificationStateRepository.save(
        schedule.id,
        DeviceScheduledNotificationState(
          notificationIds: schedule.scheduledNotificationIds,
          lastScheduledAt: schedule.lastReminderScheduledAt,
        ),
      );
    }
    final semanticDataSet = dataSet.copyWith(
      scheduledTransactions: [
        for (final schedule in dataSet.scheduledTransactions)
          schedule.scheduledNotificationIds.isEmpty &&
                  schedule.lastReminderScheduledAt == null
              ? schedule
              : schedule.copyWith(
                  scheduledNotificationIds: const [],
                  clearLastReminderScheduledAt: true,
                  sync: schedule.sync,
                ),
      ],
    );
    if (persistLocal) {
      await localRepository?.save(semanticDataSet);
    }
    _dataSet = semanticDataSet;
    await _reconcileScheduledNotifications(previousSchedules);
    notifyListeners();
  }

  Future<void> _reconcileScheduledNotifications(
    Iterable<ScheduledTransactionRecord> previousSchedules,
  ) async {
    final byId = <String, ScheduledTransactionRecord>{
      for (final schedule in previousSchedules) schedule.id: schedule,
      for (final schedule in scheduledTransactions) schedule.id: schedule,
    };
    for (final schedule in byId.values) {
      final stored = await notificationStateRepository.load(schedule.id);
      final ids = <int>{
        notificationIdFor(schedule.id),
        ...schedule.scheduledNotificationIds,
        ...?stored?.notificationIds,
      };
      await notificationScheduler.cancelScheduledTransaction(
        schedule.copyWith(
          scheduledNotificationIds: ids.toList(growable: false),
          sync: schedule.sync,
        ),
      );
      await notificationStateRepository.remove(schedule.id);
    }

    final reconciled = <ScheduledTransactionRecord>[];
    for (final schedule in scheduledTransactions) {
      reconciled.add(await _applyScheduledNotificationState(schedule));
    }
    _dataSet = _dataSet.copyWith(scheduledTransactions: reconciled);
    await localRepository?.save(_dataSet);
    await refreshScheduledNotificationBadge();
  }

  /// A JSON backup is already a v2 data set. Its successful restoration forms
  /// a new v2 authority boundary, even when the older backup predates the
  /// one-time legacy-import marker.
  Future<void> restoreBackupDataSet(FinanceDataSet dataSet) async {
    if (_authoritativeRestoreInProgress) {
      throw StateError('A backup restore is already in progress.');
    }
    _authoritativeRestoreInProgress = true;
    preferRemoteOnFirstSync = false;
    final restored = dataSet.copyWith(
      preferences: dataSet.preferences.copyWith(
        legacyV1MigrationCompleted: true,
      ),
    );
    try {
      final remote = remoteRepository;
      final currentUserId = userId;
      String? activatedGeneration;
      if (remote != null && currentUserId != null) {
        // Activate the isolated cloud generation before replacing local data.
        // If staging or activation fails, local state is still untouched. If
        // the process stops after activation, the next sync can only load the
        // restored generation, never the stale pre-restore cloud records.
        activatedGeneration = await remote.replaceDataSetAuthoritatively(
          userId: currentUserId,
          dataSet: restored,
        );
      }
      try {
        await replaceDataSet(restored);
        if (currentUserId != null && activatedGeneration != null) {
          await localRepository?.saveAcknowledgedRestoreGeneration(
            currentUserId,
            activatedGeneration,
          );
        }
      } on Object catch (error) {
        if (remote != null && currentUserId != null) {
          throw AuthoritativeRestoreLocalInstallException(error);
        }
        rethrow;
      }
    } finally {
      _authoritativeRestoreInProgress = false;
    }
  }

  /// Replaces the financial data set with a clean, empty authority boundary.
  ///
  /// App preferences and sign-in remain intact. In cloud mode the empty data
  /// set is activated remotely before local data changes, using the same
  /// generation-safe path as an authoritative backup restore.
  Future<void> resetTrackmarkData() {
    return restoreBackupDataSet(
      FinanceDataSet(
        accounts: const [],
        categories: const [],
        transactions: const [],
        scheduledTransactions: const [],
        budgets: const [],
        goals: const [],
        funds: const [],
        reservationOperations: const [],
        goalContributions: const [],
        goalFundingEvents: const [],
        preferences: preferences,
      ),
    );
  }

  Future<void> attachRemoteSync({
    required FinanceRecordRepository remoteRepository,
    required String userId,
  }) async {
    if (_authoritativeRestoreInProgress) {
      throw StateError('Cloud sync is paused while a backup is restored.');
    }
    this.remoteRepository = remoteRepository;
    this.userId = userId;

    debugPrint('Cloud sync stage: loading restore authority');
    final remoteGeneration = await remoteRepository.activeRestoreGeneration(
      userId,
    );
    debugPrint('Cloud sync stage: loading local authority acknowledgement');
    final acknowledgedGeneration = await localRepository
        ?.loadAcknowledgedRestoreGeneration(userId);
    debugPrint('Cloud sync stage: loading remote data set');
    final remoteDataSet = await remoteRepository.loadDataSet(userId);
    debugPrint('Cloud sync stage: remote data set loaded');
    if (financeDataSetHasRecords(remoteDataSet)) {
      if (remoteGeneration != null &&
          remoteGeneration != acknowledgedGeneration) {
        // A confirmed restore is an authority boundary. A device that has not
        // seen this generation must discard its stale local-only records once,
        // otherwise those records would be pushed into the restored data set.
        await replaceDataSet(remoteDataSet);
        await localRepository?.saveAcknowledgedRestoreGeneration(
          userId,
          remoteGeneration,
        );
        preferRemoteOnFirstSync = false;
        debugPrint('Cloud sync stage: migrating legacy Goals');
        await migrateLegacyGoalsToAccounts();
        debugPrint('Cloud sync stage: complete');
        return;
      }
      final merged = preferRemoteOnFirstSync
          ? mergeFinanceDataSetsPreferIncoming(
              incoming: remoteDataSet,
              current: _dataSet,
            )
          : mergeFinanceDataSetsPreferCurrent(
              incoming: remoteDataSet,
              current: _dataSet,
            );
      await replaceDataSet(merged);
      preferRemoteOnFirstSync = false;
      debugPrint('Cloud sync stage: migrating legacy Goals');
      await migrateLegacyGoalsToAccounts();
      debugPrint('Cloud sync stage: uploading merged data set');
      await pushAllRecordsToRemote(baseline: remoteDataSet);
      debugPrint('Cloud sync stage: complete');
      return;
    }

    debugPrint('Cloud sync stage: seeding empty remote data set');
    await pushAllRecordsToRemote(baseline: remoteDataSet);
    preferRemoteOnFirstSync = false;
    debugPrint('Cloud sync stage: complete');
  }

  /// Converts the former Goal-reservation/funding graph to the normal account
  /// and transfer graph exactly once.  Generated IDs are deterministic, so a
  /// restart or a second device can finish an interrupted migration without
  /// duplicating money movements.
  Future<void> migrateLegacyGoalsToAccounts() async {
    // Account-backed Goals no longer use the reservation migration flag. Clear
    // stale flags as part of an idempotent load/sync migration so users never
    // see a permanent legacy-repair state after the account is valid.
    final reconciledGoals = goals
        .where((goal) => goal.isAccountBacked && goal.requiresFundingMigration)
        .map(
          (goal) => goal.copyWith(
            requiresFundingMigration: false,
            sync: _touchAfterCurrent(goal.sync),
          ),
        )
        .toList(growable: false);
    if (reconciledGoals.isNotEmpty) {
      _dataSet = _dataSet.copyWith(
        goals: [
          for (final goal in goals)
            reconciledGoals
                    .where((candidate) => candidate.id == goal.id)
                    .firstOrNull ??
                goal,
        ],
      );
      await _commit(goalRecords: reconciledGoals);
    }

    final candidates = goals
        .where(
          (goal) =>
              !goal.isDeleted &&
              !goal.isAccountBacked &&
              !goal.usesReservationModel,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return;

    final activeContributions = <String, int>{};
    for (final contribution in goalContributions) {
      if (!contribution.isActive) continue;
      activeContributions.update(
        contribution.goalId,
        (value) => value + contribution.amountMinor.abs(),
        ifAbsent: () => contribution.amountMinor.abs(),
      );
    }
    final activeAllocations = <String, int>{};
    for (final event in goalFundingEvents.where((event) => event.isActive)) {
      for (final allocation in event.allocations) {
        activeAllocations.update(
          allocation.goalId,
          (value) => value + allocation.amountMinor.abs(),
          ifAbsent: () => allocation.amountMinor.abs(),
        );
      }
    }

    final backingGoals = <GoalRecord>[];
    for (final goal in candidates) {
      final hasHistory =
          (activeContributions[goal.id] ?? 0) > 0 ||
          (activeAllocations[goal.id] ?? 0) > 0 ||
          goal.startingAmountMinor != 0 ||
          scheduledGoalFundingNeedsAttention(goal.id);
      // An inactive empty/test definition remains directly deletable; creating
      // an otherwise useless hidden account would make its cleanup harder.
      if (!hasHistory && !goal.isActive) continue;
      backingGoals.add(goal);
    }
    if (backingGoals.isEmpty) return;

    final accountsToCreate = <AccountRecord>[];
    final migratedGoals = <GoalRecord>[];
    for (final goal in backingGoals) {
      final accountId = 'goal_account_${goal.id}';
      if (!accounts.any((account) => account.id == accountId)) {
        // Contributions and starting progress had no ordinary account effect
        // in the retired model. They become the opening balance. Account-funded
        // events are represented below as historical standard transfers.
        final openingBalance =
            goal.startingAmountMinor.abs() +
            (activeContributions[goal.id] ?? 0);
        accountsToCreate.add(
          AccountRecord(
            id: accountId,
            name: goal.name,
            type: AccountType.savings,
            openingBalanceMinor: openingBalance,
            includeInGroupBalance: false,
            includeInNetWorth: true,
            goalId: goal.id,
            sync: SyncMetadata.fresh(deviceId: deviceId),
          ),
        );
      }
      migratedGoals.add(
        goal.copyWith(
          accountId: accountId,
          accountMigrationVersion: 1,
          fundingMethod: GoalFundingMethod.accountFunded,
          requiresFundingMigration: false,
          sync: _touchAfterCurrent(goal.sync),
        ),
      );
    }
    final accountIdByGoalId = {
      for (final goal in goals.where((goal) => goal.isAccountBacked))
        goal.id: goal.accountId!,
      for (final goal in migratedGoals) goal.id: goal.accountId!,
    };
    final transfers = <TransactionRecord>[];
    final reclassifiedEvents = <GoalFundingEventRecord>[];
    for (final event in goalFundingEvents.where(
      (event) => event.isActive && !event.isMigrationEvent,
    )) {
      final destinations = [
        for (final allocation in event.allocations)
          accountIdByGoalId[allocation.goalId],
      ];
      // If a tombstoned/unknown Goal is referenced, retain the legacy event
      // untouched instead of guessing a recipient account.
      if (destinations.any((accountId) => accountId == null)) continue;
      for (var index = 0; index < event.allocations.length; index += 1) {
        final allocation = event.allocations[index];
        final id = 'goal_migration_transfer_${event.id}_${allocation.id}';
        if (transactions.any((transaction) => transaction.id == id)) continue;
        final goal =
            migratedGoals
                .where((goal) => goal.id == allocation.goalId)
                .firstOrNull ??
            goals.where((goal) => goal.id == allocation.goalId).first;
        transfers.add(
          TransactionRecord(
            id: id,
            type: TransactionType.transfer,
            accountId: event.sourceAccountId,
            transferAccountId: accountIdByGoalId[allocation.goalId],
            date: event.date,
            payee: 'Funded ${goal.name}',
            amountMinor: allocation.amountMinor.abs(),
            note: event.note,
            goalFundingEventId: event.id,
            sync: SyncMetadata.fresh(deviceId: deviceId),
          ),
        );
      }
      reclassifiedEvents.add(event.copyWith(isMigrationEvent: true));
    }
    final migratedSchedules = <ScheduledTransactionRecord>[];
    for (final schedule in scheduledTransactions.where(
      (schedule) =>
          !schedule.isDeleted &&
          schedule.type == TransactionType.goalFunding &&
          schedule.goalFundingAllocations.length == 1 &&
          schedule.occurrences.isEmpty,
    )) {
      final allocation = schedule.goalFundingAllocations.single;
      final destination = accountIdByGoalId[allocation.goalId];
      final goal = goals
          .where((goal) => goal.id == allocation.goalId)
          .firstOrNull;
      if (destination == null || goal == null) continue;
      migratedSchedules.add(
        schedule.copyWith(
          type: TransactionType.transfer,
          transferAccountId: destination,
          goalId: goal.id,
          goalFundingAllocations: const [],
          payee: 'Fund ${goal.name}',
          sync: _touchAfterCurrent(schedule.sync),
        ),
      );
    }
    if (accountsToCreate.isEmpty &&
        migratedGoals.isEmpty &&
        transfers.isEmpty &&
        migratedSchedules.isEmpty) {
      return;
    }
    final previous = _dataSet;
    try {
      _dataSet = _dataSet.copyWith(
        accounts: [...accounts, ...accountsToCreate],
        goals: [
          for (final goal in goals)
            migratedGoals
                    .where((updated) => updated.id == goal.id)
                    .firstOrNull ??
                goal,
        ],
        transactions: [...transactions, ...transfers],
        goalFundingEvents: [
          for (final event in goalFundingEvents)
            reclassifiedEvents
                    .where((updated) => updated.id == event.id)
                    .firstOrNull ??
                event,
        ],
        scheduledTransactions: [
          for (final schedule in scheduledTransactions)
            migratedSchedules
                    .where((updated) => updated.id == schedule.id)
                    .firstOrNull ??
                schedule,
        ],
      );
      await _commit(
        accounts: accountsToCreate,
        transactions: transfers,
        goalRecords: migratedGoals,
        goalFundingEvents: reclassifiedEvents,
        scheduledTransactions: migratedSchedules,
      );
    } catch (_) {
      _dataSet = previous;
      notifyListeners();
      rethrow;
    }
  }

  void detachRemoteSync() {
    remoteRepository = null;
    userId = null;
  }

  Future<void> pushAllRecordsToRemote({FinanceDataSet? baseline}) async {
    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote == null || currentUserId == null) return;

    if (remote case final BulkFinanceRecordRepository bulkRepository) {
      await bulkRepository.saveDataSet(
        userId: currentUserId,
        dataSet: _dataSet,
        baseline: baseline,
      );
      return;
    }

    for (final account in accounts) {
      await remote.saveAccount(userId: currentUserId, account: account);
    }
    for (final category in categories) {
      await remote.saveCategory(userId: currentUserId, category: category);
    }
    for (final transaction in transactions) {
      await remote.saveTransaction(
        userId: currentUserId,
        transaction: transaction,
      );
    }
    for (final scheduledTransaction in scheduledTransactions) {
      await remote.saveScheduledTransaction(
        userId: currentUserId,
        scheduledTransaction: scheduledTransaction,
      );
      if (remote is ScheduledOccurrenceStateRepository) {
        final occurrenceRepository =
            remote as ScheduledOccurrenceStateRepository;
        for (final entry in occurrenceAuthorityFor(
          scheduledTransaction,
        ).entries) {
          await occurrenceRepository.saveScheduledOccurrenceState(
            userId: currentUserId,
            scheduledTransactionId: scheduledTransaction.id,
            dayKey: entry.key,
            occurrenceState: entry.value,
          );
        }
      }
    }
    for (final budget in budgets) {
      await remote.saveBudget(userId: currentUserId, budget: budget);
    }
    for (final goal in goals) {
      await remote.saveGoal(userId: currentUserId, goal: goal);
    }
    for (final contribution in goalContributions) {
      await remote.saveGoalContribution(
        userId: currentUserId,
        contribution: contribution,
      );
    }
    for (final fundingEvent in goalFundingEvents) {
      await remote.saveGoalFundingEvent(
        userId: currentUserId,
        fundingEvent: fundingEvent,
      );
    }
    if (remote case final ReservationRecordRepository reservationRepository) {
      for (final fund in funds) {
        await reservationRepository.saveFund(userId: currentUserId, fund: fund);
      }
      for (final operation in reservationOperations) {
        await reservationRepository.saveReservationOperation(
          userId: currentUserId,
          operation: operation,
        );
      }
    }
    await remote.savePreferences(
      userId: currentUserId,
      preferences: preferences,
    );
  }

  Future<void> saveAccount(AccountRecord account) async {
    final updated = _upsert(accounts, account, (item) => item.id);
    _dataSet = _dataSet.copyWith(accounts: updated);
    await _commit(accounts: [account]);
  }

  Future<void> archiveAccount(String accountId) async {
    _ensureNoReservationContainerReferences(accountId);
    final account = accountById(accountId).copyWith(isArchived: true);
    await saveAccount(account);
    await refreshScheduledNotifications();
  }

  Future<void> deleteAccount(String accountId) async {
    _ensureNoReservationContainerReferences(accountId);
    final existing = accountById(accountId);
    final account = existing.copyWith(
      isArchived: true,
      sync: existing.sync.deleted(deviceId: deviceId),
    );
    await saveAccount(account);
    await refreshScheduledNotifications();
  }

  Future<void> restoreAccount(String accountId) async {
    final existing = accountById(accountId);
    if (existing.isDeleted) {
      throw const FinanceDataValidationException(
        'A permanently deleted account cannot be restored.',
      );
    }
    final nextSortOrder = accounts
        .where((item) => item.isVisible && item.group == existing.group)
        .fold<int>(0, (highest, item) => max(highest, item.sortOrder + 100));
    await saveAccount(
      existing.copyWith(isArchived: false, sortOrder: nextSortOrder),
    );
    await refreshScheduledNotifications();
  }

  Future<void> reorderAccountsWithinGroup({
    required AccountGroup group,
    required List<String> orderedAccountIds,
  }) async {
    final visibleGroupAccounts = accounts
        .where((item) => item.isVisible && item.group == group)
        .toList(growable: false);
    final expectedIds = visibleGroupAccounts.map((item) => item.id).toSet();
    if (orderedAccountIds.length != expectedIds.length ||
        orderedAccountIds.toSet().length != orderedAccountIds.length ||
        !orderedAccountIds.every(expectedIds.contains)) {
      throw const FinanceDataValidationException(
        'Account order must contain every active account in the group once.',
      );
    }

    final changedAccounts = <AccountRecord>[];
    for (var index = 0; index < orderedAccountIds.length; index += 1) {
      final item = accountById(orderedAccountIds[index]);
      final sortOrder = index * 100;
      if (item.sortOrder != sortOrder) {
        changedAccounts.add(item.copyWith(sortOrder: sortOrder));
      }
    }
    if (changedAccounts.isEmpty) return;

    final changedById = {for (final item in changedAccounts) item.id: item};
    _dataSet = _dataSet.copyWith(
      accounts: [for (final item in accounts) changedById[item.id] ?? item],
    );
    await _commit(accounts: changedAccounts);
  }

  AccountLinkedRecordSummary accountLinkedRecordSummary(String accountId) {
    return AccountLinkedRecordSummary(
      transactionCount: transactions
          .where(
            (transaction) =>
                !transaction.isDeleted &&
                (transaction.accountId == accountId ||
                    transaction.transferAccountId == accountId),
          )
          .length,
      scheduledTransactionCount: scheduledTransactions
          .where(
            (scheduled) =>
                !scheduled.isDeleted &&
                (scheduled.accountId == accountId ||
                    scheduled.transferAccountId == accountId),
          )
          .length,
      goalFundingEventCount: goalFundingEvents
          .where(
            (event) => event.isActive && event.sourceAccountId == accountId,
          )
          .length,
      defaultGoalCount: goals
          .where(
            (goal) =>
                !goal.isDeleted && goal.defaultFundingAccountId == accountId,
          )
          .length,
    );
  }

  Future<void> moveAccountWithinGroup({
    required String accountId,
    required int direction,
  }) async {
    if (direction == 0) return;
    final account = accountById(accountId);
    final groupAccounts =
        accounts
            .where((item) => item.isVisible && item.group == account.group)
            .toList(growable: false)
          ..sort(compareAccountDisplayOrder);
    final fromIndex = groupAccounts.indexWhere((item) => item.id == accountId);
    final toIndex = fromIndex + direction.sign;
    if (fromIndex < 0 || toIndex < 0 || toIndex >= groupAccounts.length) {
      return;
    }

    final reordered = [...groupAccounts];
    final moving = reordered.removeAt(fromIndex);
    reordered.insert(toIndex, moving);

    final changedAccounts = <AccountRecord>[];
    for (var index = 0; index < reordered.length; index += 1) {
      final normalizedSortOrder = index * 100;
      final item = reordered[index];
      if (item.sortOrder != normalizedSortOrder) {
        changedAccounts.add(item.copyWith(sortOrder: normalizedSortOrder));
      }
    }
    if (changedAccounts.isEmpty) return;

    final changedById = {for (final item in changedAccounts) item.id: item};
    final updated = [for (final item in accounts) changedById[item.id] ?? item];
    _dataSet = _dataSet.copyWith(accounts: updated);
    await _commit(accounts: changedAccounts);
  }

  Future<void> saveCategory(CategoryRecord category) async {
    final updated = _upsert(categories, category, (item) => item.id);
    _dataSet = _dataSet.copyWith(categories: updated);
    await _commit(category: category);
  }

  Future<void> saveCategoryLocalFirst(CategoryRecord category) async {
    final previousDataSet = _dataSet;
    final updated = _upsert(categories, category, (item) => item.id);
    _dataSet = _dataSet.copyWith(categories: updated);
    notifyListeners();
    try {
      await localRepository?.save(_dataSet);
    } catch (_) {
      _dataSet = previousDataSet;
      notifyListeners();
      rethrow;
    }

    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote == null || currentUserId == null) return;
    unawaited(
      remote.saveCategory(userId: currentUserId, category: category).catchError(
        (Object error) {
          debugPrint(
            'Remote category save failed; local change retained: $error',
          );
        },
      ),
    );
  }

  Future<void> archiveCategory(String categoryId) async {
    final category = categoryById(categoryId).copyWith(isArchived: true);
    await saveCategory(category);
  }

  Future<void> deleteCategory(String categoryId) async {
    final existing = categoryById(categoryId);
    final category = existing.copyWith(
      isArchived: true,
      sync: existing.sync.deleted(deviceId: deviceId),
    );
    await saveCategory(category);
  }

  Future<void> saveBudget(BudgetRecord budget) async {
    final updated = _upsert(budgets, budget, (item) => item.id);
    _dataSet = _dataSet.copyWith(budgets: updated);
    await _commit(budget: budget);
  }

  Future<void> archiveBudget(String budgetId) async {
    final budget = budgetById(budgetId).copyWith(isArchived: true);
    await saveBudget(budget);
  }

  Future<void> restoreBudget(String budgetId) async {
    final budget = budgetById(budgetId).copyWith(isArchived: false);
    await saveBudget(budget);
  }

  Future<void> deleteBudget(String budgetId) async {
    final existing = budgetById(budgetId);
    final budget = existing.copyWith(
      isArchived: true,
      sync: existing.sync.deleted(deviceId: deviceId),
    );
    await saveBudget(budget);
  }

  List<FundRecord> get activeFunds =>
      funds.where((fund) => fund.isActive).toList(growable: false);

  List<FundRecord> get inactiveFunds =>
      funds.where((fund) => fund.isArchived).toList(growable: false);

  FundRecord fundById(String id) => funds.firstWhere((fund) => fund.id == id);

  int currentFundAmountMinor(String fundId, {DateTime? asOf}) =>
      reservationAmountMinor(
        containerType: ReservationContainerType.fund,
        containerId: fundId,
        asOf: asOf,
      );

  int reservationAmountMinor({
    required ReservationContainerType containerType,
    required String containerId,
    DateTime? asOf,
  }) {
    return calculateReservationLedger(
      operations: effectiveReservationOperationsForContainer(
        operations: reservationOperations,
        transactions: transactions,
        containerType: containerType,
        containerId: containerId,
      ),
      asOf: asOf ?? DateTime.now(),
    ).reservedMinor;
  }

  List<ReservationOperationRecord> reservationActivity({
    required ReservationContainerType containerType,
    required String containerId,
  }) {
    return reservationOperations
        .where(
          (operation) =>
              operation.containerType == containerType &&
              operation.containerId == containerId,
        )
        .toList(growable: false)
      ..sort((left, right) {
        final dateOrder = right.effectiveDate.compareTo(left.effectiveDate);
        if (dateOrder != 0) return dateOrder;
        final revisionOrder = right.revision.compareTo(left.revision);
        if (revisionOrder != 0) return revisionOrder;
        return right.operationId.compareTo(left.operationId);
      });
  }

  Future<FundRecord> createFund({
    required String name,
    required String fundingAccountId,
    int targetBalanceMinor = 0,
    FundTargetCadence targetCadence = FundTargetCadence.none,
    DateTime? nextTargetDate,
    String description = '',
    String? linkedAccountId,
    int accentColorValue = 0xFF247C75,
    String? iconId,
  }) async {
    final account = accountById(fundingAccountId);
    if (!account.isVisible || !_isReservationFundingAccount(account)) {
      throw const FinanceDataValidationException(
        'Choose an active Banking or Cash account for this Fund.',
      );
    }
    if (name.trim().isEmpty) {
      throw const FinanceDataValidationException('Fund name is required.');
    }
    final now = DateTime.now().toUtc();
    final fund = FundRecord(
      id: _newId('fund'),
      name: name.trim(),
      description: description.trim(),
      fundingAccountId: fundingAccountId,
      status: FundStatus.active,
      targetBalanceMinor: targetBalanceMinor.abs(),
      targetCadence: targetCadence,
      nextTargetDate: nextTargetDate,
      linkedAccountId: linkedAccountId,
      accentColorValue: accentColorValue,
      iconId: iconId,
      sync: SyncMetadata.fresh(now: now, deviceId: deviceId),
    );
    await saveFund(fund);
    return fundById(fund.id);
  }

  Future<void> saveFund(FundRecord fund) async {
    if (fund.name.trim().isEmpty) {
      throw const FinanceDataValidationException('Fund name is required.');
    }
    final account = accounts
        .where((item) => item.id == fund.fundingAccountId)
        .firstOrNull;
    if (account == null || !_isReservationFundingAccount(account)) {
      throw const FinanceDataValidationException(
        'A Fund requires a Banking or Cash account.',
      );
    }
    final existing = funds.where((item) => item.id == fund.id).firstOrNull;
    if (existing != null &&
        existing.fundingAccountId != fund.fundingAccountId &&
        currentFundAmountMinor(existing.id) != 0) {
      throw const FinanceDataValidationException(
        'Return all reserved money before changing the funding account.',
      );
    }
    _dataSet = _dataSet.copyWith(
      funds: _upsert(funds, fund, (item) => item.id),
    );
    await _commit(funds: [fund]);
  }

  Future<void> archiveFund(String fundId) async {
    final fund = fundById(fundId);
    await saveFund(
      fund.copyWith(
        status: FundStatus.archived,
        sync: _touchAfterCurrent(fund.sync),
      ),
    );
  }

  Future<void> restoreFund(String fundId) async {
    final fund = fundById(fundId);
    await saveFund(
      fund.copyWith(
        status: FundStatus.active,
        sync: _touchAfterCurrent(fund.sync),
      ),
    );
  }

  FundDeleteEligibility fundDeleteEligibility(String fundId) {
    final amount = currentFundAmountMinor(fundId);
    final hasScheduledReference = scheduledTransactions.any(
      (scheduled) =>
          !scheduled.isDeleted &&
          scheduled.reservationContainerType == ReservationContainerType.fund &&
          scheduled.reservationContainerId == fundId,
    );
    return FundDeleteEligibility(
      hasScheduledReference: hasScheduledReference,
      hasNonZeroBalance: amount != 0,
      remainingBalanceMinor: amount,
    );
  }

  Future<void> deleteFundPermanently(String fundId) async {
    final fund = fundById(fundId);
    if (!fundDeleteEligibility(fundId).canDelete) {
      throw const FinanceDataValidationException(
        'This Fund cannot be permanently deleted until its reserved money is returned and scheduled activity is removed.',
      );
    }
    final deleted = fund.copyWith(
      status: FundStatus.archived,
      sync: fund.sync.deleted(deviceId: deviceId),
    );
    _dataSet = _dataSet.copyWith(
      funds: _upsert(funds, deleted, (item) => item.id),
    );
    await _commit(funds: [deleted]);
  }

  Future<ReservationOperationRecord> allocateReservation({
    required ReservationContainerType containerType,
    required String containerId,
    required int amountMinor,
    required DateTime date,
    String note = '',
    String? causationId,
  }) {
    return _recordReservationOperation(
      containerType: containerType,
      containerId: containerId,
      kind: ReservationOperationKind.allocate,
      amountMinor: amountMinor,
      date: date,
      note: note,
      causationId: causationId,
    );
  }

  Future<ReservationOperationRecord> returnReservation({
    required ReservationContainerType containerType,
    required String containerId,
    required int amountMinor,
    required DateTime date,
    String note = '',
  }) {
    return _recordReservationOperation(
      containerType: containerType,
      containerId: containerId,
      kind: ReservationOperationKind.returnFunds,
      amountMinor: amountMinor,
      date: date,
      note: note,
    );
  }

  Future<ReservationOperationRecord> consumeReservation({
    required ReservationContainerType containerType,
    required String containerId,
    required int amountMinor,
    required DateTime date,
    required String transactionId,
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    String note = '',
  }) {
    return _recordReservationOperation(
      containerType: containerType,
      containerId: containerId,
      kind: ReservationOperationKind.consume,
      amountMinor: amountMinor,
      date: date,
      transactionId: transactionId,
      scheduledTransactionId: scheduledTransactionId,
      scheduledOccurrenceDate: scheduledOccurrenceDate,
      note: note,
      causationId: 'transaction:$transactionId',
    );
  }

  Future<ReservationOperationRecord> reverseReservationOperation({
    required String operationId,
    DateTime? date,
    String note = '',
  }) async {
    final target = reservationOperations
        .where((operation) => operation.id == operationId && operation.isActive)
        .firstOrNull;
    if (target == null) {
      throw const FinanceDataValidationException(
        'This reservation activity is unavailable.',
      );
    }
    return _recordReservationOperation(
      containerType: target.containerType,
      containerId: target.containerId,
      kind: ReservationOperationKind.reversal,
      amountMinor: target.amountMinor,
      date: date ?? DateTime.now(),
      reversesOperationId: target.id,
      note: note,
      causationId: 'reversal:${target.id}',
    );
  }

  Future<ReservationOperationRecord> _recordReservationOperation({
    required ReservationContainerType containerType,
    required String containerId,
    required ReservationOperationKind kind,
    required int amountMinor,
    required DateTime date,
    String? transactionId,
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    String? reversesOperationId,
    String? causationId,
    String note = '',
  }) async {
    final amount = amountMinor.abs();
    if (amount <= 0) {
      throw const FinanceDataValidationException(
        'Reservation amount must be greater than zero.',
      );
    }
    final fundingAccountId = _reservationFundingAccountId(
      containerType,
      containerId,
    );
    final fundingAccount = accountById(fundingAccountId);
    if (!fundingAccount.isVisible ||
        !_isReservationFundingAccount(fundingAccount)) {
      throw const FinanceDataValidationException(
        'The reservation funding account is unavailable.',
      );
    }
    if (kind == ReservationOperationKind.consume) {
      final linkedTransaction = transactionId == null
          ? null
          : transactions
                .where(
                  (transaction) =>
                      transaction.id == transactionId && !transaction.isDeleted,
                )
                .firstOrNull;
      if (linkedTransaction == null ||
          linkedTransaction.deltaForAccount(fundingAccountId) >= 0 ||
          amount > linkedTransaction.deltaForAccount(fundingAccountId).abs()) {
        throw const FinanceDataValidationException(
          'Fund or Goal spending must link to a real outgoing transaction from its funding account.',
        );
      }
    }
    if (causationId != null) {
      final existing = reservationOperations
          .where(
            (operation) =>
                operation.isActive &&
                operation.containerType == containerType &&
                operation.containerId == containerId &&
                operation.causationId == causationId,
          )
          .firstOrNull;
      if (existing != null) return existing;
    }
    final activity = effectiveReservationOperationsForContainer(
      operations: reservationOperations,
      transactions: transactions,
      containerType: containerType,
      containerId: containerId,
    );
    final ledger = calculateReservationLedger(operations: activity, asOf: date);
    if (kind == ReservationOperationKind.allocate) {
      final available = availableToSpendForAccount(
        fundingAccountId,
        asOf: date,
      );
      if (amount > available) {
        throw FinanceDataValidationException(
          '${fundingAccount.name} has only ${(available / 100).toStringAsFixed(2)} available to reserve.',
        );
      }
    } else if (kind != ReservationOperationKind.reversal &&
        amount > ledger.reservedMinor) {
      throw const FinanceDataValidationException(
        'This reservation does not contain enough money.',
      );
    }
    final uniqueId = newReservationOperationId();
    final operation = ReservationOperationRecord(
      id: 'reservation_$uniqueId',
      containerType: containerType,
      containerId: containerId,
      fundingAccountId: fundingAccountId,
      kind: kind,
      amountMinor: amount,
      effectiveDate: DateTime(date.year, date.month, date.day),
      revision: ledger.latestRevision + 1,
      baseRevision: ledger.latestRevision,
      operationId: uniqueId,
      deviceId: deviceId,
      transactionId: transactionId,
      scheduledTransactionId: scheduledTransactionId,
      scheduledOccurrenceDate: scheduledOccurrenceDate,
      reversesOperationId: reversesOperationId,
      causationId: causationId,
      note: note.trim(),
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    final proposed = [...reservationOperations, operation];
    final proposedLedger = calculateReservationLedger(
      operations: effectiveReservationOperationsForContainer(
        operations: proposed,
        transactions: transactions,
        containerType: containerType,
        containerId: containerId,
      ),
      asOf: date,
    );
    if (proposedLedger.conflictedOperationIds.contains(operation.id)) {
      throw const FinanceDataValidationException(
        'This reservation changed on another device. Sync and try again.',
      );
    }
    final previous = _dataSet;
    try {
      _dataSet = _dataSet.copyWith(reservationOperations: proposed);
      await _commit(reservationOperations: [operation]);
    } catch (_) {
      _dataSet = previous;
      notifyListeners();
      rethrow;
    }
    return operation;
  }

  String _reservationFundingAccountId(
    ReservationContainerType containerType,
    String containerId,
  ) {
    switch (containerType) {
      case ReservationContainerType.goal:
        final goal = goalById(containerId);
        if (!goal.usesReservationModel ||
            goal.reservationFundingAccountId == null) {
          throw const FinanceDataValidationException(
            'This Goal does not use account reservations.',
          );
        }
        return goal.reservationFundingAccountId!;
      case ReservationContainerType.fund:
        return fundById(containerId).fundingAccountId;
    }
  }

  bool _isReservationFundingAccount(AccountRecord account) =>
      account.type == AccountType.checking ||
      account.type == AccountType.savings ||
      account.type == AccountType.cash ||
      account.type == AccountType.otherBanking;

  void _ensureNoReservationContainerReferences(String accountId) {
    final linkedGoal = goals
        .where(
          (goal) =>
              !goal.isDeleted &&
              goal.usesReservationModel &&
              goal.reservationFundingAccountId == accountId,
        )
        .firstOrNull;
    final linkedFund = funds
        .where((fund) => !fund.isDeleted && fund.fundingAccountId == accountId)
        .firstOrNull;
    if (linkedGoal == null && linkedFund == null) return;
    final containerName = linkedGoal?.name ?? linkedFund!.name;
    throw FinanceDataValidationException(
      'Reassign or remove $containerName before archiving this account.',
    );
  }

  GoalRecord goalById(String id) {
    return goals.firstWhere((goal) => goal.id == id);
  }

  GoalContributionRecord goalContributionById(String id) {
    return goalContributions.firstWhere(
      (contribution) => contribution.id == id,
    );
  }

  GoalFundingEventRecord goalFundingEventById(String id) {
    return goalFundingEvents.firstWhere((event) => event.id == id);
  }

  List<GoalFundingEventRecord> activeFundingEventsForGoal(String goalId) {
    return goalFundingEvents
        .where(
          (event) =>
              event.isActive &&
              event.allocations.any(
                (allocation) => allocation.goalId == goalId,
              ),
        )
        .toList(growable: false);
  }

  GoalDeleteEligibility goalDeleteEligibility(String goalId) {
    final goal = goalById(goalId);
    if (goal.usesReservationModel) {
      final amount = currentGoalAmountMinor(goalId);
      final hasScheduledReference = scheduledTransactions.any(
        (scheduled) =>
            !scheduled.isDeleted &&
            scheduled.goalFundingAllocations.any(
              (allocation) => allocation.goalId == goalId,
            ),
      );
      return GoalDeleteEligibility(
        hasContributions: false,
        hasFunding: reservationActivity(
          containerType: ReservationContainerType.goal,
          containerId: goalId,
        ).isNotEmpty,
        hasScheduledReference: hasScheduledReference,
        hasNonZeroBalance: amount != 0,
        remainingBalanceMinor: amount,
      );
    }
    final goalAccountId = goal.accountId;
    final hasPendingAccountSchedule =
        goalAccountId != null &&
        _hasPendingScheduledActivityForAccount(goalAccountId);
    if (goalAccountId != null) {
      final balance = balanceForAccount(goalAccountId);
      return GoalDeleteEligibility(
        hasContributions: false,
        hasFunding: false,
        hasScheduledReference:
            hasPendingAccountSchedule ||
            scheduledGoalFundingNeedsAttention(goalId),
        hasNonZeroBalance: balance != 0,
        remainingBalanceMinor: balance,
      );
    }
    final hasContributions = goalContributions.any(
      (item) => item.goalId == goalId,
    );
    final hasFunding = goalFundingEvents.any(
      (event) =>
          event.allocations.any((allocation) => allocation.goalId == goalId),
    );
    final hasScheduledReference = scheduledTransactions.any(
      (scheduled) =>
          scheduled.type == TransactionType.goalFunding &&
          scheduled.goalFundingAllocations.any(
            (allocation) => allocation.goalId == goalId,
          ),
    );
    return GoalDeleteEligibility(
      hasContributions: hasContributions,
      hasFunding: hasFunding,
      hasScheduledReference: hasScheduledReference,
      hasNonZeroBalance: currentGoalAmountMinor(goalId) != 0,
      remainingBalanceMinor: currentGoalAmountMinor(goalId),
    );
  }

  bool scheduledGoalFundingNeedsAttention(String goalId) {
    return scheduledTransactions.any(
      (scheduled) =>
          !scheduled.isDeleted &&
          scheduled.isGoalFunding &&
          scheduled.goalFundingAllocations.any(
            (allocation) => allocation.goalId == goalId,
          ) &&
          firstUnresolvedScheduledDate(scheduled, today: DateTime.now()) !=
              null,
    );
  }

  bool goalHasPendingScheduledActivity(String goalId) {
    final goal = goalById(goalId);
    final accountId = goal.accountId;
    return (accountId != null &&
            _hasPendingScheduledActivityForAccount(accountId)) ||
        scheduledGoalFundingNeedsAttention(goalId);
  }

  bool _hasPendingScheduledActivityForAccount(String accountId) {
    final today = DateTime.now();
    return scheduledTransactions.any(
      (scheduled) =>
          !scheduled.isDeleted &&
          (scheduled.accountId == accountId ||
              scheduled.transferAccountId == accountId) &&
          firstUnresolvedScheduledDate(scheduled, today: today) != null,
    );
  }

  Future<void> saveGoal(GoalRecord goal) async {
    final existing = goals.where((item) => item.id == goal.id).firstOrNull;
    if (existing?.usesReservationModel == true &&
        existing!.reservationFundingAccountId !=
            goal.reservationFundingAccountId &&
        currentGoalAmountMinor(existing.id) != 0) {
      throw const FinanceDataValidationException(
        'Return all reserved money before changing the funding account.',
      );
    }
    _validateGoal(goal);
    final current = goal.isAccountBacked || goal.usesReservationModel
        ? currentGoalAmountMinor(goal.id)
        : const GoalCalculator().currentAmountMinor(
            goal,
            goalContributions,
            goalFundingEvents,
          );
    final adjusted = _goalWithDerivedLifecycleStatus(goal, current);
    _dataSet = _dataSet.copyWith(
      goals: _upsert(goals, adjusted, (item) => item.id),
    );
    await _commit(goal: adjusted);
  }

  Future<GoalRecord> createGoal({
    required String name,
    required int targetAmountMinor,
    required int startingAmountMinor,
    required DateTime? targetDate,
    GoalFundingMethod fundingMethod = GoalFundingMethod.accountFunded,
    GoalType goalType = GoalType.reachTarget,
    String? defaultFundingAccountId,
    String description = '',
    int accentColorValue = 0xFF367BF5,
    DateTime? now,
  }) async {
    final anchor = now ?? DateTime.now();
    final timestamp = anchor.toUtc();
    final goalTargetDate = targetDate == null
        ? null
        : DateTime(targetDate.year, targetDate.month, targetDate.day);
    final today = DateTime(anchor.year, anchor.month, anchor.day);
    if (goalTargetDate != null &&
        startingAmountMinor.abs() < targetAmountMinor.abs() &&
        !goalTargetDate.isAfter(today)) {
      throw FinanceDataValidationException(
        goalType == GoalType.maintainBalance
            ? 'Choose a future restore-by date for a reserve below its target.'
            : 'Choose a future target date for an incomplete Goal.',
      );
    }
    if (fundingMethod != GoalFundingMethod.accountFunded) {
      throw const FinanceDataValidationException(
        'New Goals reserve money from a real Banking or Cash account.',
      );
    }
    final fundingAccount = defaultFundingAccountId == null
        ? null
        : accounts
              .where((account) => account.id == defaultFundingAccountId)
              .firstOrNull;
    if (fundingAccount == null ||
        !fundingAccount.isVisible ||
        !_isReservationFundingAccount(fundingAccount)) {
      throw const FinanceDataValidationException(
        'Choose an active Banking or Cash account for this Goal.',
      );
    }
    final goalId = _newId('goal');
    final goal = GoalRecord(
      id: goalId,
      name: name.trim(),
      description: description.trim(),
      targetAmountMinor: targetAmountMinor.abs(),
      // Reservation operations are the only money authority for new Goals.
      // The legacy cached starting amount remains zero to avoid double-counting.
      startingAmountMinor: 0,
      targetDate: goalTargetDate,
      status:
          goalType == GoalType.reachTarget &&
              startingAmountMinor.abs() >= targetAmountMinor.abs()
          ? GoalStatus.completed
          : GoalStatus.active,
      fundingMethod: GoalFundingMethod.accountFunded,
      goalType: goalType,
      defaultFundingAccountId: defaultFundingAccountId,
      accentColorValue: accentColorValue,
      reservationModelVersion: 1,
      sync: SyncMetadata.fresh(now: timestamp, deviceId: deviceId),
    );
    _validateGoal(goal);
    ReservationOperationRecord? startingOperation;
    if (startingAmountMinor.abs() > 0) {
      final startingAmount = startingAmountMinor.abs();
      final available = availableToSpendForAccount(
        fundingAccount.id,
        asOf: anchor,
      );
      if (startingAmount > available) {
        throw FinanceDataValidationException(
          '${fundingAccount.name} does not have enough available money for the starting amount.',
        );
      }
      final operationIdentity = newReservationOperationId();
      startingOperation = ReservationOperationRecord(
        id: 'reservation_$operationIdentity',
        containerType: ReservationContainerType.goal,
        containerId: goal.id,
        fundingAccountId: fundingAccount.id,
        kind: ReservationOperationKind.allocate,
        amountMinor: startingAmount,
        effectiveDate: DateTime(anchor.year, anchor.month, anchor.day),
        revision: 1,
        baseRevision: 0,
        operationId: operationIdentity,
        deviceId: deviceId,
        causationId: 'goal-starting-amount:${goal.id}',
        note: 'Starting amount',
        sync: SyncMetadata.fresh(now: timestamp, deviceId: deviceId),
      );
    }
    final previousDataSet = _dataSet;
    try {
      _dataSet = _dataSet.copyWith(
        goals: _upsert(goals, goal, (item) => item.id),
        reservationOperations: startingOperation == null
            ? reservationOperations
            : [...reservationOperations, startingOperation],
      );
      await _commit(
        goal: goal,
        reservationOperations: startingOperation == null
            ? const []
            : [startingOperation],
      );
    } catch (_) {
      _dataSet = previousDataSet;
      notifyListeners();
      rethrow;
    }
    return goalById(goal.id);
  }

  Future<GoalContributionRecord> addGoalContribution({
    required String goalId,
    required int amountMinor,
    required DateTime date,
    String? sourceAccountId,
    String note = '',
  }) async {
    final goal = goalById(goalId);
    if (!goal.isActive) {
      throw const FinanceDataValidationException(
        'Only active Goals can receive contributions.',
      );
    }
    if (goal.fundingMethod != GoalFundingMethod.trackingOnly) {
      throw const FinanceDataValidationException(
        'Use Fund Goals for an account-funded Goal.',
      );
    }
    final contribution = GoalContributionRecord(
      id: _newId('goal_contribution'),
      goalId: goalId,
      amountMinor: amountMinor.abs(),
      date: date,
      sourceAccountId: null,
      fundingMethod: goal.fundingMethod,
      note: note.trim(),
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    _validateGoalContribution(contribution, goal);

    final resultingAmount =
        currentGoalAmountMinor(goalId) + contribution.amountMinor;
    final updatedGoal = _goalWithDerivedLifecycleStatus(goal, resultingAmount);
    final previousDataSet = _dataSet;
    try {
      _dataSet = _dataSet.copyWith(
        goals: _upsert(goals, updatedGoal, (item) => item.id),
        goalContributions: _upsert(
          goalContributions,
          contribution,
          (item) => item.id,
        ),
      );
      await _commit(
        goal: identical(updatedGoal, goal) ? null : updatedGoal,
        goalContribution: contribution,
      );
    } catch (_) {
      _dataSet = previousDataSet;
      notifyListeners();
      rethrow;
    }
    return contribution;
  }

  Future<GoalFundingEventRecord> fundGoals({
    required String sourceAccountId,
    required int totalAmountMinor,
    required DateTime date,
    required List<GoalFundingAllocation> allocations,
    String note = '',
  }) async {
    final account = accounts
        .where((item) => item.id == sourceAccountId && item.isVisible)
        .firstOrNull;
    if (account == null) {
      throw const FinanceDataValidationException(
        'Choose an active source account.',
      );
    }
    final amount = totalAmountMinor.abs();
    if (amount <= 0) {
      throw const FinanceDataValidationException(
        'Funding amount must be greater than zero.',
      );
    }
    if (amount > balanceForAccount(account.id)) {
      throw FinanceDataValidationException(
        '${account.name} does not have enough available balance.',
      );
    }
    if (allocations.isEmpty) {
      throw const FinanceDataValidationException(
        'Add at least one Goal allocation.',
      );
    }
    final goalIds = <String>{};
    var allocationTotal = 0;
    for (final allocation in allocations) {
      if (allocation.amountMinor <= 0) {
        throw const FinanceDataValidationException(
          'Goal allocations must be greater than zero.',
        );
      }
      if (!goalIds.add(allocation.goalId)) {
        throw const FinanceDataValidationException(
          'A Goal can only appear once in a funding event.',
        );
      }
      final goal = goals
          .where((item) => item.id == allocation.goalId && item.isActive)
          .firstOrNull;
      if (goal == null ||
          (!goal.isAccountBacked && !goal.usesReservationModel)) {
        throw const FinanceDataValidationException(
          'Choose an active Goal with an available funding account.',
        );
      }
      if (goal.usesReservationModel &&
          goal.reservationFundingAccountId != sourceAccountId) {
        throw FinanceDataValidationException(
          '${goal.name} reserves money from a different account.',
        );
      }
      allocationTotal += allocation.amountMinor;
    }
    if (allocationTotal != amount) {
      throw const FinanceDataValidationException(
        'Goal allocations must equal the total funding amount.',
      );
    }

    final selectedGoals = [
      for (final allocation in allocations) goalById(allocation.goalId),
    ];
    final usesReservationModel = selectedGoals.every(
      (goal) => goal.usesReservationModel,
    );
    if (usesReservationModel) {
      return _fundReservationGoals(
        sourceAccountId: sourceAccountId,
        totalAmountMinor: amount,
        date: date,
        allocations: allocations,
        note: note,
      );
    }
    if (selectedGoals.any((goal) => goal.usesReservationModel)) {
      throw const FinanceDataValidationException(
        'Fund reservation Goals separately from legacy Goal accounts.',
      );
    }

    final eventId = _newId('goal_funding');
    final event = GoalFundingEventRecord(
      id: eventId,
      sourceAccountId: sourceAccountId,
      totalAmountMinor: amount,
      date: DateTime(date.year, date.month, date.day),
      note: note.trim(),
      // Retained only to group a multi-Goal action in existing history UI.
      // Standard transfer records below are the sole balance source.
      isMigrationEvent: true,
      allocations: [
        for (var index = 0; index < allocations.length; index += 1)
          GoalFundingAllocation(
            id: allocations[index].id.isEmpty
                ? _newId('goal_allocation')
                : allocations[index].id,
            fundingEventId: eventId,
            goalId: allocations[index].goalId,
            amountMinor: allocations[index].amountMinor.abs(),
            order: index,
          ),
      ],
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    final transferTransactions = <TransactionRecord>[
      for (final allocation in event.allocations)
        TransactionRecord(
          id: 'goal_transfer_${event.id}_${allocation.id}',
          type: TransactionType.transfer,
          accountId: sourceAccountId,
          transferAccountId: goalById(allocation.goalId).accountId!,
          date: event.date,
          payee: 'Funded ${goalById(allocation.goalId).name}',
          amountMinor: allocation.amountMinor,
          note: event.note,
          goalFundingEventId: event.id,
          sync: SyncMetadata.fresh(deviceId: deviceId),
        ),
    ];
    for (final transaction in transferTransactions) {
      _validateTransaction(transaction);
    }
    final allocationByGoalId = <String, int>{};
    for (final allocation in event.allocations) {
      allocationByGoalId.update(
        allocation.goalId,
        (value) => value + allocation.amountMinor,
        ifAbsent: () => allocation.amountMinor,
      );
    }
    final updatedGoals = <GoalRecord>[
      for (final entry in allocationByGoalId.entries)
        if (goalById(entry.key).goalType == GoalType.reachTarget &&
            goalById(entry.key).status == GoalStatus.active &&
            currentGoalAmountMinor(entry.key) + entry.value >=
                goalById(entry.key).targetAmountMinor)
          goalById(entry.key).copyWith(
            status: GoalStatus.completed,
            completedAt: DateTime.now(),
            clearArchivedAt: true,
            sync: _touchAfterCurrent(goalById(entry.key).sync),
          ),
    ];
    final previousDataSet = _dataSet;
    try {
      var nextGoals = goals;
      for (final goal in updatedGoals) {
        nextGoals = _upsert(nextGoals, goal, (item) => item.id);
      }
      _dataSet = _dataSet.copyWith(
        goals: nextGoals,
        goalFundingEvents: _upsert(goalFundingEvents, event, (item) => item.id),
        transactions: [
          ...transactions,
          for (final transaction in transferTransactions)
            if (!transactions.any((item) => item.id == transaction.id))
              transaction,
        ],
      );
      await _commit(
        goalRecords: updatedGoals,
        goalFundingEvents: [event],
        transactions: transferTransactions,
      );
    } catch (_) {
      _dataSet = previousDataSet;
      notifyListeners();
      rethrow;
    }
    return event;
  }

  Future<GoalFundingEventRecord> _fundReservationGoals({
    required String sourceAccountId,
    required int totalAmountMinor,
    required DateTime date,
    required List<GoalFundingAllocation> allocations,
    required String note,
  }) async {
    final available = availableToSpendForAccount(sourceAccountId, asOf: date);
    if (totalAmountMinor > available) {
      throw FinanceDataValidationException(
        '${accountById(sourceAccountId).name} does not have enough available money to reserve.',
      );
    }
    final eventId = _newId('goal_funding');
    final eventDate = DateTime(date.year, date.month, date.day);
    final event = GoalFundingEventRecord(
      id: eventId,
      sourceAccountId: sourceAccountId,
      totalAmountMinor: totalAmountMinor,
      date: eventDate,
      note: note.trim(),
      // Transitional presentation grouping only. Reservation operations are
      // the authoritative money source and this event changes no balance.
      isMigrationEvent: true,
      allocations: [
        for (var index = 0; index < allocations.length; index += 1)
          GoalFundingAllocation(
            id: allocations[index].id.isEmpty
                ? _newId('goal_allocation')
                : allocations[index].id,
            fundingEventId: eventId,
            goalId: allocations[index].goalId,
            amountMinor: allocations[index].amountMinor.abs(),
            order: index,
          ),
      ],
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    final operations = <ReservationOperationRecord>[];
    for (final allocation in event.allocations) {
      final ledger = calculateReservationLedger(
        operations: reservationOperations.where(
          (operation) =>
              operation.containerType == ReservationContainerType.goal &&
              operation.containerId == allocation.goalId,
        ),
        asOf: eventDate,
      );
      final uniqueId = newReservationOperationId();
      operations.add(
        ReservationOperationRecord(
          id: 'reservation_$uniqueId',
          containerType: ReservationContainerType.goal,
          containerId: allocation.goalId,
          fundingAccountId: sourceAccountId,
          kind: ReservationOperationKind.allocate,
          amountMinor: allocation.amountMinor,
          effectiveDate: eventDate,
          revision: ledger.latestRevision + 1,
          baseRevision: ledger.latestRevision,
          operationId: uniqueId,
          deviceId: deviceId,
          causationId: 'goal-funding:$eventId:${allocation.id}',
          note: event.note,
          sync: SyncMetadata.fresh(deviceId: deviceId),
        ),
      );
    }
    final updatedGoals = <GoalRecord>[];
    for (final allocation in event.allocations) {
      final goal = goalById(allocation.goalId);
      if (goal.goalType == GoalType.reachTarget &&
          goal.status == GoalStatus.active &&
          currentGoalAmountMinor(goal.id) + allocation.amountMinor >=
              goal.targetAmountMinor) {
        updatedGoals.add(
          goal.copyWith(
            status: GoalStatus.completed,
            completedAt: eventDate,
            clearArchivedAt: true,
            sync: _touchAfterCurrent(goal.sync),
          ),
        );
      }
    }
    final previous = _dataSet;
    try {
      var nextGoals = goals;
      for (final goal in updatedGoals) {
        nextGoals = _upsert(nextGoals, goal, (item) => item.id);
      }
      _dataSet = _dataSet.copyWith(
        goals: nextGoals,
        goalFundingEvents: _upsert(goalFundingEvents, event, (item) => item.id),
        reservationOperations: [...reservationOperations, ...operations],
      );
      await _commit(
        goalRecords: updatedGoals,
        goalFundingEvents: [event],
        reservationOperations: operations,
      );
    } catch (_) {
      _dataSet = previous;
      notifyListeners();
      rethrow;
    }
    return event;
  }

  /// Completes exactly one planned Goal Funding occurrence. Unlike an ordinary
  /// scheduled payment, this creates a Goal funding event rather than a ledger
  /// transaction. The event id is deterministic so retrying a tap or converging
  /// a remote retry cannot create a second funding event for the occurrence.
  Future<GoalFundingEventRecord> completeScheduledGoalFunding({
    required String scheduledTransactionId,
    required DateTime occurrenceDate,
    DateTime? fundingDate,
    String? note,
  }) async {
    final schedule = scheduledTransactions
        .where(
          (item) =>
              item.id == scheduledTransactionId &&
              item.type == TransactionType.goalFunding,
        )
        .firstOrNull;
    if (schedule == null) {
      throw const FinanceDataValidationException(
        'This scheduled Goal Funding item is no longer available.',
      );
    }
    final day = DateTime(
      occurrenceDate.year,
      occurrenceDate.month,
      occurrenceDate.day,
    );
    final existingOccurrence = schedule.occurrences
        .where((item) => isSameScheduledDay(item.scheduledDate, day))
        .firstOrNull;
    if (existingOccurrence?.status == ScheduledOccurrenceStatus.paid &&
        existingOccurrence?.goalFundingEventId != null) {
      final event = goalFundingEvents
          .where((item) => item.id == existingOccurrence!.goalFundingEventId)
          .firstOrNull;
      if (event != null) return event;
    }
    if (schedule.isDeleted) {
      throw const FinanceDataValidationException(
        'This scheduled Goal Funding item is no longer available.',
      );
    }
    final eventId =
        'scheduled_goal_funding_${schedule.id}_${scheduledDayKey(day)}';
    final existingEvent = goalFundingEvents
        .where((item) => item.id == eventId && item.isActive)
        .firstOrNull;
    if (existingEvent != null) return existingEvent;

    final account = accounts
        .where((item) => item.id == schedule.accountId && item.isVisible)
        .firstOrNull;
    if (account == null) {
      throw const FinanceDataValidationException(
        'Choose an active source account before funding Goals.',
      );
    }
    final amount = schedule.amountMinor.abs();
    if (amount <= 0 || !schedule.hasValidGoalFundingAllocations) {
      throw const FinanceDataValidationException(
        'Goal allocations must equal the scheduled funding amount.',
      );
    }
    final goalIds = <String>{};
    final selectedGoals = <GoalRecord>[];
    for (final allocation in schedule.goalFundingAllocations) {
      if (!goalIds.add(allocation.goalId)) {
        throw const FinanceDataValidationException(
          'A Goal can only appear once in a funding event.',
        );
      }
      final goal = goals
          .where((item) => item.id == allocation.goalId && item.isActive)
          .firstOrNull;
      if (goal == null ||
          goal.fundingMethod != GoalFundingMethod.accountFunded ||
          goal.requiresFundingMigration) {
        throw const FinanceDataValidationException(
          'Repair the Goal allocation before funding this occurrence.',
        );
      }
      selectedGoals.add(goal);
    }
    final usesReservationModel = selectedGoals.every(
      (goal) => goal.usesReservationModel,
    );
    if (selectedGoals.any((goal) => goal.usesReservationModel) &&
        !usesReservationModel) {
      throw const FinanceDataValidationException(
        'Schedule reservation Goals separately from legacy Goal accounts.',
      );
    }
    if (usesReservationModel) {
      if (selectedGoals.any(
        (goal) => goal.reservationFundingAccountId != account.id,
      )) {
        throw const FinanceDataValidationException(
          'Every scheduled Goal must reserve money from the schedule account.',
        );
      }
      if (amount > availableToSpendForAccount(account.id, asOf: day)) {
        throw FinanceDataValidationException(
          '${account.name} does not have enough available money to reserve.',
        );
      }
    } else if (amount > balanceForAccount(account.id)) {
      throw FinanceDataValidationException(
        '${account.name} does not have enough available balance.',
      );
    }

    final event = GoalFundingEventRecord(
      id: eventId,
      sourceAccountId: account.id,
      totalAmountMinor: amount,
      date: DateTime(
        (fundingDate ?? DateTime.now()).year,
        (fundingDate ?? DateTime.now()).month,
        (fundingDate ?? DateTime.now()).day,
      ),
      note: (note ?? schedule.note).trim(),
      // Reservation operations are authoritative for modern Goals. This
      // event groups Scheduled history and must not reduce the real account.
      isMigrationEvent: usesReservationModel,
      allocations: [
        for (
          var index = 0;
          index < schedule.goalFundingAllocations.length;
          index += 1
        )
          GoalFundingAllocation(
            // Schedule allocation IDs identify the editable template. Each
            // completed occurrence needs its own immutable historical line.
            id: '${eventId}_allocation_$index',
            fundingEventId: eventId,
            goalId: schedule.goalFundingAllocations[index].goalId,
            amountMinor: schedule.goalFundingAllocations[index].amountMinor,
            order: index,
          ),
      ],
      scheduledTransactionId: schedule.id,
      scheduledOccurrenceDate: day,
      scheduledPlannedAmountMinor: amount,
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    final updatedGoals = <GoalRecord>[];
    for (final allocation in event.allocations) {
      final goal = goalById(allocation.goalId);
      if (goal.goalType == GoalType.reachTarget &&
          goal.status == GoalStatus.active &&
          currentGoalAmountMinor(goal.id) + allocation.amountMinor >=
              goal.targetAmountMinor) {
        updatedGoals.add(
          goal.copyWith(
            status: GoalStatus.completed,
            completedAt: event.date,
            clearArchivedAt: true,
            sync: _touchAfterCurrent(goal.sync),
          ),
        );
      }
    }
    final reservationAllocations = <ReservationOperationRecord>[];
    if (usesReservationModel) {
      var workingOperations = [...reservationOperations];
      for (final allocation in event.allocations) {
        final operation = _draftReservationOperation(
          operations: workingOperations,
          containerType: ReservationContainerType.goal,
          containerId: allocation.goalId,
          fundingAccountId: account.id,
          kind: ReservationOperationKind.allocate,
          amountMinor: allocation.amountMinor,
          effectiveDate: event.date,
          scheduledTransactionId: schedule.id,
          scheduledOccurrenceDate: day,
          causationId: 'goal-funding:${event.id}:${allocation.id}',
          note: event.note,
        );
        reservationAllocations.add(operation);
        workingOperations.add(operation);
      }
    }
    var occurrenceState = nextOccurrenceOperation(
      schedule: schedule,
      scheduledDate: day,
      plannedAmountMinor: amount,
      status: ScheduledOccurrenceStatus.paid,
      actualAmountMinor: amount,
      actualPaymentDate: event.date,
      goalFundingEventId: event.id,
      deviceId: deviceId,
    );
    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote is ScheduledOccurrenceStateRepository && currentUserId != null) {
      occurrenceState = await (remote as ScheduledOccurrenceStateRepository)
          .saveScheduledOccurrenceState(
            userId: currentUserId,
            scheduledTransactionId: schedule.id,
            dayKey: occurrenceDayKey(day),
            occurrenceState: occurrenceState,
          );
    }
    final nextDate = nextScheduledRecurrenceDate(
      schedule.nextDate,
      schedule.frequency,
    );
    final updatedSchedule =
        nextDate == null || nextDate.isAfter(schedule.endDate ?? DateTime(9999))
        ? withOccurrenceAuthority(
            schedule.copyWith(
              lastAction: ScheduledAction.paid,
              sync: schedule.sync.deleted(deviceId: deviceId),
            ),
            occurrenceState,
          )
        : withOccurrenceAuthority(
            schedule.copyWith(
              nextDate: nextDate,
              lastAction: ScheduledAction.none,
              scheduledNotificationIds: const [],
              sync: schedule.sync.touched(deviceId: deviceId),
              clearLastReminderScheduledAt: true,
            ),
            occurrenceState,
          );
    final previousDataSet = _dataSet;
    try {
      final notificationAdjusted = await _applyScheduledNotificationState(
        updatedSchedule,
      );
      var nextGoals = goals;
      for (final goal in updatedGoals) {
        nextGoals = _upsert(nextGoals, goal, (item) => item.id);
      }
      _dataSet = _dataSet.copyWith(
        goals: nextGoals,
        goalFundingEvents: _upsert(goalFundingEvents, event, (item) => item.id),
        scheduledTransactions: _upsert(
          scheduledTransactions,
          notificationAdjusted,
          (item) => item.id,
        ),
        reservationOperations: reservationAllocations.isEmpty
            ? reservationOperations
            : [...reservationOperations, ...reservationAllocations],
      );
      await _commit(
        goalRecords: updatedGoals,
        goalFundingEvents: [event],
        reservationOperations: reservationAllocations,
        scheduledTransaction: notificationAdjusted,
      );
      await refreshScheduledNotificationBadge();
    } catch (_) {
      _dataSet = previousDataSet;
      notifyListeners();
      rethrow;
    }
    return event;
  }

  Future<GoalFundingEventRecord> undoGoalFunding(String eventId) async {
    final event = goalFundingEvents
        .where((item) => item.id == eventId && item.isActive)
        .firstOrNull;
    if (event == null) {
      throw const FinanceDataValidationException(
        'This Goal funding event has already been undone or is unavailable.',
      );
    }
    final accountExists = accounts.any(
      (account) => account.id == event.sourceAccountId && !account.isDeleted,
    );
    if (!accountExists) {
      throw const FinanceDataValidationException(
        'The source account is unavailable. Restore or reassign it before undoing this funding.',
      );
    }
    final reversed = event.copyWith(
      sync: _touchAfterCurrent(event.sync).deleted(deviceId: deviceId),
    );
    final reversedTransfers = transactions
        .where(
          (transaction) =>
              !transaction.isDeleted &&
              transaction.goalFundingEventId == event.id,
        )
        .map(
          (transaction) => transaction.copyWith(
            sync: transaction.sync.deleted(deviceId: deviceId),
          ),
        )
        .toList(growable: false);
    final affectedGoalIds = event.allocations
        .map((allocation) => allocation.goalId)
        .toSet();
    final affectedGoals = [for (final id in affectedGoalIds) goalById(id)];
    final reservationBacked = affectedGoals.every(
      (goal) => goal.usesReservationModel,
    );
    if (reservationBacked && reversedTransfers.isNotEmpty) {
      throw const FinanceDataValidationException(
        'Reservation Goal funding cannot contain hidden transfer records.',
      );
    }
    final reservationReversals = <ReservationOperationRecord>[];
    if (reservationBacked) {
      for (final allocation in event.allocations) {
        final target = reservationOperations
            .where(
              (operation) =>
                  operation.isActive &&
                  operation.containerType == ReservationContainerType.goal &&
                  operation.containerId == allocation.goalId &&
                  operation.causationId ==
                      'goal-funding:${event.id}:${allocation.id}',
            )
            .firstOrNull;
        if (target == null) {
          throw const FinanceDataValidationException(
            'The linked Goal reservation activity is unavailable.',
          );
        }
        final ledger = calculateReservationLedger(
          operations: reservationOperations.where(
            (operation) =>
                operation.containerType == ReservationContainerType.goal &&
                operation.containerId == allocation.goalId,
          ),
          asOf: DateTime.now(),
        );
        final uniqueId = newReservationOperationId();
        reservationReversals.add(
          ReservationOperationRecord(
            id: 'reservation_$uniqueId',
            containerType: ReservationContainerType.goal,
            containerId: allocation.goalId,
            fundingAccountId: event.sourceAccountId,
            kind: ReservationOperationKind.reversal,
            amountMinor: target.amountMinor,
            effectiveDate: DateTime.now(),
            revision: ledger.latestRevision + 1,
            baseRevision: ledger.latestRevision,
            operationId: uniqueId,
            deviceId: deviceId,
            reversesOperationId: target.id,
            causationId: 'undo-goal-funding:${event.id}:${allocation.id}',
            note: 'Undo Goal funding',
            sync: SyncMetadata.fresh(deviceId: deviceId),
          ),
        );
      }
      for (final goal in affectedGoals) {
        final proposed = calculateReservationLedger(
          operations: [
            ...reservationOperations.where(
              (operation) =>
                  operation.containerType == ReservationContainerType.goal &&
                  operation.containerId == goal.id,
            ),
            ...reservationReversals.where(
              (operation) => operation.containerId == goal.id,
            ),
          ],
          asOf: DateTime.now(),
        );
        if (proposed.conflictedOperationIds.any(
          (id) => reservationReversals.any((operation) => operation.id == id),
        )) {
          throw FinanceDataValidationException(
            'Cannot undo this funding because ${goal.name} has money that was already spent.',
          );
        }
      }
    }
    // Funding undo is a transfer reversal.  It cannot be allowed to remove
    // money that has subsequently been spent from a Goal account: doing so
    // would manufacture a negative Goal balance and leave the ordinary
    // expense appearing broken.  Check each affected hidden account before
    // writing any tombstones so the operation is atomic and retry-safe.
    for (final goalId in affectedGoalIds) {
      final goal = goals.where((item) => item.id == goalId).firstOrNull;
      final goalAccountId = goal?.accountId;
      if (goalAccountId == null) continue;
      final reversedIncomingMinor = reversedTransfers
          .where(
            (transaction) => transaction.transferAccountId == goalAccountId,
          )
          .fold<int>(
            0,
            (total, transaction) => total + transaction.amountMinor.abs(),
          );
      if (balanceForAccount(goalAccountId) - reversedIncomingMinor < 0) {
        throw FinanceDataValidationException(
          'Cannot undo this Goal funding because ${goal?.name ?? 'this Goal'} has money that was already spent. Delete or edit the related Goal activity first.',
        );
      }
    }
    final updatedGoals = <GoalRecord>[
      for (final goalId in affectedGoalIds)
        if (goals.where((goal) => goal.id == goalId).firstOrNull
            case final goal?
            when goal.goalType == GoalType.reachTarget &&
                goal.status == GoalStatus.completed &&
                currentGoalAmountMinor(goalId) -
                        event.allocations
                            .where((allocation) => allocation.goalId == goalId)
                            .fold<int>(
                              0,
                              (total, allocation) =>
                                  total + allocation.amountMinor,
                            ) <
                    goal.targetAmountMinor)
          goal.copyWith(
            status: GoalStatus.active,
            clearCompletedAt: true,
            sync: _touchAfterCurrent(goal.sync),
          ),
    ];
    ScheduledTransactionRecord? restoredSchedule;
    if (event.scheduledTransactionId != null &&
        event.scheduledOccurrenceDate != null) {
      final schedule = scheduledTransactions
          .where((item) => item.id == event.scheduledTransactionId)
          .firstOrNull;
      if (schedule == null) {
        throw const FinanceDataValidationException(
          'The linked scheduled Goal Funding record is unavailable.',
        );
      }
      final occurrenceDay = DateTime(
        event.scheduledOccurrenceDate!.year,
        event.scheduledOccurrenceDate!.month,
        event.scheduledOccurrenceDate!.day,
      );
      final today = DateTime.now();
      final todayDay = DateTime(today.year, today.month, today.day);
      final wasAutomaticallyClosed =
          schedule.isDeleted && schedule.lastAction == ScheduledAction.paid;
      final shouldRestoreAsNext =
          wasAutomaticallyClosed ||
          (!occurrenceDay.isBefore(todayDay) &&
              occurrenceDay.isBefore(schedule.nextDate));
      var restoredState = nextOccurrenceOperation(
        schedule: schedule,
        scheduledDate: occurrenceDay,
        plannedAmountMinor:
            event.scheduledPlannedAmountMinor ?? event.totalAmountMinor,
        status: ScheduledOccurrenceStatus.pending,
        deviceId: deviceId,
      );
      final remote = remoteRepository;
      final currentUserId = userId;
      if (remote is ScheduledOccurrenceStateRepository &&
          currentUserId != null) {
        restoredState = await (remote as ScheduledOccurrenceStateRepository)
            .saveScheduledOccurrenceState(
              userId: currentUserId,
              scheduledTransactionId: schedule.id,
              dayKey: occurrenceDayKey(occurrenceDay),
              occurrenceState: restoredState,
            );
      }
      restoredSchedule = withOccurrenceAuthority(
        schedule.copyWith(
          nextDate: shouldRestoreAsNext ? occurrenceDay : schedule.nextDate,
          lastAction: ScheduledAction.none,
          scheduledNotificationIds: const [],
          sync: schedule.isDeleted
              ? schedule.sync.restored(deviceId: deviceId)
              : schedule.sync.touched(deviceId: deviceId),
          clearLastReminderScheduledAt: true,
        ),
        restoredState,
      );
    }
    final previousDataSet = _dataSet;
    ScheduledTransactionRecord? notificationAdjusted;
    try {
      if (restoredSchedule != null) {
        notificationAdjusted = await _applyScheduledNotificationState(
          restoredSchedule,
        );
        restoredSchedule = notificationAdjusted.copyWith(
          sync: restoredSchedule.sync,
        );
      }
      var nextGoals = goals;
      for (final goal in updatedGoals) {
        nextGoals = _upsert(nextGoals, goal, (item) => item.id);
      }
      _dataSet = _dataSet.copyWith(
        goals: nextGoals,
        goalFundingEvents: _upsert(
          goalFundingEvents,
          reversed,
          (item) => item.id,
        ),
        scheduledTransactions: restoredSchedule == null
            ? scheduledTransactions
            : _upsert(
                scheduledTransactions,
                restoredSchedule,
                (item) => item.id,
              ),
        transactions: [
          for (final transaction in transactions)
            reversedTransfers
                    .where((reversed) => reversed.id == transaction.id)
                    .firstOrNull ??
                transaction,
        ],
        reservationOperations: reservationReversals.isEmpty
            ? reservationOperations
            : [...reservationOperations, ...reservationReversals],
      );
      await _commit(
        goalRecords: updatedGoals,
        goalFundingEvents: [reversed],
        transactions: reversedTransfers,
        reservationOperations: reservationReversals,
        scheduledTransaction: restoredSchedule,
      );
      if (restoredSchedule != null) {
        await refreshScheduledNotificationBadge();
      }
    } catch (_) {
      _dataSet = previousDataSet;
      if (notificationAdjusted != null &&
          notificationAdjusted.scheduledNotificationIds.isNotEmpty) {
        await notificationScheduler.cancelScheduledTransaction(
          notificationAdjusted,
        );
      }
      notifyListeners();
      rethrow;
    }
    return reversed;
  }

  Future<void> migrateLegacyGoalToAccountFunding(String goalId) async {
    final goal = goalById(goalId);
    if (!goal.requiresFundingMigration ||
        goal.fundingMethod != GoalFundingMethod.accountFunded) {
      return;
    }
    final amountsByAccount = <String, int>{};
    final defaultAccountId = goal.defaultFundingAccountId;
    if (goal.startingAmountMinor > 0) {
      if (defaultAccountId == null) {
        throw const FinanceDataValidationException(
          'Choose a funding account before converting this Goal.',
        );
      }
      amountsByAccount[defaultAccountId] = goal.startingAmountMinor.abs();
    }
    final legacyContributions = activeContributionsForGoal(
      goal.id,
    ).where((item) => item.isLegacyReservation).toList(growable: false);
    for (final contribution in legacyContributions) {
      final accountId = contribution.sourceAccountId ?? defaultAccountId;
      if (accountId == null) {
        throw const FinanceDataValidationException(
          'A previous Goal contribution has no source account.',
        );
      }
      amountsByAccount.update(
        accountId,
        (amount) => amount + contribution.amountMinor.abs(),
        ifAbsent: () => contribution.amountMinor.abs(),
      );
    }
    for (final entry in amountsByAccount.entries) {
      final account = accounts
          .where((item) => item.id == entry.key && item.isVisible)
          .firstOrNull;
      if (account == null) {
        throw const FinanceDataValidationException(
          'A linked funding account is unavailable.',
        );
      }
      if (entry.value > balanceForAccount(account.id)) {
        throw FinanceDataValidationException(
          '${account.name} does not have enough balance to convert this Goal.',
        );
      }
    }

    final timestamp = DateTime.now().toUtc();
    final events = <GoalFundingEventRecord>[];
    for (final entry in amountsByAccount.entries) {
      if (entry.value <= 0) continue;
      final eventId = _newId('goal_funding_migration');
      events.add(
        GoalFundingEventRecord(
          id: eventId,
          sourceAccountId: entry.key,
          totalAmountMinor: entry.value,
          date: DateTime.now(),
          note: 'Converted from previous Goal reservations',
          allocations: [
            GoalFundingAllocation(
              id: _newId('goal_allocation'),
              fundingEventId: eventId,
              goalId: goal.id,
              amountMinor: entry.value,
              order: 0,
            ),
          ],
          isMigrationEvent: true,
          sync: SyncMetadata.fresh(now: timestamp, deviceId: deviceId),
        ),
      );
    }
    final tombstones = [
      for (final contribution in legacyContributions)
        contribution.copyWith(
          sync: _touchAfterCurrent(
            contribution.sync,
          ).deleted(deviceId: deviceId),
        ),
    ];
    final migratedGoal = goal.copyWith(
      startingAmountMinor: 0,
      requiresFundingMigration: false,
      sync: _touchAfterCurrent(goal.sync),
    );
    final previousDataSet = _dataSet;
    try {
      var updatedContributions = goalContributions;
      for (final tombstone in tombstones) {
        updatedContributions = _upsert(
          updatedContributions,
          tombstone,
          (item) => item.id,
        );
      }
      var updatedEvents = goalFundingEvents;
      for (final event in events) {
        updatedEvents = _upsert(updatedEvents, event, (item) => item.id);
      }
      _dataSet = _dataSet.copyWith(
        goals: _upsert(goals, migratedGoal, (item) => item.id),
        goalContributions: updatedContributions,
        goalFundingEvents: updatedEvents,
      );
      await _commit(
        goal: migratedGoal,
        goalContributions: tombstones,
        goalFundingEvents: events,
      );
    } catch (_) {
      _dataSet = previousDataSet;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> migrateLegacyGoalToTrackingOnly(String goalId) async {
    final goal = goalById(goalId);
    if (!goal.requiresFundingMigration) return;
    final convertedContributions = [
      for (final contribution in activeContributionsForGoal(goal.id))
        if (contribution.isLegacyReservation)
          contribution.copyWith(
            fundingMethod: GoalFundingMethod.trackingOnly,
            clearSourceAccount: true,
            isLegacyReservation: false,
            sync: _touchAfterCurrent(contribution.sync),
          ),
    ];
    final migratedGoal = goal.copyWith(
      fundingMethod: GoalFundingMethod.trackingOnly,
      clearDefaultFundingAccount: true,
      requiresFundingMigration: false,
      sync: _touchAfterCurrent(goal.sync),
    );
    final previousDataSet = _dataSet;
    try {
      var updatedContributions = goalContributions;
      for (final contribution in convertedContributions) {
        updatedContributions = _upsert(
          updatedContributions,
          contribution,
          (item) => item.id,
        );
      }
      _dataSet = _dataSet.copyWith(
        goals: _upsert(goals, migratedGoal, (item) => item.id),
        goalContributions: updatedContributions,
      );
      await _commit(
        goal: migratedGoal,
        goalContributions: convertedContributions,
      );
    } catch (_) {
      _dataSet = previousDataSet;
      notifyListeners();
      rethrow;
    }
  }

  Future<GoalContributionRecord> undoGoalContribution(
    String contributionId,
  ) async {
    final contribution = goalContributions
        .where((item) => item.id == contributionId && item.isActive)
        .firstOrNull;
    if (contribution == null) {
      throw const FinanceDataValidationException(
        'This Goal contribution has already been undone or is unavailable.',
      );
    }
    final goal = goals
        .where((item) => item.id == contribution.goalId && !item.isDeleted)
        .firstOrNull;
    if (goal == null) {
      throw const FinanceDataValidationException(
        'The related Goal is unavailable.',
      );
    }
    final reversed = contribution.copyWith(
      sync: _touchAfterCurrent(contribution.sync).deleted(deviceId: deviceId),
    );
    final amountAfterUndo =
        currentGoalAmountMinor(goal.id) - contribution.amountMinor.abs();
    final updatedGoal =
        goal.goalType == GoalType.reachTarget &&
            goal.status == GoalStatus.completed &&
            amountAfterUndo < goal.targetAmountMinor
        ? goal.copyWith(
            status: GoalStatus.active,
            clearCompletedAt: true,
            sync: _touchAfterCurrent(goal.sync),
          )
        : _goalWithDerivedLifecycleStatus(goal, amountAfterUndo);
    final previousDataSet = _dataSet;
    try {
      _dataSet = _dataSet.copyWith(
        goals: _upsert(goals, updatedGoal, (item) => item.id),
        goalContributions: _upsert(
          goalContributions,
          reversed,
          (item) => item.id,
        ),
      );
      await _commit(
        goal: identical(updatedGoal, goal) ? null : updatedGoal,
        goalContribution: reversed,
      );
    } catch (_) {
      _dataSet = previousDataSet;
      notifyListeners();
      rethrow;
    }
    return reversed;
  }

  Future<void> archiveGoal(String goalId) async {
    final goal = goalById(goalId);
    await saveGoal(
      goal.copyWith(
        status: GoalStatus.archived,
        archivedAt: DateTime.now(),
        clearCompletedAt: true,
        sync: _touchAfterCurrent(goal.sync),
      ),
    );
  }

  Future<void> markGoalComplete(String goalId) async {
    final goal = goalById(goalId);
    await saveGoal(
      goal.copyWith(
        status: GoalStatus.completed,
        completedAt: DateTime.now(),
        clearArchivedAt: true,
        sync: _touchAfterCurrent(goal.sync),
      ),
    );
  }

  Future<void> restoreGoal(String goalId) async {
    final goal = goalById(goalId);
    if (!goal.isCompleted && !goal.isArchived) return;
    final restored = goal.copyWith(
      status: GoalStatus.active,
      clearCompletedAt: true,
      clearArchivedAt: true,
      sync: _touchAfterCurrent(goal.sync),
    );
    _dataSet = _dataSet.copyWith(
      goals: _upsert(goals, restored, (item) => item.id),
    );
    await _commit(goal: restored);
  }

  Future<void> restoreArchivedGoal(String goalId) => restoreGoal(goalId);

  Future<GoalRecord> duplicateGoal(String goalId) async {
    final source = goalById(goalId);
    final accountId = source.defaultFundingAccountId;
    final canUseAccount =
        source.fundingMethod == GoalFundingMethod.accountFunded &&
        accountId != null &&
        accounts.any((account) => account.id == accountId && account.isVisible);
    return createGoal(
      name: '${source.name} Copy',
      targetAmountMinor: source.targetAmountMinor,
      startingAmountMinor: 0,
      targetDate: source.targetDate,
      fundingMethod: canUseAccount
          ? GoalFundingMethod.accountFunded
          : GoalFundingMethod.trackingOnly,
      goalType: source.goalType,
      defaultFundingAccountId: canUseAccount ? accountId : null,
      description: source.description,
      accentColorValue: source.accentColorValue,
    );
  }

  Future<void> deleteGoalPermanently(String goalId) async {
    final goal = goalById(goalId);
    final eligibility = goalDeleteEligibility(goalId);
    if (!eligibility.canDelete) {
      throw const FinanceDataValidationException(
        'This Goal cannot be permanently deleted because it has financial or scheduled activity. Archive it to preserve its history.',
      );
    }
    final deleted = goal.copyWith(sync: goal.sync.deleted(deviceId: deviceId));
    final goalAccount = goal.accountId == null
        ? null
        : accounts.where((account) => account.id == goal.accountId).firstOrNull;
    final hasAccountHistory =
        goalAccount != null &&
        transactions.any(
          (transaction) =>
              !transaction.isDeleted &&
              (transaction.accountId == goalAccount.id ||
                  transaction.transferAccountId == goalAccount.id),
        );
    final updatedAccount = goalAccount == null
        ? null
        : hasAccountHistory
        ? goalAccount.copyWith(
            clearGoalId: true,
            isDetachedGoalAccount: true,
            sync: goalAccount.sync.touched(deviceId: deviceId),
          )
        : goalAccount.copyWith(
            sync: goalAccount.sync.deleted(deviceId: deviceId),
          );
    _dataSet = _dataSet.copyWith(
      goals: _upsert(goals, deleted, (item) => item.id),
      accounts: updatedAccount == null
          ? accounts
          : _upsert(accounts, updatedAccount, (item) => item.id),
    );
    await _commit(
      goal: deleted,
      accounts: updatedAccount == null ? const [] : [updatedAccount],
    );
  }

  GoalRecord _goalWithDerivedLifecycleStatus(
    GoalRecord goal,
    int currentAmountMinor,
  ) {
    if (goal.status == GoalStatus.archived) return goal;
    if (goal.status == GoalStatus.completed) return goal;
    final derivedStatus =
        goal.goalType == GoalType.reachTarget &&
            currentAmountMinor >= goal.targetAmountMinor
        ? GoalStatus.completed
        : GoalStatus.active;
    if (goal.status == derivedStatus) return goal;
    return goal.copyWith(
      status: derivedStatus,
      completedAt: derivedStatus == GoalStatus.completed
          ? goal.completedAt ?? DateTime.now()
          : null,
      clearCompletedAt: derivedStatus != GoalStatus.completed,
      sync: _touchAfterCurrent(goal.sync),
    );
  }

  void _validateGoal(GoalRecord goal) {
    if (goal.name.trim().isEmpty) {
      throw const FinanceDataValidationException('Goal name is required.');
    }
    if (goal.targetAmountMinor <= 0) {
      throw const FinanceDataValidationException(
        'Goal target must be greater than zero.',
      );
    }
    if (goal.startingAmountMinor < 0) {
      throw const FinanceDataValidationException(
        'Goal starting amount cannot be negative.',
      );
    }
  }

  void _validateGoalContribution(
    GoalContributionRecord contribution,
    GoalRecord goal,
  ) {
    if (contribution.amountMinor <= 0) {
      throw const FinanceDataValidationException(
        'Contribution amount must be greater than zero.',
      );
    }
    if (contribution.fundingMethod != goal.fundingMethod) {
      throw const FinanceDataValidationException(
        'Contribution funding method does not match the Goal.',
      );
    }
    if (goal.fundingMethod != GoalFundingMethod.trackingOnly ||
        contribution.sourceAccountId != null) {
      throw const FinanceDataValidationException(
        'Tracking-only contributions cannot use an account.',
      );
    }
  }

  Future<void> saveScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    final existing = scheduledTransactions
        .where((item) => item.id == scheduledTransaction.id)
        .firstOrNull;
    if (existing != null) {
      scheduledTransaction = mergeScheduledTransactionAuthority(
        incoming: existing,
        current: scheduledTransaction,
        preferCurrentOnDefinitionTie: true,
      );
    }
    scheduledTransaction = _withStableScheduledSplitLineIds(
      scheduledTransaction,
    );
    _validateScheduledTransaction(scheduledTransaction);
    final notificationAdjusted = await _applyScheduledNotificationState(
      scheduledTransaction,
    );
    final updated = _upsert(
      scheduledTransactions,
      notificationAdjusted,
      (item) => item.id,
    );
    _dataSet = _dataSet.copyWith(scheduledTransactions: updated);
    await _commit(scheduledTransaction: notificationAdjusted);
    await refreshScheduledNotificationBadge();
  }

  Future<void> saveScheduledOccurrence({
    required ScheduledTransactionRecord scheduledTransaction,
    required ScheduledOccurrenceRecord occurrence,
  }) async {
    final current = scheduledTransactions
        .where((item) => item.id == scheduledTransaction.id)
        .firstOrNull;
    if (current == null) {
      throw const FinanceDataValidationException(
        'The scheduled transaction is unavailable.',
      );
    }
    var state = nextOccurrenceOperation(
      schedule: current,
      scheduledDate: occurrence.scheduledDate,
      plannedAmountMinor: occurrence.plannedAmountMinor,
      status: occurrence.status,
      actualAmountMinor: occurrence.actualAmountMinor,
      actualPaymentDate: occurrence.actualPaymentDate,
      transactionId: occurrence.transactionId,
      goalFundingEventId: occurrence.goalFundingEventId,
      deviceId: deviceId,
    );
    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote is ScheduledOccurrenceStateRepository && currentUserId != null) {
      try {
        state = await (remote as ScheduledOccurrenceStateRepository)
            .saveScheduledOccurrenceState(
              userId: currentUserId,
              scheduledTransactionId: scheduledTransaction.id,
              dayKey: occurrenceDayKey(occurrence.scheduledDate),
              occurrenceState: state,
            );
      } on Exception catch (error) {
        // Occurrence completion is a local user action first. A temporary
        // cloud failure must not leave its already-created Ledger transaction
        // separated from the Paid/Skipped schedule state. The local
        // authoritative occurrence is retained and the normal full-sync path
        // will retry its field-scoped occurrence write later.
        debugPrint(
          'Remote scheduled occurrence save failed; local change retained: '
          '$error',
        );
      }
    }
    var updated = withOccurrenceAuthority(
      scheduledTransaction,
      state,
      normalizeNextDate: true,
    );
    updated = _withStableScheduledSplitLineIds(updated);
    _validateScheduledTransaction(updated);
    final notificationAdjusted = await _applyScheduledNotificationState(
      updated,
    );
    _dataSet = _dataSet.copyWith(
      scheduledTransactions: _upsert(
        scheduledTransactions,
        notificationAdjusted,
        (item) => item.id,
      ),
    );
    await _commit(scheduledTransaction: notificationAdjusted);
    await refreshScheduledNotificationBadge();
  }

  Future<void> saveTransactionAndSchedule({
    required TransactionRecord transaction,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {
    transaction = _withStableTransactionSplitLineIds(transaction);
    scheduledTransaction = _withStableScheduledSplitLineIds(
      scheduledTransaction,
    );
    _validateTransaction(transaction);
    _validateScheduledTransaction(scheduledTransaction);
    final reservationMutation = _planReservationMutationForTransaction(
      transaction,
    );
    final previousDataSet = _dataSet;
    ScheduledTransactionRecord? notificationAdjusted;
    try {
      notificationAdjusted = await _applyScheduledNotificationState(
        scheduledTransaction,
      );
      _dataSet = _dataSet.copyWith(
        transactions: _upsert(transactions, transaction, (item) => item.id),
        scheduledTransactions: _upsert(
          scheduledTransactions,
          notificationAdjusted,
          (item) => item.id,
        ),
        reservationOperations: reservationMutation.allOperations,
      );
      await _commit(
        transaction: transaction,
        scheduledTransaction: notificationAdjusted,
        reservationOperations: reservationMutation.newOperations,
      );
      await refreshScheduledNotificationBadge();
    } catch (_) {
      _dataSet = previousDataSet;
      if (notificationAdjusted != null &&
          notificationAdjusted.scheduledNotificationIds.isNotEmpty) {
        await notificationScheduler.cancelScheduledTransaction(
          notificationAdjusted,
        );
      }
      notifyListeners();
      rethrow;
    }
  }

  ScheduledPaymentUndoTarget? scheduledPaymentUndoTarget(String transactionId) {
    final transaction = transactions
        .where((item) => item.id == transactionId && !item.isDeleted)
        .firstOrNull;
    if (transaction == null ||
        transaction.scheduledTransactionId == null ||
        transaction.scheduledOccurrenceDate == null ||
        transaction.scheduledPlannedAmountMinor == null) {
      return null;
    }
    final scheduledTransaction = scheduledTransactions
        .where((item) => item.id == transaction.scheduledTransactionId)
        .firstOrNull;
    if (scheduledTransaction == null) return null;
    final occurrence = scheduledTransaction.occurrences
        .where(
          (item) =>
              item.status == ScheduledOccurrenceStatus.paid &&
              item.transactionId == transaction.id &&
              isSameScheduledDay(
                item.scheduledDate,
                transaction.scheduledOccurrenceDate!,
              ),
        )
        .firstOrNull;
    if (occurrence == null) return null;
    final automaticallyClosed =
        scheduledTransaction.isDeleted &&
        scheduledTransaction.lastAction == ScheduledAction.paid;
    if (scheduledTransaction.isDeleted && !automaticallyClosed) return null;
    return ScheduledPaymentUndoTarget(
      transaction: transaction,
      scheduledTransaction: scheduledTransaction,
      occurrence: occurrence,
    );
  }

  Future<ScheduledPaymentUndoTarget> undoScheduledPayment(
    String transactionId, {
    DateTime? now,
  }) async {
    final target = scheduledPaymentUndoTarget(transactionId);
    if (target == null) {
      throw const FinanceDataValidationException(
        'This scheduled payment can no longer be safely undone.',
      );
    }
    final transaction = target.transaction;
    final scheduledTransaction = target.scheduledTransaction;
    final occurrence = target.occurrence;
    if (!hasActionableScheduledAccounts(scheduledTransaction)) {
      throw const FinanceDataValidationException(
        'The related account is unavailable. Restore the account before undoing this payment.',
      );
    }

    final anchor = now ?? DateTime.now();
    final today = DateTime(anchor.year, anchor.month, anchor.day);
    final occurrenceDay = DateTime(
      occurrence.scheduledDate.year,
      occurrence.scheduledDate.month,
      occurrence.scheduledDate.day,
    );
    final wasAutomaticallyClosed =
        scheduledTransaction.isDeleted &&
        scheduledTransaction.lastAction == ScheduledAction.paid;
    final shouldRestoreAsNext =
        wasAutomaticallyClosed ||
        (!occurrenceDay.isBefore(today) &&
            occurrenceDay.isBefore(scheduledTransaction.nextDate));
    var restoredState = nextOccurrenceOperation(
      schedule: scheduledTransaction,
      scheduledDate: occurrence.scheduledDate,
      plannedAmountMinor: occurrence.plannedAmountMinor,
      status: ScheduledOccurrenceStatus.pending,
      deviceId: deviceId,
    );
    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote is ScheduledOccurrenceStateRepository && currentUserId != null) {
      restoredState = await (remote as ScheduledOccurrenceStateRepository)
          .saveScheduledOccurrenceState(
            userId: currentUserId,
            scheduledTransactionId: scheduledTransaction.id,
            dayKey: occurrenceDayKey(occurrence.scheduledDate),
            occurrenceState: restoredState,
          );
    }
    final scheduleSync = scheduledTransaction.isDeleted
        ? scheduledTransaction.sync.restored(deviceId: deviceId)
        : scheduledTransaction.sync.touched(deviceId: deviceId);
    var restoredSchedule = withOccurrenceAuthority(
      scheduledTransaction.copyWith(
        nextDate: shouldRestoreAsNext
            ? occurrence.scheduledDate
            : scheduledTransaction.nextDate,
        lastAction: ScheduledAction.none,
        scheduledNotificationIds: const [],
        sync: scheduleSync,
        clearLastReminderScheduledAt: true,
      ),
      restoredState,
    );
    final reversedTransaction = transaction.copyWith(
      sync: transaction.sync.deleted(deviceId: deviceId),
    );
    _validateTransaction(reversedTransaction);
    _validateScheduledTransaction(restoredSchedule);
    final reservationMutation = _planReservationMutationForTransaction(
      reversedTransaction,
    );

    final previousDataSet = _dataSet;
    ScheduledTransactionRecord? notificationAdjusted;
    try {
      notificationAdjusted = await _applyScheduledNotificationState(
        restoredSchedule,
      );
      restoredSchedule = notificationAdjusted.copyWith(sync: scheduleSync);
      _dataSet = _dataSet.copyWith(
        transactions: _upsert(
          transactions,
          reversedTransaction,
          (item) => item.id,
        ),
        scheduledTransactions: _upsert(
          scheduledTransactions,
          restoredSchedule,
          (item) => item.id,
        ),
        reservationOperations: reservationMutation.allOperations,
      );
      await _commit(
        transaction: reversedTransaction,
        scheduledTransaction: restoredSchedule,
        reservationOperations: reservationMutation.newOperations,
      );
      await refreshScheduledNotificationBadge(now: anchor);
    } catch (_) {
      _dataSet = previousDataSet;
      if (notificationAdjusted != null &&
          notificationAdjusted.scheduledNotificationIds.isNotEmpty) {
        await notificationScheduler.cancelScheduledTransaction(
          notificationAdjusted,
        );
      }
      if (scheduledTransaction.scheduledNotificationIds.isNotEmpty) {
        try {
          await notificationScheduler.rescheduleScheduledTransaction(
            scheduledTransaction,
          );
        } catch (error) {
          debugPrint(
            'Could not restore the prior scheduled notification after an '
            'undo rollback: $error',
          );
        }
      }
      notifyListeners();
      rethrow;
    }
    return target;
  }

  Future<void> savePreferences(UserPreferences preferences) async {
    final notificationsChanged =
        _dataSet.preferences.notificationsEnabled !=
        preferences.notificationsEnabled;
    _dataSet = _dataSet.copyWith(preferences: preferences);
    await _commit(preferences: preferences);
    if (notificationsChanged) {
      await refreshScheduledNotifications();
    }
  }

  Future<void> refreshScheduledNotifications() async {
    var changed = false;
    final updated = <ScheduledTransactionRecord>[];
    for (final scheduledTransaction in scheduledTransactions) {
      final adjusted = await _applyScheduledNotificationState(
        scheduledTransaction,
      );
      updated.add(adjusted);
      changed = changed || !identical(adjusted, scheduledTransaction);
    }
    if (!changed) {
      await refreshScheduledNotificationBadge();
      return;
    }

    _dataSet = _dataSet.copyWith(scheduledTransactions: updated);
    await _commit();
    await refreshScheduledNotificationBadge();
  }

  Future<void> refreshScheduledNotificationBadge({DateTime? now}) async {
    final count = scheduledActiveAlertCount(now: now);
    await notificationScheduler.updateBadgeCount(count);
  }

  Future<ScheduledTransactionRecord> _applyScheduledNotificationState(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    final existing = _existingScheduledTransaction(scheduledTransaction.id);
    final storedState = await notificationStateRepository.load(
      scheduledTransaction.id,
    );
    final legacyIds = existing?.scheduledNotificationIds ?? const <int>[];
    final existingIds = storedState?.notificationIds.isNotEmpty == true
        ? storedState!.notificationIds
        : legacyIds;
    if (existingIds.isNotEmpty) {
      await notificationScheduler.cancelScheduledTransaction(
        scheduledTransaction.copyWith(
          scheduledNotificationIds: existingIds,
          sync: scheduledTransaction.sync,
        ),
      );
    }

    final shouldSchedule =
        preferences.notificationsEnabled &&
        !scheduledTransaction.isDeleted &&
        hasActionableScheduledAccounts(scheduledTransaction) &&
        scheduledTransaction.hasAlert &&
        effectiveNextActionableDate(scheduledTransaction) != null;
    if (!shouldSchedule) {
      await notificationStateRepository.remove(scheduledTransaction.id);
      if (scheduledTransaction.scheduledNotificationIds.isEmpty &&
          scheduledTransaction.lastReminderScheduledAt == null) {
        return scheduledTransaction;
      }
      return scheduledTransaction.copyWith(
        scheduledNotificationIds: const [],
        clearLastReminderScheduledAt: true,
        sync: scheduledTransaction.sync,
      );
    }

    final hasPermission = await notificationScheduler
        .requestPermissionIfNeeded();
    if (!hasPermission) {
      await notificationStateRepository.remove(scheduledTransaction.id);
      return scheduledTransaction.copyWith(
        scheduledNotificationIds: const [],
        clearLastReminderScheduledAt: true,
        sync: scheduledTransaction.sync,
      );
    }

    final notificationIds = await notificationScheduler
        .scheduleScheduledTransaction(scheduledTransaction);
    await notificationStateRepository.save(
      scheduledTransaction.id,
      DeviceScheduledNotificationState(
        notificationIds: notificationIds,
        lastScheduledAt: DateTime.now(),
      ),
    );
    return scheduledTransaction.copyWith(
      scheduledNotificationIds: const [],
      clearLastReminderScheduledAt: true,
      sync: scheduledTransaction.sync,
    );
  }

  ScheduledTransactionRecord? _existingScheduledTransaction(String id) {
    for (final scheduledTransaction in scheduledTransactions) {
      if (scheduledTransaction.id == id) return scheduledTransaction;
    }
    return null;
  }

  Future<void> saveTransaction(TransactionRecord transaction) async {
    final existing = transactions
        .where((item) => item.id == transaction.id)
        .firstOrNull;
    if (transaction.reservationContainerType != null ||
        transaction.reservationContainerId != null ||
        existing?.reservationContainerType != null ||
        existing?.reservationContainerId != null) {
      await saveTransactionWithReservation(transaction);
      return;
    }
    transaction = _withStableTransactionSplitLineIds(transaction);
    _validateTransaction(transaction);
    final before = _dataSet;
    final updated = _upsert(transactions, transaction, (item) => item.id);
    _dataSet = _dataSet.copyWith(transactions: updated);
    await _commit(transaction: transaction);
    _detectBudgetLowAlerts(before: before, after: _dataSet);
  }

  Future<void> saveTransactionWithReservation(
    TransactionRecord transaction,
  ) async {
    transaction = _withStableTransactionSplitLineIds(transaction);
    _validateTransaction(transaction);
    final mutation = _planReservationMutationForTransaction(transaction);
    final before = _dataSet;
    try {
      _dataSet = _dataSet.copyWith(
        transactions: _upsert(transactions, transaction, (item) => item.id),
        reservationOperations: mutation.allOperations,
      );
      await _commit(
        transaction: transaction,
        reservationOperations: mutation.newOperations,
      );
      _detectBudgetLowAlerts(before: before, after: _dataSet);
    } catch (_) {
      _dataSet = before;
      notifyListeners();
      rethrow;
    }
  }

  ({
    List<ReservationOperationRecord> allOperations,
    List<ReservationOperationRecord> newOperations,
  })
  _planReservationMutationForTransaction(TransactionRecord transaction) {
    final hasType = transaction.reservationContainerType != null;
    final hasId = transaction.reservationContainerId?.trim().isNotEmpty == true;
    if (hasType != hasId) {
      throw const FinanceDataValidationException(
        'Choose a complete Goal or Fund reservation.',
      );
    }

    final existing = transactions
        .where((item) => item.id == transaction.id)
        .firstOrNull;
    final priorConsumptions = _effectiveReservationConsumptionsForTransaction(
      transaction.id,
    );
    final outgoingAmount = transaction
        .deltaForAccount(transaction.accountId)
        .abs();
    final desiredMatchesExisting =
        !transaction.isDeleted &&
        priorConsumptions.length == 1 &&
        priorConsumptions.single.containerType ==
            transaction.reservationContainerType &&
        priorConsumptions.single.containerId ==
            transaction.reservationContainerId &&
        priorConsumptions.single.fundingAccountId == transaction.accountId &&
        priorConsumptions.single.amountMinor == outgoingAmount &&
        existing != null &&
        isSameScheduledDay(existing.date, transaction.date);
    if (desiredMatchesExisting) {
      return (
        allOperations: reservationOperations,
        newOperations: const <ReservationOperationRecord>[],
      );
    }

    var workingOperations = [...reservationOperations];
    final newOperations = <ReservationOperationRecord>[];
    for (final prior in priorConsumptions) {
      final reversal = _draftReservationOperation(
        operations: workingOperations,
        containerType: prior.containerType,
        containerId: prior.containerId,
        fundingAccountId: prior.fundingAccountId,
        kind: ReservationOperationKind.reversal,
        amountMinor: prior.amountMinor,
        effectiveDate: DateTime.now(),
        transactionId: transaction.id,
        reversesOperationId: prior.id,
        causationId: 'transaction-edit:${transaction.id}:reverse:${prior.id}',
        note: transaction.isDeleted
            ? 'Transaction deleted'
            : 'Transaction reservation changed',
      );
      workingOperations.add(reversal);
      newOperations.add(reversal);
    }

    if (!transaction.isDeleted && hasType) {
      if (outgoingAmount <= 0 ||
          transaction.deltaForAccount(transaction.accountId) >= 0) {
        throw const FinanceDataValidationException(
          'Only an outgoing transaction can be paid from a Goal or Fund.',
        );
      }
      final containerType = transaction.reservationContainerType!;
      final containerId = transaction.reservationContainerId!;
      final fundingAccountId = _reservationFundingAccountId(
        containerType,
        containerId,
      );
      if (fundingAccountId != transaction.accountId) {
        throw const FinanceDataValidationException(
          'The transaction must use the reservation funding account.',
        );
      }
      final ledger = calculateReservationLedger(
        operations: effectiveReservationOperationsForContainer(
          operations: workingOperations,
          transactions: transactions,
          containerType: containerType,
          containerId: containerId,
        ),
      );
      if (ledger.reservedMinor < outgoingAmount) {
        throw const FinanceDataValidationException(
          'This Goal or Fund does not contain enough reserved money.',
        );
      }
      final consumption = _draftReservationOperation(
        operations: workingOperations,
        containerType: containerType,
        containerId: containerId,
        fundingAccountId: fundingAccountId,
        kind: ReservationOperationKind.consume,
        amountMinor: outgoingAmount,
        effectiveDate: transaction.date,
        transactionId: transaction.id,
        scheduledTransactionId: transaction.scheduledTransactionId,
        scheduledOccurrenceDate: transaction.scheduledOccurrenceDate,
        causationId:
            'transaction:${transaction.id}:consume:${newReservationOperationId()}',
        note: transaction.note,
      );
      workingOperations.add(consumption);
      newOperations.add(consumption);
    }

    return (allOperations: workingOperations, newOperations: newOperations);
  }

  List<ReservationOperationRecord>
  _effectiveReservationConsumptionsForTransaction(String transactionId) {
    final results = <ReservationOperationRecord>[];
    final containerKeys = reservationOperations
        .where((operation) => operation.transactionId == transactionId)
        .map(
          (operation) =>
              '${operation.containerType.name}:${operation.containerId}',
        )
        .toSet();
    for (final key in containerKeys) {
      final parts = key.split(':');
      final type = ReservationContainerType.values.firstWhere(
        (value) => value.name == parts.first,
      );
      final id = parts.sublist(1).join(':');
      final activity = effectiveReservationOperationsForContainer(
        operations: reservationOperations,
        transactions: transactions,
        containerType: type,
        containerId: id,
      );
      final ledger = calculateReservationLedger(operations: activity);
      results.addAll(
        activity.where(
          (operation) =>
              operation.kind == ReservationOperationKind.consume &&
              operation.transactionId == transactionId &&
              ledger.acceptedOperationIds.contains(operation.id) &&
              !ledger.reversedOperationIds.contains(operation.id),
        ),
      );
    }
    return results;
  }

  ReservationOperationRecord _draftReservationOperation({
    required List<ReservationOperationRecord> operations,
    required ReservationContainerType containerType,
    required String containerId,
    required String fundingAccountId,
    required ReservationOperationKind kind,
    required int amountMinor,
    required DateTime effectiveDate,
    String? transactionId,
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    String? reversesOperationId,
    String? causationId,
    String note = '',
  }) {
    final ledger = calculateReservationLedger(
      operations: operations.where(
        (operation) =>
            operation.containerType == containerType &&
            operation.containerId == containerId,
      ),
    );
    final identity = newReservationOperationId();
    return ReservationOperationRecord(
      id: 'reservation_$identity',
      containerType: containerType,
      containerId: containerId,
      fundingAccountId: fundingAccountId,
      kind: kind,
      amountMinor: amountMinor.abs(),
      effectiveDate: DateTime(
        effectiveDate.year,
        effectiveDate.month,
        effectiveDate.day,
      ),
      revision: ledger.latestRevision + 1,
      baseRevision: ledger.latestRevision,
      operationId: identity,
      deviceId: deviceId,
      transactionId: transactionId,
      scheduledTransactionId: scheduledTransactionId,
      scheduledOccurrenceDate: scheduledOccurrenceDate,
      reversesOperationId: reversesOperationId,
      causationId: causationId,
      note: note.trim(),
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
  }

  Future<TransactionRecord> setTransactionStatus(
    String transactionId,
    TransactionStatus status,
  ) async {
    final transaction = transactions.firstWhere(
      (item) => item.id == transactionId && !item.isDeleted,
    );
    if (transaction.status == status) return transaction;
    final updated = transaction.copyWith(
      status: status,
      sync: transaction.sync.touched(deviceId: deviceId),
    );
    await saveTransaction(updated);
    return updated;
  }

  TransactionRecord _withStableTransactionSplitLineIds(
    TransactionRecord transaction,
  ) {
    final splitLines = _withStableSplitLineIds(
      ownerId: transaction.id,
      splitLines: transaction.splitLines,
    );
    return identical(splitLines, transaction.splitLines)
        ? transaction
        : transaction.copyWith(splitLines: splitLines);
  }

  ScheduledTransactionRecord _withStableScheduledSplitLineIds(
    ScheduledTransactionRecord scheduledTransaction,
  ) {
    final splitLines = _withStableSplitLineIds(
      ownerId: scheduledTransaction.id,
      splitLines: scheduledTransaction.splitLines,
    );
    return identical(splitLines, scheduledTransaction.splitLines)
        ? scheduledTransaction
        : scheduledTransaction.copyWith(splitLines: splitLines);
  }

  List<TransactionSplitLine> _withStableSplitLineIds({
    required String ownerId,
    required List<TransactionSplitLine> splitLines,
  }) {
    if (!splitLines.any((line) => line.id.trim().isEmpty)) {
      return splitLines;
    }
    final usedIds = splitLines
        .map((line) => line.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    return [
      for (var index = 0; index < splitLines.length; index++)
        if (splitLines[index].id.trim().isNotEmpty)
          splitLines[index]
        else
          TransactionSplitLine(
            id: _availableSplitLineId(
              ownerId: ownerId,
              index: index,
              usedIds: usedIds,
            ),
            categoryId: splitLines[index].categoryId,
            amountMinor: splitLines[index].amountMinor,
            note: splitLines[index].note,
          ),
    ];
  }

  String _availableSplitLineId({
    required String ownerId,
    required int index,
    required Set<String> usedIds,
  }) {
    final baseId = 'split_${ownerId}_$index';
    var candidate = baseId;
    var collisionIndex = 1;
    while (!usedIds.add(candidate)) {
      candidate = '${baseId}_$collisionIndex';
      collisionIndex += 1;
    }
    return candidate;
  }

  void dismissBudgetLowAlert() {
    if (_pendingBudgetLowAlerts.isEmpty) return;
    _pendingBudgetLowAlerts.removeAt(0);
    budgetLowAlertNotifier.value = _pendingBudgetLowAlerts.firstOrNull;
  }

  void _detectBudgetLowAlerts({
    required FinanceDataSet before,
    required FinanceDataSet after,
  }) {
    final now = DateTime.now();
    final calculator = const BudgetCalculator();
    for (final budget in after.budgets) {
      if (!budget.isVisible || !budget.lowBudgetAlertEnabled) continue;
      final beforeBudget = before.budgets
          .where((item) => item.id == budget.id)
          .firstOrNull;
      if (beforeBudget == null || !beforeBudget.isVisible) continue;

      final previous = calculator.calculate(
        budget: beforeBudget,
        transactions: before.transactions,
        categories: before.categories,
        date: now,
      );
      final current = calculator.calculate(
        budget: budget,
        transactions: after.transactions,
        categories: after.categories,
        date: now,
      );
      if (current.configuration.amountMinor <= 0 ||
          !_isAboveLowBudgetThreshold(beforeBudget, previous) ||
          !_isAtOrBelowLowBudgetThreshold(budget, current)) {
        continue;
      }
      _pendingBudgetLowAlerts.add(
        BudgetLowAlert(
          budgetId: budget.id,
          budgetName: budget.name,
          remainingMinor: current.remainingMinor < 0
              ? 0
              : current.remainingMinor,
          periodStart: current.window.start,
        ),
      );
    }
    if (budgetLowAlertNotifier.value == null &&
        _pendingBudgetLowAlerts.isNotEmpty) {
      budgetLowAlertNotifier.value = _pendingBudgetLowAlerts.first;
    }
  }

  bool _isAboveLowBudgetThreshold(
    BudgetRecord budget,
    BudgetPeriodResult result,
  ) => !_isAtOrBelowLowBudgetThreshold(budget, result);

  bool _isAtOrBelowLowBudgetThreshold(
    BudgetRecord budget,
    BudgetPeriodResult result,
  ) {
    if (result.availableMinor <= 0) return result.remainingMinor <= 0;
    return result.remainingMinor * 10000 <=
        result.availableMinor * budget.lowBudgetAlertThresholdBasisPoints;
  }

  Future<TransactionRecord> addExpense({
    required String accountId,
    required String categoryId,
    required DateTime date,
    required String payee,
    required int amountMinor,
    String note = '',
    List<TransactionSplitLine> splitLines = const [],
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    int? scheduledPlannedAmountMinor,
    TransactionStatus status = TransactionStatus.cleared,
    ReservationContainerType? reservationContainerType,
    String? reservationContainerId,
  }) async {
    final transaction = TransactionRecord(
      id: _newId('txn'),
      type: TransactionType.expense,
      accountId: accountId,
      categoryId: categoryId,
      date: date,
      payee: payee,
      amountMinor: amountMinor.abs(),
      note: note,
      splitLines: splitLines,
      scheduledTransactionId: scheduledTransactionId,
      scheduledOccurrenceDate: scheduledOccurrenceDate,
      scheduledPlannedAmountMinor: scheduledPlannedAmountMinor,
      status: status,
      reservationContainerType: reservationContainerType,
      reservationContainerId: reservationContainerId,
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    await saveTransaction(transaction);
    return transaction;
  }

  Future<TransactionRecord> addIncome({
    required String accountId,
    required String categoryId,
    required DateTime date,
    required String payee,
    required int amountMinor,
    String note = '',
    List<TransactionSplitLine> splitLines = const [],
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    int? scheduledPlannedAmountMinor,
    TransactionStatus status = TransactionStatus.cleared,
  }) async {
    final transaction = TransactionRecord(
      id: _newId('txn'),
      type: TransactionType.income,
      accountId: accountId,
      categoryId: categoryId,
      date: date,
      payee: payee,
      amountMinor: amountMinor.abs(),
      note: note,
      splitLines: splitLines,
      scheduledTransactionId: scheduledTransactionId,
      scheduledOccurrenceDate: scheduledOccurrenceDate,
      scheduledPlannedAmountMinor: scheduledPlannedAmountMinor,
      status: status,
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    await saveTransaction(transaction);
    return transaction;
  }

  Future<TransactionRecord> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required DateTime date,
    required String payee,
    required int amountMinor,
    String note = '',
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    int? scheduledPlannedAmountMinor,
    TransactionStatus status = TransactionStatus.cleared,
    ReservationContainerType? reservationContainerType,
    String? reservationContainerId,
  }) async {
    final transaction = TransactionRecord(
      id: _newId('txn'),
      type: TransactionType.transfer,
      accountId: fromAccountId,
      transferAccountId: toAccountId,
      date: date,
      payee: payee,
      amountMinor: amountMinor.abs(),
      note: note,
      scheduledTransactionId: scheduledTransactionId,
      scheduledOccurrenceDate: scheduledOccurrenceDate,
      scheduledPlannedAmountMinor: scheduledPlannedAmountMinor,
      status: status,
      reservationContainerType: reservationContainerType,
      reservationContainerId: reservationContainerId,
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    await saveTransaction(transaction);
    return transaction;
  }

  Future<TransactionRecord> adjustAccountBalance({
    required String accountId,
    required int targetBalanceMinor,
    required DateTime date,
    String payee = 'Balance adjustment',
    String note = '',
  }) async {
    final currentBalance = balanceForAccount(accountId);
    final delta = targetBalanceMinor - currentBalance;
    final transaction = TransactionRecord(
      id: _newId('adj'),
      type: TransactionType.adjustment,
      accountId: accountId,
      date: date,
      payee: payee,
      amountMinor: delta,
      note: note,
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    await saveTransaction(transaction);
    return transaction;
  }

  void _validateTransaction(TransactionRecord transaction) {
    final accountExists = accounts.any(
      (account) => account.id == transaction.accountId,
    );
    if (!accountExists) {
      throw FinanceDataValidationException(
        'Transaction account does not exist: ${transaction.accountId}',
      );
    }

    if (transaction.type == TransactionType.transfer) {
      final transferAccountId = transaction.transferAccountId;
      if (transferAccountId == null || transferAccountId.isEmpty) {
        throw const FinanceDataValidationException(
          'Transfer requires a destination account.',
        );
      }
      if (transferAccountId == transaction.accountId) {
        throw const FinanceDataValidationException(
          'Transfer source and destination accounts must be different.',
        );
      }
      final destinationExists = accounts.any(
        (account) => account.id == transferAccountId,
      );
      if (!destinationExists) {
        throw FinanceDataValidationException(
          'Transfer destination account does not exist: $transferAccountId',
        );
      }
    }

    final sourceAccount = accounts.firstWhere(
      (account) => account.id == transaction.accountId,
    );
    if (sourceAccount.isGoalAccount &&
        (transaction.type == TransactionType.expense ||
            transaction.type == TransactionType.transfer)) {
      final existing = transactions
          .where((item) => item.id == transaction.id && !item.isDeleted)
          .firstOrNull;
      final balanceBeforeEdit =
          balanceForAccount(sourceAccount.id) -
          (existing?.deltaForAccount(sourceAccount.id) ?? 0);
      if (balanceBeforeEdit + transaction.deltaForAccount(sourceAccount.id) <
          0) {
        throw FinanceDataValidationException(
          '${sourceAccount.name} does not have enough available Goal funds.',
        );
      }
    }

    if (transaction.type != TransactionType.transfer &&
        transaction.type != TransactionType.adjustment &&
        transaction.type != TransactionType.goalFunding) {
      final categoryId = transaction.categoryId;
      if (categoryId == null || categoryId.isEmpty) {
        throw const FinanceDataValidationException(
          'Income and expense transactions require a category.',
        );
      }
      final categoryExists = categories.any(
        (category) => category.id == categoryId,
      );
      if (!categoryExists) {
        throw FinanceDataValidationException(
          'Transaction category does not exist: $categoryId',
        );
      }
    }

    if (!transaction.hasValidSplitTotal) {
      throw FinanceDataValidationException(
        'Split total ${transaction.splitTotalMinor} does not match transaction amount ${transaction.amountMinor.abs()}.',
      );
    }
  }

  void _validateScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) {
    if (scheduledTransaction.type == TransactionType.transfer) {
      if (scheduledTransaction.splitLines.isNotEmpty) {
        throw const FinanceDataValidationException(
          'Transfers cannot contain category splits.',
        );
      }
      return;
    }
    if (scheduledTransaction.type == TransactionType.goalFunding) {
      if (scheduledTransaction.transferAccountId != null ||
          scheduledTransaction.categoryId != null ||
          scheduledTransaction.splitLines.isNotEmpty ||
          !scheduledTransaction.hasValidGoalFundingAllocations) {
        throw const FinanceDataValidationException(
          'Scheduled Goal Funding requires balanced Goal allocations only.',
        );
      }
      final accountExists = accounts.any(
        (account) =>
            account.id == scheduledTransaction.accountId && account.isVisible,
      );
      if (!accountExists) {
        throw const FinanceDataValidationException(
          'Scheduled Goal Funding requires an active source account.',
        );
      }
      return;
    }
    if (scheduledTransaction.type == TransactionType.adjustment) return;

    final splitLines = scheduledTransaction.splitLines;
    if (splitLines.isEmpty) {
      final categoryId = scheduledTransaction.categoryId;
      if (categoryId == null || categoryId.isEmpty) {
        // Legacy scheduled records may have no category payload. The polished
        // editor repairs those records before a user saves them, while
        // allowing unrelated actions such as delete, skip, and history reset
        // to continue working without a broad migration.
        return;
      }
      final categoryExists = categories.any(
        (category) => category.id == categoryId,
      );
      if (!categoryExists) {
        throw FinanceDataValidationException(
          'Scheduled transaction category does not exist: $categoryId',
        );
      }
      return;
    }

    final categoryId = scheduledTransaction.categoryId;
    if (categoryId == null || categoryId.isEmpty) {
      throw const FinanceDataValidationException(
        'Scheduled income and expense transactions require a category.',
      );
    }
    final eligibleCategoryIds = categories
        .where((category) => category.isVisible)
        .map((category) => category.id)
        .toSet();
    if (!eligibleCategoryIds.contains(categoryId)) {
      throw FinanceDataValidationException(
        'Scheduled transaction category does not exist: $categoryId',
      );
    }

    if (!scheduledTransaction.hasValidSplitTotal) {
      throw FinanceDataValidationException(
        'Scheduled split total ${scheduledTransaction.splitTotalMinor} does not match amount ${scheduledTransaction.amountMinor.abs()}.',
      );
    }
    final categoryIds = <String>{};
    for (final line in splitLines) {
      if (line.amountMinor <= 0) {
        throw const FinanceDataValidationException(
          'Scheduled split amounts must be greater than zero.',
        );
      }
      if (!eligibleCategoryIds.contains(line.categoryId)) {
        throw FinanceDataValidationException(
          'Scheduled split category does not exist: ${line.categoryId}',
        );
      }
      if (!categoryIds.add(line.categoryId)) {
        throw const FinanceDataValidationException(
          'Scheduled split categories cannot be duplicated.',
        );
      }
    }
    if (splitLines.first.categoryId != categoryId) {
      throw const FinanceDataValidationException(
        'Scheduled primary category must match the first split.',
      );
    }
  }

  Future<void> _commit({
    List<AccountRecord> accounts = const [],
    CategoryRecord? category,
    TransactionRecord? transaction,
    List<TransactionRecord> transactions = const [],
    ScheduledTransactionRecord? scheduledTransaction,
    List<ScheduledTransactionRecord> scheduledTransactions = const [],
    BudgetRecord? budget,
    GoalRecord? goal,
    List<GoalRecord> goalRecords = const [],
    GoalContributionRecord? goalContribution,
    List<GoalContributionRecord> goalContributions = const [],
    List<GoalFundingEventRecord> goalFundingEvents = const [],
    List<FundRecord> funds = const [],
    List<ReservationOperationRecord> reservationOperations = const [],
    UserPreferences? preferences,
  }) async {
    notifyListeners();
    await localRepository?.save(_dataSet);
    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote != null && currentUserId != null) {
      try {
        for (final account in accounts) {
          await remote.saveAccount(userId: currentUserId, account: account);
        }
        if (category != null) {
          await remote.saveCategory(userId: currentUserId, category: category);
        }
        if (transaction != null) {
          await remote.saveTransaction(
            userId: currentUserId,
            transaction: transaction,
          );
        }
        for (final transactionRecord in transactions) {
          await remote.saveTransaction(
            userId: currentUserId,
            transaction: transactionRecord,
          );
        }
        if (scheduledTransaction != null) {
          await remote.saveScheduledTransaction(
            userId: currentUserId,
            scheduledTransaction: scheduledTransaction,
          );
        }
        for (final scheduledTransactionRecord in scheduledTransactions) {
          await remote.saveScheduledTransaction(
            userId: currentUserId,
            scheduledTransaction: scheduledTransactionRecord,
          );
        }
        if (budget != null) {
          await remote.saveBudget(userId: currentUserId, budget: budget);
        }
        if (goal != null) {
          await remote.saveGoal(userId: currentUserId, goal: goal);
        }
        for (final goalRecord in goalRecords) {
          await remote.saveGoal(userId: currentUserId, goal: goalRecord);
        }
        if (goalContribution != null) {
          await remote.saveGoalContribution(
            userId: currentUserId,
            contribution: goalContribution,
          );
        }
        for (final contribution in goalContributions) {
          await remote.saveGoalContribution(
            userId: currentUserId,
            contribution: contribution,
          );
        }
        for (final fundingEvent in goalFundingEvents) {
          await remote.saveGoalFundingEvent(
            userId: currentUserId,
            fundingEvent: fundingEvent,
          );
        }
        if (remote
            case final ReservationRecordRepository reservationRepository) {
          for (final fund in funds) {
            await reservationRepository.saveFund(
              userId: currentUserId,
              fund: fund,
            );
          }
          for (final operation in reservationOperations) {
            await reservationRepository.saveReservationOperation(
              userId: currentUserId,
              operation: operation,
            );
          }
        }
        if (preferences != null) {
          await remote.savePreferences(
            userId: currentUserId,
            preferences: preferences,
          );
        }
      } on Exception catch (error) {
        debugPrint('Remote finance save failed; local change retained: $error');
      }
    }
  }

  Future<void> moveAccountGroup({
    required AccountGroup group,
    required int direction,
  }) async {
    final groups = accountGroupsInDisplayOrder;
    final fromIndex = groups.indexOf(group);
    final toIndex = fromIndex + direction;
    if (fromIndex < 0 || toIndex < 0 || toIndex >= groups.length) return;

    final reordered = [...groups];
    final moving = reordered.removeAt(fromIndex);
    reordered.insert(toIndex, moving);
    await savePreferences(
      preferences.copyWith(
        accountGroupOrderNames: [
          for (final reorderedGroup in reordered) reorderedGroup.name,
        ],
      ),
    );
  }

  Future<void> renameAccountGroup({
    required AccountGroup group,
    required String label,
  }) async {
    final trimmed = label.trim();
    final overrides = {...preferences.accountGroupLabelOverrides};
    if (trimmed.isEmpty || trimmed == group.defaultLabel) {
      overrides.remove(group.name);
    } else {
      overrides[group.name] = trimmed;
    }
    await savePreferences(
      preferences.copyWith(accountGroupLabelOverrides: overrides),
    );
  }

  List<T> _upsert<T>(List<T> items, T value, String Function(T) idOf) {
    final id = idOf(value);
    var found = false;
    final updated = <T>[];
    for (final item in items) {
      if (idOf(item) == id) {
        updated.add(value);
        found = true;
      } else {
        updated.add(item);
      }
    }
    if (!found) updated.add(value);
    return updated;
  }

  String _newId(String prefix) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }
}

class AccountLinkedRecordSummary {
  const AccountLinkedRecordSummary({
    required this.transactionCount,
    required this.scheduledTransactionCount,
    required this.goalFundingEventCount,
    required this.defaultGoalCount,
  });

  final int transactionCount;
  final int scheduledTransactionCount;
  final int goalFundingEventCount;
  final int defaultGoalCount;

  bool get hasLinks =>
      transactionCount > 0 ||
      scheduledTransactionCount > 0 ||
      goalFundingEventCount > 0 ||
      defaultGoalCount > 0;
}

/// A Goal presentation may be removed after its money and live schedule work
/// have been resolved. Historical ledger records remain audit data and do not
/// themselves keep a zero-balance Goal trapped on the inactive screen.
class GoalDeleteEligibility {
  const GoalDeleteEligibility({
    required this.hasContributions,
    required this.hasFunding,
    required this.hasScheduledReference,
    this.hasNonZeroBalance = false,
    this.remainingBalanceMinor = 0,
  });

  final bool hasContributions;
  final bool hasFunding;
  final bool hasScheduledReference;
  final bool hasNonZeroBalance;
  final int remainingBalanceMinor;

  bool get canDelete => !hasScheduledReference && !hasNonZeroBalance;
}

class FundDeleteEligibility {
  const FundDeleteEligibility({
    required this.hasScheduledReference,
    required this.hasNonZeroBalance,
    required this.remainingBalanceMinor,
  });

  final bool hasScheduledReference;
  final bool hasNonZeroBalance;
  final int remainingBalanceMinor;

  bool get canDelete => !hasScheduledReference && !hasNonZeroBalance;
}

int compareAccountDisplayOrder(
  AccountRecord a,
  AccountRecord b, {
  Map<AccountGroup, int> groupOrder = const {},
}) {
  final groupComparison = (groupOrder[a.group] ?? a.group.index).compareTo(
    groupOrder[b.group] ?? b.group.index,
  );
  if (groupComparison != 0) return groupComparison;
  final sortComparison = a.sortOrder.compareTo(b.sortOrder);
  if (sortComparison != 0) return sortComparison;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

DateTime? firstUnresolvedScheduledDate(
  ScheduledTransactionRecord scheduledTransaction, {
  required DateTime today,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final resolvedDates = scheduledTransaction.occurrences
      .where(
        (occurrence) => occurrence.status != ScheduledOccurrenceStatus.pending,
      )
      .map((occurrence) => scheduledDayKey(occurrence.scheduledDate))
      .toSet();
  var candidate = DateTime(
    scheduledTransaction.nextDate.year,
    scheduledTransaction.nextDate.month,
    scheduledTransaction.nextDate.day,
  );

  // The cap is defensive for malformed legacy records. Monthly records can
  // still advance for centuries without locking the UI.
  for (var iteration = 0; iteration < 12000; iteration += 1) {
    final endDate = scheduledTransaction.endDate;
    if (endDate != null && candidate.isAfter(endDate)) return null;
    if (!candidate.isBefore(day) &&
        !resolvedDates.contains(scheduledDayKey(candidate))) {
      return candidate;
    }
    final next = nextScheduledRecurrenceDate(
      candidate,
      scheduledTransaction.frequency,
    );
    if (next == null || !next.isAfter(candidate)) return null;
    candidate = next;
  }
  return null;
}

DateTime? nextScheduledRecurrenceDate(
  DateTime date,
  RecurrenceFrequency frequency,
) {
  return switch (frequency) {
    RecurrenceFrequency.once => null,
    RecurrenceFrequency.weekly => date.add(const Duration(days: 7)),
    RecurrenceFrequency.biweekly => date.add(const Duration(days: 14)),
    RecurrenceFrequency.monthly => DateTime(
      date.year,
      date.month + 1,
      date.day,
    ),
    RecurrenceFrequency.yearly => DateTime(date.year + 1, date.month, date.day),
  };
}

bool isSameScheduledDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String scheduledDayKey(DateTime date) =>
    '${date.year}-${date.month}-${date.day}';

bool isScheduledDueOrOverdue(
  ScheduledTransactionRecord scheduledTransaction,
  DateTime now,
) {
  if (scheduledTransaction.isDeleted ||
      scheduledTransaction.lastAction != ScheduledAction.none) {
    return false;
  }
  final today = DateTime(now.year, now.month, now.day);
  final dueDate = DateTime(
    scheduledTransaction.nextDate.year,
    scheduledTransaction.nextDate.month,
    scheduledTransaction.nextDate.day,
  );
  return !dueDate.isAfter(today);
}

class ScheduledPaymentUndoTarget {
  const ScheduledPaymentUndoTarget({
    required this.transaction,
    required this.scheduledTransaction,
    required this.occurrence,
  });

  final TransactionRecord transaction;
  final ScheduledTransactionRecord scheduledTransaction;
  final ScheduledOccurrenceRecord occurrence;
}

FinanceDataSet mergeFinanceDataSetsPreferCurrent({
  required FinanceDataSet incoming,
  required FinanceDataSet current,
}) {
  return incoming.copyWith(
    accounts: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.accounts,
      current: current.accounts,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    categories: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.categories,
      current: current.categories,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    transactions: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.transactions,
      current: current.transactions,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    scheduledTransactions: mergeScheduledTransactions(
      incoming: incoming.scheduledTransactions,
      current: current.scheduledTransactions,
      preferCurrentOnDefinitionTie: true,
    ),
    budgets: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.budgets,
      current: current.budgets,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    goals: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.goals,
      current: current.goals,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    goalContributions: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.goalContributions,
      current: current.goalContributions,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    goalFundingEvents: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.goalFundingEvents,
      current: current.goalFundingEvents,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    funds: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.funds,
      current: current.funds,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    reservationOperations: mergeImmutableReservationOperations(
      incoming: incoming.reservationOperations,
      current: current.reservationOperations,
    ),
    preferences: current.preferences,
  );
}

/// Used only for the first cloud sync after a local v1 import. The remote
/// data set is already v2, so it is authoritative for every matching record;
/// locally imported legacy records may only fill missing IDs.
FinanceDataSet mergeFinanceDataSetsPreferIncoming({
  required FinanceDataSet incoming,
  required FinanceDataSet current,
}) {
  return incoming.copyWith(
    accounts: mergeFinanceRecordsPreferIncoming(
      incoming: incoming.accounts,
      current: current.accounts,
      idOf: (item) => item.id,
    ),
    categories: mergeFinanceRecordsPreferIncoming(
      incoming: incoming.categories,
      current: current.categories,
      idOf: (item) => item.id,
    ),
    transactions: mergeFinanceRecordsPreferIncoming(
      incoming: incoming.transactions,
      current: current.transactions,
      idOf: (item) => item.id,
    ),
    scheduledTransactions: mergeScheduledTransactions(
      incoming: incoming.scheduledTransactions,
      current: current.scheduledTransactions,
      preferCurrentOnDefinitionTie: false,
    ),
    budgets: mergeFinanceRecordsPreferIncoming(
      incoming: incoming.budgets,
      current: current.budgets,
      idOf: (item) => item.id,
    ),
    goals: mergeFinanceRecordsPreferIncoming(
      incoming: incoming.goals,
      current: current.goals,
      idOf: (item) => item.id,
    ),
    goalContributions: mergeFinanceRecordsPreferIncoming(
      incoming: incoming.goalContributions,
      current: current.goalContributions,
      idOf: (item) => item.id,
    ),
    goalFundingEvents: mergeFinanceRecordsPreferIncoming(
      incoming: incoming.goalFundingEvents,
      current: current.goalFundingEvents,
      idOf: (item) => item.id,
    ),
    funds: mergeFinanceRecordsPreferIncoming(
      incoming: incoming.funds,
      current: current.funds,
      idOf: (item) => item.id,
    ),
    reservationOperations: mergeImmutableReservationOperations(
      incoming: incoming.reservationOperations,
      current: current.reservationOperations,
    ),
    preferences: incoming.preferences.copyWith(
      legacyV1MigrationCompleted: true,
    ),
  );
}

/// Reservation operations are immutable facts, not last-write-wins records.
///
/// The cloud copy is authoritative for an already-published operation ID and
/// each device contributes only operation IDs the cloud has not seen yet.
/// This makes sync an idempotent set union: an absent/stale device cannot
/// erase another device's allocation, return, consumption, or reversal.
List<ReservationOperationRecord> mergeImmutableReservationOperations({
  required List<ReservationOperationRecord> incoming,
  required List<ReservationOperationRecord> current,
}) {
  final incomingIds = incoming.map((operation) => operation.id).toSet();
  return [
    ...incoming,
    for (final operation in current)
      if (!incomingIds.contains(operation.id)) operation,
  ];
}

List<T> mergeFinanceRecordsPreferCurrent<T>({
  required List<T> incoming,
  required List<T> current,
  required String Function(T item) idOf,
  required SyncMetadata Function(T item) syncOf,
}) {
  final currentById = {for (final item in current) idOf(item): item};
  final incomingIds = incoming.map(idOf).toSet();
  return [
    for (final item in incoming)
      if (currentById[idOf(item)] case final currentItem?)
        preferCurrentFinanceRecord(
          incoming: item,
          current: currentItem,
          syncOf: syncOf,
        )
      else
        item,
    for (final item in current)
      if (!incomingIds.contains(idOf(item))) item,
  ];
}

List<T> mergeFinanceRecordsPreferIncoming<T>({
  required List<T> incoming,
  required List<T> current,
  required String Function(T item) idOf,
}) {
  final incomingIds = incoming.map(idOf).toSet();
  return [
    ...incoming,
    for (final item in current)
      if (!incomingIds.contains(idOf(item))) item,
  ];
}

List<ScheduledTransactionRecord> mergeScheduledTransactions({
  required List<ScheduledTransactionRecord> incoming,
  required List<ScheduledTransactionRecord> current,
  required bool preferCurrentOnDefinitionTie,
}) {
  final currentById = {for (final item in current) item.id: item};
  final incomingIds = incoming.map((item) => item.id).toSet();
  return [
    for (final item in incoming)
      if (currentById[item.id] case final currentItem?)
        mergeScheduledTransactionAuthority(
          incoming: item,
          current: currentItem,
          preferCurrentOnDefinitionTie: preferCurrentOnDefinitionTie,
        )
      else
        item,
    for (final item in current)
      if (!incomingIds.contains(item.id)) item,
  ];
}

T preferCurrentFinanceRecord<T>({
  required T incoming,
  required T current,
  required SyncMetadata Function(T item) syncOf,
}) {
  final currentSync = syncOf(current);
  final incomingSync = syncOf(incoming);
  if (currentSync.isDeleted) return current;
  if (incomingSync.isDeleted) return incoming;
  return currentSync.updatedAt.isAfter(incomingSync.updatedAt) ||
          currentSync.updatedAt.isAtSameMomentAs(incomingSync.updatedAt)
      ? current
      : incoming;
}

bool financeDataSetHasRecords(FinanceDataSet dataSet) {
  return dataSet.accounts.isNotEmpty ||
      dataSet.categories.isNotEmpty ||
      dataSet.transactions.isNotEmpty ||
      dataSet.scheduledTransactions.isNotEmpty ||
      dataSet.budgets.isNotEmpty ||
      dataSet.goals.isNotEmpty ||
      dataSet.goalContributions.isNotEmpty ||
      dataSet.goalFundingEvents.isNotEmpty ||
      dataSet.funds.isNotEmpty ||
      dataSet.reservationOperations.isNotEmpty;
}
