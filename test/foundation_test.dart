import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_tally/src/credit/credit_insights_calculator.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/scheduled_occurrence_authority.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/notifications/notification_scheduler.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/persistence/scheduled_notification_state_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  test(
    'ordinary sync records converge on cloud authority when timestamps tie',
    () {
      final timestamp = DateTime.utc(2026, 8, 23, 19, 54);
      final remoteSync = SyncMetadata(
        createdAt: timestamp,
        updatedAt: timestamp,
        deviceId: 'phone',
        version: 2,
      );
      final staleLocalSync = SyncMetadata(
        createdAt: timestamp,
        updatedAt: timestamp,
        deviceId: 'tablet',
        version: 1,
      );
      TransactionRecord transaction({
        required SyncMetadata sync,
        required bool linked,
      }) {
        return TransactionRecord(
          id: 'paid-occurrence',
          type: TransactionType.expense,
          accountId: 'checking',
          categoryId: 'dining',
          date: DateTime(2026, 8, 22),
          payee: 'Test payment',
          amountMinor: 5000,
          scheduledTransactionId: linked ? 'schedule' : null,
          scheduledOccurrenceDate: linked ? DateTime(2026, 8, 22) : null,
          scheduledPlannedAmountMinor: linked ? 5000 : null,
          sync: sync,
        );
      }

      final authoritativeRemote = transaction(sync: remoteSync, linked: false);
      final staleLocal = transaction(sync: staleLocalSync, linked: true);
      final higherRevisionMerge = mergeFinanceDataSetsPreferCurrent(
        incoming: _emptyDataSet().copyWith(transactions: [authoritativeRemote]),
        current: _emptyDataSet().copyWith(transactions: [staleLocal]),
      );

      expect(
        higherRevisionMerge.transactions.single.scheduledTransactionId,
        isNull,
      );

      final divergentExactTie = transaction(sync: remoteSync, linked: true);
      final exactTieMerge = mergeFinanceDataSetsPreferCurrent(
        incoming: _emptyDataSet().copyWith(transactions: [authoritativeRemote]),
        current: _emptyDataSet().copyWith(transactions: [divergentExactTie]),
      );
      final repeated = mergeFinanceDataSetsPreferCurrent(
        incoming: _emptyDataSet().copyWith(transactions: [authoritativeRemote]),
        current: exactTieMerge,
      );

      expect(
        exactTieMerge.transactions.single.toJson(),
        authoritativeRemote.toJson(),
      );
      expect(
        repeated.transactions.single.toJson(),
        authoritativeRemote.toJson(),
      );
    },
  );

  test(
    'deleted transaction payloads converge instead of preferring each device',
    () {
      final createdAt = DateTime.utc(2026, 8, 20);
      final olderDeleted = TransactionRecord(
        id: 'deleted-scheduled-payment',
        type: TransactionType.expense,
        accountId: 'checking',
        date: DateTime.utc(2026, 8, 22),
        payee: 'Test payment',
        amountMinor: 5000,
        scheduledTransactionId: 'old-schedule',
        scheduledOccurrenceDate: DateTime.utc(2026, 8, 22),
        scheduledPlannedAmountMinor: 5000,
        sync: SyncMetadata(
          createdAt: createdAt,
          updatedAt: DateTime.utc(2026, 8, 22, 12),
          deletedAt: DateTime.utc(2026, 8, 22, 12),
          deviceId: 'device-b',
          version: 2,
        ),
      );
      final newerClearedLinkage = olderDeleted.copyWith(
        clearScheduledTransaction: true,
        sync: SyncMetadata(
          createdAt: createdAt,
          updatedAt: DateTime.utc(2026, 8, 23, 12),
          deletedAt: DateTime.utc(2026, 8, 22, 12),
          deviceId: 'device-a',
          version: 3,
        ),
      );

      final merged = mergeFinanceDataSetsPreferCurrent(
        incoming: _emptyDataSet().copyWith(transactions: [newerClearedLinkage]),
        current: _emptyDataSet().copyWith(transactions: [olderDeleted]),
      );

      expect(merged.transactions.single.isDeleted, isTrue);
      expect(merged.transactions.single.scheduledTransactionId, isNull);
      expect(merged.transactions.single.sync.version, 3);

      final exactTieLocal = olderDeleted.copyWith(
        sync: newerClearedLinkage.sync,
      );
      final tieMerged = mergeFinanceDataSetsPreferCurrent(
        incoming: _emptyDataSet().copyWith(transactions: [newerClearedLinkage]),
        current: _emptyDataSet().copyWith(transactions: [exactTieLocal]),
      );
      expect(tieMerged.transactions.single.scheduledTransactionId, isNull);
    },
  );

  test('scheduled occurrence metadata round trips', () {
    final scheduled = ScheduledTransactionRecord(
      id: 'sched-card',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      payee: 'Card payment',
      amountMinor: 25000,
      splitLines: const [
        TransactionSplitLine(
          id: 'split-dining',
          categoryId: 'dining',
          amountMinor: 15000,
        ),
        TransactionSplitLine(
          id: 'split-other',
          categoryId: 'other',
          amountMinor: 10000,
        ),
      ],
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
    expect(restoredSchedule.splitLines, hasLength(2));
    expect(restoredSchedule.splitTotalMinor, 25000);
    expect(restoredSchedule.hasValidSplitTotal, isTrue);
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

  test('transaction status changes use normal per-record cloud sync', () async {
    final remote = FakeRecordRepository();
    final store = FinanceDataStore(
      dataSet: _dataSet(),
      remoteRepository: remote,
      userId: 'user',
    );
    final pending = await store.addExpense(
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 7, 6),
      payee: 'Pending',
      amountMinor: 1000,
      status: TransactionStatus.pending,
    );
    final balance = store.balanceForAccount('checking');
    remote.savedTransactions.clear();

    final cleared = await store.setTransactionStatus(
      pending.id,
      TransactionStatus.cleared,
    );

    expect(cleared.status, TransactionStatus.cleared);
    expect(remote.savedTransactions, hasLength(1));
    expect(remote.savedTransactions.single.status, TransactionStatus.cleared);
    expect(store.balanceForAccount('checking'), balance);
  });

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
    expect(
      store.creditAvailableMinorForGroup(AccountGroup.creditCards),
      125000,
    );

    expect(store.remainingLoanMinorForAccount('loan'), 1000000);
    expect(store.loanPaidDownMinorForAccount('loan'), 500000);
    expect(store.remainingLoanMinorForGroup(AccountGroup.loans), 1000000);
    expect(store.originalLoanAmountMinorForGroup(AccountGroup.loans), 1500000);
  });

  test('credit insights account metadata is optional and round-trips', () {
    final account = AccountRecord(
      id: 'card',
      name: 'Credit Card',
      type: AccountType.creditCard,
      openingBalanceMinor: -50000,
      creditLimitMinor: 200000,
      interestEstimationEnabled: true,
      creditInsightsDisclosureAcknowledged: true,
      annualPercentageRate: 29.99,
      statementClosingDay: 15,
      paymentDueDay: 7,
      creditCardIconId: 'rectangleStackFill',
      creditCardAccentId: 'indigo',
      sync: SyncMetadata.fresh(now: DateTime(2026, 8, 4)),
    );

    final restored = AccountRecord.fromJson(account.toJson());
    expect(restored.interestEstimationEnabled, isTrue);
    expect(restored.creditInsightsDisclosureAcknowledged, isTrue);
    expect(restored.annualPercentageRate, 29.99);
    expect(restored.statementClosingDay, 15);
    expect(restored.paymentDueDay, 7);
    expect(restored.creditCardIconId, 'rectangleStackFill');
    expect(restored.creditCardAccentId, 'indigo');
    expect(
      restored.copyWith(clearCreditCardAccent: true).creditCardAccentId,
      isNull,
    );

    final olderRecord = AccountRecord.fromJson({
      ...account.toJson(),
      'interestEstimationEnabled': null,
      'creditInsightsDisclosureAcknowledged': null,
      'annualPercentageRate': null,
      'statementClosingDay': null,
      'paymentDueDay': null,
      'creditCardIconId': null,
      'creditCardAccentId': null,
    });
    expect(olderRecord.interestEstimationEnabled, isFalse);
    expect(olderRecord.creditInsightsDisclosureAcknowledged, isFalse);
    expect(olderRecord.annualPercentageRate, isNull);
    expect(olderRecord.statementClosingDay, isNull);
    expect(olderRecord.paymentDueDay, isNull);
    expect(olderRecord.creditCardIconId, isNull);
    expect(olderRecord.creditCardAccentId, isNull);

    final legacyEnabledRecord = AccountRecord.fromJson(
      {...account.toJson()}..remove('creditInsightsDisclosureAcknowledged'),
    );
    expect(legacyEnabledRecord.interestEstimationEnabled, isTrue);
    expect(legacyEnabledRecord.creditInsightsDisclosureAcknowledged, isTrue);
  });

  test('shared account appearance IDs round-trip for non-credit accounts', () {
    final account = AccountRecord(
      id: 'savings',
      name: 'Emergency Savings',
      type: AccountType.savings,
      openingBalanceMinor: 250000,
      creditCardIconId: 'portfolio',
      creditCardAccentId: 'gold',
      sync: SyncMetadata.fresh(now: DateTime(2026, 8, 8)),
    );

    final restored = AccountRecord.fromJson(account.toJson());

    expect(restored.appearanceIconId, 'portfolio');
    expect(restored.appearanceAccentId, 'gold');
    expect(restored.openingBalanceMinor, 250000);
    expect(restored.type, AccountType.savings);
    expect(restored.name, 'Emergency Savings');
  });

  group('credit insights daily average balance', () {
    test('constant balance uses every represented day', () {
      const calculator = CreditInsightsCalculator();
      final account = _creditInsightsAccount(
        openingBalanceMinor: -100000,
        createdAt: DateTime(2026, 7, 1),
        statementClosingDay: 31,
        annualPercentageRate: 24,
      );
      final estimate = calculator.calculate(
        account: account,
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 8, 30),
      );

      expect(estimate.cycleStart, DateTime(2026, 8, 1));
      expect(estimate.cycleEnd, DateTime(2026, 8, 31));
      expect(estimate.daysRepresented, 30);
      expect(estimate.averageDailyBalanceMinor, 100000);
      expect(estimate.estimatedInterestMinor, 2038);
      expect(estimate.projectedStatementMinor, -102038);
      expect(
        estimate.estimateCompleteness,
        CreditInsightsEstimateCompleteness.complete,
      );
    });

    test('mid-cycle purchase increases debt from its date forward', () {
      const calculator = CreditInsightsCalculator();
      final account = _creditInsightsAccount(
        openingBalanceMinor: -100000,
        createdAt: DateTime(2026, 7, 1),
        statementClosingDay: 31,
      );
      final purchase = _creditExpense(
        id: 'purchase',
        date: DateTime(2026, 8, 16),
        amountMinor: 50000,
      );
      final estimate = calculator.calculate(
        account: account,
        transactions: [purchase],
        currentBalanceMinor: -150000,
        today: DateTime(2026, 8, 30),
      );

      expect(estimate.averageDailyBalanceMinor, closeTo(125806.45, 0.01));
      expect(estimate.estimatedInterestMinor, 2564);
    });

    test('mid-cycle payment reduces debt from its date forward', () {
      const calculator = CreditInsightsCalculator();
      final account = _creditInsightsAccount(
        openingBalanceMinor: -200000,
        createdAt: DateTime(2026, 7, 1),
        statementClosingDay: 31,
      );
      final payment = _creditPayment(
        id: 'payment',
        date: DateTime(2026, 8, 16),
        amountMinor: 50000,
      );
      final estimate = calculator.calculate(
        account: account,
        transactions: [payment],
        currentBalanceMinor: -150000,
        today: DateTime(2026, 8, 30),
      );

      expect(estimate.averageDailyBalanceMinor, closeTo(174193.55, 0.01));
      expect(estimate.estimatedInterestMinor, 3551);
    });

    test('multiple purchases and payments reconstruct end-of-day balances', () {
      const calculator = CreditInsightsCalculator();
      final account = _creditInsightsAccount(
        openingBalanceMinor: -100000,
        createdAt: DateTime(2026, 7, 1),
        statementClosingDay: 31,
      );
      final estimate = calculator.calculate(
        account: account,
        transactions: [
          _creditExpense(
            id: 'purchase-1',
            date: DateTime(2026, 8, 3),
            amountMinor: 50000,
          ),
          _creditPayment(
            id: 'payment-1',
            date: DateTime(2026, 8, 5),
            amountMinor: 25000,
          ),
          _creditExpense(
            id: 'purchase-2',
            date: DateTime(2026, 8, 7),
            amountMinor: 10000,
          ),
        ],
        currentBalanceMinor: -135000,
        today: DateTime(2026, 8, 8),
      );

      // EOD debt: 1000, 1000, 1500, 1500, 1250, 1250, 1350, 1350.
      expect(estimate.averageDailyBalanceMinor, closeTo(133064.52, 0.01));
      expect(estimate.daysRepresented, 8);
    });

    test('closing day retains accrued interest', () {
      const calculator = CreditInsightsCalculator();
      final account = _creditInsightsAccount(
        openingBalanceMinor: -100000,
        createdAt: DateTime(2026, 7, 1),
        statementClosingDay: 8,
      );
      final estimate = calculator.calculate(
        account: account,
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 8, 8),
      );

      expect(estimate.daysUntilStatementClosing, 0);
      expect(estimate.daysRepresented, 31);
      expect(estimate.estimatedInterestMinor, 2038);
    });

    test('closing day 31 clamps to February month end', () {
      const calculator = CreditInsightsCalculator();
      final cycle = calculator.currentStatementCycle(
        statementClosingDay: 31,
        today: DateTime(2028, 2, 29),
      );

      expect(cycle?.start, DateTime(2028, 2, 1));
      expect(cycle?.end, DateTime(2028, 2, 29));
    });

    test('zero and credit balances never produce negative interest', () {
      const calculator = CreditInsightsCalculator();
      for (final balance in [0, 25000]) {
        final account = _creditInsightsAccount(
          openingBalanceMinor: balance,
          createdAt: DateTime(2026, 7, 1),
          statementClosingDay: 31,
        );
        final estimate = calculator.calculate(
          account: account,
          transactions: const [],
          currentBalanceMinor: balance,
          today: DateTime(2026, 8, 8),
        );

        expect(estimate.estimatedInterestMinor, 0);
        expect(estimate.projectedStatementMinor, balance);
      }
    });

    test('mid-cycle account history is explicitly partial', () {
      const calculator = CreditInsightsCalculator();
      final account = _creditInsightsAccount(
        openingBalanceMinor: -100000,
        createdAt: DateTime(2026, 8, 10),
        statementClosingDay: 31,
      );
      final estimate = calculator.calculate(
        account: account,
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 8, 20),
      );

      expect(estimate.representedStart, DateTime(2026, 8, 10));
      expect(estimate.daysRepresented, 11);
      expect(
        estimate.estimateCompleteness,
        CreditInsightsEstimateCompleteness.partial,
      );
    });

    test('history beginning after today is insufficient', () {
      const calculator = CreditInsightsCalculator();
      final account = _creditInsightsAccount(
        openingBalanceMinor: -100000,
        createdAt: DateTime(2026, 8, 10),
        statementClosingDay: 31,
      );
      final estimate = calculator.calculate(
        account: account,
        transactions: const [],
        currentBalanceMinor: -100000,
        today: DateTime(2026, 8, 8),
      );

      expect(estimate.estimatedInterestMinor, isNull);
      expect(
        estimate.estimateCompleteness,
        CreditInsightsEstimateCompleteness.insufficientHistory,
      );
    });

    test('day after closing begins the next cycle', () {
      const calculator = CreditInsightsCalculator();
      final cycle = calculator.currentStatementCycle(
        statementClosingDay: 8,
        today: DateTime(2026, 8, 9),
      );

      expect(cycle?.start, DateTime(2026, 8, 9));
      expect(cycle?.end, DateTime(2026, 9, 8));
    });
  });

  test('credit insights closing date handles passed and shortened months', () {
    const calculator = CreditInsightsCalculator();

    expect(
      calculator.nextStatementClosingDate(
        statementClosingDay: 15,
        today: DateTime(2026, 8, 16),
      ),
      DateTime(2026, 9, 15),
    );
    expect(
      calculator.nextStatementClosingDate(
        statementClosingDay: 31,
        today: DateTime(2026, 2, 1),
      ),
      DateTime(2026, 2, 28),
    );
  });

  test('credit insights due date handles boundaries and year rollover', () {
    const calculator = CreditInsightsCalculator();

    expect(
      calculator.nextPaymentDueDate(
        paymentDueDay: 31,
        today: DateTime(2026, 2, 1),
      ),
      DateTime(2026, 2, 28),
    );
    expect(
      calculator.nextPaymentDueDate(
        paymentDueDay: 7,
        today: DateTime(2026, 12, 8),
      ),
      DateTime(2027, 1, 7),
    );
    expect(
      calculator.nextPaymentDueDate(
        paymentDueDay: 8,
        today: DateTime(2026, 8, 8),
      ),
      DateTime(2026, 8, 8),
    );
  });

  test(
    'credit card payment due follows the earliest unresolved linked transfer',
    () {
      final base = _dataSet();
      final sync = SyncMetadata.fresh(now: DateTime(2026, 8, 1));
      final card = AccountRecord(
        id: 'credit-card',
        name: 'Credit Card',
        type: AccountType.creditCard,
        openingBalanceMinor: -50000,
        paymentDueDay: 28,
        sync: sync,
      );
      ScheduledTransactionRecord paymentSchedule({
        required String id,
        required DateTime nextDate,
      }) => ScheduledTransactionRecord(
        id: id,
        type: TransactionType.transfer,
        accountId: 'checking',
        transferAccountId: card.id,
        payee: 'Card payment',
        amountMinor: 10000,
        nextDate: nextDate,
        frequency: RecurrenceFrequency.monthly,
        sync: sync,
      );
      final store = FinanceDataStore(
        dataSet: base.copyWith(
          accounts: [...base.accounts, card],
          scheduledTransactions: [
            paymentSchedule(
              id: 'later-payment',
              nextDate: DateTime(2026, 9, 5),
            ),
            paymentSchedule(
              id: 'august-payment',
              nextDate: DateTime(2026, 8, 28),
            ),
          ],
        ),
      );

      expect(
        store.nextCreditCardPaymentDueDate(card.id, now: DateTime(2026, 8, 14)),
        DateTime(2026, 8, 28),
      );
      expect(
        store.nextCreditCardPaymentDueDate(
          'checking',
          now: DateTime(2026, 8, 14),
        ),
        isNull,
      );
    },
  );

  test(
    'paid card occurrence advances regardless of Pending or Cleared status',
    () {
      final base = _dataSet();
      final dueDate = DateTime(2026, 8, 28);
      final nextDate = DateTime(2026, 9, 28);
      final sync = SyncMetadata.fresh(now: DateTime(2026, 8, 1));
      final card = AccountRecord(
        id: 'credit-card',
        name: 'Credit Card',
        type: AccountType.creditCard,
        openingBalanceMinor: -50000,
        sync: sync,
      );
      final occurrence = ScheduledOccurrenceRecord(
        scheduledDate: dueDate,
        plannedAmountMinor: 10000,
        status: ScheduledOccurrenceStatus.paid,
        actualAmountMinor: 10000,
        actualPaymentDate: DateTime(2026, 8, 14),
        transactionId: 'card-payment',
      );
      final schedule = ScheduledTransactionRecord(
        id: 'card-payment-schedule',
        type: TransactionType.transfer,
        accountId: 'checking',
        transferAccountId: card.id,
        payee: 'Card payment',
        amountMinor: 10000,
        nextDate: nextDate,
        frequency: RecurrenceFrequency.monthly,
        occurrences: [occurrence],
        sync: sync,
      );

      for (final status in [
        TransactionStatus.pending,
        TransactionStatus.cleared,
      ]) {
        final transaction = TransactionRecord(
          id: 'card-payment',
          type: TransactionType.transfer,
          accountId: 'checking',
          transferAccountId: card.id,
          date: DateTime(2026, 8, 14),
          payee: 'Card payment',
          amountMinor: 10000,
          status: status,
          scheduledTransactionId: schedule.id,
          scheduledOccurrenceDate: dueDate,
          scheduledPlannedAmountMinor: 10000,
          sync: sync,
        );
        final store = FinanceDataStore(
          dataSet: base.copyWith(
            accounts: [...base.accounts, card],
            transactions: [transaction],
            scheduledTransactions: [schedule],
          ),
        );

        expect(
          store.nextCreditCardPaymentDueDate(
            card.id,
            now: DateTime(2026, 8, 14),
          ),
          nextDate,
          reason: 'Ledger status $status must not keep August due',
        );
      }
    },
  );

  test('undo card payment restores the earlier unresolved due date', () async {
    final base = _dataSet();
    final dueDate = DateTime(2026, 8, 28);
    final sync = SyncMetadata.fresh(now: DateTime(2026, 8, 1));
    final card = AccountRecord(
      id: 'credit-card',
      name: 'Credit Card',
      type: AccountType.creditCard,
      openingBalanceMinor: -50000,
      sync: sync,
    );
    final transaction = TransactionRecord(
      id: 'card-payment',
      type: TransactionType.transfer,
      accountId: 'checking',
      transferAccountId: card.id,
      date: DateTime(2026, 8, 14),
      payee: 'Card payment',
      amountMinor: 10000,
      status: TransactionStatus.pending,
      scheduledTransactionId: 'card-payment-schedule',
      scheduledOccurrenceDate: dueDate,
      scheduledPlannedAmountMinor: 10000,
      sync: sync,
    );
    final schedule = ScheduledTransactionRecord(
      id: 'card-payment-schedule',
      type: TransactionType.transfer,
      accountId: 'checking',
      transferAccountId: card.id,
      payee: 'Card payment',
      amountMinor: 10000,
      nextDate: DateTime(2026, 9, 28),
      frequency: RecurrenceFrequency.monthly,
      occurrences: [
        ScheduledOccurrenceRecord(
          scheduledDate: dueDate,
          plannedAmountMinor: 10000,
          status: ScheduledOccurrenceStatus.paid,
          actualAmountMinor: 10000,
          actualPaymentDate: transaction.date,
          transactionId: transaction.id,
        ),
      ],
      sync: sync,
    );
    final store = FinanceDataStore(
      dataSet: base.copyWith(
        accounts: [...base.accounts, card],
        transactions: [transaction],
        scheduledTransactions: [schedule],
      ),
    );

    expect(
      store.nextCreditCardPaymentDueDate(card.id, now: DateTime(2026, 8, 14)),
      DateTime(2026, 9, 28),
    );
    await store.undoScheduledPayment(
      transaction.id,
      now: DateTime(2026, 8, 14),
    );
    expect(
      store.nextCreditCardPaymentDueDate(card.id, now: DateTime(2026, 8, 14)),
      dueDate,
    );
  });

  test(
    'card payment due handles no future occurrence and stored month end',
    () {
      final base = _dataSet();
      final sync = SyncMetadata.fresh(now: DateTime(2028, 1, 1));
      final card = AccountRecord(
        id: 'credit-card',
        name: 'Credit Card',
        type: AccountType.creditCard,
        openingBalanceMinor: -50000,
        sync: sync,
      );
      ScheduledTransactionRecord schedule({
        required String id,
        required DateTime nextDate,
        RecurrenceFrequency frequency = RecurrenceFrequency.monthly,
        ScheduledAction lastAction = ScheduledAction.none,
        SyncMetadata? recordSync,
      }) => ScheduledTransactionRecord(
        id: id,
        type: TransactionType.transfer,
        accountId: 'checking',
        transferAccountId: card.id,
        payee: 'Card payment',
        amountMinor: 10000,
        nextDate: nextDate,
        frequency: frequency,
        lastAction: lastAction,
        sync: recordSync ?? sync,
      );
      final monthEndStore = FinanceDataStore(
        dataSet: base.copyWith(
          accounts: [...base.accounts, card],
          scheduledTransactions: [
            schedule(id: 'february-leap', nextDate: DateTime(2028, 2, 29)),
            schedule(id: 'march-31', nextDate: DateTime(2028, 3, 31)),
          ],
        ),
      );
      expect(
        monthEndStore.nextCreditCardPaymentDueDate(
          card.id,
          now: DateTime(2028, 2, 1),
        ),
        DateTime(2028, 2, 29),
      );

      final completedOnce = schedule(
        id: 'completed-once',
        nextDate: DateTime(2028, 2, 29),
        frequency: RecurrenceFrequency.once,
        lastAction: ScheduledAction.paid,
        recordSync: sync.deleted(now: DateTime(2028, 2, 1)),
      );
      final completedStore = FinanceDataStore(
        dataSet: base.copyWith(
          accounts: [...base.accounts, card],
          scheduledTransactions: [completedOnce],
        ),
      );
      expect(
        completedStore.nextCreditCardPaymentDueDate(
          card.id,
          now: DateTime(2028, 2, 1),
        ),
        isNull,
      );
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
      categories: [
        for (final category in _dataSet().categories)
          if (category.id == 'dining')
            category.copyWith(iconName: 'fork.knife', colorValue: 0xFF0F766E)
          else if (category.id == 'snacks')
            category.copyWith(iconName: 'food.tip', colorValue: 0xFF7C3AED)
          else
            category,
      ],
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
      budgets: [
        BudgetRecord(
          id: 'budget-weekly',
          name: 'Weekly groceries',
          period: BudgetPeriod.weekly,
          amountMinor: 25000,
          categoryIds: const ['dining'],
          weekStartDay: DateTime.monday,
          rolloverEnabled: true,
          note: 'Carry the difference',
          configurationRevisions: [
            BudgetConfigurationRevision(
              id: 'budget-weekly-r1',
              effectiveDate: DateTime(2026, 7, 6),
              period: BudgetPeriod.weekly,
              amountMinor: 25000,
              categoryIds: const ['dining'],
              anchorDate: DateTime(2026, 7, 6),
              weekStartDay: DateTime.monday,
              rolloverEnabled: true,
            ),
          ],
          sync: SyncMetadata.fresh(now: DateTime(2026, 7, 6)),
        ),
      ],
    );

    final restored = codec.decodeJson(codec.encodeJson(dataSet));

    expect(restored.accounts.length, dataSet.accounts.length);
    expect(restored.accounts.first.creditLimitMinor, 250000);
    expect(restored.transactions.single.type, TransactionType.transfer);
    expect(restored.transactions.single.transferAccountId, 'cash');
    expect(
      restored.categories.singleWhere((item) => item.id == 'dining').iconName,
      'fork.knife',
    );
    expect(
      restored.categories.singleWhere((item) => item.id == 'snacks').iconName,
      'food.tip',
    );
    expect(
      restored.categories.singleWhere((item) => item.id == 'snacks').colorValue,
      0xFF7C3AED,
    );
    expect(restored.budgets.single.period, BudgetPeriod.weekly);
    expect(restored.budgets.single.rolloverEnabled, isTrue);
    expect(restored.budgets.single.configurationRevisions, hasLength(1));
    expect(
      restored.budgets.single.configurationRevisions.single.weekStartDay,
      DateTime.monday,
    );
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

  test('scheduled splits persist locally and through record sync', () async {
    SharedPreferences.setMockInitialValues({});
    const localRepository = LocalFinanceDataSetRepository(
      storageKey: 'scheduled_split_persistence_test',
    );
    final remote = FakeRecordRepository();
    final store = FinanceDataStore(
      dataSet: _dataSet(),
      localRepository: localRepository,
      remoteRepository: remote,
      userId: 'split-user',
    );
    final schedule = ScheduledTransactionRecord(
      id: 'scheduled-split',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      splitLines: const [
        TransactionSplitLine(
          id: 'scheduled-dining',
          categoryId: 'dining',
          amountMinor: 6000,
        ),
        TransactionSplitLine(
          id: 'scheduled-snacks',
          categoryId: 'snacks',
          amountMinor: 4000,
        ),
      ],
      payee: 'Split plan',
      amountMinor: 10000,
      nextDate: DateTime(2026, 8, 15),
      frequency: RecurrenceFrequency.monthly,
      sync: SyncMetadata.fresh(now: DateTime(2026, 7, 20)),
    );

    await store.saveScheduledTransaction(schedule);

    expect(remote.savedScheduled, hasLength(1));
    expect(
      remote.savedScheduled.single.splitLines.map((line) => line.toJson()),
      schedule.splitLines.map((line) => line.toJson()),
    );
    final reloaded = await FinanceDataStore.load(
      localRepository: localRepository,
    );
    final persisted = reloaded.scheduledTransactions.singleWhere(
      (item) => item.id == schedule.id,
    );
    expect(
      persisted.splitLines.map((line) => line.toJson()),
      schedule.splitLines.map((line) => line.toJson()),
    );
    expect(persisted.splitTotalMinor, 10000);
    expect(persisted.hasValidSplitTotal, isTrue);
  });

  test('scheduled split validation rejects an unbalanced payload', () async {
    final store = FinanceDataStore(dataSet: _dataSet());
    final schedule = ScheduledTransactionRecord(
      id: 'unbalanced-split',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      splitLines: const [
        TransactionSplitLine(
          id: 'scheduled-dining',
          categoryId: 'dining',
          amountMinor: 6000,
        ),
        TransactionSplitLine(
          id: 'scheduled-snacks',
          categoryId: 'snacks',
          amountMinor: 3000,
        ),
      ],
      payee: 'Unbalanced plan',
      amountMinor: 10000,
      nextDate: DateTime(2026, 8, 15),
      frequency: RecurrenceFrequency.monthly,
      sync: SyncMetadata.fresh(now: DateTime(2026, 7, 20)),
    );

    await expectLater(
      store.saveScheduledTransaction(schedule),
      throwsA(isA<FinanceDataValidationException>()),
    );
    expect(store.scheduledTransactions, isEmpty);
  });

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

  test('store uses repository bulk capability for a full sync', () async {
    final remote = BulkFakeRecordRepository(dataSet: _emptyDataSet());
    final localDataSet = _dataSet();
    final store = FinanceDataStore(dataSet: localDataSet);

    await store.attachRemoteSync(remoteRepository: remote, userId: 'user-1');

    expect(remote.bulkSaveCount, 1);
    expect(remote.bulkSavedUserId, 'user-1');
    expect(remote.bulkSavedDataSet?.toJson(), localDataSet.toJson());
    expect(remote.bulkSavedBaseline?.toJson(), _emptyDataSet().toJson());
    expect(remote.savedAccounts, isEmpty);
    expect(remote.savedTransactions, isEmpty);
  });

  test(
    'store provides the remote snapshot as the bulk sync baseline',
    () async {
      final dataSet = _dataSet();
      final remote = BulkFakeRecordRepository(dataSet: dataSet);
      final store = FinanceDataStore(dataSet: dataSet);

      await store.attachRemoteSync(remoteRepository: remote, userId: 'user-1');

      expect(remote.bulkSaveCount, 1);
      expect(remote.bulkSavedDataSet?.toJson(), dataSet.toJson());
      expect(remote.bulkSavedBaseline?.toJson(), dataSet.toJson());
    },
  );

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
    'Goal records, contributions, and undo tombstones use per-record sync',
    () async {
      final goal = GoalRecord(
        id: 'remote-goal',
        name: 'Emergency Fund',
        targetAmountMinor: 100000,
        status: GoalStatus.active,
        fundingMethod: GoalFundingMethod.trackingOnly,
        sync: SyncMetadata.fresh(now: DateTime.utc(2026, 7, 20)),
      );
      final contribution = GoalContributionRecord(
        id: 'remote-contribution',
        goalId: goal.id,
        amountMinor: 25000,
        date: DateTime(2026, 7, 21),
        fundingMethod: GoalFundingMethod.trackingOnly,
        sync: SyncMetadata.fresh(now: DateTime.utc(2026, 7, 21)),
      );
      final remote = FakeRecordRepository(dataSet: _emptyDataSet());
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          goals: [goal],
          goalContributions: [contribution],
        ),
        deviceId: 'phone',
      );

      await store.attachRemoteSync(remoteRepository: remote, userId: 'user-1');

      expect(remote.savedGoals.single.id, goal.id);
      expect(remote.savedGoalContributions.single.id, contribution.id);

      await store.undoGoalContribution(contribution.id);
      final tombstone = remote.savedGoalContributions.last;
      expect(tombstone.id, contribution.id);
      expect(tombstone.isDeleted, isTrue);

      remote.remoteDataSet = _emptyDataSet().copyWith(
        goals: [goal],
        goalContributions: [tombstone],
      );
      final signedBackIn = FinanceDataStore(
        dataSet: _emptyDataSet(),
        deviceId: 'tablet',
      );
      await signedBackIn.attachRemoteSync(
        remoteRepository: remote,
        userId: 'user-1',
      );

      expect(signedBackIn.goalById(goal.id).name, 'Emergency Fund');
      expect(
        signedBackIn.goalContributionById(contribution.id).isDeleted,
        isTrue,
      );
      expect(signedBackIn.currentGoalAmountMinor(goal.id), 0);
    },
  );

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
    expect(request.occurrenceDate, DateTime(2026, 8, 1));
    expect(request.title, 'Payment due');
    expect(request.body, 'Rent is due.');
    expect(request.scheduledFor, DateTime(2026, 7, 29, 9));
    expect(request.repeatUntilResolved, isTrue);
    expect(request.id, notificationIdFor('sched-rent'));
    final payload = ScheduledNotificationPayload.tryParse(request.payload);
    expect(payload?.scheduledTransactionId, 'sched-rent');
    expect(payload?.occurrenceDate, DateTime(2026, 8, 1));
  });

  test('notification payload accepts legacy schedule-only identity', () {
    final payload = ScheduledNotificationPayload.tryParse('sched-legacy');
    expect(payload?.scheduledTransactionId, 'sched-legacy');
    expect(payload?.occurrenceDate, isNull);
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
    final afterSkipped = planner.planOne(
      base.copyWith(
        alertPreference: AlertPreference.sameDay,
        occurrences: [
          ScheduledOccurrenceRecord(
            scheduledDate: base.nextDate,
            plannedAmountMinor: base.amountMinor,
            status: ScheduledOccurrenceStatus.skipped,
          ),
        ],
      ),
      now: DateTime(2026, 7, 20),
    );
    expect(afterSkipped?.occurrenceDate, DateTime(2026, 9, 1));
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
      final localNotificationState =
          InMemoryScheduledNotificationStateRepository();
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          preferences: const UserPreferences(notificationsEnabled: true),
        ),
        notificationScheduler: scheduler,
        notificationStateRepository: localNotificationState,
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
      expect(scheduled.scheduledNotificationIds, isEmpty);
      expect(scheduled.lastReminderScheduledAt, isNull);
      expect(
        (await localNotificationState.load('sched-rent'))?.notificationIds,
        [42],
      );

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
          _scheduledTransaction(
            id: 'today',
            nextDate: DateTime(2026, 7, 6),
          ).copyWith(alertPreference: AlertPreference.sameDay),
          _scheduledTransaction(
            id: 'future',
            nextDate: DateTime(2026, 7, 8),
          ).copyWith(alertPreference: AlertPreference.sameDay),
        ],
      ),
      notificationScheduler: scheduler,
    );

    await store.refreshScheduledNotificationBadge(
      now: DateTime(2026, 7, 6, 18),
    );
    expect(scheduler.badgeCounts, [1]);

    await store.savePreferences(
      store.preferences.copyWith(notificationsEnabled: false),
    );
    expect(scheduler.badgeCounts.last, 0);
  });

  test(
    'active alerts are occurrence-specific and independent of OS permission',
    () async {
      final scheduler = RecordingNotificationScheduler(
        permissionGranted: false,
      );
      final due = DateTime(2026, 7, 10);
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          preferences: const UserPreferences(notificationsEnabled: true),
          scheduledTransactions: [
            _scheduledTransaction(
              id: 'rent',
              nextDate: due,
            ).copyWith(alertPreference: AlertPreference.threeDaysBefore),
          ],
        ),
        notificationScheduler: scheduler,
      );

      await store.refreshScheduledNotifications();

      expect(
        store.scheduledTransactions.single.scheduledNotificationIds,
        isEmpty,
      );
      final alerts = store.activeScheduledAlerts(now: DateTime(2026, 7, 7, 12));
      expect(alerts, hasLength(1));
      expect(alerts.single.scheduledTransaction.id, 'rent');
      expect(alerts.single.occurrenceDate, due);
      expect(store.scheduledActiveAlertCount(now: DateTime(2026, 7, 7, 12)), 1);
    },
  );

  test('active alert lifecycle tracks resolution, undo, and recurrence', () {
    final august = DateTime(2026, 8, 28);
    final september = DateTime(2026, 9, 28);
    final base = _scheduledTransaction(id: 'card-payment', nextDate: september)
        .copyWith(
          alertPreference: AlertPreference.oneWeekBefore,
          occurrences: [
            ScheduledOccurrenceRecord(
              scheduledDate: august,
              plannedAmountMinor: 25000,
              status: ScheduledOccurrenceStatus.paid,
            ),
          ],
        );
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        preferences: const UserPreferences(notificationsEnabled: true),
        scheduledTransactions: [base],
      ),
    );

    expect(store.activeScheduledAlerts(now: DateTime(2026, 8, 28)), isEmpty);
    final next = store.activeScheduledAlerts(now: DateTime(2026, 9, 21, 12));
    expect(next, hasLength(1));
    expect(next.single.occurrenceDate, september);

    final restored = base.copyWith(
      nextDate: august,
      occurrences: [
        ScheduledOccurrenceRecord(
          scheduledDate: august,
          plannedAmountMinor: 25000,
          status: ScheduledOccurrenceStatus.pending,
        ),
      ],
    );
    final restoredStore = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        preferences: const UserPreferences(notificationsEnabled: true),
        scheduledTransactions: [restored],
      ),
    );
    final restoredAlerts = restoredStore.activeScheduledAlerts(
      now: DateTime(2026, 8, 28, 12),
    );
    expect(restoredAlerts, hasLength(1));
    expect(restoredAlerts.single.occurrenceDate, august);
  });

  test('editing or deleting a schedule changes the derived active alert', () {
    final original = _scheduledTransaction(
      id: 'editable-alert',
      nextDate: DateTime(2026, 8, 10),
    ).copyWith(alertPreference: AlertPreference.sameDay);
    final dataSet = _dataSet().copyWith(
      preferences: const UserPreferences(notificationsEnabled: true),
      scheduledTransactions: [original],
    );
    final originalStore = FinanceDataStore(dataSet: dataSet);
    expect(
      originalStore.scheduledActiveAlertCount(now: DateTime(2026, 8, 10, 12)),
      1,
    );

    final editedStore = FinanceDataStore(
      dataSet: dataSet.copyWith(
        scheduledTransactions: [
          original.copyWith(nextDate: DateTime(2026, 8, 20)),
        ],
      ),
    );
    expect(
      editedStore.scheduledActiveAlertCount(now: DateTime(2026, 8, 10, 12)),
      0,
    );

    final deletedStore = FinanceDataStore(
      dataSet: dataSet.copyWith(
        scheduledTransactions: [
          original.copyWith(sync: original.sync.deleted(deviceId: 'test')),
        ],
      ),
    );
    expect(
      deletedStore.scheduledActiveAlertCount(now: DateTime(2026, 8, 10, 12)),
      0,
    );
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
            occurrenceStates: {
              '20260921': ScheduledOccurrenceState(
                scheduledDate: DateTime(2026, 9, 21),
                plannedAmountMinor: 25000,
                status: ScheduledOccurrenceStatus.pending,
                revision: 2,
                operationId: 'undo-pending',
                changedAt: DateTime.utc(2026, 8, 22),
                deviceId: 'phone',
              ),
            },
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
      expect(resetSchedule.occurrences.map((item) => item.status), [
        ScheduledOccurrenceStatus.pending,
      ]);
      expect(resetSchedule.occurrenceHistoryEpoch?.revision, 1);
      expect(resetSchedule.occurrenceStates.keys, ['20260921']);
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
      expect(
        remote.savedScheduled.single.occurrences.map((item) => item.status),
        [ScheduledOccurrenceStatus.pending],
      );
      expect(remote.savedTransactions.single.scheduledTransactionId, isNull);

      final reloaded = await FinanceDataStore.load(
        localRepository: localRepository,
      );
      expect(
        reloaded.scheduledTransactions.single.occurrences.map(
          (item) => item.status,
        ),
        [ScheduledOccurrenceStatus.pending],
      );
      expect(reloaded.transactions, hasLength(2));

      remote.remoteDataSet = before;
      await store.attachRemoteSync(remoteRepository: remote, userId: 'user');
      // A stale epoch-zero replica cannot resurrect erased Paid/Skipped
      // history, while the explicitly preserved Pending occurrence remains.
      expect(
        store.scheduledTransactions.single.occurrences.map(
          (item) => item.status,
        ),
        [ScheduledOccurrenceStatus.pending],
      );
      expect(
        store.transactions
            .singleWhere((item) => item.id == 'generated')
            .scheduledTransactionId,
        isNull,
      );
    },
  );

  test('reset preserves actionable Pending alert and badge state', () async {
    final scheduler = RecordingNotificationScheduler(idsToReturn: [81]);
    final today = DateTime(2026, 8, 23);
    final historicalDate = DateTime(2026, 7, 23);
    final historical = ScheduledOccurrenceState(
      scheduledDate: historicalDate,
      plannedAmountMinor: 25000,
      status: ScheduledOccurrenceStatus.paid,
      revision: 1,
      operationId: 'paid-history',
      changedAt: DateTime.utc(2026, 7, 23),
      deviceId: 'phone',
    );
    final pending = ScheduledOccurrenceState(
      scheduledDate: today,
      plannedAmountMinor: 25000,
      status: ScheduledOccurrenceStatus.pending,
      revision: 2,
      operationId: 'undo-current',
      changedAt: DateTime.utc(2026, 8, 22),
      deviceId: 'phone',
    );
    final base = _scheduledTransaction(id: 'alert', nextDate: today).copyWith(
      occurrenceStates: {
        occurrenceDayKey(historicalDate): historical,
        occurrenceDayKey(today): pending,
      },
      occurrences: legacyOccurrencesFromAuthority([historical, pending]),
      sync: _scheduledTransaction(id: 'alert', nextDate: today).sync,
    );
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        preferences: const UserPreferences(notificationsEnabled: true),
        scheduledTransactions: [base],
      ),
      notificationScheduler: scheduler,
    );

    final afterAlert = DateTime(2026, 8, 23, 23, 59);
    await store.resetScheduledHistory(now: afterAlert);

    final reset = store.scheduledTransactions.single;
    expect(reset.occurrenceStates.keys, [occurrenceDayKey(today)]);
    expect(
      reset.occurrenceStates[occurrenceDayKey(today)]?.status,
      ScheduledOccurrenceStatus.pending,
    );
    expect(store.activeScheduledAlerts(now: afterAlert), hasLength(1));
    expect(scheduler.badgeCounts.last, 1);
  });

  test(
    'cloud history-reset failure is surfaced and local data is retained',
    () async {
      final occurrenceDate = DateTime(2026, 8, 21);
      final schedule =
          _scheduledTransaction(
            id: 'cloud-failure',
            nextDate: occurrenceDate,
          ).copyWith(
            occurrences: [
              ScheduledOccurrenceRecord(
                scheduledDate: occurrenceDate,
                plannedAmountMinor: 25000,
                status: ScheduledOccurrenceStatus.paid,
              ),
            ],
            sync: _scheduledTransaction(
              id: 'cloud-failure',
              nextDate: occurrenceDate,
            ).sync,
          );
      final before = _dataSet().copyWith(scheduledTransactions: [schedule]);
      final store = FinanceDataStore(
        dataSet: before,
        remoteRepository: FailingHistoryResetRepository(dataSet: before),
        userId: 'user',
      );

      await expectLater(
        store.resetScheduledHistory(now: DateTime(2026, 8, 22)),
        throwsA(isA<StateError>()),
      );
      expect(store.scheduledTransactions.single.occurrences, hasLength(1));
      expect(store.scheduledTransactions.single.occurrenceHistoryEpoch, isNull);
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

  test(
    'undo scheduled overpayment restores planned occurrence and exact balance',
    () async {
      final occurrenceDate = DateTime(2026, 8, 21);
      final paymentDate = DateTime(2026, 8, 15);
      final occurrence = ScheduledOccurrenceRecord(
        scheduledDate: occurrenceDate,
        plannedAmountMinor: 10000,
        status: ScheduledOccurrenceStatus.paid,
        actualAmountMinor: 90000,
        actualPaymentDate: paymentDate,
        transactionId: 'generated-overpayment',
      );
      final schedule =
          _scheduledTransaction(
            id: 'scheduled-overpayment',
            nextDate: DateTime(2026, 9, 21),
          ).copyWith(
            amountMinor: 10000,
            occurrences: [occurrence],
            scheduledNotificationIds: const [41],
          );
      final generated = TransactionRecord(
        id: 'generated-overpayment',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: paymentDate,
        payee: 'Planned bill',
        amountMinor: 90000,
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: occurrenceDate,
        scheduledPlannedAmountMinor: 10000,
        sync: SyncMetadata.fresh(now: paymentDate),
      );
      final scheduler = RecordingNotificationScheduler(idsToReturn: const [42]);
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          transactions: [generated],
          scheduledTransactions: [schedule],
          preferences: const UserPreferences(notificationsEnabled: true),
        ),
        notificationScheduler: scheduler,
      );

      expect(store.scheduledPaymentUndoTarget(generated.id), isNotNull);
      expect(store.balanceForAccount('checking'), 10000);

      await store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1));

      final reversed = store.transactions.single;
      final restored = store.scheduledTransactions.single;
      expect(reversed.isDeleted, isTrue);
      expect(store.balanceForAccount('checking'), 100000);
      expect(restored.nextDate, occurrenceDate);
      expect(restored.amountMinor, 10000);
      expect(restored.occurrences, hasLength(1));
      expect(
        restored.occurrences.single.status,
        ScheduledOccurrenceStatus.pending,
      );
      expect(restored.occurrences.single.plannedAmountMinor, 10000);
      expect(restored.occurrences.single.actualAmountMinor, isNull);
      expect(restored.occurrences.single.actualPaymentDate, isNull);
      expect(restored.occurrences.single.transactionId, isNull);
      expect(
        store
            .actionableScheduledTransactions(now: DateTime(2026, 8, 1))
            .single
            .nextDate,
        occurrenceDate,
      );
      expect(scheduler.cancelledIds, contains(schedule.id));
      expect(scheduler.scheduledIds, contains(schedule.id));
      expect(store.scheduledPaymentUndoTarget(generated.id), isNull);
      await expectLater(
        store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1)),
        throwsA(isA<FinanceDataValidationException>()),
      );
    },
  );

  test('undo scheduled transfer reverses both account effects once', () async {
    final occurrenceDate = DateTime(2026, 8, 21);
    final occurrence = ScheduledOccurrenceRecord(
      scheduledDate: occurrenceDate,
      plannedAmountMinor: 25000,
      status: ScheduledOccurrenceStatus.paid,
      actualAmountMinor: 25000,
      actualPaymentDate: occurrenceDate,
      transactionId: 'generated-transfer',
    );
    final schedule = ScheduledTransactionRecord(
      id: 'scheduled-transfer',
      type: TransactionType.transfer,
      accountId: 'checking',
      transferAccountId: 'cash',
      payee: 'Savings transfer',
      amountMinor: 25000,
      nextDate: DateTime(2026, 9, 21),
      frequency: RecurrenceFrequency.monthly,
      occurrences: [occurrence],
      sync: SyncMetadata.fresh(now: DateTime(2026, 7, 21)),
    );
    final generated = TransactionRecord(
      id: 'generated-transfer',
      type: TransactionType.transfer,
      accountId: 'checking',
      transferAccountId: 'cash',
      date: occurrenceDate,
      payee: 'Savings transfer',
      amountMinor: 25000,
      scheduledTransactionId: schedule.id,
      scheduledOccurrenceDate: occurrenceDate,
      scheduledPlannedAmountMinor: 25000,
      sync: SyncMetadata.fresh(now: occurrenceDate),
    );
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        transactions: [generated],
        scheduledTransactions: [schedule],
      ),
    );

    expect(store.balanceForAccount('checking'), 75000);
    expect(store.balanceForAccount('cash'), 35000);
    await store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1));
    expect(store.balanceForAccount('checking'), 100000);
    expect(store.balanceForAccount('cash'), 10000);
    expect(store.transactions.single.isDeleted, isTrue);
    expect(
      store.scheduledTransactions.single.occurrences.single.status,
      ScheduledOccurrenceStatus.pending,
    );
  });

  test(
    'undo scheduled split removes generated transaction without orphaning lines',
    () async {
      final occurrenceDate = DateTime(2026, 8, 21);
      final occurrence = ScheduledOccurrenceRecord(
        scheduledDate: occurrenceDate,
        plannedAmountMinor: 10000,
        status: ScheduledOccurrenceStatus.paid,
        actualAmountMinor: 10000,
        actualPaymentDate: occurrenceDate,
        transactionId: 'generated-split',
      );
      final schedule =
          _scheduledTransaction(
            id: 'scheduled-split-undo',
            nextDate: DateTime(2026, 9, 21),
          ).copyWith(
            amountMinor: 10000,
            splitLines: const [
              TransactionSplitLine(
                id: 'planned-dining',
                categoryId: 'dining',
                amountMinor: 6000,
              ),
              TransactionSplitLine(
                id: 'planned-snacks',
                categoryId: 'snacks',
                amountMinor: 4000,
              ),
            ],
            occurrences: [occurrence],
          );
      final generated = TransactionRecord(
        id: 'generated-split',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: occurrenceDate,
        payee: 'Split bill',
        amountMinor: 10000,
        splitLines: const [
          TransactionSplitLine(
            id: 'actual-dining',
            categoryId: 'dining',
            amountMinor: 6000,
          ),
          TransactionSplitLine(
            id: 'actual-snacks',
            categoryId: 'snacks',
            amountMinor: 4000,
          ),
        ],
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: occurrenceDate,
        scheduledPlannedAmountMinor: 10000,
        sync: SyncMetadata.fresh(now: occurrenceDate),
      );
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          transactions: [generated],
          scheduledTransactions: [schedule],
        ),
      );

      await store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1));

      expect(store.transactions.where((item) => !item.isDeleted), isEmpty);
      expect(store.transactions.single.splitLines, hasLength(2));
      expect(store.scheduledTransactions.single.splitLines, hasLength(2));
      expect(
        store.scheduledTransactions.single.occurrences.single.status,
        ScheduledOccurrenceStatus.pending,
      );
    },
  );

  test('undo fails atomically when a linked account is unavailable', () async {
    final occurrenceDate = DateTime(2026, 8, 21);
    final occurrence = ScheduledOccurrenceRecord(
      scheduledDate: occurrenceDate,
      plannedAmountMinor: 10000,
      status: ScheduledOccurrenceStatus.paid,
      actualAmountMinor: 10000,
      actualPaymentDate: occurrenceDate,
      transactionId: 'generated-orphan',
    );
    final schedule = _scheduledTransaction(
      id: 'scheduled-orphan',
      nextDate: DateTime(2026, 9, 21),
    ).copyWith(amountMinor: 10000, occurrences: [occurrence]);
    final generated = TransactionRecord(
      id: 'generated-orphan',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      date: occurrenceDate,
      payee: 'Orphaned payment',
      amountMinor: 10000,
      scheduledTransactionId: schedule.id,
      scheduledOccurrenceDate: occurrenceDate,
      scheduledPlannedAmountMinor: 10000,
      sync: SyncMetadata.fresh(now: occurrenceDate),
    );
    final deletedChecking = _dataSet().accounts.first.copyWith(
      isArchived: true,
      sync: _dataSet().accounts.first.sync.deleted(),
    );
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        accounts: [deletedChecking, _dataSet().accounts.last],
        transactions: [generated],
        scheduledTransactions: [schedule],
      ),
    );

    await expectLater(
      store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1)),
      throwsA(isA<FinanceDataValidationException>()),
    );
    expect(store.transactions.single.isDeleted, isFalse);
    expect(
      store.scheduledTransactions.single.occurrences.single.status,
      ScheduledOccurrenceStatus.paid,
    );
  });

  test('manual and incomplete links are never eligible for scheduled undo', () {
    final manual = TransactionRecord(
      id: 'manual',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 8, 1),
      payee: 'Manual',
      amountMinor: 1000,
      sync: SyncMetadata.fresh(now: DateTime(2026, 8, 1)),
    );
    final incomplete = TransactionRecord(
      id: 'incomplete',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 8, 1),
      payee: 'Incomplete',
      amountMinor: 1000,
      scheduledTransactionId: 'missing-schedule',
      scheduledOccurrenceDate: DateTime(2026, 8, 1),
      scheduledPlannedAmountMinor: 1000,
      sync: SyncMetadata.fresh(now: DateTime(2026, 8, 1)),
    );
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(transactions: [manual, incomplete]),
    );

    expect(store.scheduledPaymentUndoTarget(manual.id), isNull);
    expect(store.scheduledPaymentUndoTarget(incomplete.id), isNull);
  });

  test('editing a generated payment preserves its undo linkage', () async {
    final occurrenceDate = DateTime(2026, 8, 21);
    final occurrence = ScheduledOccurrenceRecord(
      scheduledDate: occurrenceDate,
      plannedAmountMinor: 10000,
      status: ScheduledOccurrenceStatus.paid,
      actualAmountMinor: 90000,
      actualPaymentDate: DateTime(2026, 8, 15),
      transactionId: 'generated-edited',
    );
    final schedule = _scheduledTransaction(
      id: 'scheduled-edited',
      nextDate: DateTime(2026, 9, 21),
    ).copyWith(amountMinor: 10000, occurrences: [occurrence]);
    final generated = TransactionRecord(
      id: 'generated-edited',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 8, 15),
      payee: 'Edited payment',
      amountMinor: 90000,
      scheduledTransactionId: schedule.id,
      scheduledOccurrenceDate: occurrenceDate,
      scheduledPlannedAmountMinor: 10000,
      sync: SyncMetadata.fresh(now: DateTime(2026, 8, 15)),
    );
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        transactions: [generated],
        scheduledTransactions: [schedule],
      ),
    );

    await store.saveTransaction(generated.copyWith(amountMinor: 80000));

    expect(store.scheduledPaymentUndoTarget(generated.id), isNotNull);
    expect(store.balanceForAccount('checking'), 20000);
    await store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1));
    expect(store.balanceForAccount('checking'), 100000);
    expect(store.scheduledTransactions.single.amountMinor, 10000);
  });

  test(
    'undoing an older occurrence preserves later completion and future alert',
    () async {
      final restoredDate = DateTime(2026, 7, 21);
      final laterDate = DateTime(2026, 8, 21);
      final restoredOccurrence = ScheduledOccurrenceRecord(
        scheduledDate: restoredDate,
        plannedAmountMinor: 10000,
        status: ScheduledOccurrenceStatus.paid,
        actualAmountMinor: 15000,
        actualPaymentDate: DateTime(2026, 7, 20),
        transactionId: 'generated-older',
      );
      final laterOccurrence = ScheduledOccurrenceRecord(
        scheduledDate: laterDate,
        plannedAmountMinor: 10000,
        status: ScheduledOccurrenceStatus.paid,
        actualAmountMinor: 10000,
        actualPaymentDate: laterDate,
        transactionId: 'generated-later',
      );
      final schedule =
          _scheduledTransaction(
            id: 'scheduled-history',
            nextDate: DateTime(2026, 9, 21),
          ).copyWith(
            amountMinor: 10000,
            occurrences: [restoredOccurrence, laterOccurrence],
          );
      final olderTransaction = TransactionRecord(
        id: 'generated-older',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: DateTime(2026, 7, 20),
        payee: 'Older payment',
        amountMinor: 15000,
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: restoredDate,
        scheduledPlannedAmountMinor: 10000,
        sync: SyncMetadata.fresh(now: DateTime(2026, 7, 20)),
      );
      final laterTransaction = TransactionRecord(
        id: 'generated-later',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: laterDate,
        payee: 'Later payment',
        amountMinor: 10000,
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: laterDate,
        scheduledPlannedAmountMinor: 10000,
        sync: SyncMetadata.fresh(now: laterDate),
      );
      final scheduler = RecordingNotificationScheduler(idsToReturn: const [88]);
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          transactions: [olderTransaction, laterTransaction],
          scheduledTransactions: [schedule],
          preferences: const UserPreferences(notificationsEnabled: true),
        ),
        notificationScheduler: scheduler,
      );

      await store.undoScheduledPayment(
        olderTransaction.id,
        now: DateTime(2026, 8, 25),
      );

      final restored = store.scheduledTransactions.single;
      expect(restored.nextDate, restoredDate);
      expect(
        restored.occurrences
            .singleWhere(
              (item) => isSameScheduledDay(item.scheduledDate, restoredDate),
            )
            .status,
        ScheduledOccurrenceStatus.pending,
      );
      expect(
        restored.occurrences
            .singleWhere(
              (item) => isSameScheduledDay(item.scheduledDate, laterDate),
            )
            .status,
        ScheduledOccurrenceStatus.paid,
      );
      expect(
        store.transactions
            .singleWhere((item) => item.id == laterTransaction.id)
            .isDeleted,
        isFalse,
      );
      expect(scheduler.scheduledIds, contains(schedule.id));
    },
  );

  test(
    'undo safely reopens an automatically closed one-time schedule',
    () async {
      final occurrenceDate = DateTime(2026, 8, 21);
      final occurrence = ScheduledOccurrenceRecord(
        scheduledDate: occurrenceDate,
        plannedAmountMinor: 10000,
        status: ScheduledOccurrenceStatus.paid,
        actualAmountMinor: 10000,
        actualPaymentDate: occurrenceDate,
        transactionId: 'generated-once',
      );
      final schedule = ScheduledTransactionRecord(
        id: 'scheduled-once',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        payee: 'One time',
        amountMinor: 10000,
        nextDate: occurrenceDate,
        frequency: RecurrenceFrequency.once,
        lastAction: ScheduledAction.paid,
        occurrences: [occurrence],
        sync: SyncMetadata.fresh(
          now: DateTime(2026, 8, 1),
        ).deleted(now: occurrenceDate),
      );
      final generated = TransactionRecord(
        id: 'generated-once',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: occurrenceDate,
        payee: 'One time',
        amountMinor: 10000,
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: occurrenceDate,
        scheduledPlannedAmountMinor: 10000,
        sync: SyncMetadata.fresh(now: occurrenceDate),
      );
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          transactions: [generated],
          scheduledTransactions: [schedule],
        ),
      );

      expect(store.scheduledPaymentUndoTarget(generated.id), isNotNull);
      await store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1));

      final restored = store.scheduledTransactions.single;
      expect(restored.isDeleted, isFalse);
      expect(restored.lastAction, ScheduledAction.none);
      expect(restored.nextDate, occurrenceDate);
      expect(
        restored.occurrences.single.status,
        ScheduledOccurrenceStatus.pending,
      );
    },
  );

  test(
    'undo persists its tombstone and pending occurrence locally and remotely',
    () async {
      SharedPreferences.setMockInitialValues({});
      const localRepository = LocalFinanceDataSetRepository(
        storageKey: 'undo_scheduled_payment_persistence_test',
      );
      final occurrenceDate = DateTime(2026, 8, 21);
      final occurrence = ScheduledOccurrenceRecord(
        scheduledDate: occurrenceDate,
        plannedAmountMinor: 10000,
        status: ScheduledOccurrenceStatus.paid,
        actualAmountMinor: 10000,
        actualPaymentDate: occurrenceDate,
        transactionId: 'generated-persisted-undo',
      );
      final schedule = _scheduledTransaction(
        id: 'scheduled-persisted-undo',
        nextDate: DateTime(2026, 9, 21),
      ).copyWith(amountMinor: 10000, occurrences: [occurrence]);
      final generated = TransactionRecord(
        id: 'generated-persisted-undo',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'dining',
        date: occurrenceDate,
        payee: 'Persisted undo',
        amountMinor: 10000,
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: occurrenceDate,
        scheduledPlannedAmountMinor: 10000,
        sync: SyncMetadata.fresh(now: occurrenceDate),
      );
      final remote = FakeRecordRepository();
      final store = FinanceDataStore(
        dataSet: _dataSet().copyWith(
          transactions: [generated],
          scheduledTransactions: [schedule],
        ),
        localRepository: localRepository,
        remoteRepository: remote,
        userId: 'undo-user',
      );

      await store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1));

      expect(remote.savedTransactions.single.isDeleted, isTrue);
      expect(
        remote.savedScheduled.single.occurrences.single.status,
        ScheduledOccurrenceStatus.pending,
      );
      final reloaded = await FinanceDataStore.load(
        localRepository: localRepository,
      );
      expect(reloaded.transactions.single.isDeleted, isTrue);
      expect(
        reloaded.scheduledTransactions.single.occurrences.single.status,
        ScheduledOccurrenceStatus.pending,
      );
      expect(reloaded.scheduledPaymentUndoTarget(generated.id), isNull);
    },
  );

  test('undo rolls back both records when local persistence fails', () async {
    final occurrenceDate = DateTime(2026, 8, 21);
    final occurrence = ScheduledOccurrenceRecord(
      scheduledDate: occurrenceDate,
      plannedAmountMinor: 10000,
      status: ScheduledOccurrenceStatus.paid,
      actualAmountMinor: 10000,
      actualPaymentDate: occurrenceDate,
      transactionId: 'generated-failing-undo',
    );
    final schedule = _scheduledTransaction(
      id: 'scheduled-failing-undo',
      nextDate: DateTime(2026, 9, 21),
    ).copyWith(amountMinor: 10000, occurrences: [occurrence]);
    final generated = TransactionRecord(
      id: 'generated-failing-undo',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'dining',
      date: occurrenceDate,
      payee: 'Failing undo',
      amountMinor: 10000,
      scheduledTransactionId: schedule.id,
      scheduledOccurrenceDate: occurrenceDate,
      scheduledPlannedAmountMinor: 10000,
      sync: SyncMetadata.fresh(now: occurrenceDate),
    );
    final store = FinanceDataStore(
      dataSet: _dataSet().copyWith(
        transactions: [generated],
        scheduledTransactions: [schedule],
      ),
      localRepository: const AlwaysFailingLocalRepository(),
    );

    await expectLater(
      store.undoScheduledPayment(generated.id, now: DateTime(2026, 8, 1)),
      throwsStateError,
    );

    expect(store.transactions.single.isDeleted, isFalse);
    expect(
      store.scheduledTransactions.single.occurrences.single.status,
      ScheduledOccurrenceStatus.paid,
    );
    expect(store.balanceForAccount('checking'), 90000);
  });
}

