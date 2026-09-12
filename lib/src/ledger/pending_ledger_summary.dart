import '../domain/transaction.dart';
import 'ledger_projection.dart';

/// Financially neutral presentation summary for pending Ledger activity.
///
/// Goal funding is represented by ordinary linked transfer records.  Those
/// records remain transfers for account math, but are presented in their own
/// Goals bucket so internal Goal movement is never mislabeled as spending.
class PendingLedgerSummary {
  const PendingLedgerSummary({
    required this.transactionIds,
    required this.expensesMinor,
    required this.incomeMinor,
    required this.transfersMinor,
    required this.goalsMinor,
  });

  final Set<String> transactionIds;
  final int expensesMinor;
  final int incomeMinor;
  final int transfersMinor;
  final int goalsMinor;

  int get count => transactionIds.length;
  bool get isEmpty => transactionIds.isEmpty;
}

PendingLedgerSummary summarizePendingLedgerTransactions(
  Iterable<LedgerTransactionProjection> projections,
) {
  final ids = <String>{};
  var expenses = 0;
  var income = 0;
  var transfers = 0;
  var goals = 0;

  for (final projection in projections) {
    final transaction = projection.transaction;
    if (transaction.status != TransactionStatus.pending ||
        !ids.add(transaction.id)) {
      continue;
    }
    final amount = projection.displayedAmountMinor.abs();
    if (transaction.goalFundingEventId?.isNotEmpty == true) {
      goals += amount;
      continue;
    }
    switch (transaction.type) {
      case TransactionType.expense:
        expenses += amount;
      case TransactionType.income:
        income += amount;
      case TransactionType.transfer:
        transfers += amount;
      case TransactionType.goalFunding:
        goals += amount;
      case TransactionType.adjustment:
        // Adjustments retain Pending status and remain visible in the drill-in,
        // but are not mislabeled as income, expense, transfer, or Goal funding.
        break;
    }
  }

  return PendingLedgerSummary(
    transactionIds: Set.unmodifiable(ids),
    expensesMinor: expenses,
    incomeMinor: income,
    transfersMinor: transfers,
    goalsMinor: goals,
  );
}
