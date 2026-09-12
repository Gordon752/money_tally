import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  test('missing and new transaction status default to cleared', () async {
    final json = _transaction(status: TransactionStatus.pending).toJson()
      ..remove('status');
    expect(TransactionRecord.fromJson(json).status, TransactionStatus.cleared);

    final store = FinanceDataStore(dataSet: _dataSet());
    final created = await store.addExpense(
      accountId: 'checking',
      categoryId: 'expense',
      date: DateTime(2026, 8, 13),
      payee: 'Default',
      amountMinor: 1000,
    );
    expect(created.status, TransactionStatus.cleared);
  });

  test(
    'pending persists and status changes preserve every financial delta',
    () async {
      final store = FinanceDataStore(dataSet: _dataSet());
      final pending = await store.addExpense(
        accountId: 'checking',
        categoryId: 'expense',
        date: DateTime(2026, 8, 13),
        payee: 'Pending bill',
        amountMinor: 2500,
        status: TransactionStatus.pending,
      );
      final balance = store.balanceForAccount('checking');
      final delta = pending.deltaForAccount('checking');

      await store.setTransactionStatus(pending.id, TransactionStatus.cleared);
      final cleared = store.transactions.single;
      expect(cleared.status, TransactionStatus.cleared);
      expect(cleared.id, pending.id);
      expect(cleared.sync.updatedAt, isNot(pending.sync.updatedAt));
      expect(cleared.deltaForAccount('checking'), delta);
      expect(store.balanceForAccount('checking'), balance);

      await store.setTransactionStatus(cleared.id, TransactionStatus.pending);
      expect(store.transactions.single.status, TransactionStatus.pending);
      expect(store.balanceForAccount('checking'), balance);
    },
  );

  test(
    'pending transfers and splits retain normal account semantics',
    () async {
      final store = FinanceDataStore(dataSet: _dataSet());
      final transfer = await store.addTransfer(
        fromAccountId: 'checking',
        toAccountId: 'cash',
        date: DateTime(2026, 8, 13),
        payee: 'Pending transfer',
        amountMinor: 10000,
        status: TransactionStatus.pending,
      );
      expect(transfer.deltaForAccount('checking'), -10000);
      expect(transfer.deltaForAccount('cash'), 10000);

      final split = await store.addExpense(
        accountId: 'checking',
        categoryId: 'expense',
        date: DateTime(2026, 8, 13, 1),
        payee: 'Pending split',
        amountMinor: 3000,
        status: TransactionStatus.pending,
        splitLines: const [
          TransactionSplitLine(
            id: 'split-1',
            categoryId: 'expense',
            amountMinor: 2000,
          ),
          TransactionSplitLine(
            id: 'split-2',
            categoryId: 'other-expense',
            amountMinor: 1000,
          ),
        ],
      );
      expect(split.deltaForAccount('checking'), -3000);
      expect(store.balanceForAccount('checking'), 87000);
    },
  );

  test('pending status survives JSON round trip', () {
    final pending = _transaction(status: TransactionStatus.pending);
    final restored = TransactionRecord.fromJson(pending.toJson());
    expect(restored.status, TransactionStatus.pending);
    expect(restored.toJson(), pending.toJson());
  });
}

TransactionRecord _transaction({required TransactionStatus status}) {
  return TransactionRecord(
    id: 'transaction',
    type: TransactionType.expense,
    accountId: 'checking',
    categoryId: 'expense',
    date: DateTime(2026, 8, 13, 10, 30),
    payee: 'Payee',
    amountMinor: 1000,
    status: status,
    sync: SyncMetadata.fresh(deviceId: 'test'),
  );
}

FinanceDataSet _dataSet() {
  final sync = SyncMetadata.fresh(deviceId: 'test');
  return FinanceDataSet(
    transactions: const [],
    scheduledTransactions: const [],
    budgets: const [],
    accounts: [
      AccountRecord(
        id: 'checking',
        name: 'Checking',
        type: AccountType.checking,
        openingBalanceMinor: 100000,
        sync: sync,
      ),
      AccountRecord(
        id: 'cash',
        name: 'Cash',
        type: AccountType.cash,
        openingBalanceMinor: 0,
        sync: sync,
      ),
    ],
    categories: [
      CategoryRecord(
        id: 'expense',
        name: 'Expense',
        kind: CategoryKind.expense,
        sync: sync,
      ),
      CategoryRecord(
        id: 'other-expense',
        name: 'Other Expense',
        kind: CategoryKind.expense,
        sync: sync,
      ),
    ],
    preferences: const UserPreferences(),
  );
}
