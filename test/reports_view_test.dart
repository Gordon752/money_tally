import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/account.dart' as v2_account;
import 'package:money_tally/src/domain/category.dart' as v2_category;
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

void main() {
  testWidgets(
    'reports range updates every section and responds to store data',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = reportStore();

      await pumpReports(tester, store);

      expect(find.text('Spending by Category'), findsOneWidget);
      expect(find.text('Spending by Account'), findsOneWidget);
      expect(find.text('Income by Source'), findsOneWidget);
      expect(find.text('Monthly Trend'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spending-category-donut')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('monthly-trend-chart')), findsNothing);
      final trendExpand = find.byKey(const ValueKey('report-trend-expand'));
      await tester.ensureVisible(trendExpand);
      await tester.tap(trendExpand);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('monthly-trend-chart')), findsOneWidget);
      final categoryExpand = find.byKey(
        const ValueKey('report-categories-expand'),
      );
      await tester.ensureVisible(categoryExpand);
      await tester.tap(categoryExpand);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spending-category-donut')),
        findsOneWidget,
      );
      expect(find.text(r'$1,000.00'), findsWidgets);
      expect(find.text(r'$250.00'), findsWidgets);
      expect(find.text(r'$750.00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reports-date-range')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last Month').last);
      await tester.pumpAndSettle();

      expect(find.text('Last Month'), findsWidgets);
      expect(find.text(r'$400.00'), findsWidgets);
      expect(find.text(r'$100.00'), findsWidgets);
      expect(find.text(r'$300.00'), findsWidgets);

      await store.addExpense(
        accountId: 'checking',
        categoryId: 'groceries',
        date: DateTime(2026, 6, 20),
        payee: 'Market',
        amountMinor: 5000,
      );
      await tester.pumpAndSettle();

      expect(find.text(r'$150.00'), findsWidgets);
      expect(find.text(r'$250.00'), findsWidgets);
    },
  );

  testWidgets('reports show useful empty states in dark mode', (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FinanceDataStore.empty();

    await tester.pumpWidget(
      FinanceDataStoreScope(
        store: store,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportsView(now: () => DateTime(2026, 7, 23)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No expense data for this period'), findsOneWidget);
    expect(find.text('No account spending for this period'), findsOneWidget);
    expect(find.text('No income data for this period'), findsOneWidget);
    expect(find.text('No trend data yet'), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
    expect(find.byType(BarChart), findsNothing);
  });

  testWidgets('category chart opens Ledger on tap but never on hover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpReports(tester, reportStore());
    final expandCategories = find.byKey(
      const ValueKey('report-categories-expand'),
    );
    await tester.ensureVisible(expandCategories);
    await tester.tap(expandCategories);
    await tester.pumpAndSettle();

    final chart = find.byKey(const ValueKey('spending-category-donut'));
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    final chartRect = tester.getRect(chart);
    final categorySectionPoint = Offset(
      chartRect.center.dx + 74,
      chartRect.center.dy,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: categorySectionPoint);
    await mouse.moveTo(categorySectionPoint);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('report-ledger-screen')), findsNothing);

    await tester.tapAt(categorySectionPoint);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-ledger-screen')), findsOneWidget);
  });

  testWidgets(
    'report drill-downs reuse Ledger filters and Back preserves report state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = reportStore();

      await pumpReports(tester, store);
      await tester.tap(find.byKey(const ValueKey('reports-date-range')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last Month').last);
      await tester.pumpAndSettle();

      final expandCategories = find.byKey(
        const ValueKey('report-categories-expand'),
      );
      await tester.ensureVisible(expandCategories);
      await tester.tap(expandCategories);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spending-category-donut')),
        findsOneWidget,
      );

      final category = find.byKey(const ValueKey('report-category-groceries'));
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('report-ledger-screen')),
        findsOneWidget,
      );
      expect(find.text('Category: Groceries'), findsOneWidget);
      expect(find.text('Last Month'), findsOneWidget);
      expect(find.text('june-expense'), findsWidgets);
      expect(find.text('july-expense'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('report-ledger-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('report-ledger-screen')), findsNothing);
      expect(find.text('Last Month'), findsWidgets);
      expect(
        find.byKey(const ValueKey('spending-category-donut')),
        findsOneWidget,
      );

      final account = find.byKey(const ValueKey('report-account-checking'));
      await tester.ensureVisible(account);
      await tester.tap(account);
      await tester.pumpAndSettle();
      expect(find.text('Account: Checking'), findsOneWidget);
      expect(find.text('june-expense'), findsWidgets);
      expect(find.text('june-income'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('report-ledger-back')));
      await tester.pumpAndSettle();

      final income = find.byKey(const ValueKey('report-income-june-income'));
      await tester.ensureVisible(income);
      await tester.tap(income);
      await tester.pumpAndSettle();
      expect(find.text('Income source: june-income'), findsOneWidget);
      expect(find.text('june-income'), findsWidgets);
      expect(find.text('june-expense'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('report-ledger-back')));
      await tester.pumpAndSettle();

      expect(find.text('Last Month'), findsWidgets);
      expect(
        find.byKey(const ValueKey('report-account-checking')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Reports filtered Ledger supports native iOS edge swipe back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpReports(tester, reportStore(), platform: TargetPlatform.iOS);
    final category = find.byKey(const ValueKey('report-category-groceries'));
    await tester.tap(category);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-ledger-screen')), findsOneWidget);

    await tester.dragFrom(const Offset(1, 300), const Offset(340, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('report-ledger-screen')), findsNothing);
    expect(find.text('Spending by Category'), findsOneWidget);
  });
}

Future<void> pumpReports(
  WidgetTester tester,
  FinanceDataStore store, {
  TargetPlatform? platform,
}) async {
  await tester.pumpWidget(
    FinanceDataStoreScope(
      store: store,
      child: MaterialApp(
        theme: AppTheme.light().copyWith(platform: platform),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ReportsView(now: () => DateTime(2026, 7, 23)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FinanceDataStore reportStore() {
  final sync = v2_sync.SyncMetadata.fresh(now: DateTime(2026, 1, 1));
  return FinanceDataStore(
    dataSet: FinanceDataSet(
      accounts: [
        v2_account.AccountRecord(
          id: 'checking',
          name: 'Checking',
          type: v2_account.AccountType.checking,
          openingBalanceMinor: 0,
          sync: sync,
        ),
        v2_account.AccountRecord(
          id: 'savings',
          name: 'Savings',
          type: v2_account.AccountType.savings,
          openingBalanceMinor: 0,
          sync: sync,
        ),
      ],
      categories: [
        v2_category.CategoryRecord(
          id: 'income',
          name: 'Income',
          kind: v2_category.CategoryKind.income,
          sync: sync,
        ),
        v2_category.CategoryRecord(
          id: 'groceries',
          name: 'Groceries',
          kind: v2_category.CategoryKind.expense,
          sync: sync,
        ),
      ],
      transactions: [
        reportTransaction(
          id: 'july-income',
          type: TransactionType.income,
          date: DateTime(2026, 7, 2),
          amountMinor: 100000,
          categoryId: 'income',
          sync: sync,
        ),
        reportTransaction(
          id: 'july-expense',
          type: TransactionType.expense,
          date: DateTime(2026, 7, 3),
          amountMinor: 25000,
          categoryId: 'groceries',
          sync: sync,
        ),
        reportTransaction(
          id: 'june-income',
          type: TransactionType.income,
          date: DateTime(2026, 6, 2),
          amountMinor: 40000,
          categoryId: 'income',
          sync: sync,
        ),
        reportTransaction(
          id: 'june-expense',
          type: TransactionType.expense,
          date: DateTime(2026, 6, 3),
          amountMinor: 10000,
          categoryId: 'groceries',
          sync: sync,
        ),
        reportTransaction(
          id: 'july-transfer',
          type: TransactionType.transfer,
          date: DateTime(2026, 7, 4),
          amountMinor: 99900,
          sync: sync,
        ),
      ],
      scheduledTransactions: const [],
      budgets: const [],
      preferences: const UserPreferences(),
    ),
  );
}

TransactionRecord reportTransaction({
  required String id,
  required TransactionType type,
  required DateTime date,
  required int amountMinor,
  required v2_sync.SyncMetadata sync,
  String? categoryId,
}) {
  return TransactionRecord(
    id: id,
    type: type,
    accountId: 'checking',
    transferAccountId: type == TransactionType.transfer ? 'savings' : null,
    categoryId: categoryId,
    date: date,
    payee: id,
    amountMinor: amountMinor,
    sync: sync,
  );
}
