import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/goals/goal_calculator.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Goal calculations', () {
    test(
      'unfunded Reach Target Goals are not started with or without date',
      () {
        final calculator = const GoalCalculator();
        final dated = calculator.calculate(
          _goal(targetAmountMinor: 100000, targetDate: DateTime(2026, 12, 31)),
          const [],
          now: DateTime(2026, 8, 23),
        );
        final undated = calculator.calculate(
          _goal(targetAmountMinor: 100000),
          const [],
          now: DateTime(2026, 8, 23),
        );

        expect(dated.status, GoalProgressStatus.notStarted);
        expect(undated.status, GoalProgressStatus.notStarted);
        expect(dated.status.label, 'Not started');
        expect(undated.status.label, 'Not started');
        expect(dated.requiredWeeklyMinor, 5385);
        expect(dated.requiredMonthlyMinor, 23414);
        expect(undated.requiredWeeklyMinor, 0);
        expect(undated.requiredMonthlyMinor, 0);
      },
    );

    test(
      'new zero-funded dated Goal calculates the funding pace immediately',
      () {
        final metrics = const GoalCalculator().calculate(
          _goal(
            targetAmountMinor: 100000,
            targetDate: DateTime(2026, 9, 30),
            createdAt: DateTime(2026, 8, 24),
          ),
          const [],
          now: DateTime(2026, 8, 24),
        );

        expect(metrics.status, GoalProgressStatus.notStarted);
        expect(metrics.currentAmountMinor, 0);
        expect(metrics.remainingAmountMinor, 100000);
        expect(metrics.requiredWeeklyMinor, 18919);
        expect(metrics.requiredMonthlyMinor, 82264);
      },
    );

    test('funded undated Reach Target Goal remains timeline-neutral', () {
      final goal = _goal(targetAmountMinor: 100000);
      final metrics = const GoalCalculator().calculate(goal, [
        _contribution(goalId: goal.id, amountMinor: 25000),
      ], now: DateTime(2026, 8, 23));

      expect(metrics.currentAmountMinor, 25000);
      expect(metrics.remainingAmountMinor, 75000);
      expect(metrics.status, GoalProgressStatus.noTargetDate);
      expect(
        metrics.status,
        isNot(
          anyOf(
            GoalProgressStatus.onTrack,
            GoalProgressStatus.ahead,
            GoalProgressStatus.behind,
            GoalProgressStatus.seriouslyBehind,
          ),
        ),
      );
    });

    test('derives progress, requirements, and on-track status', () {
      final goal = _goal(
        targetAmountMinor: 100000,
        startingAmountMinor: 10000,
        targetDate: DateTime(2026, 7, 31),
        createdAt: DateTime(2026, 7, 1),
      );
      final contribution = _contribution(
        goalId: goal.id,
        amountMinor: 42500,
        date: DateTime(2026, 7, 15),
      );

      final metrics = const GoalCalculator().calculate(goal, [
        contribution,
      ], now: DateTime(2026, 7, 16));

      expect(metrics.currentAmountMinor, 52500);
      expect(metrics.expectedAmountMinor, 55000);
      expect(metrics.aheadBehindMinor, -2500);
      expect(metrics.requiredWeeklyMinor, 22167);
      expect(metrics.requiredMonthlyMinor, 96386);
      expect(metrics.status, GoalProgressStatus.onTrack);
    });

    test('central thresholds distinguish moderately and seriously behind', () {
      final goal = _goal(
        targetAmountMinor: 100000,
        targetDate: DateTime(2026, 7, 31),
        createdAt: DateTime(2026, 7, 1),
      );

      final moderatelyBehind = const GoalCalculator().calculate(goal, [
        _contribution(
          goalId: goal.id,
          amountMinor: 40000,
          date: DateTime(2026, 7, 15),
        ),
      ], now: DateTime(2026, 7, 16));
      final seriouslyBehind = const GoalCalculator().calculate(goal, [
        _contribution(
          goalId: goal.id,
          amountMinor: 20000,
          date: DateTime(2026, 7, 15),
        ),
      ], now: DateTime(2026, 7, 16));

      expect(moderatelyBehind.status, GoalProgressStatus.behind);
      expect(seriouslyBehind.status, GoalProgressStatus.seriouslyBehind);
    });

    test('target edits recalculate without rewriting contributions', () {
      final original = _goal(
        targetAmountMinor: 100000,
        targetDate: DateTime(2027, 7, 1),
      );
      final contribution = _contribution(
        goalId: original.id,
        amountMinor: 50000,
      );
      final edited = original.copyWith(
        targetAmountMinor: 40000,
        targetDate: DateTime(2026, 12, 1),
      );

      final metrics = const GoalCalculator().calculate(edited, [
        contribution,
      ], now: DateTime(2026, 7, 24));

      expect(contribution.amountMinor, 50000);
      expect(metrics.currentAmountMinor, 50000);
      expect(metrics.remainingAmountMinor, 0);
      expect(metrics.status, GoalProgressStatus.completed);
    });

    test('weekly and monthly requirements use one remaining day interval', () {
      final calculator = const GoalCalculator();
      final exactlyTwelveMonths = calculator.calculate(
        _goal(
          targetAmountMinor: 1000000,
          startingAmountMinor: 50000,
          targetDate: DateTime(2027, 7, 24),
          createdAt: DateTime(2026, 7, 24),
        ),
        const [],
        now: DateTime(2026, 7, 24),
      );
      final thirteenMonths = calculator.calculate(
        _goal(
          targetAmountMinor: 1000000,
          startingAmountMinor: 50000,
          targetDate: DateTime(2027, 8, 24),
          createdAt: DateTime(2026, 7, 24),
        ),
        const [],
        now: DateTime(2026, 7, 24),
      );

      expect(exactlyTwelveMonths.remainingAmountMinor, 950000);
      expect(exactlyTwelveMonths.requiredWeeklyMinor, 18220);
      expect(exactlyTwelveMonths.requiredMonthlyMinor, 79221);
      expect(thirteenMonths.requiredWeeklyMinor, 16793);
      expect(thirteenMonths.requiredMonthlyMinor, 73020);
    });

    test('requirement boundaries handle short, today, and past targets', () {
      final calculator = const GoalCalculator();
      GoalProgressMetrics metricsFor(DateTime targetDate) {
        return calculator.calculate(
          _goal(
            targetAmountMinor: 1000000,
            startingAmountMinor: 50000,
            targetDate: targetDate,
            createdAt: DateTime(2026, 7, 1),
          ),
          const [],
          now: DateTime(2026, 7, 24),
        );
      }

      final fewerThanThirtyDays = metricsFor(DateTime(2026, 8, 13));
      final today = metricsFor(DateTime(2026, 7, 24));
      final past = metricsFor(DateTime(2026, 7, 23));

      expect(fewerThanThirtyDays.requiredWeeklyMinor, 332500);
      expect(fewerThanThirtyDays.requiredMonthlyMinor, 1445782);
      expect(today.requiredWeeklyMinor, 950000);
      expect(today.requiredMonthlyMinor, 950000);
      expect(past.requiredWeeklyMinor, 950000);
      expect(past.requiredMonthlyMinor, 950000);
      expect(past.status, GoalProgressStatus.seriouslyBehind);
    });

    test('Maintain a Balance uses reserve and restoration language states', () {
      final calculator = const GoalCalculator();
      final goal = _goal(
        goalType: GoalType.maintainBalance,
        targetAmountMinor: 100000,
        targetDate: DateTime(2026, 8, 24),
      );

      final replenishing = calculator.calculate(goal, [
        _contribution(goalId: goal.id, amountMinor: 80000),
      ], now: DateTime(2026, 7, 24));
      final fullyFunded = calculator.calculate(goal, [
        _contribution(goalId: goal.id, amountMinor: 100000),
      ], now: DateTime(2026, 9, 24));
      final aboveTarget = calculator.calculate(goal, [
        _contribution(goalId: goal.id, amountMinor: 110000),
      ], now: DateTime(2026, 9, 24));
      final overdue = calculator.calculate(
        goal.copyWith(targetDate: DateTime(2026, 7, 23)),
        [_contribution(goalId: goal.id, amountMinor: 50000)],
        now: DateTime(2026, 7, 24),
      );

      expect(replenishing.status, GoalProgressStatus.replenishing);
      expect(replenishing.remainingAmountMinor, 20000);
      expect(replenishing.requiredWeeklyMinor, 4517);
      expect(replenishing.requiredMonthlyMinor, 19638);
      expect(fullyFunded.status, GoalProgressStatus.fullyFunded);
      expect(fullyFunded.requiredMonthlyMinor, 0);
      expect(aboveTarget.status, GoalProgressStatus.aboveReserveTarget);
      expect(aboveTarget.aheadBehindMinor, 10000);
      expect(overdue.status, GoalProgressStatus.restoreOverdue);
    });

    test('Maintain a Balance without restore date remains timing-neutral', () {
      final goal = _goal(
        goalType: GoalType.maintainBalance,
        targetAmountMinor: 100000,
      );
      final metrics = const GoalCalculator().calculate(goal, [
        _contribution(goalId: goal.id, amountMinor: 90000),
      ], now: DateTime(2026, 7, 24));

      expect(metrics.status, GoalProgressStatus.noRestoreDate);
      expect(metrics.remainingAmountMinor, 10000);
      expect(metrics.requiredWeeklyMinor, 0);
      expect(metrics.requiredMonthlyMinor, 0);
    });
  });

  group('Goal accounting and undo', () {
    test(
      'funding moves account value into a Goal without changing net worth',
      () async {
        final store = _store();
        final netWorthBefore = store.netWorthMinor;
        final goal = await store.createGoal(
          name: 'Emergency Fund',
          targetAmountMinor: 1000000,
          startingAmountMinor: 0,
          targetDate: DateTime(2027, 7, 24),
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
          now: DateTime(2026, 7, 24),
        );

        await store.fundGoals(
          sourceAccountId: 'checking',
          totalAmountMinor: 50000,
          date: DateTime(2026, 7, 24),
          allocations: [_allocation(goal.id, 50000)],
        );

        expect(store.currentGoalAmountMinor(goal.id), 50000);
        expect(store.balanceForAccount('checking'), 250000);
        expect(store.reservedForAccount('checking'), 50000);
        expect(store.availableToSpendForAccount('checking'), 200000);
        expect(store.fundedGoalAssetsMinor, 0);
        expect(store.netWorthMinor, netWorthBefore);
        expect(store.transactions, isEmpty);
      },
    );

    test('one funding event allocates across multiple Goals', () async {
      final store = _store();
      final first = await store.createGoal(
        name: 'Emergency',
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: null,
        fundingMethod: GoalFundingMethod.accountFunded,
        defaultFundingAccountId: 'checking',
      );
      final second = await store.createGoal(
        name: 'Vacation',
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: null,
        fundingMethod: GoalFundingMethod.accountFunded,
        defaultFundingAccountId: 'checking',
      );

      final event = await store.fundGoals(
        sourceAccountId: 'checking',
        totalAmountMinor: 42000,
        date: DateTime(2026, 7, 24),
        allocations: [
          _allocation(first.id, 15000),
          _allocation(second.id, 27000, order: 1),
        ],
      );

      expect(event.allocations, hasLength(2));
      expect(store.balanceForAccount('checking'), 250000);
      expect(store.reservedForAccount('checking'), 42000);
      expect(store.availableToSpendForAccount('checking'), 208000);
      expect(store.currentGoalAmountMinor(first.id), 15000);
      expect(store.currentGoalAmountMinor(second.id), 27000);
      expect(store.netWorthMinor, 250000);
    });

    test(
      'Maintain a Balance remains active when funded at and above target',
      () async {
        final store = _store();
        final goal = await store.createGoal(
          name: 'Truck Maintenance',
          goalType: GoalType.maintainBalance,
          targetAmountMinor: 100000,
          startingAmountMinor: 0,
          targetDate: DateTime(2027, 7, 24),
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
        );

        final event = await store.fundGoals(
          sourceAccountId: 'checking',
          totalAmountMinor: 110000,
          date: DateTime(2026, 7, 24),
          allocations: [_allocation(goal.id, 110000)],
        );

        expect(store.goalById(goal.id).isActive, isTrue);
        expect(store.goalById(goal.id).isCompleted, isFalse);
        expect(
          store.goalMetrics(goal.id).status,
          GoalProgressStatus.aboveReserveTarget,
        );
        expect(store.balanceForAccount('checking'), 250000);
        expect(store.reservedForAccount('checking'), 110000);
        expect(store.availableToSpendForAccount('checking'), 140000);
        expect(store.netWorthMinor, 250000);

        await store.undoGoalFunding(event.id);
        expect(store.goalById(goal.id).isActive, isTrue);
        expect(store.currentGoalAmountMinor(goal.id), 0);
        expect(store.balanceForAccount('checking'), 250000);
        expect(store.reservedForAccount('checking'), 0);
        expect(store.availableToSpendForAccount('checking'), 250000);
        expect(store.netWorthMinor, 250000);
      },
    );

    test(
      'changing Goal type preserves history, balances, and net worth',
      () async {
        final store = _store();
        final goal = await store.createGoal(
          name: 'Flexible Goal',
          targetAmountMinor: 100000,
          startingAmountMinor: 0,
          targetDate: DateTime(2027, 7, 24),
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
        );
        await store.fundGoals(
          sourceAccountId: 'checking',
          totalAmountMinor: 40000,
          date: DateTime(2026, 7, 24),
          allocations: [_allocation(goal.id, 40000)],
        );
        final balanceBefore = store.balanceForAccount('checking');
        final netWorthBefore = store.netWorthMinor;

        await store.saveGoal(
          store.goalById(goal.id).copyWith(goalType: GoalType.maintainBalance),
        );

        expect(store.goalById(goal.id).goalType, GoalType.maintainBalance);
        expect(store.currentGoalAmountMinor(goal.id), 40000);
        expect(store.goalFundingEvents, hasLength(1));
        expect(store.balanceForAccount('checking'), balanceBefore);
        expect(store.netWorthMinor, netWorthBefore);
      },
    );

    test(
      'legacy direct contributions are rejected for account-backed Goals',
      () async {
        final store = _store();
        final goal = await store.createGoal(
          name: 'Outside Savings',
          targetAmountMinor: 100000,
          startingAmountMinor: 0,
          targetDate: null,
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
        );
        expect(
          store.addGoalContribution(
            goalId: goal.id,
            amountMinor: 25000,
            date: DateTime(2026, 7, 24),
          ),
          throwsA(isA<FinanceDataValidationException>()),
        );
        expect(store.currentGoalAmountMinor(goal.id), 0);
        expect(store.balanceForAccount('checking'), 250000);
        expect(store.netWorthMinor, 250000);
      },
    );

    test('undo reverses the exact whole funding event once', () async {
      final store = _store();
      final goal = await store.createGoal(
        name: 'Car',
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: null,
        fundingMethod: GoalFundingMethod.accountFunded,
        defaultFundingAccountId: 'checking',
      );
      final event = await store.fundGoals(
        sourceAccountId: 'checking',
        totalAmountMinor: 50000,
        date: DateTime(2026, 7, 24),
        allocations: [_allocation(goal.id, 50000)],
      );

      await store.undoGoalFunding(event.id);

      expect(store.goalFundingEventById(event.id).isDeleted, isTrue);
      expect(store.currentGoalAmountMinor(goal.id), 0);
      expect(store.balanceForAccount('checking'), 250000);
      expect(store.netWorthMinor, 250000);
      expect(
        store.undoGoalFunding(event.id),
        throwsA(isA<FinanceDataValidationException>()),
      );
    });

    test('achievement remains historical after funding is undone', () async {
      final store = _store(openingBalanceMinor: 50000);
      final goal = await store.createGoal(
        name: 'Complete Me',
        targetAmountMinor: 25000,
        startingAmountMinor: 0,
        targetDate: null,
        fundingMethod: GoalFundingMethod.accountFunded,
        defaultFundingAccountId: 'checking',
      );
      final event = await store.fundGoals(
        sourceAccountId: 'checking',
        totalAmountMinor: 25000,
        date: DateTime(2026, 7, 24),
        allocations: [_allocation(goal.id, 25000)],
      );

      expect(store.goalById(goal.id).isCompleted, isTrue);
      final achievedAt = store.goalById(goal.id).completedAt;

      await store.undoGoalFunding(event.id);

      expect(store.goalById(goal.id).isAchieved, isTrue);
      expect(store.goalById(goal.id).completedAt, achievedAt);
      expect(store.currentGoalAmountMinor(goal.id), 0);
      expect(store.activeGoals, contains(store.goalById(goal.id)));
    });

    test(
      'achieve, archive, and restore preserve Goal history and lifecycle',
      () async {
        final store = _store();
        final goal = await store.createGoal(
          name: 'Lifecycle Goal',
          targetAmountMinor: 100000,
          startingAmountMinor: 0,
          targetDate: DateTime(2027, 7, 24),
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
        );
        final funding = await store.fundGoals(
          sourceAccountId: 'checking',
          date: DateTime(2026, 7, 24),
          totalAmountMinor: 25000,
          allocations: [_allocation(goal.id, 25000)],
        );

        await store.fundGoals(
          sourceAccountId: 'checking',
          date: DateTime(2026, 7, 25),
          totalAmountMinor: 75000,
          allocations: [_allocation(goal.id, 75000)],
        );
        expect(store.goalById(goal.id).isCompleted, isTrue);
        expect(store.goalById(goal.id).completedAt, isNotNull);
        final achievedAt = store.goalById(goal.id).completedAt;
        expect(store.activeGoals, contains(store.goalById(goal.id)));
        expect(store.inactiveGoals, isNot(contains(store.goalById(goal.id))));
        expect(store.goalFundingEventById(funding.id).isActive, isTrue);

        await store.archiveGoal(goal.id);
        expect(store.goalById(goal.id).isArchived, isTrue);
        expect(store.goalById(goal.id).completedAt, achievedAt);
        expect(store.inactiveGoals, contains(store.goalById(goal.id)));

        await store.restoreGoal(goal.id);
        expect(store.goalById(goal.id).isAchieved, isTrue);
        expect(store.goalById(goal.id).completedAt, achievedAt);
        expect(store.currentGoalAmountMinor(goal.id), 100000);
        expect(store.goalFundingEventById(funding.id).isActive, isTrue);
        expect(store.activeGoals, contains(store.goalById(goal.id)));
      },
    );

    test(
      'permanent Goal deletion is limited to Goals without history',
      () async {
        final store = _store();
        final unused = await store.createGoal(
          name: 'Unused',
          targetAmountMinor: 100000,
          startingAmountMinor: 0,
          targetDate: null,
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
        );
        expect(store.goalDeleteEligibility(unused.id).canDelete, isTrue);
        await store.deleteGoalPermanently(unused.id);
        expect(store.goalById(unused.id).isDeleted, isTrue);

        final used = await store.createGoal(
          name: 'Used',
          targetAmountMinor: 100000,
          startingAmountMinor: 0,
          targetDate: null,
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
        );
        await store.fundGoals(
          sourceAccountId: 'checking',
          totalAmountMinor: 1000,
          allocations: [_allocation(used.id, 1000)],
          date: DateTime(2026, 7, 24),
        );
        expect(store.goalDeleteEligibility(used.id).canDelete, isFalse);
        expect(
          store.deleteGoalPermanently(used.id),
          throwsA(isA<FinanceDataValidationException>()),
        );
      },
    );

    test(
      'duplicating an inactive Goal copies configuration but not history',
      () async {
        final store = _store();
        final goal = await store.createGoal(
          name: 'Original',
          targetAmountMinor: 100000,
          startingAmountMinor: 0,
          targetDate: DateTime(2027, 7, 24),
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
        );
        await store.fundGoals(
          sourceAccountId: 'checking',
          totalAmountMinor: 25000,
          allocations: [_allocation(goal.id, 25000)],
          date: DateTime(2026, 7, 24),
        );
        await store.archiveGoal(goal.id);

        final duplicate = await store.duplicateGoal(goal.id);
        expect(duplicate.id, isNot(goal.id));
        expect(duplicate.name, 'Original Copy');
        expect(duplicate.isActive, isTrue);
        expect(store.currentGoalAmountMinor(duplicate.id), 0);
        expect(
          store.goalContributions.where((item) => item.goalId == duplicate.id),
          isEmpty,
        );
      },
    );

    test('funding validates balance and active source account', () async {
      final store = _store(openingBalanceMinor: 50000);
      final goal = await store.createGoal(
        name: 'Account Goal',
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: null,
        fundingMethod: GoalFundingMethod.accountFunded,
        defaultFundingAccountId: 'checking',
      );

      expect(
        store.fundGoals(
          sourceAccountId: 'checking',
          totalAmountMinor: 50001,
          date: DateTime(2026, 7, 24),
          allocations: [_allocation(goal.id, 50001)],
        ),
        throwsA(isA<FinanceDataValidationException>()),
      );
      expect(
        store.archiveAccount('checking'),
        throwsA(isA<FinanceDataValidationException>()),
      );
    });
  });

  group('Goal reservation migration', () {
    test('legacy reservation records require an explicit migration choice', () {
      final goal = GoalRecord.fromJson({
        'id': 'legacy-goal',
        'name': 'Legacy Goal',
        'targetAmountMinor': 100000,
        'startingAmountMinor': 10000,
        'status': 'active',
        'fundingMethod': 'reserveFromAccount',
        'defaultFundingAccountId': 'checking',
        'sync': SyncMetadata.fresh(now: DateTime.utc(2026, 7, 1)).toJson(),
      });
      final contribution = GoalContributionRecord.fromJson({
        'id': 'legacy-contribution',
        'goalId': goal.id,
        'amountMinor': 15000,
        'date': DateTime(2026, 7, 10).toIso8601String(),
        'sourceAccountId': 'checking',
        'fundingMethod': 'reserveFromAccount',
        'sync': SyncMetadata.fresh(now: DateTime.utc(2026, 7, 10)).toJson(),
      });

      expect(goal.fundingMethod, GoalFundingMethod.accountFunded);
      expect(goal.requiresFundingMigration, isTrue);
      expect(contribution.isLegacyReservation, isTrue);
    });

    test(
      'guided account migration preserves the legacy account and Goal value',
      () async {
        final legacyGoal = GoalRecord.fromJson({
          'id': 'legacy-goal',
          'name': 'Legacy Goal',
          'targetAmountMinor': 100000,
          'startingAmountMinor': 10000,
          'status': 'active',
          'fundingMethod': 'reserveFromAccount',
          'defaultFundingAccountId': 'checking',
          'sync': SyncMetadata.fresh(now: DateTime.utc(2026, 7, 1)).toJson(),
        });
        final legacyContribution = GoalContributionRecord.fromJson({
          'id': 'legacy-contribution',
          'goalId': legacyGoal.id,
          'amountMinor': 15000,
          'date': DateTime(2026, 7, 10).toIso8601String(),
          'sourceAccountId': 'checking',
          'fundingMethod': 'reserveFromAccount',
          'sync': SyncMetadata.fresh(now: DateTime.utc(2026, 7, 10)).toJson(),
        });
        final store = FinanceDataStore(
          dataSet: _dataSet().copyWith(
            goals: [legacyGoal],
            goalContributions: [legacyContribution],
          ),
        );

        expect(store.balanceForAccount('checking'), 250000);
        expect(store.currentGoalAmountMinor(legacyGoal.id), 25000);
        await store.migrateLegacyGoalToAccountFunding(legacyGoal.id);

        expect(store.goalById(legacyGoal.id).requiresFundingMigration, isFalse);
        expect(store.currentGoalAmountMinor(legacyGoal.id), 25000);
        expect(store.balanceForAccount('checking'), 250000);
        expect(store.netWorthMinor, 275000);
        expect(store.goalFundingEvents, hasLength(1));
        expect(
          store.goalContributionById(legacyContribution.id).isDeleted,
          isTrue,
        );

        await store.migrateLegacyGoalToAccountFunding(legacyGoal.id);
        expect(store.balanceForAccount('checking'), 250000);
        expect(store.goalFundingEvents, hasLength(1));
      },
    );

    test(
      'guided tracking migration preserves progress without account impact',
      () async {
        final legacyGoal = GoalRecord.fromJson({
          'id': 'legacy-goal',
          'name': 'Legacy Goal',
          'targetAmountMinor': 100000,
          'startingAmountMinor': 10000,
          'status': 'active',
          'fundingMethod': 'reserveFromAccount',
          'defaultFundingAccountId': 'checking',
          'sync': SyncMetadata.fresh(now: DateTime.utc(2026, 7, 1)).toJson(),
        });
        final legacyContribution = GoalContributionRecord.fromJson({
          'id': 'legacy-contribution',
          'goalId': legacyGoal.id,
          'amountMinor': 15000,
          'date': DateTime(2026, 7, 10).toIso8601String(),
          'sourceAccountId': 'checking',
          'fundingMethod': 'reserveFromAccount',
          'sync': SyncMetadata.fresh(now: DateTime.utc(2026, 7, 10)).toJson(),
        });
        final store = FinanceDataStore(
          dataSet: _dataSet().copyWith(
            goals: [legacyGoal],
            goalContributions: [legacyContribution],
          ),
        );

        await store.migrateLegacyGoalToTrackingOnly(legacyGoal.id);

        expect(
          store.goalById(legacyGoal.id).fundingMethod,
          GoalFundingMethod.trackingOnly,
        );
        expect(store.goalById(legacyGoal.id).requiresFundingMigration, isFalse);
        expect(store.currentGoalAmountMinor(legacyGoal.id), 25000);
        expect(store.balanceForAccount('checking'), 250000);
        expect(store.goalFundingEvents, isEmpty);
      },
    );
  });

  group('Goal persistence', () {
    test('older Goal JSON defaults to Reach a Target', () {
      final decoded = GoalRecord.fromJson({
        'id': 'legacy-type-goal',
        'name': 'Existing Goal',
        'targetAmountMinor': 100000,
        'status': 'completed',
        'fundingMethod': 'trackingOnly',
        'sync': SyncMetadata.fresh(now: DateTime.utc(2026, 7, 1)).toJson(),
      });

      expect(decoded.goalType, GoalType.reachTarget);
      expect(decoded.status, GoalStatus.completed);
      expect(decoded.isCompleted, isTrue);
    });

    test('Goal type survives JSON and local restart', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = LocalFinanceDataSetRepository(
        storageKey: 'goal_type_restart_test',
      );
      final store = _store(localRepository: repository);
      final goal = await store.createGoal(
        name: 'Repair Reserve',
        goalType: GoalType.maintainBalance,
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: DateTime(2027, 7, 24),
        fundingMethod: GoalFundingMethod.accountFunded,
        defaultFundingAccountId: 'checking',
      );

      final restored = await FinanceDataStore.load(localRepository: repository);

      expect(restored.goalById(goal.id).goalType, GoalType.maintainBalance);
      expect(
        FinanceDataSet.fromJson(
          restored.dataSet.toJson(),
        ).goals.single.goalType,
        GoalType.maintainBalance,
      );
    });

    test(
      'funding event and its account effect survive local restart',
      () async {
        SharedPreferences.setMockInitialValues({});
        const repository = LocalFinanceDataSetRepository(
          storageKey: 'goal_funding_restart_test',
        );
        final store = _store(localRepository: repository);
        final goal = await store.createGoal(
          name: 'Funded Goal',
          targetAmountMinor: 100000,
          startingAmountMinor: 0,
          targetDate: null,
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
        );
        final event = await store.fundGoals(
          sourceAccountId: 'checking',
          totalAmountMinor: 40000,
          date: DateTime(2026, 7, 24),
          allocations: [_allocation(goal.id, 40000)],
        );

        final restored = await FinanceDataStore.load(
          localRepository: repository,
        );

        expect(restored.goalFundingEventById(event.id).isActive, isTrue);
        expect(restored.currentGoalAmountMinor(goal.id), 40000);
        expect(restored.balanceForAccount('checking'), 250000);
        expect(restored.reservedForAccount('checking'), 40000);
        expect(restored.availableToSpendForAccount('checking'), 210000);
        expect(restored.netWorthMinor, 250000);
      },
    );

    test(
      'Goals and ordinary funding transfers survive local restart',
      () async {
        SharedPreferences.setMockInitialValues({});
        const repository = LocalFinanceDataSetRepository(
          storageKey: 'goal_restart_test',
        );
        final store = _store(localRepository: repository);
        final goal = await store.createGoal(
          name: 'Restart Goal',
          targetAmountMinor: 100000,
          startingAmountMinor: 0,
          targetDate: null,
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
        );
        final funding = await store.fundGoals(
          sourceAccountId: 'checking',
          totalAmountMinor: 10000,
          allocations: [_allocation(goal.id, 10000)],
          date: DateTime(2026, 7, 24),
          note: 'Persist me',
        );

        final restored = await FinanceDataStore.load(
          localRepository: repository,
        );

        expect(restored.goalById(goal.id).name, 'Restart Goal');
        expect(restored.goalFundingEventById(funding.id).note, 'Persist me');
        expect(restored.currentGoalAmountMinor(goal.id), 10000);
      },
    );

    test('undone Goal funding tombstone survives restart', () async {
      SharedPreferences.setMockInitialValues({});
      const repository = LocalFinanceDataSetRepository(
        storageKey: 'goal_undo_restart_test',
      );
      final store = _store(localRepository: repository);
      final goal = await store.createGoal(
        name: 'Undo Goal',
        targetAmountMinor: 100000,
        startingAmountMinor: 0,
        targetDate: null,
        fundingMethod: GoalFundingMethod.accountFunded,
        defaultFundingAccountId: 'checking',
      );
      final funding = await store.fundGoals(
        sourceAccountId: 'checking',
        totalAmountMinor: 10000,
        allocations: [_allocation(goal.id, 10000)],
        date: DateTime(2026, 7, 24),
      );
      await store.undoGoalFunding(funding.id);

      final restored = await FinanceDataStore.load(localRepository: repository);

      expect(restored.goalFundingEventById(funding.id).isDeleted, isTrue);
      expect(restored.currentGoalAmountMinor(goal.id), 0);
    });

    test('JSON round trip preserves Goal sync and contribution linkage', () {
      final goal = _goal();
      final contribution = _contribution(goalId: goal.id);
      final encoded = _dataSet().copyWith(
        goals: [goal],
        goalContributions: [contribution],
      );

      final decoded = FinanceDataSet.fromJson(encoded.toJson());

      expect(decoded.goals.single.toJson(), goal.toJson());
      expect(decoded.goalContributions.single.toJson(), contribution.toJson());
    });

    test('sync merge keeps contribution tombstones and newer Goal edits', () {
      final activeContribution = _contribution(goalId: 'goal-1');
      final tombstone = activeContribution.copyWith(
        sync: activeContribution.sync.deleted(
          now: DateTime.utc(2026, 7, 20),
          deviceId: 'phone',
        ),
      );
      final oldGoal = _goal(createdAt: DateTime.utc(2026, 7, 1));
      final remoteGoal = oldGoal.copyWith(
        name: 'Edited on another device',
        sync: oldGoal.sync.touched(
          now: DateTime.utc(2026, 7, 22),
          deviceId: 'tablet',
        ),
      );
      final current = _dataSet().copyWith(
        goals: [oldGoal],
        goalContributions: [tombstone],
      );
      final incoming = _dataSet().copyWith(
        goals: [remoteGoal],
        goalContributions: [activeContribution],
      );

      final merged = mergeFinanceDataSetsPreferCurrent(
        incoming: incoming,
        current: current,
      );

      expect(merged.goals.single.name, 'Edited on another device');
      expect(merged.goalContributions.single.isDeleted, isTrue);
    });

    test('sync merge keeps a Goal funding tombstone', () {
      final event = GoalFundingEventRecord(
        id: 'funding',
        sourceAccountId: 'checking',
        totalAmountMinor: 10000,
        date: DateTime(2026, 7, 24),
        allocations: [_allocation('goal-1', 10000)],
        sync: SyncMetadata.fresh(
          now: DateTime.utc(2026, 7, 24),
          deviceId: 'tablet',
        ),
      );
      final tombstone = event.copyWith(
        sync: event.sync.deleted(
          now: DateTime.utc(2026, 7, 25),
          deviceId: 'phone',
        ),
      );

      final merged = mergeFinanceDataSetsPreferCurrent(
        incoming: _dataSet().copyWith(goalFundingEvents: [event]),
        current: _dataSet().copyWith(goalFundingEvents: [tombstone]),
      );

      expect(merged.goalFundingEvents.single.isDeleted, isTrue);
    });
  });
}

