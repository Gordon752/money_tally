import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/notifications/notification_scheduler.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  test('scheduled occurrence metadata round trips', () {
    final scheduled = ScheduledTransactionRecord(
      id: 'sched-card',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      payee: 'Card payment',
      amountMinor: 25000,
      nextDate: DateTime(2026, 8, 1),
      frequency: RecurrenceFrequency.monthly,
      occurrences: [
        ScheduledOccurrenceRecord(
          scheduledDate: DateTime(2026, 7, 1),
          plannedAmountMinor: 25000,
          status: ScheduledOccurrenceStatus.paid,
          actualAmountMinor: 90000,
          actualPaymentDate: DateTime(2026, 7, 3),
          transactionId: 'txn-paid',
        ),
      ],
      sync: SyncMetadata.fresh(now: DateTime(2026, 7, 1)),
    );
    final transaction = TransactionRecord(
      id: 'txn-paid',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 7, 3),
      payee: 'Card payment',
      amountMinor: 90000,
      scheduledTransactionId: 'sched-card',
      scheduledOccurrenceDate: DateTime(2026, 7, 1),
      scheduledPlannedAmountMinor: 25000,
      sync: SyncMetadata.fresh(now: DateTime(2026, 7, 3)),
    );

    final restoredSchedule = ScheduledTransactionRecord.fromJson(
      scheduled.toJson(),
    );
    final restoredTransaction = TransactionRecord.fromJson(
      transaction.toJson(),
    );

    expect(restoredSchedule.occurrences, hasLength(1));
    expect(restoredSchedule.occurrences.single.actualAmountMinor, 90000);
    expect(restoredSchedule.occurrences.single.plannedAmountMinor, 25000);
    expect(restoredTransaction.scheduledOccurrenceDate, DateTime(2026, 7, 1));
    expect(restoredTransaction.scheduledPlannedAmountMinor, 25000);
  });

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

  test('deleted transactions are ignored by balances and summaries', () async {
    final store = FinanceDataStore(dataSet: _dataSet());

    final expense = await store.addExpense(
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 7, 6),
      payee: 'Void',
      amountMinor: 1000,
    );

    await store.saveTransaction(
      expense.copyWith(sync: expense.sync.deleted(deviceId: store.deviceId)),
    );

    expect(store.balanceForAccount('checking'), 100000);
    expect(store.expensesThisMonthMinor(now: DateTime(2026, 7, 10)), 0);
  });

  test('deletion tombstones survive a complete local-store reload', () async {
    SharedPreferences.setMockInitialValues({});
    const repository = LocalFinanceDataSetRepository(
      storageKey: 'persistence_restart_regression',
    );
    final sync = SyncMetadata.fresh(now: DateTime(2026, 7, 6));
    final transaction = TransactionRecord(
      id: 'transaction',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 7, 6),
      payee: 'Dinner',
      amountMinor: 2500,
      sync: sync,
    );
    final scheduled = _scheduledTransaction(
      id: 'scheduled',
      nextDate: DateTime(2026, 8, 1),
      sync: sync,
    );
    final budget = BudgetRecord(
      id: 'budget',
      name: 'Dining',
      amountMinor: 30000,
      categoryIds: const ['dining'],
      sync: sync,
    );
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        transactions: [transaction],
        scheduledTransactions: [scheduled],
        budgets: [budget],
      ),
      localRepository: repository,
    );
    await repository.save(store.dataSet);

    await store.deleteAccount('checking');
    await store.saveTransaction(
      transaction.copyWith(
        sync: transaction.sync.deleted(deviceId: store.deviceId),
      ),
    );
    await store.saveScheduledTransaction(
      scheduled.copyWith(
        sync: scheduled.sync.deleted(deviceId: store.deviceId),
      ),
    );
    await store.deleteBudget('budget');

    final reloaded = await FinanceDataStore.load(localRepository: repository);

    expect(reloaded.accountById('checking').isDeleted, isTrue);
    expect(
      reloaded.transactions
          .singleWhere((item) => item.id == 'transaction')
          .isDeleted,
      isTrue,
    );
    expect(
      reloaded.scheduledTransactions
          .singleWhere((item) => item.id == 'scheduled')
          .isDeleted,
      isTrue,
    );
    expect(reloaded.budgetById('budget').isDeleted, isTrue);
    expect(reloaded.activeAccountsInDisplayOrder.map((item) => item.id), [
      'cash',
    ]);
  });

  test('store can reorder accounts within a fixed group', () async {
    final sync = SyncMetadata.fresh(now: DateTime(2026, 7, 6));
    final repository = FakeRecordRepository();
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        accounts: [
          ..._dataSet().accounts,
          AccountRecord(
            id: 'savings',
            name: 'Savings',
            type: AccountType.savings,
            openingBalanceMinor: 50000,
            sortOrder: 100,
            sync: sync,
          ),
        ],
      ),
      remoteRepository: repository,
      userId: 'user-1',
    );

    expect(
      store.activeAccountsInDisplayOrder
          .where((account) => account.group == AccountGroup.banking)
          .map((account) => account.id),
      ['checking', 'savings'],
    );

    await store.moveAccountWithinGroup(accountId: 'checking', direction: 1);

    expect(
      store.activeAccountsInDisplayOrder
          .where((account) => account.group == AccountGroup.banking)
          .map((account) => account.id),
      ['savings', 'checking'],
    );
    expect(repository.savedAccounts.map((account) => account.id), [
      'savings',
      'checking',
    ]);
  });

  test('store can reorder fixed account groups', () async {
    final store = FinanceDataStore(dataSet: _dataSet());

    expect(store.activeAccountsInDisplayOrder.map((account) => account.id), [
      'checking',
      'cash',
    ]);

    await store.moveAccountGroup(group: AccountGroup.cash, direction: -1);

    expect(store.preferences.accountGroupOrderNames.take(2), [
      'cash',
      'banking',
    ]);
    expect(store.activeAccountsInDisplayOrder.map((account) => account.id), [
      'cash',
      'checking',
    ]);
  });

  test('store can rename fixed account group display labels', () async {
    final store = FinanceDataStore(dataSet: _dataSet());

    await store.renameAccountGroup(
      group: AccountGroup.banking,
      label: 'Everyday Money',
    );

    expect(store.accountGroupLabel(AccountGroup.banking), 'Everyday Money');
    expect(
      store.preferences.accountGroupLabelOverrides,
      containsPair('banking', 'Everyday Money'),
    );

    await store.renameAccountGroup(group: AccountGroup.banking, label: '');

    expect(store.accountGroupLabel(AccountGroup.banking), 'Banking');
    expect(
      store.preferences.accountGroupLabelOverrides,
      isNot(contains('banking')),
    );
  });

  test('category parent validation prevents hierarchy cycles', () {
    final sync = SyncMetadata.fresh(now: DateTime(2026, 7, 6));
    final categories = [
      CategoryRecord(
        id: 'food',
        name: 'Food',
        kind: CategoryKind.expense,
        sync: sync,
      ),
      CategoryRecord(
        id: 'dining',
        name: 'Dining',
        kind: CategoryKind.expense,
        parentCategoryId: 'food',
        sync: sync,
      ),
      CategoryRecord(
        id: 'snacks',
        name: 'Snacks',
        kind: CategoryKind.expense,
        parentCategoryId: 'dining',
        sync: sync,
      ),
      CategoryRecord(
        id: 'transportation',
        name: 'Transportation',
        kind: CategoryKind.expense,
        sync: sync,
      ),
    ];

    expect(
      wouldCreateCategoryParentCycle(
        categories,
        categoryId: 'food',
        parentCategoryId: 'food',
      ),
      isTrue,
    );
    expect(
      wouldCreateCategoryParentCycle(
        categories,
        categoryId: 'food',
        parentCategoryId: 'snacks',
      ),
      isTrue,
    );
    expect(
      wouldCreateCategoryParentCycle(
        categories,
        categoryId: 'food',
        parentCategoryId: 'transportation',
      ),
      isFalse,
    );
    expect(
      wouldCreateCategoryParentCycle(
        categories,
        categoryId: 'food',
        parentCategoryId: null,
      ),
      isFalse,
    );
  });

  test('store derives credit card and loan progress values', () {
    final sync = SyncMetadata.fresh(now: DateTime(2026, 7, 6));
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        accounts: [
          ..._dataSet().accounts,
          AccountRecord(
            id: 'card',
            name: 'Credit Card',
            type: AccountType.creditCard,
            openingBalanceMinor: -50000,
            creditLimitMinor: 200000,
            sync: sync,
          ),
          AccountRecord(
            id: 'card_without_limit',
            name: 'Card Without Limit',
            type: AccountType.creditCard,
            openingBalanceMinor: -25000,
            sync: sync,
          ),
          AccountRecord(
            id: 'loan',
            name: 'Truck Loan',
            type: AccountType.loan,
            openingBalanceMinor: -1000000,
            originalLoanAmountMinor: 1500000,
            sync: sync,
          ),
        ],
      ),
    );

    expect(store.creditUsedMinorForAccount('card'), 50000);
    expect(store.creditAvailableMinorForAccount('card'), 150000);
    expect(store.creditUsedMinorForGroup(AccountGroup.creditCards), 75000);
    expect(store.creditLimitMinorForGroup(AccountGroup.creditCards), 200000);

    expect(store.remainingLoanMinorForAccount('loan'), 1000000);
    expect(store.loanPaidDownMinorForAccount('loan'), 500000);
    expect(store.remainingLoanMinorForGroup(AccountGroup.loans), 1000000);
    expect(store.originalLoanAmountMinorForGroup(AccountGroup.loans), 1500000);
  });

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
      accounts: [
        for (final account in _dataSet().accounts)
          if (account.id == 'checking')
            account.copyWith(
              type: AccountType.creditCard,
              creditLimitMinor: 250000,
            )
          else
            account,
      ],
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
    expect(restored.accounts.first.creditLimitMinor, 250000);
    expect(restored.transactions.single.type, TransactionType.transfer);
    expect(restored.transactions.single.transferAccountId, 'cash');
  });

  test('backup codec exports ledger transactions as csv', () {
    const codec = BackupCodec();
    final dataSet = _dataSet().copyWith(
      transactions: [
        TransactionRecord(
          id: 'expense-1',
          type: TransactionType.expense,
          accountId: 'checking',
          categoryId: 'dining',
          date: DateTime(2026, 7, 6),
          payee: 'Cafe, Inc.',
          note: 'Morning coffee',
          amountMinor: 1250,
          scheduledTransactionId: 'sched-cafe',
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
              categoryId: 'dining',
              amountMinor: 1200,
            ),
            TransactionSplitLine(
              id: 'line-2',
              categoryId: 'snacks',
              amountMinor: 1800,
              note: 'Snacks, drinks',
            ),
          ],
          sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)),
        ),
      ],
    );

    final csv = codec.encodeTransactionsCsv(dataSet);
    final lines = csv.split('\n');

    expect(
      lines.first,
      'transaction_id,split_line_id,date,type,account,transfer_account,category,payee,note,amount,status,scheduled_transaction_id,deleted',
    );
    expect(
      lines,
      contains(
        'expense-1,,2026-07-06,expense,Checking,,Dining,"Cafe, Inc.",Morning coffee,12.50,cleared,sched-cafe,false',
      ),
    );
    expect(
      lines,
      contains(
        'split-1,line-2,2026-07-07,expense,Checking,,Snacks,Store,"Snacks, drinks",18.00,cleared,,false',
      ),
    );
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
    'paired transaction and schedule save rolls back on local failure',
    () async {
      final store = FinanceDataStore(
        dataSet: _dataSet(),
        localRepository: const AlwaysFailingLocalRepository(),
      );
      final schedule = ScheduledTransactionRecord(
        id: 'sched-paired',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        payee: 'Paired save',
        amountMinor: 2500,
        nextDate: DateTime(2026, 8, 1),
        frequency: RecurrenceFrequency.monthly,
        sync: SyncMetadata.fresh(now: DateTime(2026, 7, 1)),
      );
      final transaction = TransactionRecord(
        id: 'txn-paired',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: DateTime(2026, 7, 1),
        payee: 'Paired save',
        amountMinor: 2500,
        scheduledTransactionId: schedule.id,
        sync: SyncMetadata.fresh(now: DateTime(2026, 7, 1)),
      );

      await expectLater(
        store.saveTransactionAndSchedule(
          transaction: transaction,
          scheduledTransaction: schedule,
        ),
        throwsStateError,
      );

      expect(store.transactions, isEmpty);
      expect(store.scheduledTransactions, isEmpty);
    },
  );

  test('store seeds empty per-record remote when sync attaches', () async {
    final remote = FakeRecordRepository(dataSet: _emptyDataSet());
    final store = FinanceDataStore(dataSet: _dataSet());

    await store.attachRemoteSync(remoteRepository: remote, userId: 'user-1');

    expect(remote.savedAccounts.map((account) => account.id), [
      'checking',
      'cash',
    ]);
    expect(remote.savedCategories.map((category) => category.id), [
      'dining',
      'snacks',
      'income',
    ]);
    expect(remote.savedPreferences, isNotNull);

    await store.addIncome(
      accountId: 'checking',
      categoryId: 'income',
      date: DateTime(2026, 7, 6),
      payee: 'Settlement',
      amountMinor: 120000,
    );

    expect(remote.savedTransactions.single.payee, 'Settlement');
  });

  test('store loads existing per-record remote when sync attaches', () async {
    final remoteDataSet = _dataSet().copyWith(
      accounts: [
        for (final account in _dataSet().accounts)
          if (account.id == 'checking')
            account.copyWith(name: 'Cloud Checking')
          else
            account,
      ],
    );
    final remote = FakeRecordRepository(dataSet: remoteDataSet);
    final store = FinanceDataStore(dataSet: _emptyDataSet());

    await store.attachRemoteSync(remoteRepository: remote, userId: 'user-1');

    expect(store.accountById('checking').name, 'Cloud Checking');
    expect(remote.savedAccounts.map((account) => account.id), [
      'checking',
      'cash',
    ]);
  });

  test(
    'local-first category survives sync attach and notifies listeners',
    () async {
      final remote = FakeRecordRepository(dataSet: _dataSet());
      final store = FinanceDataStore(dataSet: _dataSet());
      var notifications = 0;
      store.addListener(() => notifications += 1);
      final category = CategoryRecord(
        id: 'new-local-category',
        name: 'New Local Category',
        kind: CategoryKind.expense,
        sync: SyncMetadata.fresh(now: DateTime(2026, 7, 21)),
      );

      await store.saveCategoryLocalFirst(category);
      expect(notifications, 1);
      expect(store.categoryById(category.id), category);

      await store.attachRemoteSync(remoteRepository: remote, userId: 'user-1');

      expect(store.categoryById(category.id).name, 'New Local Category');
      expect(
        remote.savedCategories.any((saved) => saved.id == category.id),
        isTrue,
      );
    },
  );

  test('store treats remote tombstones as existing sync data', () async {
    final deletedChecking = _dataSet().accounts
        .firstWhere((account) => account.id == 'checking')
        .copyWith(
          isArchived: true,
          sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)).deleted(),
        );
    final remote = FakeRecordRepository(
      dataSet: _emptyDataSet().copyWith(accounts: [deletedChecking]),
    );
    final store = FinanceDataStore(dataSet: _dataSet());

    await store.attachRemoteSync(remoteRepository: remote, userId: 'user-1');

    expect(store.accountById('checking').isDeleted, isTrue);
    expect(store.activeAccountsInDisplayOrder.map((account) => account.id), [
      'cash',
    ]);
    expect(
      remote.savedAccounts
          .singleWhere((account) => account.id == 'checking')
          .isDeleted,
      isTrue,
    );
  });

  test(
    'budget spending includes matching transaction and split categories',
    () {
      final dataSet = _dataSet().copyWith(
        categories: [
          ..._dataSet().categories,
          CategoryRecord(
            id: 'coffee',
            name: 'Coffee',
            kind: CategoryKind.expense,
            parentCategoryId: 'dining',
            sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)),
          ),
        ],
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
            id: 'expense-2',
            type: TransactionType.expense,
            accountId: 'checking',
            categoryId: 'coffee',
            date: DateTime(2026, 7, 6),
            payee: 'Coffee',
            amountMinor: 950,
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
        3000,
      );
    },
  );

  test('store reports available cash and this-month totals', () {
    final dataSet = _dataSet().copyWith(
      transactions: [
        TransactionRecord(
          id: 'income-1',
          type: TransactionType.income,
          accountId: 'checking',
          categoryId: 'income',
          date: DateTime(2026, 7, 6),
          payee: 'Settlement',
          amountMinor: 50000,
          sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)),
        ),
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
          id: 'old-expense',
          type: TransactionType.expense,
          accountId: 'checking',
          categoryId: 'dining',
          date: DateTime(2026, 6, 30),
          payee: 'Old Cafe',
          amountMinor: 900,
          sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)),
        ),
      ],
    );
    final store = FinanceDataStore(dataSet: dataSet);

    expect(store.availableCashMinor, 157850);
    expect(store.openingNetWorthMinor, 110000);
    expect(store.netWorthLedgerChangeMinor, 47850);
    expect(store.incomeThisMonthMinor(now: DateTime(2026, 7, 10)), 50000);
    expect(store.expensesThisMonthMinor(now: DateTime(2026, 7, 10)), 1250);
  });

  test('user preferences copy without losing unrelated settings', () {
    const preferences = UserPreferences(
      appearanceMode: AppearanceMode.dark,
      currency: CurrencyFormatSettings(currencyCode: 'USD', symbol: r'$'),
      defaultTransactionType: DefaultTransactionType.lastUsed,
      collapsedAccountGroupNames: {'cash'},
      accountGroupOrderNames: ['cash', 'banking', 'creditCards', 'loans'],
      accountGroupLabelOverrides: {'banking': 'Everyday Money'},
      savedPayeeNames: ['Cafe', 'Old Store'],
      archivedPayeeNames: {'cafe'},
      deletedPayeeNames: {'old store'},
    );

    final updated = preferences.copyWith(
      launchScreen: LaunchScreen.ledger,
      currency: preferences.currency.copyWith(
        currencyCode: 'CAD',
        symbol: r'C$',
      ),
    );

    expect(updated.launchScreen, LaunchScreen.ledger);
    expect(updated.appearanceMode, AppearanceMode.dark);
    expect(updated.currency.currencyCode, 'CAD');
    expect(updated.defaultTransactionType, DefaultTransactionType.lastUsed);
    expect(updated.collapsedAccountGroupNames, {'cash'});
    expect(updated.accountGroupOrderNames.take(2), ['cash', 'banking']);
    expect(updated.accountGroupLabelOverrides, {'banking': 'Everyday Money'});

    final roundTripped = UserPreferences.fromJson(updated.toJson());
    expect(roundTripped.collapsedAccountGroupNames, {'cash'});
    expect(roundTripped.accountGroupOrderNames.take(2), ['cash', 'banking']);
    expect(roundTripped.accountGroupLabelOverrides, {
      'banking': 'Everyday Money',
    });
    expect(roundTripped.savedPayeeNames, ['Cafe', 'Old Store']);
    expect(roundTripped.archivedPayeeNames, {'cafe'});
    expect(roundTripped.deletedPayeeNames, {'old store'});
  });

  test('notification planner converts alert preferences into requests', () {
    const planner = ScheduledNotificationPlanner();
    final request = planner.planOne(
      ScheduledTransactionRecord(
        id: 'sched-rent',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        payee: 'Rent',
        amountMinor: 90000,
        nextDate: DateTime(2026, 8, 1),
        frequency: RecurrenceFrequency.monthly,
        alertPreference: AlertPreference.threeDaysBefore,
        repeatAlertUntilResolved: true,
        sync: SyncMetadata.fresh(now: DateTime(2026, 7, 1)),
      ),
      now: DateTime(2026, 7, 20),
    );

    expect(request, isNotNull);
    expect(request!.scheduledTransactionId, 'sched-rent');
    expect(request.title, 'Payment due');
    expect(request.body, 'Rent is due.');
    expect(request.scheduledFor, DateTime(2026, 7, 29, 9));
    expect(request.repeatUntilResolved, isTrue);
    expect(request.id, notificationIdFor('sched-rent'));
  });

  test('notification planner skips disabled and resolved schedules', () {
    const planner = ScheduledNotificationPlanner();
    final base = ScheduledTransactionRecord(
      id: 'sched-rent',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      payee: 'Rent',
      amountMinor: 90000,
      nextDate: DateTime(2026, 8, 1),
      frequency: RecurrenceFrequency.monthly,
      sync: SyncMetadata.fresh(now: DateTime(2026, 7, 1)),
    );

    expect(planner.planOne(base, now: DateTime(2026, 7, 20)), isNull);
    expect(
      planner.planOne(
        base.copyWith(alertPreference: AlertPreference.sameDay),
        now: DateTime(2026, 8, 1, 10),
      ),
      isNull,
    );
    expect(
      planner.planOne(
        base.copyWith(
          alertPreference: AlertPreference.sameDay,
          lastAction: ScheduledAction.skipped,
        ),
        now: DateTime(2026, 7, 20),
      ),
      isNull,
    );
    expect(
      planner.planOne(
        base.copyWith(
          alertPreference: AlertPreference.sameDay,
          sync: base.sync.deleted(),
        ),
        now: DateTime(2026, 7, 20),
      ),
      isNull,
    );
  });

  test(
    'store schedules and cancels scheduled transaction notifications',
    () async {
      final scheduler = RecordingNotificationScheduler(idsToReturn: [42]);
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          preferences: const UserPreferences(notificationsEnabled: true),
        ),
        notificationScheduler: scheduler,
      );

      await store.saveScheduledTransaction(
        ScheduledTransactionRecord(
          id: 'sched-rent',
          type: TransactionType.expense,
          accountId: 'checking',
          categoryId: 'dining',
          payee: 'Rent',
          amountMinor: 90000,
          nextDate: DateTime(2026, 8, 1),
          frequency: RecurrenceFrequency.monthly,
          alertPreference: AlertPreference.sameDay,
          sync: SyncMetadata.fresh(now: DateTime(2026, 7, 1)),
        ),
      );

      final scheduled = store.scheduledTransactions.single;
      expect(scheduler.permissionRequests, 1);
      expect(scheduler.scheduledIds, ['sched-rent']);
      expect(scheduled.scheduledNotificationIds, [42]);
      expect(scheduled.lastReminderScheduledAt, isNotNull);

      await store.savePreferences(
        store.preferences.copyWith(notificationsEnabled: false),
      );

      final cancelled = store.scheduledTransactions.single;
      expect(scheduler.cancelledIds, ['sched-rent']);
      expect(cancelled.scheduledNotificationIds, isEmpty);
      expect(cancelled.lastReminderScheduledAt, isNull);
    },
  );

  test('store counts only active due scheduled transactions', () {
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        scheduledTransactions: [
          _scheduledTransaction(id: 'overdue', nextDate: DateTime(2026, 7, 5)),
          _scheduledTransaction(id: 'today', nextDate: DateTime(2026, 7, 6)),
          _scheduledTransaction(id: 'future', nextDate: DateTime(2026, 7, 7)),
          _scheduledTransaction(
            id: 'skipped',
            nextDate: DateTime(2026, 7, 4),
            lastAction: ScheduledAction.skipped,
          ),
          _scheduledTransaction(
            id: 'deleted',
            nextDate: DateTime(2026, 7, 4),
            sync: SyncMetadata.fresh(
              now: DateTime(2026, 7, 1),
            ).deleted(deviceId: 'test'),
          ),
        ],
      ),
    );

    expect(store.scheduledDueOrOverdueCount(now: DateTime(2026, 7, 6, 18)), 2);
  });

  test('store refreshes scheduled notification badge count', () async {
    final scheduler = RecordingNotificationScheduler();
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        preferences: const UserPreferences(notificationsEnabled: true),
        scheduledTransactions: [
          _scheduledTransaction(id: 'today', nextDate: DateTime(2026, 7, 6)),
          _scheduledTransaction(id: 'future', nextDate: DateTime(2026, 7, 8)),
        ],
      ),
      notificationScheduler: scheduler,
    );

    await store.refreshScheduledNotificationBadge(now: DateTime(2026, 7, 6));
    expect(scheduler.badgeCounts, [1]);

    await store.savePreferences(
      store.preferences.copyWith(notificationsEnabled: false),
    );
    expect(scheduler.badgeCounts.last, 0);
  });

  test(
    'actionable schedules exclude resolved, deleted, and orphaned items',
    () {
      final today = DateTime(2026, 7, 21);
      final nextDate = DateTime(2026, 8, 21);
      final paidOnce =
          _scheduledTransaction(id: 'paid-once', nextDate: nextDate).copyWith(
            frequency: RecurrenceFrequency.once,
            occurrences: [
              ScheduledOccurrenceRecord(
                scheduledDate: nextDate,
                plannedAmountMinor: 90000,
                status: ScheduledOccurrenceStatus.paid,
              ),
            ],
          );
      final skippedOnce =
          _scheduledTransaction(
            id: 'skipped-once',
            nextDate: nextDate,
          ).copyWith(
            frequency: RecurrenceFrequency.once,
            occurrences: [
              ScheduledOccurrenceRecord(
                scheduledDate: nextDate,
                plannedAmountMinor: 90000,
                status: ScheduledOccurrenceStatus.skipped,
              ),
            ],
          );
      final deleted = _scheduledTransaction(id: 'deleted', nextDate: nextDate)
          .copyWith(
            sync: SyncMetadata.fresh(
              now: DateTime(2026, 7, 1),
            ).deleted(deviceId: 'test'),
          );
      final orphan = _scheduledTransaction(
        id: 'orphan',
        nextDate: nextDate,
      ).copyWith(accountId: 'missing');
      final orphanedTransfer =
          _scheduledTransaction(
            id: 'orphaned-transfer',
            nextDate: nextDate,
          ).copyWith(
            type: TransactionType.transfer,
            transferAccountId: 'missing-destination',
            clearCategory: true,
          );
      final staleRecurring =
          _scheduledTransaction(
            id: 'stale-recurring',
            nextDate: nextDate,
          ).copyWith(
            occurrences: [
              ScheduledOccurrenceRecord(
                scheduledDate: nextDate,
                plannedAmountMinor: 90000,
                status: ScheduledOccurrenceStatus.paid,
              ),
            ],
          );
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          scheduledTransactions: [
            paidOnce,
            skippedOnce,
            deleted,
            orphan,
            orphanedTransfer,
            staleRecurring,
          ],
        ),
      );

      final actionable = store.actionableScheduledTransactions(now: today);

      expect(actionable, hasLength(1));
      expect(actionable.single.id, 'stale-recurring');
      expect(actionable.single.nextDate, DateTime(2026, 9, 21));
    },
  );

  test(
    'reset scheduled history persists, syncs, and preserves schedules and ledger',
    () async {
      SharedPreferences.setMockInitialValues({});
      const localRepository = LocalFinanceDataSetRepository(
        storageKey: 'scheduled_history_reset_test',
      );
      final scheduler = RecordingNotificationScheduler(idsToReturn: [71]);
      final occurrenceDate = DateTime(2026, 8, 21);
      final activeSchedule =
          _scheduledTransaction(
            id: 'active',
            nextDate: occurrenceDate,
          ).copyWith(
            scheduledNotificationIds: const [42],
            occurrences: [
              ScheduledOccurrenceRecord(
                scheduledDate: occurrenceDate,
                plannedAmountMinor: 25000,
                status: ScheduledOccurrenceStatus.paid,
                actualAmountMinor: 90000,
                actualPaymentDate: DateTime(2026, 8, 22),
                transactionId: 'generated',
              ),
              ScheduledOccurrenceRecord(
                scheduledDate: DateTime(2026, 7, 21),
                plannedAmountMinor: 25000,
                status: ScheduledOccurrenceStatus.skipped,
              ),
            ],
          );
      final generated = TransactionRecord(
        id: 'generated',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: DateTime(2026, 8, 22),
        payee: 'Paid occurrence',
        amountMinor: 90000,
        scheduledTransactionId: activeSchedule.id,
        scheduledOccurrenceDate: occurrenceDate,
        scheduledPlannedAmountMinor: 25000,
        sync: SyncMetadata.fresh(now: DateTime(2026, 8, 22)),
      );
      final manual = TransactionRecord(
        id: 'manual',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: DateTime(2026, 8, 23),
        payee: 'Manual purchase',
        amountMinor: 1234,
        sync: SyncMetadata.fresh(now: DateTime(2026, 8, 23)),
      );
      final before = _dataSet().copyWith(
        preferences: const UserPreferences(notificationsEnabled: true),
        transactions: [generated, manual],
        scheduledTransactions: [activeSchedule],
      );
      final remote = FakeRecordRepository(dataSet: before);
      final store = FinanceDataStore(
        dataSet: before,
        localRepository: localRepository,
        remoteRepository: remote,
        notificationScheduler: scheduler,
        userId: 'user',
      );

      await store.resetScheduledHistory(now: DateTime(2026, 8, 22));

      final resetSchedule = store.scheduledTransactions.single;
      expect(resetSchedule.occurrences, isEmpty);
      expect(resetSchedule.nextDate, DateTime(2026, 9, 21));
      expect(resetSchedule.lastAction, ScheduledAction.none);
      expect(resetSchedule.amountMinor, activeSchedule.amountMinor);
      expect(resetSchedule.frequency, activeSchedule.frequency);
      expect(resetSchedule.accountId, activeSchedule.accountId);
      expect(resetSchedule.categoryId, activeSchedule.categoryId);
      expect(resetSchedule.payee, activeSchedule.payee);
      expect(store.transactions, hasLength(2));
      expect(
        store.transactions.singleWhere((item) => item.id == 'manual'),
        manual,
      );
      final retainedGenerated = store.transactions.singleWhere(
        (item) => item.id == 'generated',
      );
      expect(retainedGenerated.amountMinor, 90000);
      expect(retainedGenerated.scheduledTransactionId, isNull);
      expect(retainedGenerated.scheduledOccurrenceDate, isNull);
      expect(retainedGenerated.scheduledPlannedAmountMinor, isNull);
      expect(scheduler.cancelledIds, contains('active'));
      expect(scheduler.scheduledIds, contains('active'));
      expect(remote.savedScheduled.single.occurrences, isEmpty);
      expect(remote.savedTransactions.single.scheduledTransactionId, isNull);

      final reloaded = await FinanceDataStore.load(
        localRepository: localRepository,
      );
      expect(reloaded.scheduledTransactions.single.occurrences, isEmpty);
      expect(reloaded.transactions, hasLength(2));

      remote.remoteDataSet = before;
      await store.attachRemoteSync(remoteRepository: remote, userId: 'user');
      expect(store.scheduledTransactions.single.occurrences, isEmpty);
      expect(
        store.transactions
            .singleWhere((item) => item.id == 'generated')
            .scheduledTransactionId,
        isNull,
      );
    },
  );

  test(
    'deleting a source account immediately removes its actionable schedule',
    () async {
      final scheduler = RecordingNotificationScheduler();
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          preferences: const UserPreferences(notificationsEnabled: true),
          scheduledTransactions: [
            _scheduledTransaction(
              id: 'future',
              nextDate: DateTime(2026, 8, 21),
            ).copyWith(scheduledNotificationIds: const [42]),
          ],
        ),
        notificationScheduler: scheduler,
      );
      expect(
        store.actionableScheduledTransactions(now: DateTime(2026, 7, 21)),
        hasLength(1),
      );

      await store.deleteAccount('checking');

      expect(
        store.actionableScheduledTransactions(now: DateTime(2026, 7, 21)),
        isEmpty,
      );
      expect(scheduler.cancelledIds, contains('future'));
    },
  );

  test(
    'sync-deleting a schedule immediately removes it from actionable data',
    () async {
      final schedule = _scheduledTransaction(
        id: 'future',
        nextDate: DateTime(2026, 8, 21),
      );
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(scheduledTransactions: [schedule]),
      );
      var notifications = 0;
      store.addListener(() => notifications += 1);
      expect(
        store.actionableScheduledTransactions(now: DateTime(2026, 7, 21)),
        hasLength(1),
      );

      await store.saveScheduledTransaction(
        schedule.copyWith(
          sync: schedule.sync.deleted(deviceId: store.deviceId),
        ),
      );

      expect(
        store.actionableScheduledTransactions(now: DateTime(2026, 7, 21)),
        isEmpty,
      );
      expect(notifications, greaterThan(0));
    },
  );
}

