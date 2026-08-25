import 'account.dart';
import 'budget.dart';
import 'category.dart';
import 'fund.dart';
import 'goal.dart';
import 'goal_funding.dart';
import 'json_helpers.dart';
import 'reservation.dart';
import 'scheduled_occurrence_authority.dart';
import 'scheduled_transaction.dart';
import 'transaction.dart';
import 'user_preferences.dart';

class FinanceDataSet {
  const FinanceDataSet({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.scheduledTransactions,
    required this.budgets,
    required this.preferences,
    this.goals = const [],
    this.funds = const [],
    this.reservationOperations = const [],
    this.goalContributions = const [],
    this.goalFundingEvents = const [],
  });

  final List<AccountRecord> accounts;
  final List<CategoryRecord> categories;
  final List<TransactionRecord> transactions;
  final List<ScheduledTransactionRecord> scheduledTransactions;
  final List<BudgetRecord> budgets;
  final List<GoalRecord> goals;
  final List<FundRecord> funds;
  final List<ReservationOperationRecord> reservationOperations;
  final List<GoalContributionRecord> goalContributions;
  final List<GoalFundingEventRecord> goalFundingEvents;
  final UserPreferences preferences;

  FinanceDataSet copyWith({
    List<AccountRecord>? accounts,
    List<CategoryRecord>? categories,
    List<TransactionRecord>? transactions,
    List<ScheduledTransactionRecord>? scheduledTransactions,
    List<BudgetRecord>? budgets,
    List<GoalRecord>? goals,
    List<FundRecord>? funds,
    List<ReservationOperationRecord>? reservationOperations,
    List<GoalContributionRecord>? goalContributions,
    List<GoalFundingEventRecord>? goalFundingEvents,
    UserPreferences? preferences,
  }) {
    return FinanceDataSet(
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      scheduledTransactions:
          scheduledTransactions ?? this.scheduledTransactions,
      budgets: budgets ?? this.budgets,
      goals: goals ?? this.goals,
      funds: funds ?? this.funds,
      reservationOperations:
          reservationOperations ?? this.reservationOperations,
      goalContributions: goalContributions ?? this.goalContributions,
      goalFundingEvents: goalFundingEvents ?? this.goalFundingEvents,
      preferences: preferences ?? this.preferences,
    );
  }

  int balanceForAccount(String accountId) {
    final account = accounts.firstWhere((item) => item.id == accountId);
    final transactionBalance = transactions
        .where((transaction) => !transaction.isDeleted)
        .fold(
          account.openingBalanceMinor,
          (total, transaction) =>
              total + transaction.deltaForAccount(accountId),
        );
    final goalFundingTotal = goalFundingEvents
        .where(
          (event) =>
              event.isActive &&
              !event.isMigrationEvent &&
              event.sourceAccountId == accountId,
        )
        .fold<int>(0, (total, event) => total + event.totalAmountMinor.abs());
    return transactionBalance - goalFundingTotal;
  }

  /// Posted balance through [asOf]. Pending and future-dated records are
  /// deliberately excluded from the user-facing Balance bucket.
  int clearedBalanceForAccount(String accountId, {DateTime? asOf}) {
    final account = accounts.firstWhere((item) => item.id == accountId);
    final cutoff = _calendarDate(asOf ?? DateTime.now());
    final transactionBalance = transactions
        .where((transaction) {
          return !transaction.isDeleted &&
              transaction.status != TransactionStatus.pending &&
              !_calendarDate(transaction.date).isAfter(cutoff);
        })
        .fold<int>(
          account.openingBalanceMinor,
          (total, transaction) =>
              total + transaction.deltaForAccount(accountId),
        );
    final legacyGoalFunding = goalFundingEvents
        .where((event) {
          return event.isActive &&
              !event.isMigrationEvent &&
              event.sourceAccountId == accountId &&
              !_calendarDate(event.date).isAfter(cutoff);
        })
        .fold<int>(0, (total, event) => total + event.totalAmountMinor.abs());
    return transactionBalance - legacyGoalFunding;
  }

  int pendingEffectForAccount(String accountId, {DateTime? asOf}) {
    final cutoff = _calendarDate(asOf ?? DateTime.now());
    return transactions
        .where((transaction) {
          return !transaction.isDeleted &&
              transaction.status == TransactionStatus.pending &&
              !_calendarDate(transaction.date).isAfter(cutoff);
        })
        .fold<int>(
          0,
          (total, transaction) =>
              total + transaction.deltaForAccount(accountId),
        );
  }

