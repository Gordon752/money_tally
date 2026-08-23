import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  test(
    'Goal funding reserves real account money without a hidden transfer',
    () async {
      final store = _store();
      final before = store.netWorthMinor;
      final goal = await store.createGoal(
        name: 'Tires',
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: null,
        defaultFundingAccountId: 'checking',
      );

      expect(goal.usesReservationModel, isTrue);
      expect(goal.accountId, isNull);

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

      expect(store.balanceForAccount('checking'), 100000);
      expect(store.currentGoalAmountMinor(goal.id), 25000);
      expect(store.reservedForAccount('checking'), 25000);
      expect(store.availableToSpendForAccount('checking'), 75000);
      expect(store.netWorthMinor, before);
      expect(store.transactions, isEmpty);

      await store.undoGoalFunding(event.id);
      expect(store.balanceForAccount('checking'), 100000);
      expect(store.currentGoalAmountMinor(goal.id), 0);
      expect(store.reservedForAccount('checking'), 0);
      expect(store.availableToSpendForAccount('checking'), 100000);
    },
  );

  test(
    'spending from a Goal changes the real balance and reservation once',
    () async {
      final store = _store();
      final goal = await store.createGoal(
        name: 'Repair reserve',
        targetAmountMinor: 100000,
        startingAmountMinor: 30000,
        targetDate: null,
        defaultFundingAccountId: 'checking',
      );

      final expense = await store.addExpense(
        accountId: 'checking',
        categoryId: 'maintenance',
        date: DateTime(2026, 7, 30),
        payee: 'Tire shop',
        amountMinor: 12000,
        reservationContainerType: ReservationContainerType.goal,
        reservationContainerId: goal.id,
      );
      expect(store.currentGoalAmountMinor(goal.id), 18000);
      expect(store.expensesThisMonthMinor(now: DateTime(2026, 7, 30)), 12000);
      expect(store.balanceForAccount('checking'), 88000);
      expect(store.availableToSpendForAccount('checking'), 70000);

      await store.saveTransaction(
        expense.copyWith(sync: expense.sync.deleted(deviceId: store.deviceId)),
      );
      expect(store.currentGoalAmountMinor(goal.id), 30000);
      expect(store.balanceForAccount('checking'), 100000);
      expect(store.availableToSpendForAccount('checking'), 70000);
      expect(store.transactions.single.isDeleted, isTrue);

      await expectLater(
        store.addExpense(
          accountId: 'checking',
          categoryId: 'maintenance',
          date: DateTime(2026, 7, 30),
          payee: 'Too much',
          amountMinor: 30001,
          reservationContainerType: ReservationContainerType.goal,
          reservationContainerId: goal.id,
        ),
        throwsA(isA<FinanceDataValidationException>()),
      );
    },
  );

  test('returning more than a Goal reservation is rejected', () async {
    final store = _store();
    final goal = await store.createGoal(
      name: 'test',
      targetAmountMinor: 50000,
      startingAmountMinor: 0,
      targetDate: null,
      defaultFundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.goal,
      containerId: goal.id,
      amountMinor: 20000,
      date: DateTime(2026, 7, 31),
    );
    await store.returnReservation(
      containerType: ReservationContainerType.goal,
      containerId: goal.id,
      amountMinor: 10000,
      date: DateTime(2026, 7, 31),
    );

    await expectLater(
      store.returnReservation(
        containerType: ReservationContainerType.goal,
        containerId: goal.id,
        amountMinor: 10001,
        date: DateTime(2026, 7, 31),
      ),
      throwsA(isA<FinanceDataValidationException>()),
    );
    expect(store.currentGoalAmountMinor(goal.id), 10000);
  });

  test('zero-reservation Goal can be archived and deleted safely', () async {
    final store = _store();
    final goal = await store.createGoal(
      name: 'Temporary Goal',
      targetAmountMinor: 100000,
      startingAmountMinor: 0,
      targetDate: null,
      defaultFundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.goal,
      containerId: goal.id,
      amountMinor: 25000,
      date: DateTime(2026, 7, 30),
    );
    await store.returnReservation(
      containerType: ReservationContainerType.goal,
      containerId: goal.id,
      amountMinor: 25000,
      date: DateTime(2026, 7, 30),
    );
    await store.archiveGoal(goal.id);

    expect(store.currentGoalAmountMinor(goal.id), 0);
    expect(store.goalDeleteEligibility(goal.id).canDelete, isTrue);
    expect(store.goalById(goal.id).isArchived, isTrue);
    expect(store.balanceForAccount('checking'), 100000);
    expect(store.reservedForAccount('checking'), 0);

    await store.deleteGoalPermanently(goal.id);
    expect(store.goalById(goal.id).isDeleted, isTrue);
  });

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
            AccountRecord(
              id: 'discover',
              name: 'Discover',
              type: AccountType.creditCard,
              openingBalanceMinor: -12345,
              creditLimitMinor: 650000,
              includeInGroupBalance: false,
              includeInNetWorth: false,
              sortOrder: 300,
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
      final unrelatedAccountBefore = store.accountById('discover').toJson();

      await store.migrateLegacyGoalsToAccounts();
      final migrated = store.goalById('legacy-goal');
      expect(migrated.accountId, 'goal_account_legacy-goal');
      expect(store.balanceForAccount('checking'), balanceBefore);
      expect(store.currentGoalAmountMinor(migrated.id), 25000);
      expect(store.netWorthMinor, netWorthBefore);
      expect(store.goalFundingEvents.single.isMigrationEvent, isTrue);
      expect(store.transactions, hasLength(1));
      expect(store.hasUsableGoalAccount(migrated.id), isTrue);
      expect(store.accountById('discover').toJson(), unrelatedAccountBefore);
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