class RecordingNotificationScheduler implements NotificationScheduler {
  RecordingNotificationScheduler({
    this.permissionGranted = true,
    this.idsToReturn = const [],
  });

  final bool permissionGranted;
  final List<int> idsToReturn;
  var permissionRequests = 0;
  final scheduledIds = <String>[];
  final cancelledIds = <String>[];
  final badgeCounts = <int>[];

  @override
  Future<void> cancelScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    cancelledIds.add(scheduledTransaction.id);
  }

  @override
  Future<bool> requestPermissionIfNeeded() async {
    permissionRequests += 1;
    return permissionGranted;
  }

  @override
  Future<void> rescheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    cancelledIds.add(scheduledTransaction.id);
    scheduledIds.add(scheduledTransaction.id);
  }

  @override
  Future<List<int>> scheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    scheduledIds.add(scheduledTransaction.id);
    return idsToReturn;
  }

  @override
  Future<void> updateBadgeCount(int dueOrOverdueCount) async {
    badgeCounts.add(dueOrOverdueCount);
  }
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

FinanceDataSet _emptyDataSet() {
  return const FinanceDataSet(
    accounts: [],
    categories: [],
    transactions: [],
    scheduledTransactions: [],
    budgets: [],
    preferences: UserPreferences(),
  );
}

