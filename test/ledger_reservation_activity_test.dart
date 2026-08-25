import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/account.dart' as v2_account;
import 'package:money_tally/src/domain/category.dart' as v2_category;
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/transaction.dart' as v2_transaction;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/ledger/reservation_ledger_activity.dart';
import 'package:money_tally/src/design/widgets/account_balance_text.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

void main() {
  test(
    'same-day reservation activity uses creation order before lexical IDs',
    () {
      final effectiveDate = DateTime(2026, 8, 24);
      final olderSync = v2_sync.SyncMetadata.fresh(
        now: DateTime.utc(2026, 8, 24, 12),
        deviceId: 'test',
      );
      final newerSync = v2_sync.SyncMetadata.fresh(
        now: DateTime.utc(2026, 8, 24, 13),
        deviceId: 'test',
      );
      ReservationOperationRecord allocation({
        required String id,
        required String fundId,
        required v2_sync.SyncMetadata sync,
      }) {
        return ReservationOperationRecord(
          id: id,
          containerType: ReservationContainerType.fund,
          containerId: fundId,
          fundingAccountId: 'checking',
          kind: ReservationOperationKind.allocate,
          amountMinor: 1000,
          effectiveDate: effectiveDate,
          revision: 1,
          baseRevision: 0,
          operationId: id,
          deviceId: 'test',
          sync: sync,
        );
      }

      final activities = projectLedgerReservationActivities(
        goals: const [],
        funds: [
          FundRecord(
            id: 'older',
            name: 'Older',
            fundingAccountId: 'checking',
            status: FundStatus.active,
            sync: olderSync,
          ),
          FundRecord(
            id: 'newer',
            name: 'Newer',
            fundingAccountId: 'checking',
            status: FundStatus.active,
            sync: newerSync,
          ),
        ],
        operations: [
          allocation(id: 'z-older', fundId: 'older', sync: olderSync),
          allocation(id: 'a-newer', fundId: 'newer', sync: newerSync),
        ],
        transactions: const [],
      );

      expect(activities.map((activity) => activity.reservationOperationId), [
        'a-newer',
        'z-older',
      ]);
    },
  );

  testWidgets(
    'Ledger presents Goal and Fund allocations and returns with names',
    (tester) async {
      await _setPhoneSize(tester);
      final store = _reservationLedgerStore();
      await tester.pumpWidget(_testApp(store));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ledger-reservation-row-goal-allocate')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ledger-reservation-row-goal-return')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ledger-reservation-row-fund-allocate')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ledger-reservation-row-fund-return')),
        findsOneWidget,
      );
      expect(find.text('Allocated to Emergency'), findsOneWidget);
      expect(find.text('Returned from Emergency'), findsOneWidget);
      expect(find.text('Allocated to Bills'), findsOneWidget);
      expect(find.text('Returned from Bills'), findsOneWidget);
      expect(find.text('Checking • Emergency Goal'), findsNWidgets(2));
      expect(find.text('Checking • Bills Fund'), findsNWidgets(2));
      expect(find.text('Funded Goals'), findsNothing);
    },
  );

  testWidgets('Ledger type filter offers and displays Goal activity', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(_testApp(_reservationLedgerStore()));
    await tester.pumpAndSettle();

    await _openTypeFilter(tester);
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Funds'), findsOneWidget);
    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ledger-reservation-row-goal-allocate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-goal-return')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-fund-allocate')),
      findsNothing,
    );
    expect(find.text('Utility Bill'), findsNothing);
    expect(find.textContaining('Emergency Goal'), findsWidgets);
    expect(find.text('No activities match'), findsNothing);
  });

  testWidgets(
    'Ledger Funds filter excludes Goal activity and keeps linked spend once',
    (tester) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_testApp(_reservationLedgerStore()));
      await tester.pumpAndSettle();

      await _openTypeFilter(tester);
      await tester.tap(find.text('Funds'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ledger-reservation-row-fund-allocate')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ledger-reservation-row-fund-return')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ledger-reservation-row-goal-allocate')),
        findsNothing,
      );
      expect(find.text('Utility Bill'), findsOneWidget);
      final spendMetadata = tester.widget<Text>(
        find.byKey(const ValueKey('ledger-metadata-details-spend')),
      );
      expect(spendMetadata.data, contains('Bills Fund'));
      expect(find.textContaining('Bills Fund'), findsWidgets);
      expect(find.text('No activities match'), findsNothing);
    },
  );

  testWidgets('Ledger search finds reservation names and linked real spend', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(_testApp(_reservationLedgerStore()));
    await tester.pumpAndSettle();

    final search = find.byType(TextField);
    expect(search, findsOneWidget);

    await tester.enterText(search, 'Emergency');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ledger-reservation-row-goal-allocate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-goal-return')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-fund-allocate')),
      findsNothing,
    );
    expect(find.text('Utility Bill'), findsNothing);

    await tester.enterText(search, 'Bills');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ledger-reservation-row-fund-allocate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-fund-return')),
      findsOneWidget,
    );
    expect(find.text('Utility Bill'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-goal-allocate')),
      findsNothing,
    );
  });

  testWidgets(
    'Ledger category filter excludes reservation-only activity but keeps spend',
    (tester) async {
      await _setPhoneSize(tester);
      await tester.pumpWidget(_testApp(_reservationLedgerStore()));
      await tester.pumpAndSettle();

      await _openFilterRow(
        tester,
        const ValueKey('ledger-filter-category-row'),
      );
      await tester.tap(find.text('Utilities'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ledger-reservation-row-goal-allocate')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ledger-reservation-row-goal-return')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ledger-reservation-row-fund-allocate')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ledger-reservation-row-fund-return')),
        findsNothing,
      );
      expect(find.text('Utility Bill'), findsOneWidget);
    },
  );

  testWidgets('Ledger account filter scopes reservation activity', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(_testApp(_reservationLedgerStore()));
    await tester.pumpAndSettle();

    await _openFilterRow(tester, const ValueKey('ledger-filter-account-row'));
    await tester.tap(find.text('Savings').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ledger-reservation-row-travel-allocate')),
      findsOneWidget,
    );
    expect(find.text('Allocated to Travel'), findsOneWidget);
    expect(find.text('Travel Fund'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-fund-allocate')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-goal-allocate')),
      findsNothing,
    );
    expect(find.text('Utility Bill'), findsNothing);
  });

  testWidgets('Ledger date filter excludes older reservation activity', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    await tester.pumpWidget(_testApp(_reservationLedgerStore()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ledger-reservation-row-travel-allocate')),
      findsOneWidget,
    );
    await _openFilterRow(tester, const ValueKey('ledger-filter-date-row'));
    await tester.tap(find.text('Last 30 days'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ledger-reservation-row-travel-allocate')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-goal-allocate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ledger-reservation-row-fund-allocate')),
      findsOneWidget,
    );
    expect(find.text('Utility Bill'), findsOneWidget);
  });

  testWidgets(
    'linked Fund spend stays one financial row and reservations stay nonfinancial',
    (tester) async {
      await _setPhoneSize(tester);
      final store = _reservationLedgerStore();
      await tester.pumpWidget(
        _testApp(store, initialAccountFilterId: 'checking'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Utility Bill'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ledger-reservation-row-fund-consume')),
        findsNothing,
      );
      final spendMetadata = tester.widget<Text>(
        find.byKey(const ValueKey('ledger-metadata-details-spend')),
      );
      expect(spendMetadata.data, contains('Bills Fund'));

      final monthlySummary = tester.widget<LedgerMonthlySummary>(
        find.byType(LedgerMonthlySummary),
      );
      expect(monthlySummary.incomeMinor, 0);
      expect(monthlySummary.expensesMinor, 3000);
      expect(monthlySummary.netMinor, -3000);
      expect(store.clearedBalanceForAccount('checking'), 247000);

      final runningBalance = tester.widget<AccountBalanceText>(
        find.byKey(const ValueKey('ledger-running-balance-spend')),
      );
      expect(runningBalance.signedBalanceMinor, 247000);
    },
  );
}

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openTypeFilter(WidgetTester tester) async {
  await _openFilterRow(tester, const ValueKey('ledger-filter-type-row'));
}

