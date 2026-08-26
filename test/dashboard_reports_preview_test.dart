import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  final now = DateTime(2026, 7, 23);

  testWidgets(
    'dashboard report preview uses report totals and shows top spending',
    (tester) async {
      var viewFullCount = 0;
      await pumpPreview(
        tester,
        dashboardReportStore(now),
        now: now,
        onViewFull: () => viewFullCount += 1,
      );

      expect(find.text('This Month'), findsOneWidget);
      expect(find.text(r'$1,000.00'), findsOneWidget);
      expect(find.text(r'$450.00'), findsOneWidget);
      expect(find.text(r'$550.00'), findsOneWidget);
      expect(find.text('Top Spending'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dashboard-top-spending-groceries')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dashboard-top-spending-fuel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dashboard-top-spending-dining')),
        findsNothing,
      );
      expect(find.text(r'$250.00'), findsOneWidget);
      expect(find.text(r'$150.00'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('dashboard-view-full-report')),
      );
      expect(viewFullCount, 1);
    },
  );

  testWidgets('empty dashboard report preview stays useful', (tester) async {
    await pumpPreview(
      tester,
      FinanceDataStore.empty(),
      now: now,
      onViewFull: () {},
    );

    expect(find.text('Top Spending'), findsOneWidget);
    expect(find.text('No expenses recorded this month.'), findsOneWidget);
    expect(find.text('View Full Report'), findsOneWidget);
  });

  testWidgets('dashboard report action opens existing Reports route on phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FinanceDataStoreScope(
        store: dashboardReportStore(DateTime.now()),
        child: MaterialApp(theme: AppTheme.light(), home: const FinanceHome()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Goals'), findsWidgets);
    final viewReport = find.byKey(const ValueKey('dashboard-view-full-report'));
    await tester.ensureVisible(viewReport);
    await tester.pumpAndSettle();
    await tester.tap(viewReport);
    await tester.pumpAndSettle();

    expect(find.text('Spending by Category'), findsOneWidget);
    expect(find.text('Monthly Trend'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dashboard-reports-preview')),
      findsOneWidget,
    );
  });
}

Future<void> pumpPreview(
  WidgetTester tester,
  FinanceDataStore store, {
  required DateTime now,
  required VoidCallback onViewFull,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    FinanceDataStoreScope(
      store: store,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DashboardReportsPreviewCard(
              now: () => now,
              onViewFull: onViewFull,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FinanceDataStore dashboardReportStore(DateTime now) {
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
        v2_category.CategoryRecord(
          id: 'fuel',
          name: 'Fuel',
          kind: v2_category.CategoryKind.expense,
          sync: sync,
        ),
        v2_category.CategoryRecord(
          id: 'dining',
          name: 'Dining',
          kind: v2_category.CategoryKind.expense,
          sync: sync,
        ),
      ],
      transactions: [
        dashboardTransaction(
          id: 'income',
          type: TransactionType.income,
          date: DateTime(now.year, now.month, 2),
          amountMinor: 100000,
          categoryId: 'income',
          sync: sync,
        ),
        dashboardTransaction(
          id: 'groceries-expense',
          type: TransactionType.expense,
          date: DateTime(now.year, now.month, 3),
          amountMinor: 25000,
          categoryId: 'groceries',
          sync: sync,
        ),
        dashboardTransaction(
          id: 'fuel-expense',
          type: TransactionType.expense,
          date: DateTime(now.year, now.month, 3),
          amountMinor: 15000,
          categoryId: 'fuel',
          sync: sync,
        ),
        dashboardTransaction(
          id: 'dining-expense',
          type: TransactionType.expense,
          date: DateTime(now.year, now.month, 3),
          amountMinor: 5000,
          categoryId: 'dining',
          sync: sync,
        ),
        dashboardTransaction(
          id: 'transfer',
          type: TransactionType.transfer,
          date: DateTime(now.year, now.month, 4),
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

TransactionRecord dashboardTransaction({
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