ScheduledTransactionRecord _scheduledTransaction({
  required String id,
  required DateTime nextDate,
  ScheduledAction lastAction = ScheduledAction.none,
  SyncMetadata? sync,
}) {
  return ScheduledTransactionRecord(
    id: id,
    type: TransactionType.expense,
    accountId: 'checking',
    categoryId: 'dining',
    payee: 'Rent',
    amountMinor: 90000,
    nextDate: nextDate,
    frequency: RecurrenceFrequency.monthly,
    alertPreference: AlertPreference.sameDay,
    lastAction: lastAction,
    sync: sync ?? SyncMetadata.fresh(now: DateTime(2026, 7, 1)),
  );
}

class FakeRecordRepository implements FinanceRecordRepository {
  FakeRecordRepository({FinanceDataSet? dataSet})
    : remoteDataSet = dataSet ?? _dataSet();

  FinanceDataSet remoteDataSet;
  final savedAccounts = <AccountRecord>[];
  final savedCategories = <CategoryRecord>[];
  final savedTransactions = <TransactionRecord>[];
  final savedScheduled = <ScheduledTransactionRecord>[];
  final savedBudgets = <BudgetRecord>[];
  UserPreferences? savedPreferences;

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async => remoteDataSet;

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

class AlwaysFailingLocalRepository extends LocalFinanceDataSetRepository {
  const AlwaysFailingLocalRepository();

  @override
  Future<void> save(FinanceDataSet dataSet) {
    throw StateError('Local paired save failed');
  }
}