FinanceDataStore _store({
  int openingBalanceMinor = 250000,
  LocalFinanceDataSetRepository? localRepository,
}) {
  return FinanceDataStore(
    dataSet: _dataSet(openingBalanceMinor: openingBalanceMinor),
    localRepository: localRepository,
    deviceId: 'test-device',
  );
}

FinanceDataSet _dataSet({int openingBalanceMinor = 250000}) {
  return FinanceDataSet(
    accounts: [
      AccountRecord(
        id: 'checking',
        name: 'Checking',
        type: AccountType.checking,
        openingBalanceMinor: openingBalanceMinor,
        sync: SyncMetadata.fresh(now: DateTime.utc(2026, 7, 1)),
      ),
    ],
    categories: const [],
    transactions: const [],
    scheduledTransactions: const [],
    budgets: const [],
    preferences: const UserPreferences(),
  );
}

GoalRecord _goal({
  String id = 'goal-1',
  int targetAmountMinor = 100000,
  int startingAmountMinor = 0,
  DateTime? targetDate,
  DateTime? createdAt,
  GoalType goalType = GoalType.reachTarget,
}) {
  return GoalRecord(
    id: id,
    name: 'Test Goal',
    targetAmountMinor: targetAmountMinor,
    startingAmountMinor: startingAmountMinor,
    targetDate: targetDate,
    status: GoalStatus.active,
    fundingMethod: GoalFundingMethod.trackingOnly,
    goalType: goalType,
    sync: SyncMetadata.fresh(
      now: createdAt ?? DateTime.utc(2026, 7, 1),
      deviceId: 'test-device',
    ),
  );
}

GoalContributionRecord _contribution({
  String id = 'contribution-1',
  required String goalId,
  int amountMinor = 10000,
  DateTime? date,
}) {
  return GoalContributionRecord(
    id: id,
    goalId: goalId,
    amountMinor: amountMinor,
    date: date ?? DateTime(2026, 7, 10),
    fundingMethod: GoalFundingMethod.trackingOnly,
    sync: SyncMetadata.fresh(
      now: DateTime.utc(2026, 7, 10),
      deviceId: 'test-device',
    ),
  );
}

GoalFundingAllocation _allocation(
  String goalId,
  int amountMinor, {
  int order = 0,
}) {
  return GoalFundingAllocation(
    id: 'allocation-$goalId-$order',
    fundingEventId: '',
    goalId: goalId,
    amountMinor: amountMinor,
    order: order,
  );
}