Future<void> _openFilterRow(WidgetTester tester, Key rowKey) async {
  await tester.tap(find.byKey(const ValueKey('ledger-filter-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(rowKey));
  await tester.pumpAndSettle();
}

Widget _testApp(FinanceDataStore store, {String? initialAccountFilterId}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FinanceDataStoreScope(
      store: store,
      child: Scaffold(
        body: SafeArea(
          child: LedgerView(initialAccountFilterId: initialAccountFilterId),
        ),
      ),
    ),
  );
}

FinanceDataStore _reservationLedgerStore() {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  final sync = v2_sync.SyncMetadata.fresh(
    now: DateTime.utc(2026, 8, 24),
    deviceId: 'test',
  );
  ReservationOperationRecord operation({
    required String id,
    required ReservationContainerType containerType,
    required String containerId,
    required ReservationOperationKind kind,
    required int amountMinor,
    required int revision,
    required int hour,
    String fundingAccountId = 'checking',
    int dayOffset = 0,
    String? transactionId,
  }) {
    return ReservationOperationRecord(
      id: id,
      containerType: containerType,
      containerId: containerId,
      fundingAccountId: fundingAccountId,
      kind: kind,
      amountMinor: amountMinor,
      effectiveDate: day.add(Duration(days: dayOffset, hours: hour)),
      revision: revision,
      baseRevision: revision - 1,
      operationId: id,
      deviceId: 'test',
      transactionId: transactionId,
      sync: sync,
    );
  }

  return FinanceDataStore(
    dataSet: FinanceDataSet(
      accounts: [
        v2_account.AccountRecord(
          id: 'checking',
          name: 'Checking',
          type: v2_account.AccountType.checking,
          openingBalanceMinor: 250000,
          sync: sync,
        ),
        v2_account.AccountRecord(
          id: 'savings',
          name: 'Savings',
          type: v2_account.AccountType.savings,
          openingBalanceMinor: 50000,
          sync: sync,
        ),
      ],
      categories: [
        v2_category.CategoryRecord(
          id: 'utilities',
          name: 'Utilities',
          kind: v2_category.CategoryKind.expense,
          sync: sync,
        ),
      ],
      transactions: [
        v2_transaction.TransactionRecord(
          id: 'spend',
          type: v2_transaction.TransactionType.expense,
          accountId: 'checking',
          categoryId: 'utilities',
          date: day.add(const Duration(hours: 16)),
          payee: 'Utility Bill',
          amountMinor: 3000,
          reservationContainerType: ReservationContainerType.fund,
          reservationContainerId: 'bills',
          sync: sync,
        ),
      ],
      scheduledTransactions: const [],
      budgets: const [],
      goals: [
        GoalRecord(
          id: 'emergency',
          name: 'Emergency',
          targetAmountMinor: 100000,
          status: GoalStatus.active,
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
          reservationModelVersion: 1,
          sync: sync,
        ),
      ],
      funds: [
        FundRecord(
          id: 'bills',
          name: 'Bills',
          fundingAccountId: 'checking',
          status: FundStatus.active,
          sync: sync,
        ),
        FundRecord(
          id: 'travel',
          name: 'Travel',
          fundingAccountId: 'savings',
          status: FundStatus.active,
          sync: sync,
        ),
      ],
      goalFundingEvents: [
        GoalFundingEventRecord(
          id: 'goal-event-mirror',
          sourceAccountId: 'checking',
          totalAmountMinor: 10000,
          date: day.add(const Duration(hours: 8)),
          isMigrationEvent: true,
          allocations: const [
            GoalFundingAllocation(
              id: 'goal-allocation-mirror',
              fundingEventId: 'goal-event-mirror',
              goalId: 'emergency',
              amountMinor: 10000,
              order: 0,
            ),
          ],
          sync: sync,
        ),
      ],
      reservationOperations: [
        operation(
          id: 'goal-allocate',
          containerType: ReservationContainerType.goal,
          containerId: 'emergency',
          kind: ReservationOperationKind.allocate,
          amountMinor: 10000,
          revision: 1,
          hour: 8,
        ),
        operation(
          id: 'goal-return',
          containerType: ReservationContainerType.goal,
          containerId: 'emergency',
          kind: ReservationOperationKind.returnFunds,
          amountMinor: 2500,
          revision: 2,
          hour: 9,
        ),
        operation(
          id: 'fund-allocate',
          containerType: ReservationContainerType.fund,
          containerId: 'bills',
          kind: ReservationOperationKind.allocate,
          amountMinor: 20000,
          revision: 1,
          hour: 10,
        ),
        operation(
          id: 'fund-return',
          containerType: ReservationContainerType.fund,
          containerId: 'bills',
          kind: ReservationOperationKind.returnFunds,
          amountMinor: 5000,
          revision: 2,
          hour: 11,
        ),
        operation(
          id: 'fund-consume',
          containerType: ReservationContainerType.fund,
          containerId: 'bills',
          kind: ReservationOperationKind.consume,
          amountMinor: 3000,
          revision: 3,
          hour: 16,
          transactionId: 'spend',
        ),
        operation(
          id: 'travel-allocate',
          containerType: ReservationContainerType.fund,
          containerId: 'travel',
          kind: ReservationOperationKind.allocate,
          amountMinor: 1000,
          revision: 1,
          hour: 12,
          fundingAccountId: 'savings',
          dayOffset: -40,
        ),
      ],
      preferences: const UserPreferences(showRunningBalance: true),
    ),
    deviceId: 'test',
  );
}
