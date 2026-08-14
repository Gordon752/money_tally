import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/ledger/ledger_projection.dart';
import 'package:money_tally/src/ledger/pending_ledger_summary.dart';

void main() {
  test(
    'pending summary keeps transfers and Goal funding semantically separate',
    () {
      final projections = projectLedgerTransactions([
        _transaction('expense', TransactionType.expense, 3166),
        _transaction('income', TransactionType.income, 80000),
        _transaction('transfer', TransactionType.transfer, 56160),
        _transaction(
          'goal',
          TransactionType.transfer,
          25000,
          goalFundingEventId: 'goal-event',
        ),
        _transaction(
          'cleared',
          TransactionType.expense,
          99999,
          status: TransactionStatus.cleared,
        ),
      ]);

      final summary = summarizePendingLedgerTransactions(projections);

      expect(summary.count, 4);
      expect(summary.expensesMinor, 3166);
      expect(summary.incomeMinor, 80000);
      expect(summary.transfersMinor, 56160);
      expect(summary.goalsMinor, 25000);
      expect(summary.transactionIds, {'expense', 'income', 'transfer', 'goal'});
    },
  );

  test(
    'category projection uses only the amount represented in current scope',
    () {
      final transaction = _transaction('split', TransactionType.expense, 10000)
          .copyWith(
            splitLines: const [
              TransactionSplitLine(
                id: 'fuel-line',
                categoryId: 'fuel',
                amountMinor: 6000,
              ),
              TransactionSplitLine(
                id: 'food-line',
                categoryId: 'food',
                amountMinor: 4000,
              ),
            ],
          );
      final projection = LedgerTransactionProjection(
        transaction: transaction,
        displayedAmountMinor: -6000,
        matchingAllocations: const [
          TransactionSplitLine(
            id: 'fuel-line',
            categoryId: 'fuel',
            amountMinor: 6000,
          ),
        ],
      );

      expect(
        summarizePendingLedgerTransactions([projection]).expensesMinor,
        6000,
      );
    },
  );
}

TransactionRecord _transaction(
  String id,
  TransactionType type,
  int amountMinor, {
  TransactionStatus status = TransactionStatus.pending,
  String? goalFundingEventId,
}) {
  return TransactionRecord(
    id: id,
    type: type,
    accountId: 'checking',
    transferAccountId: type == TransactionType.transfer ? 'savings' : null,
    date: DateTime(2026, 8, 14, 12),
    payee: id,
    amountMinor: amountMinor,
    status: status,
    goalFundingEventId: goalFundingEventId,
    sync: SyncMetadata.fresh(deviceId: 'test'),
  );
}