  /// Pending positive inflows remain visible in Pending but do not become
  /// spendable until they clear.
  int pendingOutflowCommitmentsForAccount(String accountId, {DateTime? asOf}) {
    final cutoff = _calendarDate(asOf ?? DateTime.now());
    return transactions
        .where((transaction) {
          return !transaction.isDeleted &&
              transaction.status == TransactionStatus.pending &&
              !_calendarDate(transaction.date).isAfter(cutoff) &&
              transaction.deltaForAccount(accountId) < 0;
        })
        .fold<int>(
          0,
          (total, transaction) =>
              total + transaction.deltaForAccount(accountId).abs(),
        );
  }

  int futureEffectForAccount(String accountId, {DateTime? asOf}) {
    final cutoff = _calendarDate(asOf ?? DateTime.now());
    return transactions
        .where(
          (transaction) =>
              !transaction.isDeleted &&
              _calendarDate(transaction.date).isAfter(cutoff),
        )
        .fold<int>(
          0,
          (total, transaction) =>
              total + transaction.deltaForAccount(accountId),
        );
  }

  int reservedForAccount(String accountId, {DateTime? asOf}) {
    final containerKeys = <String>{
      for (final goal in goals)
        if (!goal.isDeleted && goal.usesReservationModel)
          '${ReservationContainerType.goal.name}:${goal.id}',
      for (final fund in funds)
        if (!fund.isDeleted) '${ReservationContainerType.fund.name}:${fund.id}',
    };
    final grouped = <String, List<ReservationOperationRecord>>{};
    for (final operation in reservationOperations) {
      if (operation.fundingAccountId != accountId) continue;
      final key = '${operation.containerType.name}:${operation.containerId}';
      if (!containerKeys.contains(key)) continue;
      grouped.putIfAbsent(key, () => []).add(operation);
    }
    return grouped.values.fold<int>(
      0,
      (total, operations) =>
          total +
          calculateReservationLedger(
            operations: effectiveReservationOperationsForContainer(
              operations: operations,
              transactions: transactions,
              scheduledTransactions: scheduledTransactions,
              containerType: operations.first.containerType,
              containerId: operations.first.containerId,
            ),
            asOf: asOf ?? DateTime.now(),
          ).reservedMinor,
    );
  }

  int availableToSpendForAccount(String accountId, {DateTime? asOf}) {
    return clearedBalanceForAccount(accountId, asOf: asOf) -
        pendingOutflowCommitmentsForAccount(accountId, asOf: asOf) -
        reservedForAccount(accountId, asOf: asOf);
  }

  int economicBalanceForAccount(String accountId, {DateTime? asOf}) {
    return clearedBalanceForAccount(accountId, asOf: asOf) +
        pendingEffectForAccount(accountId, asOf: asOf);
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 5,
      'accounts': accounts.map((item) => item.toJson()).toList(),
      'categories': categories.map((item) => item.toJson()).toList(),
      'transactions': transactions.map((item) => item.toJson()).toList(),
      'scheduledTransactions': scheduledTransactions
          .map((item) => item.toJson())
          .toList(),
      'budgets': budgets.map((item) => item.toJson()).toList(),
      'goals': goals.map((item) => item.toJson()).toList(),
      'funds': funds.map((item) => item.toJson()).toList(),
      'reservationOperations': reservationOperations
          .map((item) => item.toJson())
          .toList(),
      'goalContributions': goalContributions
          .map((item) => item.toJson())
          .toList(),
      'goalFundingEvents': goalFundingEvents
          .map((item) => item.toJson())
          .toList(),
      'preferences': preferences.toJson(),
    };
  }

  factory FinanceDataSet.fromJson(Map<String, Object?> json) {
    return FinanceDataSet(
      accounts: stringMapList(
        json['accounts'],
      ).map(AccountRecord.fromJson).toList(),
      categories: stringMapList(
        json['categories'],
      ).map(CategoryRecord.fromJson).toList(),
      transactions: stringMapList(
        json['transactions'],
      ).map(TransactionRecord.fromJson).toList(),
      scheduledTransactions: stringMapList(
        json['scheduledTransactions'],
      ).map(ScheduledTransactionRecord.fromJson).toList(),
      budgets: stringMapList(
        json['budgets'],
      ).map(BudgetRecord.fromJson).toList(),
      goals: stringMapList(json['goals']).map(GoalRecord.fromJson).toList(),
      funds: stringMapList(json['funds']).map(FundRecord.fromJson).toList(),
      reservationOperations: stringMapList(
        json['reservationOperations'],
      ).map(ReservationOperationRecord.fromJson).toList(),
      goalContributions: stringMapList(
        json['goalContributions'],
      ).map(GoalContributionRecord.fromJson).toList(),
      goalFundingEvents: stringMapList(
        json['goalFundingEvents'],
      ).map(GoalFundingEventRecord.fromJson).toList(),
      preferences: UserPreferences.fromJson(stringMap(json['preferences'])),
    );
  }
}

