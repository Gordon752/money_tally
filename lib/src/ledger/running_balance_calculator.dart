import '../domain/account.dart';
import '../domain/goal_funding.dart';
import '../domain/transaction.dart';

class AccountRunningBalances {
  const AccountRunningBalances({
    required this.afterTransaction,
    required this.afterGoalFundingEvent,
  });

  final Map<String, int> afterTransaction;
  final Map<String, int> afterGoalFundingEvent;
}

/// Reconstructs an account's authoritative balance chronologically once.
///
/// Transactions use the same [TransactionRecord.deltaForAccount] semantics as
/// the store. Legacy Goal funding events remain a separate account effect
/// because that is also how [FinanceDataSet.balanceForAccount] represents
/// them. Derived balances are presentation state and are never persisted.
AccountRunningBalances calculateAccountRunningBalances({
  required AccountRecord account,
  required Iterable<TransactionRecord> transactions,
  Iterable<GoalFundingEventRecord> goalFundingEvents = const [],
}) {
  final activities = <_AccountBalanceActivity>[
    for (final transaction in transactions)
      if (!transaction.isDeleted &&
          transaction.deltaForAccount(account.id) != 0)
        _AccountBalanceActivity(
          id: transaction.id,
          date: transaction.date,
          createdAt: transaction.sync.createdAt,
          deltaMinor: transaction.deltaForAccount(account.id),
          isTransaction: true,
        ),
    for (final event in goalFundingEvents)
      if (event.isActive &&
          !event.isMigrationEvent &&
          event.sourceAccountId == account.id)
        _AccountBalanceActivity(
          id: event.id,
          date: event.date,
          createdAt: event.sync.createdAt,
          deltaMinor: -event.totalAmountMinor.abs(),
          isTransaction: false,
        ),
  ]..sort(_compareOldestFirst);

  var balance = account.openingBalanceMinor;
  final afterTransaction = <String, int>{};
  final afterGoalFundingEvent = <String, int>{};
  for (final activity in activities) {
    balance += activity.deltaMinor;
    if (activity.isTransaction) {
      afterTransaction[activity.id] = balance;
    } else {
      afterGoalFundingEvent[activity.id] = balance;
    }
  }
  return AccountRunningBalances(
    afterTransaction: Map.unmodifiable(afterTransaction),
    afterGoalFundingEvent: Map.unmodifiable(afterGoalFundingEvent),
  );
}

class _AccountBalanceActivity {
  const _AccountBalanceActivity({
    required this.id,
    required this.date,
    required this.createdAt,
    required this.deltaMinor,
    required this.isTransaction,
  });

  final String id;
  final DateTime date;
  final DateTime createdAt;
  final int deltaMinor;
  final bool isTransaction;
}

int _compareOldestFirst(
  _AccountBalanceActivity left,
  _AccountBalanceActivity right,
) {
  final dateOrder = left.date.compareTo(right.date);
  if (dateOrder != 0) return dateOrder;
  final createdOrder = left.createdAt.compareTo(right.createdAt);
  if (createdOrder != 0) return createdOrder;
  return left.id.compareTo(right.id);
}
