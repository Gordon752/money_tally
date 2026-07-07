import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/money.dart';
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

  testWidgets('scheduled screen renders v2 scheduled rows', (tester) async {
    await tester.pumpWidget(MoneyTallyApp());

    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();

    expect(find.text('Insurance'), findsOneWidget);
    expect(find.text('Alerts are required'), findsOneWidget);
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
      dataSet: const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
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
