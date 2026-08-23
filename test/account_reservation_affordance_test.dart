import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/account.dart' as v2_account;
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

void main() {
  testWidgets('account planning metadata has an independent details action', (
    tester,
  ) async {
    await _setSize(tester, const Size(393, 852));
    final store = _store();
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 200000,
      date: DateTime.now(),
    );
    var ledgerOpenCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: FinanceDataStoreScope(
          store: store,
          child: Scaffold(
            body: SingleChildScrollView(
              child: AccountsView(
                onOpenLedgerForAccount: (_) => ledgerOpenCount += 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('account-name-checking')));
    await tester.pump();
    expect(ledgerOpenCount, 1);
    await tester.tap(find.byKey(const ValueKey('account-leading-checking')));
    await tester.pump();
    expect(ledgerOpenCount, 2);
    await tester.tap(find.byKey(const ValueKey('account-balance-checking')));
    await tester.pump();
    expect(ledgerOpenCount, 3);

    final planningAction = find.byKey(
      const ValueKey('account-availability-action-checking'),
    );
    expect(planningAction, findsOneWidget);
    expect(tester.getSize(planningAction).height, greaterThanOrEqualTo(44));
    final planningText = tester.widget<Text>(
      find.byKey(const ValueKey('account-availability-checking')),
    );
    expect(planningText.style?.decoration, TextDecoration.underline);
    expect(planningText.style?.decorationThickness, lessThanOrEqualTo(0.7));
    await tester.tap(planningAction);
    await tester.pumpAndSettle();
    expect(ledgerOpenCount, 3);
    expect(find.byKey(const ValueKey('account-details-view')), findsOneWidget);
    expect(find.textContaining('Bills Fund'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('account-name-checking')));
    await tester.pumpAndSettle();
    expect(find.text('Account Details'), findsOneWidget);
  });

  testWidgets('account planning affordance remains clean at iPad width', (
    tester,
  ) async {
    await _setSize(tester, const Size(1024, 1366));
    final store = _store();
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 200000,
      date: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: FinanceDataStoreScope(
          store: store,
          child: const Scaffold(body: AccountsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final planningAction = find.byKey(
      const ValueKey('account-availability-action-checking'),
    );
    expect(planningAction, findsOneWidget);
    expect(tester.getSize(planningAction).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

FinanceDataStore _store() {
  final sync = v2_sync.SyncMetadata.fresh(
    now: DateTime.utc(2026, 8, 22),
    deviceId: 'test',
  );
  return FinanceDataStore(
    dataSet: FinanceDataSet(
      accounts: [
        v2_account.AccountRecord(
          id: 'checking',
          name: 'CTBI',
          type: v2_account.AccountType.checking,
          openingBalanceMinor: 500000,
          sync: sync,
        ),
      ],
      categories: const [],
      transactions: const [],
      scheduledTransactions: const [],
      budgets: const [],
      preferences: const UserPreferences(),
    ),
    deviceId: 'test',
  );
}