/// Resolves immutable transaction-linked consumption against the winning
/// transaction record after sync.
///
/// Concurrent devices may legitimately publish different immutable consume
/// operations while editing the same transaction. Only one operation whose
/// stable linkage, account, amount, and date match the installed transaction
/// is financially effective. Every operation remains persisted for causal
/// history and possible reversals.
List<ReservationOperationRecord> effectiveReservationOperationsForContainer({
  required Iterable<ReservationOperationRecord> operations,
  required Iterable<TransactionRecord> transactions,
  Iterable<ScheduledTransactionRecord> scheduledTransactions = const [],
  required ReservationContainerType containerType,
  required String containerId,
}) {
  final scheduledById = {
    for (final schedule in scheduledTransactions)
      if (schedule.isScheduledFundFunding) schedule.id: schedule,
  };
  final activity = operations
      .where(
        (operation) =>
            operation.containerType == containerType &&
            operation.containerId == containerId &&
            _isAuthoritativeScheduledFundOperation(operation, scheduledById),
      )
      .toList(growable: false);
  if (!activity.any(
    (operation) =>
        operation.kind == ReservationOperationKind.consume &&
        operation.transactionId != null,
  )) {
    return activity;
  }

  final rawLedger = calculateReservationLedger(operations: activity);
  final transactionById = {
    for (final transaction in transactions) transaction.id: transaction,
  };
  final candidatesByTransaction = <String, List<ReservationOperationRecord>>{};
  for (final operation in activity) {
    final transactionId = operation.transactionId;
    if (operation.kind != ReservationOperationKind.consume ||
        transactionId == null ||
        rawLedger.reversedOperationIds.contains(operation.id)) {
      continue;
    }
    final transaction = transactionById[transactionId];
    if (transaction == null ||
        transaction.isDeleted ||
        transaction.reservationContainerType != containerType ||
        transaction.reservationContainerId != containerId ||
        transaction.accountId != operation.fundingAccountId ||
        transaction.deltaForAccount(transaction.accountId) >= 0 ||
        operation.amountMinor >
            transaction.deltaForAccount(transaction.accountId).abs() ||
        !_sameCalendarDate(transaction.date, operation.effectiveDate)) {
      continue;
    }
    candidatesByTransaction.putIfAbsent(transactionId, () => []).add(operation);
  }

  final selectedConsumptionIds = <String>{};
  for (final candidates in candidatesByTransaction.values) {
    candidates.sort((left, right) {
      final revisionOrder = left.revision.compareTo(right.revision);
      if (revisionOrder != 0) return revisionOrder;
      final operationOrder = left.operationId.compareTo(right.operationId);
      if (operationOrder != 0) return operationOrder;
      return left.id.compareTo(right.id);
    });
    selectedConsumptionIds.add(candidates.last.id);
  }

  return [
    for (final operation in activity)
      if (operation.kind != ReservationOperationKind.consume ||
          (operation.transactionId != null &&
              selectedConsumptionIds.contains(operation.id)))
        operation,
  ];
}

/// Scheduled Fund-funding operations are immutable causal history. Their
/// financial effect is selected by the winning occurrence authority rather
/// than by whichever operation documents happened to arrive first.
///
/// This makes concurrent Paid/Paid and Paid/Skip actions converge safely:
/// only the allocation linked by the winning Paid state is effective. A
/// winning Pending (Undo) or Skipped state makes every allocation/reversal
/// from that occurrence inert without deleting its audit history.
bool _isAuthoritativeScheduledFundOperation(
  ReservationOperationRecord operation,
  Map<String, ScheduledTransactionRecord> scheduledById,
) {
  final scheduleId = operation.scheduledTransactionId;
  if (scheduleId == null) return true;
  final schedule = scheduledById[scheduleId];
  if (schedule == null) return true;

  final occurrenceDate = operation.scheduledOccurrenceDate;
  if (occurrenceDate == null) return false;
  final authority = occurrenceAuthorityFor(
    schedule,
  )[occurrenceDayKey(occurrenceDate)];
  return authority?.status == ScheduledOccurrenceStatus.paid &&
      authority!.reservationOperationId == operation.id &&
      operation.kind == ReservationOperationKind.allocate;
}

bool _sameCalendarDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

DateTime _calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);
