import 'package:flutter_test/flutter_test.dart';
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
    expect(store.incomeThisMonthMinor(now: DateTime(2026, 7, 10)), 50000);
    expect(store.expensesThisMonthMinor(now: DateTime(2026, 7, 10)), 1250);
  });

  test('user preferences copy without losing unrelated settings', () {
    const preferences = UserPreferences(
      appearanceMode: AppearanceMode.dark,
      currency: CurrencyFormatSettings(currencyCode: 'USD', symbol: r'$'),
      defaultTransactionType: DefaultTransactionType.lastUsed,
      collapsedAccountGroupNames: {'cash'},
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

    final roundTripped = UserPreferences.fromJson(updated.toJson());
    expect(roundTripped.collapsedAccountGroupNames, {'cash'});
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
