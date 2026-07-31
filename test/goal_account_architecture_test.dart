import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  test(
    'Goal funding is an ordinary transfer into a hidden Goal account',
    () async {
      final store = _store();
      final before = store.netWorthMinor;
      final goal = await store.createGoal(
        name: 'Tires',
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: null,
      );

      expect(goal.isAccountBacked, isTrue);
      expect(
        store.activeAccountsInDisplayOrder.map((a) => a.id),
        isNot(contains(goal.accountId)),
      );

      final event = await store.fundGoals(
        sourceAccountId: 'checking',
        totalAmountMinor: 25000,
        date: DateTime(2026, 7, 30),
        allocations: [
          GoalFundingAllocation(
            id: 'tires-allocation',
            fundingEventId: '',
            goalId: goal.id,
            amountMinor: 25000,
            order: 0,
          ),
        ],
      );

      expect(store.balanceForAccount('checking'), 75000);
      expect(store.currentGoalAmountMinor(goal.id), 25000);
      expect(store.netWorthMinor, before);
      final transfer = store.transactions.single;
      expect(transfer.accountId, 'checking');
      expect(transfer.transferAccountId, goal.accountId);
      expect(transfer.goalFundingEventId, event.id);

      await store.undoGoalFunding(event.id);
      expect(store.balanceForAccount('checking'), 100000);
      expect(store.currentGoalAmountMinor(goal.id), 0);
      expect(store.transactions.single.isDeleted, isTrue);
    },
  );

  test(
    'spending from a Goal is an expense and cannot overdraw the Goal',
    () async {
      final store = _store();
      final goal = await store.createGoal(
        name: 'Repair reserve',
        targetAmountMinor: 100000,
        startingAmountMinor: 30000,
        targetDate: null,
      );

      await store.addExpense(
        accountId: goal.accountId!,
        categoryId: 'maintenance',
        date: DateTime(2026, 7, 30),
        payee: 'Tire shop',
        amountMinor: 12000,
      );
      expect(store.currentGoalAmountMinor(goal.id), 18000);
      expect(store.expensesThisMonthMinor(now: DateTime(2026, 7, 30)), 12000);

      await expectLater(
        store.addExpense(
          accountId: goal.accountId!,
          categoryId: 'maintenance',
          date: DateTime(2026, 7, 30),
          payee: 'Too much',
          amountMinor: 18001,
        ),
        throwsA(isA<FinanceDataValidationException>()),
      );
    },
  );

  test(
    'legacy Goal funding migrates once without changing balances or net worth',
    () async {
      final sync = SyncMetadata.fresh(now: DateTime(2026, 7, 1));
      final legacyGoal = GoalRecord(
        id: 'legacy-goal',
        name: 'Legacy reserve',
        targetAmountMinor: 100000,
        status: GoalStatus.archived,
        fundingMethod: GoalFundingMethod.accountFunded,
        sync: sync,
      );
      final legacyFunding = GoalFundingEventRecord(
        id: 'legacy-funding',
        sourceAccountId: 'checking',
        totalAmountMinor: 25000,
        date: DateTime(2026, 7, 2),
        allocations: const [
          GoalFundingAllocation(
            id: 'legacy-allocation',
            fundingEventId: 'legacy-funding',
            goalId: 'legacy-goal',
            amountMinor: 25000,
            order: 0,
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
          categories: const [],
          transactions: const [],
          scheduledTransactions: const [],
          budgets: const [],
          goals: [legacyGoal],
          goalFundingEvents: [legacyFunding],
          preferences: const UserPreferences(),
        ),
      );
      final balanceBefore = store.balanceForAccount('checking');
      final netWorthBefore = store.netWorthMinor;

      await store.migrateLegacyGoalsToAccounts();
      final migrated = store.goalById('legacy-goal');
      expect(migrated.accountId, 'goal_account_legacy-goal');
      expect(store.balanceForAccount('checking'), balanceBefore);
      expect(store.currentGoalAmountMinor(migrated.id), 25000);
      expect(store.netWorthMinor, netWorthBefore);
      expect(store.goalFundingEvents.single.isMigrationEvent, isTrue);
      expect(store.transactions, hasLength(1));

      await store.migrateLegacyGoalsToAccounts();
      expect(store.transactions, hasLength(1));
    },
  );
}

FinanceDataStore _store() {
  final sync = SyncMetadata.fresh(now: DateTime(2026, 7, 1));
  return FinanceDataStore(
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
          id: 'maintenance',
          name: 'Maintenance',
          kind: CategoryKind.expense,
          sync: sync,
        ),
      ],
      transactions: const [],
      scheduledTransactions: const [],
      budgets: const [],
      preferences: const UserPreferences(),
    ),
  );
}
