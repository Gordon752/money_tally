import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart'
    as v2_scheduled;
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/transaction.dart' as v2_transaction;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/migration/v1_snapshot_migrator.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

void main() {
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
    expect(find.text('Banking'), findsOneWidget);
    expect(find.text('Adjust balance'), findsNothing);
  });

  testWidgets('ledger screen renders v2 transaction rows', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Ledger').last);
    await tester.pumpAndSettle();

    expect(find.text('Walmart'), findsWidgets);
    expect(find.textContaining('Checking'), findsWidgets);
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
    expect(find.text(r'$1,802.40'), findsOneWidget);
    expect(find.text(r'$297.00'), findsOneWidget);
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

  testWidgets('scheduled screen renders v2 scheduled rows', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();

    expect(find.text('Insurance'), findsOneWidget);
    expect(find.byTooltip('Collapse calendar'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse calendar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand calendar'), findsOneWidget);
    expect(find.text('Alerts are required'), findsOneWidget);
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
    expect(scheduled.lastAction, v2_scheduled.ScheduledAction.paid);
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

  testWidgets('budgets screen renders v2 budget progress text', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Budgets').last);
    await tester.pumpAndSettle();

    expect(find.text('Dining'), findsOneWidget);
    expect(find.textContaining('Spent'), findsWidgets);
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
    expect(find.text('Data Ownership'), findsOneWidget);
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
    expect(find.text('Budget history'), findsOneWidget);
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
