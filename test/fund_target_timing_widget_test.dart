import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' show AppTheme, showFundEditor;
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

const _fixedChoice = 'Choose date — repeat monthly on that day';

void main() {
  for (final width in [390.0, 1024.0, 1440.0]) {
    testWidgets('create explicit month-end Fund at width $width', (
      tester,
    ) async {
      final store = _store();
      await _openEditor(tester, store, width: width);
      await tester.enterText(find.byKey(const ValueKey('fund-name')), 'Bills');
      await tester.tap(find.byKey(const ValueKey('fund-funding-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CTBI').last);
      await tester.pumpAndSettle();
      await _chooseTiming(tester, 'End of every month');
      final now = DateTime.now();
      expect(find.text('Last day of every month'), findsOneWidget);
      expect(find.text('First target date'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _save(tester);
      final fund = store.funds.single;
      expect(fund.targetCadence, FundTargetCadence.monthly);
      expect(fund.targetDayRule, FundTargetDayRule.endOfMonth);
      expect(fund.nextTargetDate, DateTime(now.year, now.month + 1, 0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chosen date creates fixed-day monthly recurrence', (
    tester,
  ) async {
    final store = _store();
    await _openEditor(tester, store);
    await tester.enterText(find.byKey(const ValueKey('fund-name')), 'Bills');
    await tester.tap(find.byKey(const ValueKey('fund-funding-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CTBI').last);
    await tester.pumpAndSettle();
    await _chooseTiming(tester, _fixedChoice);
    await _enterDate(tester, '09/15/2026');
    await _save(tester);
    final fund = store.funds.single;
    expect(fund.targetCadence, FundTargetCadence.monthly);
    expect(fund.targetDayRule, FundTargetDayRule.fixedDay);
    expect(fund.nextTargetDate, DateTime(2026, 9, 15));
    expect(
      effectiveFundTargetDate(fund, asOf: DateTime(2026, 10, 1)),
      DateTime(2026, 10, 15),
    );
  });

  testWidgets('legacy edit preserves fixed-day until explicitly changed', (
    tester,
  ) async {
    final store = _store();
    final legacy = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
      targetBalanceMinor: 360000,
      targetCadence: FundTargetCadence.monthly,
      nextTargetDate: DateTime(2026, 9, 30),
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: legacy.id,
      amountMinor: 50000,
      date: DateTime(2026, 9, 1),
    );
    final history = store.reservationOperations
        .map((op) => op.toJson())
        .toList();
    final balance = store.balanceForAccount('checking');
    await _openEditor(tester, store, fundId: legacy.id);
    final timing = find.byKey(const ValueKey('fund-target-cadence'));
    await tester.ensureVisible(timing);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: timing, matching: find.text('Monthly on day 30')),
      findsOneWidget,
    );
    await _save(tester);
    expect(store.fundById(legacy.id).targetDayRule, FundTargetDayRule.fixedDay);
    expect(
      effectiveFundTargetDate(
        store.fundById(legacy.id),
        asOf: DateTime(2026, 10, 1),
      ),
      DateTime(2026, 10, 30),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _chooseTiming(tester, 'End of every month');
    await _save(tester);
    expect(
      store.fundById(legacy.id).targetDayRule,
      FundTargetDayRule.endOfMonth,
    );
    expect(
      effectiveFundTargetDate(
        store.fundById(legacy.id),
        asOf: DateTime(2026, 10, 1),
      ),
      DateTime(2026, 10, 31),
    );
    expect(store.currentFundAmountMinor(legacy.id), 50000);
    expect(store.balanceForAccount('checking'), balance);
    expect(
      store.reservationOperations.map((op) => op.toJson()).toList(),
      history,
    );

    // A cancelled date choice must not silently turn EOM back into fixed-day.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _chooseTiming(tester, _fixedChoice);
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester);
    expect(
      store.fundById(legacy.id).targetDayRule,
      FundTargetDayRule.endOfMonth,
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _chooseTiming(tester, _fixedChoice);
    await _enterDate(tester, '09/30/2026');
    await _save(tester);
    expect(store.fundById(legacy.id).targetDayRule, FundTargetDayRule.fixedDay);
    expect(
      effectiveFundTargetDate(
        store.fundById(legacy.id),
        asOf: DateTime(2026, 10, 1),
      ),
      DateTime(2026, 10, 30),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing first month retains explicit EOM semantics', (
    tester,
  ) async {
    final store = _store();
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
      targetCadence: FundTargetCadence.monthly,
      targetDayRule: FundTargetDayRule.endOfMonth,
      nextTargetDate: DateTime(2026, 9, 30),
    );
    await _openEditor(tester, store, fundId: fund.id);
    final date = find.byKey(const ValueKey('fund-target-date'));
    await tester.ensureVisible(date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    await _enterDate(tester, '02/15/2028');
    await _save(tester);
    final saved = store.fundById(fund.id);
    expect(saved.targetDayRule, FundTargetDayRule.endOfMonth);
    expect(saved.nextTargetDate, DateTime(2028, 2, 29));
    expect(
      effectiveFundTargetDate(saved, asOf: DateTime(2028, 3, 1)),
      DateTime(2028, 3, 31),
    );
  });
}

Future<void> _openEditor(
  WidgetTester tester,
  FinanceDataStore store, {
  String? fundId,
  double width = 430,
}) async {
  tester.view.physicalSize = Size(width, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light().copyWith(
        platform: width >= 1440 ? TargetPlatform.macOS : TargetPlatform.iOS,
      ),
      home: FinanceDataStoreScope(
        store: store,
        child: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showFundEditor(
                context,
                initialFund: fundId == null ? null : store.fundById(fundId),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _chooseTiming(WidgetTester tester, String label) async {
  final row = find.byKey(const ValueKey('fund-target-cadence'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _enterDate(WidgetTester tester, String value) async {
  final dialog = find.byType(DatePickerDialog);
  final localizations = MaterialLocalizations.of(tester.element(dialog));
  await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(TextFormField)),
    value,
  );
  await tester.tap(find.descendant(of: dialog, matching: find.text('OK')));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

FinanceDataStore _store() => FinanceDataStore(
  dataSet: FinanceDataSet(
    accounts: [
      AccountRecord(
        id: 'checking',
        name: 'CTBI',
        type: AccountType.checking,
        openingBalanceMinor: 1000000,
        sync: SyncMetadata.fresh(now: DateTime.utc(2026, 9, 4)),
      ),
    ],
    categories: const [],
    transactions: const [],
    scheduledTransactions: const [],
    budgets: const [],
    preferences: const UserPreferences(),
  ),
);