AccountRecord _creditInsightsAccount({
  required int openingBalanceMinor,
  required DateTime createdAt,
  required int statementClosingDay,
  double annualPercentageRate = 24,
}) {
  return AccountRecord(
    id: 'card',
    name: 'Card',
    type: AccountType.creditCard,
    openingBalanceMinor: openingBalanceMinor,
    interestEstimationEnabled: true,
    annualPercentageRate: annualPercentageRate,
    statementClosingDay: statementClosingDay,
    sync: SyncMetadata.fresh(now: createdAt),
  );
}

TransactionRecord _creditExpense({
  required String id,
  required DateTime date,
  required int amountMinor,
}) {
  return TransactionRecord(
    id: id,
    type: TransactionType.expense,
    accountId: 'card',
    date: date,
    payee: 'Purchase',
    amountMinor: amountMinor,
    sync: SyncMetadata.fresh(now: date),
  );
}

TransactionRecord _creditPayment({
  required String id,
  required DateTime date,
  required int amountMinor,
}) {
  return TransactionRecord(
    id: id,
    type: TransactionType.transfer,
    accountId: 'checking',
    transferAccountId: 'card',
    date: date,
    payee: 'Card payment',
    amountMinor: amountMinor,
    sync: SyncMetadata.fresh(now: date),
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

class FakeRecordRepository
    implements FinanceRecordRepository, ScheduledHistoryResetRepository {
  FakeRecordRepository({FinanceDataSet? dataSet})
    : remoteDataSet = dataSet ?? _dataSet();

  FinanceDataSet remoteDataSet;
  final savedAccounts = <AccountRecord>[];
  final savedCategories = <CategoryRecord>[];
  final savedTransactions = <TransactionRecord>[];
  final savedScheduled = <ScheduledTransactionRecord>[];
  final savedBudgets = <BudgetRecord>[];
  final savedGoals = <GoalRecord>[];
  final savedGoalContributions = <GoalContributionRecord>[];
  final savedGoalFundingEvents = <GoalFundingEventRecord>[];
  UserPreferences? savedPreferences;
  FinanceDataSet? authoritativeDataSet;
  String? activeGeneration;

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async => remoteDataSet;

  @override
  Future<String?> activeRestoreGeneration(String userId) async =>
      activeGeneration;

  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async {
    authoritativeDataSet = dataSet;
    remoteDataSet = dataSet;
    return activeGeneration = 'test-generation';
  }

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
  Future<void> saveGoal({
    required String userId,
    required GoalRecord goal,
  }) async {
    savedGoals.add(goal);
  }

  @override
  Future<void> saveGoalContribution({
    required String userId,
    required GoalContributionRecord contribution,
  }) async {
    savedGoalContributions.add(contribution);
  }

  @override
  Future<void> saveGoalFundingEvent({
    required String userId,
    required GoalFundingEventRecord fundingEvent,
  }) async {
    savedGoalFundingEvents.add(fundingEvent);
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
  Future<void> saveScheduledHistoryReset({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {
    savedScheduled.add(scheduledTransaction);
    remoteDataSet = remoteDataSet.copyWith(
      scheduledTransactions: [
        for (final existing in remoteDataSet.scheduledTransactions)
          if (existing.id == scheduledTransaction.id)
            scheduledTransaction
          else
            existing,
      ],
    );
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

class BulkFakeRecordRepository extends FakeRecordRepository
    implements BulkFinanceRecordRepository {
  BulkFakeRecordRepository({super.dataSet});

  int bulkSaveCount = 0;
  String? bulkSavedUserId;
  FinanceDataSet? bulkSavedDataSet;
  FinanceDataSet? bulkSavedBaseline;

  @override
  Future<void> saveDataSet({
    required String userId,
    required FinanceDataSet dataSet,
    FinanceDataSet? baseline,
  }) async {
    bulkSaveCount += 1;
    bulkSavedUserId = userId;
    bulkSavedDataSet = dataSet;
    bulkSavedBaseline = baseline;
    remoteDataSet = dataSet;
  }
}

class FailingHistoryResetRepository extends FakeRecordRepository {
  FailingHistoryResetRepository({super.dataSet});

  @override
  Future<void> saveScheduledHistoryReset({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) {
    throw StateError('cloud unavailable');
  }
}

class AlwaysFailingLocalRepository extends LocalFinanceDataSetRepository {
  const AlwaysFailingLocalRepository();

  @override
  Future<void> save(FinanceDataSet dataSet) {
    throw StateError('Local paired save failed');
  }
}
