import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/design/widgets/amount_entry_field.dart';
import 'package:money_tally/src/design/widgets/account_card.dart';
import 'package:money_tally/src/design/widgets/transaction_row.dart';
import 'package:money_tally/src/domain/category.dart' as v2_category;
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart'
    as v2_scheduled;
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/transaction.dart' as v2_transaction;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/migration/v1_snapshot_migrator.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

void main() {
  testWidgets('amount entry field formats typed digits as money', (
    tester,
  ) async {
    var amountMinor = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AmountEntryField(onChanged: (value) => amountMinor = value),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '500');
    await tester.pump();
    expect(amountMinor, 500);
    expect(find.text(r'$5.00'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    expect(amountMinor, 12345);
    expect(find.text(r'$123.45'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1000000');
    await tester.pump();
    expect(amountMinor, 1000000);
    expect(find.text(r'$10,000.00'), findsOneWidget);
  });

  test('finance snapshot round trips through json', () {
    final store = FinanceStore.seeded();
    store.addCategory('Fuel');
    store.addTransaction(
      accountId: 'checking',
      categoryId: 'dining',
      date: DateTime(2026, 7, 6),
      payee: 'Cafe',
      amountCents: -1299,
    );

    final snapshot = FinanceSnapshot.fromJson(store.snapshot().toJson());

    expect(snapshot.accounts.length, store.accounts.length);
    expect(snapshot.categories.last.name, 'Fuel');
    expect(snapshot.categories.last.sync.version, 1);
    expect(snapshot.categories.last.sync.deviceId, 'local');
    expect(snapshot.transactions.first.payee, 'Cafe');
    expect(snapshot.transactions.first.amountCents, -1299);
    expect(snapshot.transactions.first.sync.createdAt, isA<DateTime>());
  });

  test('sync metadata updates when records are edited', () {
    final store = FinanceStore.seeded();
    final before = store.accountById('checking').sync;

    store.adjustAccountBalance('checking', 200000);

    final after = store.accountById('checking').sync;
    expect(after.createdAt, before.createdAt);
    expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
    expect(after.version, before.version + 1);
  });

  test(
    'data store soft deletes accounts from active lists and totals',
    () async {
      final legacyStore = FinanceStore.seeded();
      final dataSet = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final dataStore = FinanceDataStore(dataSet: dataSet);

      await dataStore.deleteAccount('checking');

      final deletedAccount = dataStore.accountById('checking');
      expect(deletedAccount.isArchived, isTrue);
      expect(deletedAccount.isDeleted, isTrue);
      expect(
        dataStore.activeAccountsInDisplayOrder.map((account) => account.id),
        isNot(contains('checking')),
      );
      expect(dataStore.totalAssetsMinor, 24700);
      expect(dataStore.availableCashMinor, 24700);
    },
  );

  test(
    'store can push and pull snapshots through a remote repository',
    () async {
      final local = FinanceStore.seeded();
      final remote = FakeRemoteFinanceRepository();

      await local.pushSnapshot(remoteRepository: remote, userId: 'user-1');

      final restored = FinanceStore.seeded();
      restored.addCategory('Temporary');
      final pulled = await restored.pullSnapshot(
        remoteRepository: remote,
        userId: 'user-1',
      );

      expect(pulled, isTrue);
      expect(
        restored.categories.map((category) => category.name),
        isNot(contains('Temporary')),
      );
      expect(restored.accounts.length, local.accounts.length);
    },
  );

  testWidgets('renders finance dashboard', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    expect(find.text('Money Tally'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('NET WORTH'), findsOneWidget);
    expect(find.text('TOTAL ASSETS'), findsOneWidget);
    expect(find.text('AVAILABLE CASH'), findsOneWidget);
    expect(find.text('MONTH EXPENSES'), findsOneWidget);
    expect(find.text('Accounts'), findsWidgets);
  });

  testWidgets('uses v2 currency preference for visible money values', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            currency: CurrencyFormatSettings(
              currencyCode: 'CAD',
              symbol: r'C$',
            ),
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    expect(find.text(r'C$1,852.40'), findsWidgets);
  });

  testWidgets('provides v2 finance data store beside legacy store', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    final context = tester.element(find.byType(MaterialApp));
    final dataStore = FinanceDataStoreScope.read(context);

    expect(
      dataStore.balanceForAccount('checking'),
      legacyStore.accountById('checking').balanceCents,
    );
  });

  testWidgets('accounts screen renders v2 account cards', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();

    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Banking'), findsWidgets);
    expect(find.text('Adjust balance'), findsNothing);
  });

  testWidgets('accounts screen can collapse account groups', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Collapse Banking'));
    await tester.pumpAndSettle();

    expect(find.text('Banking'), findsWidgets);
    expect(find.text('Checking'), findsNothing);
    expect(find.byTooltip('Expand Banking'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand Banking'));
    await tester.pumpAndSettle();

    expect(find.text('Checking'), findsOneWidget);
  });

  testWidgets('accounts group long press can reorder fixed groups', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('account-group-cash')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move Up'));
    await tester.pumpAndSettle();

    expect(dataStore.preferences.accountGroupOrderNames.take(2), [
      'cash',
      'banking',
    ]);
  });

  testWidgets('accounts group long press can rename fixed group label', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('account-group-banking')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Everyday Money');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(dataStore.preferences.accountGroupLabelOverrides, {
      'banking': 'Everyday Money',
    });
    expect(find.text('Everyday Money'), findsWidgets);
    expect(find.byTooltip('Collapse Everyday Money'), findsOneWidget);
  });

  testWidgets('ledger screen renders v2 transaction rows', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    expect(find.text('Walmart'), findsWidgets);
    expect(find.textContaining('Checking'), findsWidgets);
  });

  testWidgets('ledger search filters visible transactions', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Diner');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TransactionRow, 'Diner'), findsOneWidget);
    expect(find.widgetWithText(TransactionRow, 'Walmart'), findsNothing);
    expect(find.widgetWithText(TransactionRow, 'Settlement'), findsNothing);
  });

  testWidgets('ledger filters by account type category and date', (
    tester,
  ) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ledger-account-')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit Card').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TransactionRow, 'Diner'), findsOneWidget);
    expect(find.widgetWithText(TransactionRow, 'Walmart'), findsNothing);
    expect(find.widgetWithText(TransactionRow, 'Settlement'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-type-')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TransactionRow, 'Settlement'), findsOneWidget);
    expect(find.widgetWithText(TransactionRow, 'Walmart'), findsNothing);
    expect(find.widgetWithText(TransactionRow, 'Diner'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-category-')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TransactionRow, 'Diner'), findsOneWidget);
    expect(find.widgetWithText(TransactionRow, 'Walmart'), findsNothing);
    expect(find.widgetWithText(TransactionRow, 'Settlement'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-date-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TransactionRow, 'Diner'), findsNothing);
    expect(find.widgetWithText(TransactionRow, 'Walmart'), findsNothing);
    expect(find.widgetWithText(TransactionRow, 'Settlement'), findsNothing);
    expect(find.text('No transactions match'), findsOneWidget);
  });

  testWidgets('ledger long press can duplicate and delete transaction', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(
      dataStore.transactions.map((transaction) => transaction.payee),
      contains('Walmart copy'),
    );
    expect(find.text('Walmart copy'), findsOneWidget);

    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    final original = dataStore.transactions.singleWhere(
      (transaction) => transaction.payee == 'Walmart',
    );
    expect(original.isDeleted, isTrue);
    expect(find.text('Walmart'), findsNothing);
    expect(find.text('Walmart copy'), findsOneWidget);
  });

  testWidgets('ledger long press can edit transaction', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'Walmart Grocery');
    await tester.enterText(fields.at(2), '12.34');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final edited = dataStore.transactions.singleWhere(
      (transaction) => transaction.payee == 'Walmart Grocery',
    );
    expect(edited.amountMinor, 1234);
    expect(edited.type, v2_transaction.TransactionType.expense);
    expect(find.text('Walmart Grocery'), findsOneWidget);
  });

  testWidgets('ledger long press can split transaction', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('split-amount-0')),
      '3000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('split-amount-1')),
      '34.28',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final transaction = dataStore.transactions.singleWhere(
      (item) => item.payee == 'Walmart',
    );
    expect(transaction.isSplit, isTrue);
    expect(transaction.splitLines.length, 2);
    expect(transaction.splitTotalMinor, transaction.amountMinor);
  });

  testWidgets('ledger long press can make transaction scheduled', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Walmart').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make Scheduled'));
    await tester.pumpAndSettle();

    final schedule = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'Walmart',
    );
    expect(schedule.type, v2_transaction.TransactionType.expense);
    expect(schedule.accountId, 'checking');
    expect(schedule.categoryId, 'walmart');
    expect(schedule.frequency, v2_scheduled.RecurrenceFrequency.monthly);
    expect(schedule.nextDate.isAfter(DateTime.now()), isTrue);

    final transaction = dataStore.transactions.singleWhere(
      (item) => item.payee == 'Walmart',
    );
    expect(transaction.scheduledTransactionId, schedule.id);
  });

  testWidgets('add transaction dialog honors default income preference', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            defaultTransactionType: DefaultTransactionType.income,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add transaction'));
    await tester.pumpAndSettle();

    final segmented = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );

    expect(segmented.selected, {false});
  });

  testWidgets('floating add menu opens income transaction dialog', (
    tester,
  ) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();

    expect(find.text('Add transaction'), findsOneWidget);
    final segmented = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(segmented.selected, {false});
  });

  testWidgets('floating add button honors left placement preference', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            floatingAddButtonPosition: FloatingAddButtonPosition.left,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));

    expect(
      scaffold.floatingActionButtonLocation,
      FloatingActionButtonLocation.startFloat,
    );
  });

  testWidgets('floating add account creates visible account', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Travel Fund');
    await tester.enterText(fields.at(1), '123.45');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    expect(find.text('Travel Fund'), findsOneWidget);
    expect(find.text(r'$123.45'), findsOneWidget);
    expect(
      legacyStore.accounts.map((account) => account.name),
      contains('Travel Fund'),
    );
  });

  testWidgets('floating add transfer creates first-class transfer', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '50.00');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    final transfer = dataStore.transactions.singleWhere(
      (transaction) =>
          transaction.type == v2_transaction.TransactionType.transfer,
    );
    expect(transfer.transferAccountId, 'cash');
    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    expect(find.text(r'$1,802.40'), findsWidgets);
    expect(find.text(r'$297.00'), findsWidgets);
  });

  testWidgets('floating add scheduled transaction creates v2 schedule', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scheduled Transaction'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Rent');
    await tester.enterText(fields.at(1), '900.00');
    await tester.enterText(fields.at(2), '2026-08-01');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.payee == 'Rent',
    );
    expect(scheduled.type, v2_transaction.TransactionType.expense);
    expect(scheduled.amountMinor, 90000);
    expect(scheduled.nextDate, DateTime(2026, 8));
    expect(scheduled.frequency, v2_scheduled.RecurrenceFrequency.monthly);
    expect(scheduled.categoryId, isNotNull);

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();

    expect(find.text('Rent'), findsOneWidget);
  });

  testWidgets('account long press can edit account name', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Checking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Main Checking');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Main Checking'), findsOneWidget);
    expect(legacyStore.accountById('checking').name, 'Main Checking');
  });

  testWidgets('account edit can toggle balance inclusion flags', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Checking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Include in group balance'),
    );
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Include in net worth'),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final account = dataStore.accountById('checking');
    expect(account.includeInGroupBalance, isFalse);
    expect(account.includeInNetWorth, isFalse);
  });

  testWidgets('account edit can set credit card limit', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.accounts,
          ),
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    final card = find.byWidgetPredicate(
      (widget) => widget is AccountCard && widget.account.name == 'Credit Card',
    );
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.longPress(card);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Credit limit'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '2500.00');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final account = dataStore.accountById('card');
    expect(account.creditLimitMinor, 250000);
    expect(dataStore.creditAvailableMinorForAccount('card'), 206178);
    expect(find.text(r'Credit used $438.22 of $2,500.00'), findsWidgets);
  });

  testWidgets('account long press can add expense for selected account', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.accounts,
          ),
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    final cashCard = find.byWidgetPredicate(
      (widget) => widget is AccountCard && widget.account.id == 'cash',
    );
    await tester.ensureVisible(cashCard);
    await tester.pumpAndSettle();
    await tester.longPress(cashCard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Expense'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Coffee');
    await tester.enterText(fields.at(1), '4.50');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    final transaction = dataStore.transactions.singleWhere(
      (item) => item.payee == 'Coffee',
    );
    expect(transaction.accountId, 'cash');
    expect(transaction.amountMinor, 450);
    expect(transaction.type, v2_transaction.TransactionType.expense);
  });

  testWidgets('account long press can archive account', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Checking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Checking'), findsNothing);
    expect(legacyStore.accountById('checking').isArchived, isTrue);
  });

  testWidgets('account long press can delete account', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Checking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Checking'), findsNothing);
    expect(legacyStore.accountById('checking').isArchived, isTrue);
    expect(dataStore.accountById('checking').isDeleted, isTrue);
  });

  testWidgets('scheduled screen renders v2 scheduled rows', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();

    expect(find.text('Insurance'), findsOneWidget);
    expect(find.byTooltip('Collapse calendar'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse calendar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand calendar'), findsOneWidget);
    expect(find.text('Local alerts'), findsOneWidget);
  });

  testWidgets('dashboard shows scheduled due count', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          scheduledTransactions: [
            rentSchedule(
              nextDate: DateTime.now().subtract(const Duration(days: 1)),
            ),
          ],
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    expect(find.text('1 due'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
  });

  testWidgets('scheduled long press can mark paid and advance item', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(scheduledTransactions: [rentSchedule()]);
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark Paid'));
    await tester.pumpAndSettle();

    final paid = dataStore.transactions.singleWhere(
      (transaction) => transaction.scheduledTransactionId == 'sched-rent',
    );
    expect(paid.type, v2_transaction.TransactionType.expense);
    expect(paid.amountMinor, 90000);

    final scheduled = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(scheduled.nextDate, DateTime(2026, 9));
    expect(scheduled.lastAction, v2_scheduled.ScheduledAction.none);
  });

  testWidgets('scheduled long press can duplicate and delete item', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(scheduledTransactions: [rentSchedule()]);
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(
      dataStore.scheduledTransactions.map((item) => item.payee),
      contains('Rent copy'),
    );
    expect(find.text('Rent copy'), findsOneWidget);

    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    final original = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(original.isDeleted, isTrue);
    expect(find.text('Rent'), findsNothing);
    expect(find.text('Rent copy'), findsOneWidget);
  });

  testWidgets('scheduled long press can edit item', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(scheduledTransactions: [rentSchedule()]);
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit scheduled transaction'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Mortgage');
    await tester.enterText(find.byType(TextField).at(1), '925.50');
    await tester.enterText(find.byType(TextField).at(2), '2026-08-15');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final edited = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(edited.payee, 'Mortgage');
    expect(edited.amountMinor, 92550);
    expect(edited.nextDate, DateTime(2026, 8, 15));
    expect(edited.lastAction, v2_scheduled.ScheduledAction.none);
    expect(find.text('Mortgage'), findsOneWidget);
    expect(find.text('Rent'), findsNothing);
  });

  testWidgets('scheduled edit persists custom alert options', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          scheduledTransactions: [
            rentSchedule().copyWith(
              alertPreference: v2_scheduled.AlertPreference.custom,
              customAlertTimeMinutes: 11 * 60 + 15,
              repeatAlertUntilResolved: true,
            ),
          ],
        );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Custom alert time'), findsOneWidget);
    expect(find.text('11:15'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(3), '14:30');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final edited = dataStore.scheduledTransactions.singleWhere(
      (item) => item.id == 'sched-rent',
    );
    expect(edited.alertPreference, v2_scheduled.AlertPreference.custom);
    expect(edited.customAlertTimeMinutes, 14 * 60 + 30);
    expect(edited.repeatAlertUntilResolved, isFalse);
  });

  testWidgets('budgets screen renders v2 budget progress text', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Budgets').last);
    await tester.pumpAndSettle();

    expect(find.text('Dining'), findsOneWidget);
    expect(find.textContaining('Spent'), findsWidgets);
  });

  testWidgets('budget dialog creates budget with categories', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Budgets').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add budget'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Fuel');
    await tester.enterText(fields.at(1), '250.00');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Dining'));
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final budget = dataStore.budgets.singleWhere((item) => item.name == 'Fuel');
    expect(budget.amountMinor, 25000);
    expect(budget.categoryIds, contains('dining'));
    expect(find.text('Fuel'), findsOneWidget);
  });

  testWidgets('budget long press can rename budget', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Budgets').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Food');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(
      dataStore.budgets.singleWhere((item) => item.id == 'b1').name,
      'Food',
    );
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('budget long press archives budget', (tester) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Budgets').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(
      dataStore.budgets.singleWhere((item) => item.name == 'Dining').isArchived,
      isTrue,
    );
    expect(find.text('Dining'), findsNothing);
  });

  testWidgets('categories screen renders v2 categories on wide layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();

    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('Expense'), findsWidgets);
  });

  testWidgets('category dialog creates v2 and legacy category', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fuel');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Fuel'), findsOneWidget);
    expect(
      dataStore.categories.map((category) => category.name),
      contains('Fuel'),
    );
    expect(
      legacyStore.categories.map((category) => category.name),
      contains('Fuel'),
    );
  });

  testWidgets('category long press archives category', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Categories').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(dataStore.categoryById('dining').isArchived, isTrue);
    expect(find.text('Dining'), findsNothing);
  });

  testWidgets('settings screen renders v2 preferences on wide layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('App Preferences'), findsOneWidget);
    expect(find.text('Launch screen'), findsOneWidget);
    expect(find.text('Money Format'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Manage accounts'), findsOneWidget);
    expect(find.text('Manage categories'), findsOneWidget);
    expect(find.text('Data Ownership'), findsOneWidget);
  });

  testWidgets('settings management rows navigate to accounts and categories', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final manageAccounts = find.widgetWithText(ListTile, 'Manage accounts');
    await tester.ensureVisible(manageAccounts);
    await tester.pumpAndSettle();
    await tester.tap(manageAccounts);
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsWidgets);
    expect(find.text('Checking'), findsOneWidget);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final manageCategories = find.widgetWithText(ListTile, 'Manage categories');
    await tester.ensureVisible(manageCategories);
    await tester.pumpAndSettle();
    await tester.tap(manageCategories);
    await tester.pumpAndSettle();

    expect(find.text('Categories'), findsWidgets);
    expect(find.text('Dining'), findsOneWidget);
  });

  testWidgets('settings toggles notification preference', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(dataStore.preferences.notificationsEnabled, isTrue);
  });

  testWidgets('settings can save custom currency code and symbol', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Custom currency'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Currency code'),
      'mxn',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Symbol'), r'MX$ ');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(dataStore.preferences.currency.currencyCode, 'MXN');
    expect(dataStore.preferences.currency.symbol, r'MX$ ');
    expect(find.text(r'MXN MX$ '), findsOneWidget);
  });

  testWidgets('settings export rows copy data', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final clipboardWrites = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final data = call.arguments as Map<Object?, Object?>;
          clipboardWrites.add(data['text']! as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Export CSV'));
    await tester.pump();
    expect(find.text('CSV export copied'), findsOneWidget);
    expect(clipboardWrites.single, contains('transaction_id,split_line_id'));

    await tester.tap(find.widgetWithText(ListTile, 'Export JSON'));
    await tester.pump();
    expect(clipboardWrites.length, 2);
    expect(clipboardWrites.last, contains('"accounts"'));
  });

  testWidgets('settings restores JSON backup from clipboard', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final restoredDataSet = dataSet.copyWith(
      accounts: [
        for (final account in dataSet.accounts)
          if (account.id == 'checking')
            account.copyWith(name: 'Restored Checking')
          else
            account,
      ],
    );
    final dataStore = FinanceDataStore(dataSet: dataSet);
    final restoredJson = const BackupCodec().encodeJson(restoredDataSet);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': restoredJson};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Backup and restore'));
    await tester.pump();

    expect(dataStore.accountById('checking').name, 'Restored Checking');
    expect(find.text('JSON backup restored'), findsOneWidget);
  });

  testWidgets('settings reports invalid JSON restore clipboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': 'not json'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Backup and restore'));
    await tester.pump();

    expect(find.text('Could not restore JSON backup'), findsOneWidget);
  });

  testWidgets('launch screen preference selects initial finance section', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            launchScreen: LaunchScreen.reports,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    expect(find.text('Reports'), findsWidgets);
    expect(find.text('Income vs expenses'), findsOneWidget);
    expect(find.text('Net worth history'), findsOneWidget);
  });

  testWidgets('reports screen is reachable from wide navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();

    expect(find.text('Monthly spending'), findsOneWidget);
    expect(find.text('Category breakdown'), findsOneWidget);
    expect(find.text('Budget history'), findsOneWidget);
    expect(find.text(r'$82.78'), findsWidgets);
    expect(find.text(r'$1,264.00'), findsWidgets);
    expect(find.text('Walmart'), findsWidgets);
    expect(find.byTooltip('Add'), findsNothing);
  });

  testWidgets('applies v2 appearance preference to app theme mode', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final dataSet = const V1SnapshotMigrator()
        .migrate(legacyStore.snapshot().toJson())
        .copyWith(
          preferences: const UserPreferences(
            appearanceMode: AppearanceMode.dark,
          ),
        );

    await tester.pumpWidget(
      MoneyTallyApp(
        store: legacyStore,
        dataStore: FinanceDataStore(dataSet: dataSet),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme, isNotNull);
  });

  test('legacy v2 mirror refreshes in-memory v2 balances', () async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator()
          .migrate(legacyStore.snapshot().toJson())
          .copyWith(
            preferences: const UserPreferences(
              appearanceMode: AppearanceMode.dark,
            ),
          ),
    );
    final mirror = LegacyV2StoreMirror(
      legacyStore: legacyStore,
      dataStore: dataStore,
    )..start();
    addTearDown(mirror.dispose);

    legacyStore.adjustAccountBalance('checking', 200000);
    await Future<void>.delayed(Duration.zero);

    expect(dataStore.balanceForAccount('checking'), 200000);
    expect(dataStore.preferences.appearanceMode, AppearanceMode.dark);
  });

  test('legacy v2 mirror preserves v2-only transactions', () async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator()
          .migrate(legacyStore.snapshot().toJson())
          .copyWith(
            transactions: [
              v2_transaction.TransactionRecord(
                id: 'v2-transfer',
                type: v2_transaction.TransactionType.transfer,
                accountId: 'checking',
                transferAccountId: 'cash',
                date: DateTime(2026, 7, 7),
                payee: 'Transfer',
                amountMinor: 0,
                sync: v2_sync.SyncMetadata.fresh(),
              ),
            ],
          ),
    );
    final mirror = LegacyV2StoreMirror(
      legacyStore: legacyStore,
      dataStore: dataStore,
    )..start();
    addTearDown(mirror.dispose);

    legacyStore.adjustAccountBalance('checking', 200000);
    await Future<void>.delayed(Duration.zero);

    expect(
      dataStore.transactions.map((transaction) => transaction.id),
      contains('v2-transfer'),
    );
  });

  test('legacy v2 mirror preserves newer v2 transaction changes', () async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final editedTransaction = migrated.transactions.first.copyWith(
      payee: 'Edited payee',
    );
    final deletedTransaction = migrated.transactions[1].copyWith(
      sync: migrated.transactions[1].sync.deleted(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        transactions: [
          editedTransaction,
          deletedTransaction,
          ...migrated.transactions.skip(2),
        ],
      ),
    );
    final mirror = LegacyV2StoreMirror(
      legacyStore: legacyStore,
      dataStore: dataStore,
    )..start();
    addTearDown(mirror.dispose);

    legacyStore.adjustAccountBalance('checking', 200000);
    await Future<void>.delayed(Duration.zero);

    expect(
      dataStore.transactions
          .singleWhere((transaction) => transaction.id == editedTransaction.id)
          .payee,
      'Edited payee',
    );
    expect(
      dataStore.transactions
          .singleWhere((transaction) => transaction.id == deletedTransaction.id)
          .isDeleted,
      isTrue,
    );
  });

  test('legacy v2 mirror preserves enriched v2 categories', () async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        categories: [
          for (final category in migrated.categories)
            if (category.id == 'dining')
              category.copyWith(iconName: 'fork.knife', colorValue: 0xFF0F766E)
            else
              category,
          v2_category.CategoryRecord(
            id: 'snacks',
            name: 'Snacks',
            kind: v2_category.CategoryKind.expense,
            parentCategoryId: 'dining',
            iconName: 'tag',
            sync: v2_sync.SyncMetadata.fresh(),
          ),
        ],
      ),
    );
    final mirror = LegacyV2StoreMirror(
      legacyStore: legacyStore,
      dataStore: dataStore,
    )..start();
    addTearDown(mirror.dispose);

    legacyStore.adjustAccountBalance('checking', 200000);
    await Future<void>.delayed(Duration.zero);

    expect(dataStore.categoryById('dining').iconName, 'fork.knife');
    expect(dataStore.categoryById('dining').colorValue, 0xFF0F766E);
    expect(dataStore.categoryById('snacks').parentCategoryId, 'dining');
  });

  test('legacy v2 mirror preserves v2-only scheduled transactions', () async {
    final legacyStore = FinanceStore.seeded();
    final dataStore = FinanceDataStore(
      dataSet: const V1SnapshotMigrator()
          .migrate(legacyStore.snapshot().toJson())
          .copyWith(
            scheduledTransactions: [
              v2_scheduled.ScheduledTransactionRecord(
                id: 'v2-scheduled',
                type: v2_transaction.TransactionType.expense,
                accountId: 'checking',
                categoryId: 'dining',
                payee: 'Rent',
                amountMinor: 90000,
                nextDate: DateTime(2026, 8),
                frequency: v2_scheduled.RecurrenceFrequency.monthly,
                sync: v2_sync.SyncMetadata.fresh(),
              ),
            ],
          ),
    );
    final mirror = LegacyV2StoreMirror(
      legacyStore: legacyStore,
      dataStore: dataStore,
    )..start();
    addTearDown(mirror.dispose);

    legacyStore.adjustAccountBalance('checking', 200000);
    await Future<void>.delayed(Duration.zero);

    expect(
      dataStore.scheduledTransactions.map((scheduled) => scheduled.id),
      contains('v2-scheduled'),
    );
  });

  test('legacy v2 mirror does not overwrite remote-attached v2 data', () async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataSet = migrated.copyWith(
      accounts: [
        for (final account in migrated.accounts)
          if (account.id == 'checking')
            account.copyWith(name: 'Cloud Checking')
          else
            account,
      ],
    );
    final dataStore = FinanceDataStore(dataSet: dataSet, userId: 'user-1');
    final mirror = LegacyV2StoreMirror(
      legacyStore: legacyStore,
      dataStore: dataStore,
    )..start();
    addTearDown(mirror.dispose);

    legacyStore.adjustAccountBalance('checking', 200000);
    await Future<void>.delayed(Duration.zero);

    expect(dataStore.accountById('checking').name, 'Cloud Checking');
  });
}

class FakeRemoteFinanceRepository implements FinanceRemoteRepository {
  final Map<String, FinanceSnapshot> snapshots = {};

  @override
  Future<FinanceSnapshot?> loadSnapshot({required String userId}) async {
    return snapshots[userId];
  }

  @override
  Future<void> saveSnapshot({
    required String userId,
    required FinanceSnapshot snapshot,
  }) async {
    snapshots[userId] = FinanceSnapshot.fromJson(snapshot.toJson());
  }
}

v2_scheduled.ScheduledTransactionRecord rentSchedule({DateTime? nextDate}) {
  return v2_scheduled.ScheduledTransactionRecord(
    id: 'sched-rent',
    type: v2_transaction.TransactionType.expense,
    accountId: 'checking',
    categoryId: 'dining',
    payee: 'Rent',
    amountMinor: 90000,
    nextDate: nextDate ?? DateTime(2026, 8),
    frequency: v2_scheduled.RecurrenceFrequency.monthly,
    sync: v2_sync.SyncMetadata.fresh(),
  );
}
