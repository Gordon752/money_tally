import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
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
      expect(store.balanceForAccount('checking'), 100000);

      await store.saveTransaction(
        store.transactions.single.copyWith(
          sync: store.transactions.single.sync.deleted(
            deviceId: store.deviceId,
          ),
        ),
      );
      expect(store.currentGoalAmountMinor(goal.id), 30000);
      expect(store.balanceForAccount('checking'), 100000);
      expect(store.transactions.single.isDeleted, isTrue);

      await expectLater(
        store.addExpense(
          accountId: goal.accountId!,
          categoryId: 'maintenance',
          date: DateTime(2026, 7, 30),
          payee: 'Too much',
          amountMinor: 30001,
        ),
        throwsA(isA<FinanceDataValidationException>()),
      );
    },
  );

  test(
    'undoing Goal funding cannot create a negative Goal after spending',
    () async {
      final store = _store();
      final goal = await store.createGoal(
        name: 'test',
        targetAmountMinor: 50000,
        startingAmountMinor: 0,
        targetDate: null,
      );
      final funding = await store.fundGoals(
        sourceAccountId: 'checking',
        totalAmountMinor: 20000,
        date: DateTime(2026, 7, 31),
        allocations: [
          GoalFundingAllocation(
            id: 'test-funding-allocation',
            fundingEventId: '',
            goalId: goal.id,
            amountMinor: 20000,
            order: 0,
          ),
        ],
      );
      await store.addExpense(
        accountId: goal.accountId!,
        categoryId: 'maintenance',
        date: DateTime(2026, 7, 31),
        payee: "Love's",
        amountMinor: 10000,
      );

      await expectLater(
        store.undoGoalFunding(funding.id),
        throwsA(isA<FinanceDataValidationException>()),
      );
      expect(store.currentGoalAmountMinor(goal.id), 10000);
      expect(store.transactions.where((item) => !item.isDeleted), hasLength(2));
      expect(store.goalFundingEvents.single.isActive, isTrue);
    },
  );

  test(
    'a zero-balance archived Goal detaches cleanly despite ledger history',
    () async {
      final store = _store();
      final goal = await store.createGoal(
        name: 'Temporary Goal',
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: null,
      );
      await store.fundGoals(
        sourceAccountId: 'checking',
        totalAmountMinor: 25000,
        date: DateTime(2026, 7, 30),
        allocations: [
          GoalFundingAllocation(
            id: 'temporary-allocation',
            fundingEventId: '',
            goalId: goal.id,
            amountMinor: 25000,
            order: 0,
          ),
        ],
      );
      await store.addTransfer(
        fromAccountId: goal.accountId!,
        toAccountId: 'checking',
        date: DateTime(2026, 7, 30),
        payee: 'Withdraw temporary Goal',
        amountMinor: 25000,
      );
      await store.archiveGoal(goal.id);

      expect(store.currentGoalAmountMinor(goal.id), 0);
      expect(store.goalDeleteEligibility(goal.id).canDelete, isTrue);

      await store.deleteGoalPermanently(goal.id);

      expect(store.goalById(goal.id).isDeleted, isTrue);
      final retainedAccount = store.accounts.singleWhere(
        (account) => account.id == goal.accountId,
      );
      expect(retainedAccount.isDetachedGoalAccount, isTrue);
      expect(retainedAccount.isInternalGoalAccount, isTrue);
    },
  );

  test(
    'completed scheduled Goal history does not block zero-balance deletion',
    () async {
      final store = _store();
      final goal = await store.createGoal(
        name: 'Completed schedule Goal',
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: null,
      );
      await store.saveScheduledTransaction(
        ScheduledTransactionRecord(
          id: 'completed-goal-transfer',
          type: TransactionType.transfer,
          accountId: 'checking',
          transferAccountId: goal.accountId,
          goalId: goal.id,
          payee: 'Fund completed schedule Goal',
          amountMinor: 10000,
          nextDate: DateTime(2026, 7, 1),
          frequency: RecurrenceFrequency.once,
          occurrences: [
            ScheduledOccurrenceRecord(
              scheduledDate: DateTime(2026, 7, 1),
              plannedAmountMinor: 10000,
              status: ScheduledOccurrenceStatus.paid,
            ),
          ],
          sync: SyncMetadata.fresh(now: DateTime(2026, 7, 1)),
        ),
      );
      await store.archiveGoal(goal.id);

      expect(store.goalDeleteEligibility(goal.id).canDelete, isTrue);
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
      expect(store.hasUsableGoalAccount(migrated.id), isTrue);
      expect(
        store.goalDeleteEligibility(migrated.id).remainingBalanceMinor,
        25000,
      );

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
