import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/goal.dart';
import '../domain/goal_funding.dart';
import '../domain/scheduled_transaction.dart';
import '../domain/sync_metadata.dart';
import '../domain/transaction.dart';
import '../domain/user_preferences.dart';
import '../goals/goal_calculator.dart';
import '../notifications/notification_scheduler.dart';
import '../persistence/finance_record_repository.dart';
import '../persistence/local_finance_data_set_repository.dart';

class FinanceDataValidationException implements Exception {
  const FinanceDataValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FinanceDataStore extends ChangeNotifier {
  factory FinanceDataStore({
    required FinanceDataSet dataSet,
    LocalFinanceDataSetRepository? localRepository,
    FinanceRecordRepository? remoteRepository,
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler(),
    String? userId,
    String deviceId = 'local',
  }) {
    return FinanceDataStore._(
      dataSet,
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      notificationScheduler: notificationScheduler,
      userId: userId,
      deviceId: deviceId,
    );
  }

  FinanceDataStore._(
    this._dataSet, {
    this.localRepository,
    this.remoteRepository,
    this.notificationScheduler = const NoopNotificationScheduler(),
    this.userId,
    this.deviceId = 'local',
  });

  factory FinanceDataStore.empty({
    LocalFinanceDataSetRepository? localRepository,
    FinanceRecordRepository? remoteRepository,
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler(),
    String? userId,
    String deviceId = 'local',
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
  }) async {
    final localData = await localRepository.load();
    return FinanceDataStore(
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
    );
  }

  FinanceDataSet _dataSet;
  final LocalFinanceDataSetRepository? localRepository;
  FinanceRecordRepository? remoteRepository;
  final NotificationScheduler notificationScheduler;
  String? userId;
  final String deviceId;

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
  UserPreferences get preferences => _dataSet.preferences;

  List<AccountRecord> get activeAccountsInDisplayOrder {
    final groupOrder = accountGroupDisplayOrderIndexes;
    return accounts
        .where((account) => account.isVisible)
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
        if (!goal.isDeleted && !goal.requiresFundingMigration) goal.id,
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
    return const GoalCalculator().currentAmountMinor(
      goal,
      goalContributions,
      goalFundingEvents,
    );
  }

  GoalProgressMetrics goalMetrics(String goalId, {DateTime? now}) {
    return const GoalCalculator().calculate(
      goalById(goalId),
      goalContributions,
      fundingEvents: goalFundingEvents,
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
    return firstUnresolvedScheduledDate(
      scheduledTransaction,
      today: now ?? DateTime.now(),
    );
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
    final anchor = now ?? DateTime.now();
    final periodStart = DateTime(anchor.year, anchor.month);
    final periodEnd = DateTime(anchor.year, anchor.month + 1);
    final categoryIds = _categoryAndDescendantIds(budget.categoryIds);

    return transactions
        .where((transaction) {
          return !transaction.isDeleted &&
              transaction.type == TransactionType.expense &&
              !transaction.date.isBefore(periodStart) &&
              transaction.date.isBefore(periodEnd);
        })
        .fold(0, (total, transaction) {
          if (transaction.isSplit) {
            final splitSpent = transaction.splitLines
                .where((line) => categoryIds.contains(line.categoryId))
                .fold(
                  0,
                  (splitTotal, line) => splitTotal + line.amountMinor.abs(),
                );
            return total + splitSpent;
          }
          return categoryIds.contains(transaction.categoryId)
              ? total + transaction.amountMinor.abs()
              : total;
        });
  }

  Set<String> _categoryAndDescendantIds(Iterable<String> rootCategoryIds) {
    final categoryIds = rootCategoryIds.toSet();
    var changed = true;
    while (changed) {
      changed = false;
      for (final category in categories) {
        final parentId = category.parentCategoryId;
        if (parentId != null &&
            categoryIds.contains(parentId) &&
            categoryIds.add(category.id)) {
          changed = true;
        }
      }
    }
    return categoryIds;
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
    _dataSet = dataSet;
    if (persistLocal) {
      await localRepository?.save(_dataSet);
    }
    await refreshScheduledNotificationBadge();
    notifyListeners();
  }

  Future<void> attachRemoteSync({
    required FinanceRecordRepository remoteRepository,
    required String userId,
  }) async {
    this.remoteRepository = remoteRepository;
    this.userId = userId;

    final remoteDataSet = await remoteRepository.loadDataSet(userId);
    if (financeDataSetHasRecords(remoteDataSet)) {
      final merged = mergeFinanceDataSetsPreferCurrent(
        incoming: remoteDataSet,
        current: _dataSet,
      );
      await replaceDataSet(merged);
      await pushAllRecordsToRemote();
      return;
    }

    await pushAllRecordsToRemote();
  }

  void detachRemoteSync() {
    remoteRepository = null;
    userId = null;
  }

  Future<void> pushAllRecordsToRemote() async {
    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote == null || currentUserId == null) return;

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
    final account = accountById(accountId).copyWith(isArchived: true);
    await saveAccount(account);
    await refreshScheduledNotifications();
  }

  Future<void> deleteAccount(String accountId) async {
    final existing = accountById(accountId);
    final account = existing.copyWith(
      isArchived: true,
      sync: existing.sync.deleted(deviceId: deviceId),
    );
    await saveAccount(account);
    await refreshScheduledNotifications();
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

  Future<void> deleteBudget(String budgetId) async {
    final existing = budgetById(budgetId);
    final budget = existing.copyWith(
      isArchived: true,
      sync: existing.sync.deleted(deviceId: deviceId),
    );
    await saveBudget(budget);
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

  Future<void> saveGoal(GoalRecord goal) async {
    _validateGoal(goal);
    final current = const GoalCalculator().currentAmountMinor(
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
    required GoalFundingMethod fundingMethod,
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
    final isAccountFunded = fundingMethod == GoalFundingMethod.accountFunded;
    final goal = GoalRecord(
      id: _newId('goal'),
      name: name.trim(),
      description: description.trim(),
      targetAmountMinor: targetAmountMinor.abs(),
      startingAmountMinor: isAccountFunded ? 0 : startingAmountMinor.abs(),
      targetDate: goalTargetDate,
      status:
          goalType == GoalType.reachTarget &&
              startingAmountMinor.abs() >= targetAmountMinor.abs()
          ? GoalStatus.completed
          : GoalStatus.active,
      fundingMethod: fundingMethod,
      goalType: goalType,
      defaultFundingAccountId: isAccountFunded ? defaultFundingAccountId : null,
      accentColorValue: accentColorValue,
      sync: SyncMetadata.fresh(now: timestamp, deviceId: deviceId),
    );
    _validateGoal(goal);
    GoalFundingEventRecord? initialFunding;
    if (isAccountFunded && startingAmountMinor.abs() > 0) {
      final accountId = defaultFundingAccountId;
      final account = accounts
          .where((item) => item.id == accountId && item.isVisible)
          .firstOrNull;
      if (account == null) {
        throw const FinanceDataValidationException(
          'Choose an active funding account.',
        );
      }
      if (startingAmountMinor.abs() > balanceForAccount(account.id)) {
        throw FinanceDataValidationException(
          '${account.name} does not have enough available balance.',
        );
      }
      final eventId = _newId('goal_funding');
      initialFunding = GoalFundingEventRecord(
        id: eventId,
        sourceAccountId: account.id,
        totalAmountMinor: startingAmountMinor.abs(),
        date: today,
        note: 'Starting Goal balance',
        allocations: [
          GoalFundingAllocation(
            id: _newId('goal_allocation'),
            fundingEventId: eventId,
            goalId: goal.id,
            amountMinor: startingAmountMinor.abs(),
            order: 0,
          ),
        ],
        sync: SyncMetadata.fresh(now: timestamp, deviceId: deviceId),
      );
    }
    final previousDataSet = _dataSet;
    try {
      _dataSet = _dataSet.copyWith(
        goals: _upsert(goals, goal, (item) => item.id),
        goalFundingEvents: initialFunding == null
            ? goalFundingEvents
            : _upsert(goalFundingEvents, initialFunding, (item) => item.id),
      );
      await _commit(
        goal: goal,
        goalFundingEvents: initialFunding == null ? const [] : [initialFunding],
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
          goal.fundingMethod != GoalFundingMethod.accountFunded) {
        throw const FinanceDataValidationException(
          'Choose an active account-funded Goal.',
        );
      }
      if (goal.requiresFundingMigration) {
        throw FinanceDataValidationException(
          '${goal.name} must convert its previous reservations first.',
        );
      }
      allocationTotal += allocation.amountMinor;
    }
    if (allocationTotal != amount) {
      throw const FinanceDataValidationException(
        'Goal allocations must equal the total funding amount.',
      );
    }

    final eventId = _newId('goal_funding');
    final event = GoalFundingEventRecord(
      id: eventId,
      sourceAccountId: sourceAccountId,
      totalAmountMinor: amount,
      date: DateTime(date.year, date.month, date.day),
      note: note.trim(),
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
      );
      await _commit(goalRecords: updatedGoals, goalFundingEvents: [event]);
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
    final affectedGoalIds = event.allocations
        .map((allocation) => allocation.goalId)
        .toSet();
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
            sync: _touchAfterCurrent(goal.sync),
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
        goalFundingEvents: _upsert(
          goalFundingEvents,
          reversed,
          (item) => item.id,
        ),
      );
      await _commit(goalRecords: updatedGoals, goalFundingEvents: [reversed]);
    } catch (_) {
      _dataSet = previousDataSet;
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
    final updatedGoal = _goalWithDerivedLifecycleStatus(goal, amountAfterUndo);
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
        sync: _touchAfterCurrent(goal.sync),
      ),
    );
  }

  Future<void> markGoalComplete(String goalId) async {
    final goal = goalById(goalId);
    if (goal.goalType == GoalType.maintainBalance) {
      throw const FinanceDataValidationException(
        'Maintain a Balance Goals remain active while in use.',
      );
    }
    await saveGoal(
      goal.copyWith(
        status: GoalStatus.completed,
        sync: _touchAfterCurrent(goal.sync),
      ),
    );
  }

  Future<void> restoreArchivedGoal(String goalId) async {
    final goal = goalById(goalId);
    if (!goal.isArchived) return;
    final status =
        goal.goalType == GoalType.reachTarget &&
            currentGoalAmountMinor(goal.id) >= goal.targetAmountMinor
        ? GoalStatus.completed
        : GoalStatus.active;
    await saveGoal(
      goal.copyWith(status: status, sync: _touchAfterCurrent(goal.sync)),
    );
  }

  GoalRecord _goalWithDerivedLifecycleStatus(
    GoalRecord goal,
    int currentAmountMinor,
  ) {
    if (goal.status == GoalStatus.archived) return goal;
    final derivedStatus =
        goal.goalType == GoalType.reachTarget &&
            currentAmountMinor >= goal.targetAmountMinor
        ? GoalStatus.completed
        : GoalStatus.active;
    if (goal.status == derivedStatus) return goal;
    return goal.copyWith(
      status: derivedStatus,
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
    if (goal.status != GoalStatus.archived &&
        goal.fundingMethod == GoalFundingMethod.accountFunded) {
      final accountId = goal.defaultFundingAccountId;
      final account = accounts
          .where((item) => item.id == accountId && item.isVisible)
          .firstOrNull;
      if (account == null) {
        throw const FinanceDataValidationException(
          'Choose an active funding account.',
        );
      }
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

  Future<void> saveTransactionAndSchedule({
    required TransactionRecord transaction,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {
    _validateTransaction(transaction);
    _validateScheduledTransaction(scheduledTransaction);
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
      );
      await _commit(
        transaction: transaction,
        scheduledTransaction: notificationAdjusted,
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
    final restoredOccurrence = ScheduledOccurrenceRecord(
      scheduledDate: occurrence.scheduledDate,
      plannedAmountMinor: occurrence.plannedAmountMinor,
      status: ScheduledOccurrenceStatus.pending,
    );
    final restoredOccurrences = [
      for (final existing in scheduledTransaction.occurrences)
        if (existing.transactionId != transaction.id ||
            !isSameScheduledDay(
              existing.scheduledDate,
              occurrence.scheduledDate,
            ))
          existing,
      restoredOccurrence,
    ];
    final scheduleSync = scheduledTransaction.isDeleted
        ? scheduledTransaction.sync.restored(deviceId: deviceId)
        : scheduledTransaction.sync.touched(deviceId: deviceId);
    var restoredSchedule = scheduledTransaction.copyWith(
      nextDate: shouldRestoreAsNext
          ? occurrence.scheduledDate
          : scheduledTransaction.nextDate,
      lastAction: ScheduledAction.none,
      occurrences: restoredOccurrences,
      scheduledNotificationIds: const [],
      sync: scheduleSync,
      clearLastReminderScheduledAt: true,
    );
    final reversedTransaction = transaction.copyWith(
      sync: transaction.sync.deleted(deviceId: deviceId),
    );
    _validateTransaction(reversedTransaction);
    _validateScheduledTransaction(restoredSchedule);

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
      );
      await _commit(
        transaction: reversedTransaction,
        scheduledTransaction: restoredSchedule,
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
    final count = preferences.notificationsEnabled
        ? scheduledDueOrOverdueCount(now: now)
        : 0;
    await notificationScheduler.updateBadgeCount(count);
  }

  Future<ScheduledTransactionRecord> _applyScheduledNotificationState(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    final existing = _existingScheduledTransaction(scheduledTransaction.id);
    if (existing != null && existing.scheduledNotificationIds.isNotEmpty) {
      await notificationScheduler.cancelScheduledTransaction(existing);
    }

    final shouldSchedule =
        preferences.notificationsEnabled &&
        !scheduledTransaction.isDeleted &&
        hasActionableScheduledAccounts(scheduledTransaction) &&
        scheduledTransaction.hasAlert &&
        scheduledTransaction.lastAction == ScheduledAction.none;
    if (!shouldSchedule) {
      if (scheduledTransaction.scheduledNotificationIds.isEmpty &&
          scheduledTransaction.lastReminderScheduledAt == null) {
        return scheduledTransaction;
      }
      return scheduledTransaction.copyWith(
        scheduledNotificationIds: const [],
        clearLastReminderScheduledAt: true,
      );
    }

    final hasPermission = await notificationScheduler
        .requestPermissionIfNeeded();
    if (!hasPermission) {
      return scheduledTransaction.copyWith(
        scheduledNotificationIds: const [],
        clearLastReminderScheduledAt: true,
      );
    }

    final notificationIds = await notificationScheduler
        .scheduleScheduledTransaction(scheduledTransaction);
    return scheduledTransaction.copyWith(
      scheduledNotificationIds: notificationIds,
      lastReminderScheduledAt: DateTime.now(),
    );
  }

  ScheduledTransactionRecord? _existingScheduledTransaction(String id) {
    for (final scheduledTransaction in scheduledTransactions) {
      if (scheduledTransaction.id == id) return scheduledTransaction;
    }
    return null;
  }

  Future<void> saveTransaction(TransactionRecord transaction) async {
    _validateTransaction(transaction);
    final updated = _upsert(transactions, transaction, (item) => item.id);
    _dataSet = _dataSet.copyWith(transactions: updated);
    await _commit(transaction: transaction);
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

    if (transaction.type != TransactionType.transfer &&
        transaction.type != TransactionType.adjustment) {
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
    if (scheduledTransaction.type == TransactionType.adjustment) return;

    final splitLines = scheduledTransaction.splitLines;
    if (splitLines.isEmpty) {
      // Legacy scheduled records may have no category or split payload. The
      // polished editor repairs those records before a user saves them, while
      // allowing unrelated actions such as delete, skip, and history reset to
      // continue working without a broad migration.
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
    ScheduledTransactionRecord? scheduledTransaction,
    BudgetRecord? budget,
    GoalRecord? goal,
    List<GoalRecord> goalRecords = const [],
    GoalContributionRecord? goalContribution,
    List<GoalContributionRecord> goalContributions = const [],
    List<GoalFundingEventRecord> goalFundingEvents = const [],
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
        if (scheduledTransaction != null) {
          await remote.saveScheduledTransaction(
            userId: currentUserId,
            scheduledTransaction: scheduledTransaction,
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
    scheduledTransactions: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.scheduledTransactions,
      current: current.scheduledTransactions,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
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
    preferences: current.preferences,
  );
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
      dataSet.goalFundingEvents.isNotEmpty;
}
