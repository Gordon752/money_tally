import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  test(
    'account balances are derived from opening balance and ledger activity',
    () async {
      final store = FinanceDataStore(dataSet: _dataSet());

      await store.addExpense(
        accountId: 'checking',
        categoryId: 'dining',
        date: DateTime(2026, 7, 6),
        payee: 'Cafe',
        amountMinor: 1250,
      );
      await store.addIncome(
        accountId: 'checking',
        categoryId: 'income',
        date: DateTime(2026, 7, 6),
        payee: 'Settlement',
        amountMinor: 20000,
      );
      await store.adjustAccountBalance(
        accountId: 'checking',
        targetBalanceMinor: 150000,
        date: DateTime(2026, 7, 6),
      );

      expect(store.accountById('checking').openingBalanceMinor, 100000);
      expect(store.balanceForAccount('checking'), 150000);
      expect(store.transactions.last.type, TransactionType.adjustment);
      expect(store.transactions.last.amountMinor, 31250);
    },
  );

  test(
    'transfers affect both accounts and do not require a category',
    () async {
      final store = FinanceDataStore(dataSet: _dataSet());

      await store.addTransfer(
        fromAccountId: 'checking',
        toAccountId: 'cash',
        date: DateTime(2026, 7, 6),
        payee: 'ATM',
        amountMinor: 5000,
      );

      final transfer = store.transactions.single;
      expect(transfer.type, TransactionType.transfer);
      expect(transfer.categoryId, isNull);
      expect(store.balanceForAccount('checking'), 95000);
      expect(store.balanceForAccount('cash'), 15000);
    },
  );

  test('split transactions must match the parent amount', () async {
    final store = FinanceDataStore(dataSet: _dataSet());

    await store.addExpense(
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 7, 6),
      payee: 'Mixed receipt',
      amountMinor: 3000,
      splitLines: const [
        TransactionSplitLine(
          id: 'split-1',
          categoryId: 'dining',
          amountMinor: 1200,
        ),
        TransactionSplitLine(
          id: 'split-2',
          categoryId: 'snacks',
          amountMinor: 1800,
        ),
      ],
    );

    expect(store.transactions.single.hasValidSplitTotal, isTrue);

    await expectLater(
      store.addExpense(
        accountId: 'checking',
        categoryId: 'dining',
        date: DateTime(2026, 7, 6),
        payee: 'Bad split',
        amountMinor: 3000,
        splitLines: const [
          TransactionSplitLine(
            id: 'split-1',
            categoryId: 'dining',
            amountMinor: 1200,
          ),
        ],
      ),
      throwsA(isA<FinanceDataValidationException>()),
    );
  });

  test('backup codec preserves v2 data set records', () {
    const codec = BackupCodec();
    final dataSet = _dataSet().copyWith(
      transactions: [
        TransactionRecord(
          id: 'transfer-1',
          type: TransactionType.transfer,
          accountId: 'checking',
          transferAccountId: 'cash',
          date: DateTime(2026, 7, 6),
          payee: 'ATM',
          amountMinor: 5000,
          sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)),
        ),
      ],
    );

    final restored = codec.decodeJson(codec.encodeJson(dataSet));

    expect(restored.accounts.length, dataSet.accounts.length);
    expect(restored.transactions.single.type, TransactionType.transfer);
    expect(restored.transactions.single.transferAccountId, 'cash');
  });

  test('store writes changed records to per-record repository', () async {
    final remote = FakeRecordRepository();
    final store = FinanceDataStore(
      dataSet: _dataSet(),
      remoteRepository: remote,
      userId: 'user-1',
    );

    await store.addIncome(
      accountId: 'checking',
      categoryId: 'income',
      date: DateTime(2026, 7, 6),
      payee: 'Settlement',
      amountMinor: 120000,
    );

    expect(remote.savedTransactions.length, 1);
    expect(remote.savedTransactions.single.type, TransactionType.income);
  });

  test(
    'budget spending includes matching transaction and split categories',
    () {
      final dataSet = _dataSet().copyWith(
        budgets: [
          BudgetRecord(
            id: 'food-budget',
            name: 'Food',
            amountMinor: 10000,
            categoryIds: const ['dining', 'snacks'],
            sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)),
          ),
        ],
        transactions: [
          TransactionRecord(
            id: 'expense-1',
            type: TransactionType.expense,
            accountId: 'checking',
            categoryId: 'dining',
            date: DateTime(2026, 7, 6),
            payee: 'Cafe',
            amountMinor: 1250,
            sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)),
          ),
          TransactionRecord(
            id: 'split-1',
            type: TransactionType.expense,
            accountId: 'checking',
            categoryId: 'dining',
            date: DateTime(2026, 7, 7),
            payee: 'Store',
            amountMinor: 3000,
            splitLines: const [
              TransactionSplitLine(
                id: 'line-1',
                categoryId: 'snacks',
                amountMinor: 800,
              ),
              TransactionSplitLine(
                id: 'line-2',
                categoryId: 'other',
                amountMinor: 2200,
              ),
            ],
            sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)),
          ),
        ],
      );
      final store = FinanceDataStore(dataSet: dataSet);

      expect(
        store.spentThisMonthForBudget(
          dataSet.budgets.single,
          now: DateTime(2026, 7, 10),
        ),
        2050,
      );
    },
  );
}

FinanceDataSet _dataSet() {
  final sync = SyncMetadata.fresh(now: DateTime(2026, 7, 6));
  return FinanceDataSet(
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
        openingBalanceMinor: 10000,
        sync: sync,
      ),
    ],
    categories: [
      CategoryRecord(
        id: 'dining',
        name: 'Dining',
        kind: CategoryKind.expense,
        sync: sync,
      ),
      CategoryRecord(
        id: 'snacks',
        name: 'Snacks',
        kind: CategoryKind.expense,
        sync: sync,
      ),
      CategoryRecord(
        id: 'income',
        name: 'Income',
        kind: CategoryKind.income,
        sync: sync,
      ),
    ],
    transactions: const [],
    scheduledTransactions: const [],
    budgets: const [],
    preferences: const UserPreferences(),
  );
}

class FakeRecordRepository implements FinanceRecordRepository {
  final savedAccounts = <AccountRecord>[];
  final savedCategories = <CategoryRecord>[];
  final savedTransactions = <TransactionRecord>[];
  final savedScheduled = <ScheduledTransactionRecord>[];
  final savedBudgets = <BudgetRecord>[];
  UserPreferences? savedPreferences;

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async => _dataSet();

  @override
  Future<void> saveAccount({
    required String userId,
    required AccountRecord account,
  }) async {
    savedAccounts.add(account);
  }

  @override
  Future<void> saveBudget({
    required String userId,
    required BudgetRecord budget,
  }) async {
    savedBudgets.add(budget);
  }

  @override
  Future<void> saveCategory({
    required String userId,
    required CategoryRecord category,
  }) async {
    savedCategories.add(category);
  }

  @override
  Future<void> savePreferences({
    required String userId,
    required UserPreferences preferences,
  }) async {
    savedPreferences = preferences;
  }

  @override
  Future<void> saveScheduledTransaction({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {
    savedScheduled.add(scheduledTransaction);
  }

  @override
  Future<void> saveTransaction({
    required String userId,
    required TransactionRecord transaction,
  }) async {
    savedTransactions.add(transaction);
  }

  @override
  Stream<FinanceDataSet> watchDataSet(String userId) async* {
    yield _dataSet();
  }
}
