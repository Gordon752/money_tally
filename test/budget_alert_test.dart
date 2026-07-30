import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  test(
    'low budget alert fires once on a five-percent threshold crossing',
    () async {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final sync = SyncMetadata.fresh(now: now.toUtc());
      final budget = BudgetRecord(
        id: 'budget',
        name: 'Groceries',
        amountMinor: 10000,
        categoryIds: const ['groceries'],
        startDate: start,
        configurationRevisions: [
          BudgetConfigurationRevision(
            id: 'budget_config',
            effectiveDate: start,
            period: BudgetPeriod.monthly,
            amountMinor: 10000,
            categoryIds: const ['groceries'],
            startDate: start,
            anchorDate: start,
          ),
        ],
        sync: sync,
      );
      final store = FinanceDataStore(
        dataSet: FinanceDataSet(
          accounts: [
            AccountRecord(
              id: 'checking',
              name: 'Checking',
              type: AccountType.checking,
              openingBalanceMinor: 100000,
              sync: sync,
            ),
          ],
          categories: [
            CategoryRecord(
              id: 'groceries',
              name: 'Groceries',
              kind: CategoryKind.expense,
              sync: sync,
            ),
          ],
          transactions: const [],
          scheduledTransactions: const [],
          budgets: [budget],
          preferences: const UserPreferences(),
        ),
      );

      await store.addExpense(
        accountId: 'checking',
        categoryId: 'groceries',
        date: now,
        payee: 'Store',
        amountMinor: 9400,
      );
      expect(store.budgetLowAlertNotifier.value, isNull);

      await store.addExpense(
        accountId: 'checking',
        categoryId: 'groceries',
        date: now,
        payee: 'Store',
        amountMinor: 100,
      );
      expect(store.budgetLowAlertNotifier.value?.budgetId, 'budget');
      expect(store.budgetLowAlertNotifier.value?.remainingMinor, 500);

      store.dismissBudgetLowAlert();
      await store.addExpense(
        accountId: 'checking',
        categoryId: 'groceries',
        date: now,
        payee: 'Store',
        amountMinor: 50,
      );
      expect(store.budgetLowAlertNotifier.value, isNull);
    },
  );
}
