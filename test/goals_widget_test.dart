import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/account.dart' as v2_account;
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/goals/goal_calculator.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('Goal status copy expresses pace, achievement, and replenishment', () {
    const currency = CurrencyFormatSettings();
    final dated = _goal(
      id: 'dated-labels',
      name: 'Dated Labels',
      targetDate: DateTime(2027, 8, 23),
    );
    GoalProgressMetrics metrics({
      required GoalProgressStatus status,
      required int current,
      required int remaining,
      required int difference,
    }) => GoalProgressMetrics(
      currentAmountMinor: current,
      remainingAmountMinor: remaining,
      percentageComplete: current / dated.targetAmountMinor,
      expectedAmountMinor: current - difference,
      aheadBehindMinor: difference,
      requiredWeeklyMinor: 0,
      requiredMonthlyMinor: 0,
      status: status,
    );

    expect(
      goalCurrentStateLabel(
        dated,
        metrics(
          status: GoalProgressStatus.onTrack,
          current: 50000,
          remaining: 50000,
          difference: 0,
        ),
        currency,
      ),
      'On track',
    );
    expect(
      goalCurrentStateLabel(
        dated,
        metrics(
          status: GoalProgressStatus.ahead,
          current: 60000,
          remaining: 40000,
          difference: 10000,
        ),
        currency,
      ),
      r'Ahead by $100.00',
    );
    expect(
      goalCurrentStateLabel(
        dated,
        metrics(
          status: GoalProgressStatus.behind,
          current: 40000,
          remaining: 60000,
          difference: -10000,
        ),
        currency,
      ),
      r'Behind by $100.00',
    );

    final achieved = dated.copyWith(status: GoalStatus.completed);
    expect(
      goalCurrentStateLabel(
        achieved,
        metrics(
          status: GoalProgressStatus.completed,
          current: 100000,
          remaining: 0,
          difference: 0,
        ),
        currency,
      ),
      'Achieved',
    );

    final maintain = _goal(
      id: 'maintain-labels',
      name: 'Maintain Labels',
      goalType: GoalType.maintainBalance,
    );
    expect(
      goalCurrentStateLabel(
        maintain,
        metrics(
          status: GoalProgressStatus.replenishing,
          current: 0,
          remaining: 100000,
          difference: -100000,
        ),
        currency,
      ),
      r'$1,000.00 needed to replenish',
    );
  });

  testWidgets(
    'Dashboard Goal preview shows an empty state and opens creation',
    (tester) async {
      await _setPhoneSize(tester);
      final store = _store();
      await tester.pumpWidget(_testApp(store, const GoalsPreviewCard()));

      expect(find.text('No goals yet'), findsOneWidget);
      expect(
        find.text('Create a goal to start tracking your progress.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('dashboard-create-goal')));
      await tester.pumpAndSettle();

      expect(find.text('Create Goal'), findsWidgets);
      expect(find.byKey(const ValueKey('goal-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('goal-save')), findsOneWidget);
    },
  );

  testWidgets('Create Goal validates and persists an unfunded Goal', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showCreateGoalSheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('goal-save')),
    );
    expect(save.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('goal-name')),
      'Emergency Fund',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-amount')),
      '100000',
    );
    await _selectCheckingFundingAccount(tester);
    await tester.pump();

    final enabledSave = tester.widget<FilledButton>(
      find.byKey(const ValueKey('goal-save')),
    );
    expect(enabledSave.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();

    expect(store.goals, hasLength(1));
    expect(store.goals.single.name, 'Emergency Fund');
    expect(store.goals.single.fundingMethod, GoalFundingMethod.accountFunded);
    expect(store.goals.single.defaultFundingAccountId, 'checking');
    expect(store.goals.single.accountId, isNull);
    expect(store.reservedForAccount('checking'), 0);
    expect(store.goals.single.goalType, GoalType.reachTarget);
  });

  testWidgets('new Goals start at zero without a Starting Balance field', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showCreateGoalSheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Starting amount'), findsNothing);
    expect(find.byKey(const ValueKey('goal-starting-amount')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('goal-name')),
      'Emergency Fund',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-amount')),
      '50000',
    );
    await _selectCheckingFundingAccount(tester);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();

    final goal = store.goals.single;
    expect(goal.startingAmountMinor, 0);
    expect(store.currentGoalAmountMinor(goal.id), 0);
    expect(store.balanceForAccount('checking'), 250000);
    expect(store.reservedForAccount('checking'), 0);
  });

  testWidgets(
    'active Goal long press exposes actions and can delete directly',
    (tester) async {
      await _setPhoneSize(tester);
      final store = _store();
      final goal = await store.createGoal(
        name: 'Temporary Goal',
        targetAmountMinor: 50000,
        startingAmountMinor: 0,
        targetDate: null,
        defaultFundingAccountId: 'checking',
      );
      await tester.pumpWidget(_testApp(store, GoalCard(goal: goal)));

      await tester.longPress(find.byKey(ValueKey('goal-card-${goal.id}')));
      await tester.pumpAndSettle();
      expect(find.text('View Activity'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Delete'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this Goal permanently?'), findsOneWidget);
      await tester.tap(find.text('Delete Permanently'));
      await tester.pumpAndSettle();
      expect(store.goalById(goal.id).isDeleted, isTrue);
    },
  );

  testWidgets('Goal Actions schedules funding with the current Goal selected', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Emergency Fund',
      targetAmountMinor: 50000,
      startingAmountMinor: 0,
      targetDate: null,
      defaultFundingAccountId: 'checking',
    );
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showGoalActionsSheet(context, goal.id),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule Funding'), findsOneWidget);

    await tester.tap(find.text('Schedule Funding'));
    await tester.pumpAndSettle();

    expect(find.text('Create Scheduled Goal Funding'), findsOneWidget);
    expect(find.text('Emergency Fund'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('scheduled-goal-funding-total')),
      '10000',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scheduled-goal-funding-save')));
    await tester.pumpAndSettle();

    expect(store.scheduledTransactions, hasLength(1));
    final schedule = store.scheduledTransactions.single;
    expect(schedule.type, TransactionType.goalFunding);
    expect(schedule.goalFundingAllocations.single.goalId, goal.id);
    expect(schedule.accountId, 'checking');
  });

  testWidgets('active Goal delete explains a remaining-balance block', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Funded Goal',
      targetAmountMinor: 50000,
      startingAmountMinor: 0,
      targetDate: null,
      defaultFundingAccountId: 'checking',
    );
    await store.fundGoals(
      sourceAccountId: 'checking',
      totalAmountMinor: 10000,
      date: DateTime(2026, 8, 1),
      allocations: [
        GoalFundingAllocation(
          id: 'funded-goal-allocation',
          fundingEventId: '',
          goalId: goal.id,
          amountMinor: 10000,
          order: 0,
        ),
      ],
    );
    await tester.pumpWidget(_testApp(store, GoalCard(goal: goal)));

    await tester.longPress(find.byKey(ValueKey('goal-card-${goal.id}')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delete'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Goal can’t be deleted yet'), findsOneWidget);
    expect(
      find.text('Withdraw the remaining \$100.00 before deleting this Goal.'),
      findsOneWidget,
    );
  });

  testWidgets('Goal allocation amount keeps fifty thousand dollars visible', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Emergency Fund',
      targetAmountMinor: 10000000,
      startingAmountMinor: 0,
      targetDate: null,
      defaultFundingAccountId: 'checking',
    );
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showFundGoalsSheet(context, initialGoalId: goal.id),
            child: const Text('Open funding'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open funding'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('fund-goals-total')),
      '5000000',
    );
    await tester.pump();

    final amountField = find.byKey(
      const ValueKey('fund-goals-amount-goal-allocation-draft-0'),
    );
    expect(tester.getSize(amountField).width, greaterThanOrEqualTo(165));
    expect(
      tester.widget<TextField>(amountField).controller!.text,
      r'$50,000.00',
    );
  });

  testWidgets('Create Goal selects Maintain a Balance and updates date label', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showCreateGoalSheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Reach a Target'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('goal-type')));
    await tester.tap(find.byKey(const ValueKey('goal-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maintain a Balance').last);
    await tester.pumpAndSettle();

    expect(find.text('Replenish by date'), findsOneWidget);
    expect(find.text('No replenishment deadline'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('goal-name')),
      'Truck Maintenance',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-amount')),
      '100000',
    );
    await _selectCheckingFundingAccount(tester);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();

    expect(store.goals.single.goalType, GoalType.maintainBalance);
    expect(store.goals.single.isActive, isTrue);
  });

  testWidgets('changing a funded Goal type requires confirmation', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final goal = _goal(
      id: 'convert-type',
      name: 'Convertible',
      fundingMethod: GoalFundingMethod.trackingOnly,
    );
    final contribution = GoalContributionRecord(
      id: 'progress',
      goalId: goal.id,
      amountMinor: 10000,
      date: DateTime(2026, 7, 24),
      fundingMethod: GoalFundingMethod.trackingOnly,
      sync: v2_sync.SyncMetadata.fresh(now: DateTime.utc(2026, 7, 24)),
    );
    final store = _store(goals: [goal], contributions: [contribution]);
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showGoalEditor(context, initialGoal: goal),
            child: const Text('Edit'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('goal-type')));
    await tester.tap(find.byKey(const ValueKey('goal-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maintain a Balance').last);
    await tester.pumpAndSettle();

    expect(find.text('Change Goal type?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Reach a Target'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('goal-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maintain a Balance').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();

    expect(store.goalById(goal.id).goalType, GoalType.maintainBalance);
    expect(store.goalContributions.single.id, contribution.id);
    expect(store.currentGoalAmountMinor(goal.id), 10000);
    expect(store.balanceForAccount('checking'), 250000);
  });

  testWidgets('Dashboard previews at most two urgent active Goals', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store(
      goals: [
        _goal(id: 'urgent', name: 'Urgent', targetDate: DateTime(2026, 8, 1)),
        _goal(id: 'second', name: 'Second', targetDate: DateTime(2026, 9, 1)),
        _goal(id: 'later', name: 'Later', targetDate: DateTime(2027, 1, 1)),
      ],
    );
    await tester.pumpWidget(_testApp(store, const GoalsPreviewCard()));

    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
    expect(
      find.byKey(const ValueKey('dashboard-view-all-goals')),
      findsOneWidget,
    );
  });

  testWidgets('Goals page keeps achieved Goals main and archives separate', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store(
      goals: [
        _goal(id: 'active', name: 'Active'),
        _goal(id: 'done', name: 'Done', status: GoalStatus.completed),
        _goal(id: 'old', name: 'Old', status: GoalStatus.archived),
      ],
    );
    await tester.pumpWidget(_testApp(store, const GoalsPage()));

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Archived Goals (1)'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Old'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('view-archived-goals')));
    await tester.pumpAndSettle();

    expect(find.text('Archived Goals'), findsOneWidget);
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    expect(find.text('Old'), findsOneWidget);
  });

  testWidgets('Maintain a Balance stays current and shows Target met', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Truck Maintenance',
      goalType: GoalType.maintainBalance,
      startingAmountMinor: 100000,
      targetAmountMinor: 100000,
      targetDate: DateTime(2027, 6, 20),
      defaultFundingAccountId: 'checking',
    );
    await tester.pumpWidget(_testApp(store, const GoalsPage()));

    expect(find.text('Truck Maintenance'), findsOneWidget);
    expect(find.text('Target met'), findsOneWidget);
    expect(find.text('100% funded'), findsOneWidget);
    expect(find.text('Completed (1)'), findsNothing);

    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showGoalDetails(context, goal.id),
            child: const Text('Open details'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    expect(find.text('Goal Details'), findsOneWidget);
    expect(find.text('Maintain a Balance'), findsOneWidget);
    expect(find.text('Replenish by date'), findsOneWidget);
    expect(find.text('Mark Complete'), findsNothing);
    expect(find.text('Goal Actions'), findsNothing);
  });

  testWidgets('Goal card and details share Reach Target status semantics', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final dated = await store.createGoal(
      name: 'Dated Empty',
      targetAmountMinor: 100000,
      startingAmountMinor: 0,
      targetDate: DateTime(2027, 8, 23),
      defaultFundingAccountId: 'checking',
    );
    await tester.pumpWidget(_testApp(store, GoalCard(goal: dated)));

    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('On track'), findsNothing);

    await tester.tap(find.byKey(ValueKey('goal-card-${dated.id}')));
    await tester.pumpAndSettle();
    expect(find.text('View Activity'), findsOneWidget);
    expect(find.text('Goal Details'), findsNothing);
    await tester.tap(find.text('View Activity'));
    await tester.pumpAndSettle();

    expect(find.text('Goal Details'), findsOneWidget);
    expect(find.text('Not started'), findsWidgets);
    expect(find.text('On track'), findsNothing);
  });

  testWidgets('undated funded Goal uses remaining language everywhere', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Undated Funded',
      targetAmountMinor: 100000,
      startingAmountMinor: 0,
      targetDate: null,
      defaultFundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.goal,
      containerId: goal.id,
      amountMinor: 25000,
      date: DateTime(2026, 8, 23),
    );
    await tester.pumpWidget(_testApp(store, GoalCard(goal: goal)));

    expect(find.text(r'$750.00 remaining'), findsOneWidget);
    expect(find.text('On track'), findsNothing);
    expect(find.textContaining('Ahead'), findsNothing);
    expect(find.textContaining('Behind'), findsNothing);

    await tester.tap(find.byKey(ValueKey('goal-card-${goal.id}')));
    await tester.pumpAndSettle();
    expect(find.text('View Activity'), findsOneWidget);
    await tester.tap(find.text('View Activity'));
    await tester.pumpAndSettle();

    expect(find.text('Goal Details'), findsOneWidget);
    expect(find.text(r'$750.00 remaining'), findsWidgets);
    expect(find.text('On track'), findsNothing);
    expect(find.textContaining('Ahead'), findsNothing);
    expect(find.textContaining('Behind'), findsNothing);
  });

  testWidgets(
    'Achieved Goal stays current with spend return and Activity available',
    (tester) async {
      await _setPhoneSize(tester);
      final store = _store();
      final goal = await store.createGoal(
        name: 'Vacation',
        targetAmountMinor: 50000,
        startingAmountMinor: 0,
        targetDate: null,
        defaultFundingAccountId: 'checking',
      );
      await store.allocateReservation(
        containerType: ReservationContainerType.goal,
        containerId: goal.id,
        amountMinor: 50000,
        date: DateTime(2026, 8, 23),
      );

      await tester.pumpWidget(_testApp(store, const GoalsPage()));
      expect(find.text('Vacation'), findsOneWidget);
      expect(find.textContaining('Achieved'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('goal-card-${goal.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Goal Actions'), findsNothing);
      expect(find.text('Spend from Goal'), findsOneWidget);
      expect(find.text('Return Reserved Money'), findsOneWidget);
      expect(find.text('View Activity'), findsOneWidget);
      expect(find.text('Restore as Active'), findsNothing);

      await tester.tap(find.text('View Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Goal Details'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.textContaining('Allocated'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            'goal-reservation-activity-${store.reservationOperations.single.id}',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('Add Contribution updates Goal and can be undone by exact ID', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final goal = _goal(
      id: 'tracking-goal',
      name: 'Tracking Goal',
      fundingMethod: GoalFundingMethod.trackingOnly,
    );
    final store = _store(goals: [goal]);
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showAddGoalContributionSheet(context, goal.id),
            child: const Text('Contribute'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Contribute'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('goal-contribution-amount')),
      '25000',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('goal-contribution-save')));
    await tester.pumpAndSettle();

    expect(store.currentGoalAmountMinor(goal.id), 25000);
    final contribution = store.goalContributions.single;

    await tester.pumpWidget(
      _testApp(
        store,
        GoalContributionRow(contribution: contribution, onTap: () {}),
      ),
    );
    final context = tester.element(find.byType(GoalContributionRow));
    showGoalContributionDetails(context, contribution.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('undo-goal-contribution')));
    await tester.pumpAndSettle();
    expect(find.text('Undo Goal progress?'), findsOneWidget);
    await tester.tap(find.text('Undo Progress').last);
    await tester.pumpAndSettle();

    expect(store.currentGoalAmountMinor(goal.id), 0);
    expect(store.goalContributionById(contribution.id).isDeleted, isTrue);
  });

  testWidgets('Goal Actions Allocate opens the dedicated funding sheet', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Emergency Fund',
      startingAmountMinor: 0,
      defaultFundingAccountId: 'checking',
      targetAmountMinor: 1000000,
      targetDate: null,
    );
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showAddGoalContributionSheet(context, goal.id),
            child: const Text('Contribute'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Contribute'));
    await tester.pumpAndSettle();

    expect(find.text('View Activity'), findsOneWidget);
    await tester.tap(find.text('Allocate'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Fund Goals'), findsWidgets);
    expect(find.text('Emergency Fund'), findsOneWidget);
    expect(find.text('From Account'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Goal Allocations'), findsOneWidget);
  });

  testWidgets('Fund Goals saves once and whole-event undo restores account', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Emergency Fund',
      startingAmountMinor: 0,
      defaultFundingAccountId: 'checking',
      targetAmountMinor: 1000000,
      targetDate: null,
    );
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showFundGoalsSheet(context, initialGoalId: goal.id),
            child: const Text('Open Funding'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Funding'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('fund-goals-total')),
      '50000',
    );
    await tester.pump();
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('fund-goals-save')),
    );
    expect(save.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('fund-goals-save')));
    await tester.pumpAndSettle();

    expect(store.goalFundingEvents, hasLength(1));
    expect(store.currentGoalAmountMinor(goal.id), 50000);
    expect(store.balanceForAccount('checking'), 250000);
    expect(store.reservedForAccount('checking'), 50000);
    expect(store.availableToSpendForAccount('checking'), 200000);
    expect(store.netWorthMinor, 250000);
    final event = store.goalFundingEvents.single;

    final context = tester.element(find.text('Open Funding'));
    showGoalFundingDetails(context, event.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('undo-goal-funding')));
    await tester.pumpAndSettle();
    expect(find.text('Undo goal funding?'), findsOneWidget);
    await tester.tap(find.text('Undo Funding').last);
    await tester.pumpAndSettle();

    expect(store.goalFundingEventById(event.id).isDeleted, isTrue);
    expect(store.currentGoalAmountMinor(goal.id), 0);
    expect(store.balanceForAccount('checking'), 250000);
    expect(store.reservedForAccount('checking'), 0);
    expect(store.availableToSpendForAccount('checking'), 250000);
    expect(store.netWorthMinor, 250000);
  });

  testWidgets(
    'exact-available Goal allocation stays valid while persistence is pending',
    (tester) async {
      await _setPhoneSize(tester);
      final repository = _BlockingLocalFinanceRepository();
      final store = _store(localRepository: repository);
      final goal = await store.createGoal(
        name: 'Emergency Fund',
        startingAmountMinor: 0,
        defaultFundingAccountId: 'checking',
        targetAmountMinor: 250000,
        targetDate: null,
      );
      await tester.pumpWidget(
        _testApp(
          store,
          Builder(
            builder: (context) => FilledButton(
              onPressed: () =>
                  showFundGoalsSheet(context, initialGoalId: goal.id),
              child: const Text('Open Funding'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Funding'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fund-goals-total')),
        '250000',
      );
      await tester.pump();
      expect(find.text('After allocation · \$0.00 available'), findsOneWidget);
      expect(
        find.text('Funding exceeds the selected account balance.'),
        findsNothing,
      );

      repository.blockNextSave();
      await tester.tap(find.byKey(const ValueKey('fund-goals-save')));
      await tester.pump();

      expect(find.text('Fund Goals'), findsWidgets);
      expect(find.text('After allocation · \$0.00 available'), findsOneWidget);
      expect(
        find.text('Funding exceeds the selected account balance.'),
        findsNothing,
      );

      repository.releaseSave();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fund-goals-total')), findsNothing);
      expect(store.currentGoalAmountMinor(goal.id), 250000);
    },
  );

  testWidgets('tracking-only Add Contribution omits the account section', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final goal = _goal(id: 'tracking', name: 'Outside Savings');
    final store = _store(goals: [goal]);
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showAddGoalContributionSheet(context, goal.id),
            child: const Text('Contribute'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Contribute'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Source account'), findsNothing);
    expect(
      find.byKey(const ValueKey('goal-contribution-account')),
      findsNothing,
    );
  });

  testWidgets('Ledger shows one blue activity for a multi-Goal funding event', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final first = _goal(
      id: 'goal-a',
      name: 'Emergency',
      fundingMethod: GoalFundingMethod.accountFunded,
      defaultFundingAccountId: 'checking',
    );
    final second = _goal(
      id: 'goal-b',
      name: 'Vacation',
      fundingMethod: GoalFundingMethod.accountFunded,
      defaultFundingAccountId: 'checking',
    );
    final event = _fundingEvent(
      allocations: [
        _fundingAllocation('goal-a', 30000),
        _fundingAllocation('goal-b', 20000, order: 1),
      ],
    );
    final store = _store(goals: [first, second], fundingEvents: [event]);
    await tester.pumpWidget(_testApp(store, const LedgerView()));

    expect(find.text('Funded Goals'), findsOneWidget);
    expect(find.text('Checking • 2 Goals'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GoalFundingLedgerRow),
        matching: find.text(r'-$500.00'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Funded Goals'));
    await tester.pumpAndSettle();

    expect(find.text('Goal Funding Details'), findsOneWidget);
    expect(find.text('Emergency'), findsOneWidget);
    expect(find.text('Vacation'), findsOneWidget);
  });

  testWidgets(
    'Goal card opens actions then Activity in the nested app navigator',
    (tester) async {
      await _setPhoneSize(tester);
      final store = _store();
      final goal = await store.createGoal(
        name: 'Emergency Fund',
        startingAmountMinor: 0,
        targetAmountMinor: 100000,
        targetDate: DateTime(2027, 8, 20),
        defaultFundingAccountId: 'checking',
      );
      await tester.pumpWidget(_testApp(store, GoalCard(goal: goal)));

      await tester.tap(find.byKey(ValueKey('goal-card-${goal.id}')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('View Activity'), findsOneWidget);
      expect(find.text('Goal Details'), findsNothing);
      await tester.tap(find.text('View Activity'));
      await tester.pumpAndSettle();

      expect(find.text('Goal Details'), findsOneWidget);
      expect(find.text('Emergency Fund'), findsWidgets);
      expect(find.text('Goal Actions'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Goal Details'), findsNothing);
    },
  );

  testWidgets(
    'ordinary Goal-account expense opens the standard transaction details',
    (tester) async {
      await _setPhoneSize(tester);
      final sync = v2_sync.SyncMetadata.fresh(now: DateTime(2026, 7, 30));
      final goal = _goal(
        id: 'goal-test',
        name: 'test',
        startingAmountMinor: 10000,
      ).copyWith(accountId: 'goal-account', accountMigrationVersion: 1);
      final store = FinanceDataStore(
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
              id: 'goal-account',
              name: 'test',
              type: v2_account.AccountType.savings,
              openingBalanceMinor: 10000,
              goalId: goal.id,
              includeInGroupBalance: false,
              sync: sync,
            ),
          ],
          categories: const [],
          transactions: [
            TransactionRecord(
              id: 'loves-expense',
              type: TransactionType.expense,
              accountId: 'goal-account',
              categoryId: 'maintenance',
              date: DateTime(2026, 7, 30),
              payee: "Love's",
              amountMinor: 10000,
              sync: sync,
            ),
          ],
          scheduledTransactions: const [],
          budgets: const [],
          goals: [goal],
          preferences: const UserPreferences(),
        ),
      );
      await tester.pumpWidget(
        _testApp(
          store,
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => showGoalDetails(context, goal.id),
              child: const Text('Open details'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Love's"));
      await tester.pumpAndSettle();

      expect(find.text('Transaction Details'), findsOneWidget);
      expect(find.text("Love's"), findsWidgets);

      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      await tester.longPress(find.text("Love's"));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets(
    'global Ledger routes a hidden Goal-account expense to standard details',
    (tester) async {
      await _setPhoneSize(tester);
      final sync = v2_sync.SyncMetadata.fresh(now: DateTime(2026, 7, 30));
      final goal = _goal(
        id: 'global-goal-test',
        name: 'test',
        startingAmountMinor: 10000,
      ).copyWith(accountId: 'global-goal-account', accountMigrationVersion: 1);
      final store = FinanceDataStore(
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
              id: 'global-goal-account',
              name: 'test',
              type: v2_account.AccountType.savings,
              openingBalanceMinor: 10000,
              goalId: goal.id,
              includeInGroupBalance: false,
              sync: sync,
            ),
          ],
          categories: const [],
          transactions: [
            TransactionRecord(
              id: 'global-loves-expense',
              type: TransactionType.expense,
              accountId: 'global-goal-account',
              categoryId: 'maintenance',
              date: DateTime(2026, 7, 30),
              payee: "Love's",
              amountMinor: 10000,
              sync: sync,
            ),
          ],
          scheduledTransactions: const [],
          budgets: const [],
          goals: [goal],
          preferences: const UserPreferences(),
        ),
      );
      await tester.pumpWidget(_testApp(store, const LedgerView()));

      await tester.tap(find.text("Love's"));
      await tester.pumpAndSettle();

      expect(find.text('Transaction Details'), findsOneWidget);
    },
  );

  test('negative Goal deletion guidance explains the required resolution', () {
    expect(
      goalDeletionBlockedMessage(
        const GoalDeleteEligibility(
          hasContributions: false,
          hasFunding: false,
          hasScheduledReference: false,
          hasNonZeroBalance: true,
          remainingBalanceMinor: -10000,
        ),
        const UserPreferences().currency,
      ),
      'This Goal is \$100.00 below zero. Resolve or delete the related transactions before deleting this Goal.',
    );
  });

  testWidgets('missing Goal lookup reports safely without opening a barrier', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    await tester.pumpWidget(
      _testApp(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showGoalDetails(context, 'missing'),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    final barrierCountBefore = find.byType(ModalBarrier).evaluate().length;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('This Goal is no longer available.'), findsOneWidget);
    expect(find.text('Goal Details'), findsNothing);
    expect(find.byType(ModalBarrier), findsNWidgets(barrierCountBefore));
  });

  testWidgets('Goal card separates percentage from large progress amounts', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final goal = _goal(
      id: 'large',
      name: 'Large Goal',
      startingAmountMinor: 500000000,
      targetAmountMinor: 10000000000,
    );
    final store = _store(goals: [goal]);

    await tester.pumpWidget(_testApp(store, GoalCard(goal: goal)));

    expect(find.text(r'$5,000,000.00 of $100,000,000.00'), findsOneWidget);
    expect(find.text('5% complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Goal calendar activity uses a blue accent and excludes tombstones',
    (tester) async {
      await _setPhoneSize(tester);
      final goal = _goal(id: 'calendar-goal', name: 'Vacation');
      final active = GoalContributionRecord(
        id: 'active-contribution',
        goalId: goal.id,
        amountMinor: 5000,
        date: DateTime(2026, 7, 24),
        fundingMethod: GoalFundingMethod.trackingOnly,
        sync: v2_sync.SyncMetadata.fresh(now: DateTime.utc(2026, 7, 24)),
      );
      final undone = GoalContributionRecord(
        id: 'undone-contribution',
        goalId: goal.id,
        amountMinor: 7000,
        date: DateTime(2026, 7, 24),
        fundingMethod: GoalFundingMethod.trackingOnly,
        sync: v2_sync.SyncMetadata.fresh(
          now: DateTime.utc(2026, 7, 24),
        ).deleted(now: DateTime.utc(2026, 7, 25)),
      );
      final activities = goalCalendarActivitiesForMonth(
        [goal],
        [active, undone],
        const [],
        DateTime(2026, 7),
      );

      expect(activities, hasLength(1));
      expect(activities.single.type, CalendarActivityType.goal);

      final store = _store(goals: [goal], contributions: [active, undone]);
      await tester.pumpWidget(
        _testApp(
          store,
          Column(
            children: [
              SizedBox(
                width: 70,
                child: ScheduledCalendarDayCell(
                  day: 24,
                  month: DateTime(2026, 7),
                  activitySummary: CalendarDayActivitySummary([
                    CalendarDayActivity.goal(activities.single),
                  ]),
                  activityFilter: CalendarActivityFilter.all,
                  currency: const UserPreferences().currency,
                  isSelected: false,
                  isToday: false,
                  onSelectDate: (_) {},
                ),
              ),
              GoalCalendarActivityRow(
                activity: activities.single,
                currency: const UserPreferences().currency,
              ),
            ],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('calendar-activity-dots')),
        findsOneWidget,
      );
      expect(find.text('Vacation'), findsOneWidget);
      expect(find.text(r'$50.00'), findsOneWidget);
      final amount = tester.widget<Text>(find.text(r'$50.00'));
      expect(amount.style?.color, const Color(0xFF367BF5));
    },
  );

  testWidgets('Scheduled page excludes Goal progress activity', (tester) async {
    await _setPhoneSize(tester);
    final today = DateTime.now();
    final goal = _goal(id: 'filtered-goal', name: 'Emergency Fund');
    final contribution = GoalContributionRecord(
      id: 'filtered-progress',
      goalId: goal.id,
      amountMinor: 2000000,
      date: today,
      fundingMethod: GoalFundingMethod.trackingOnly,
      sync: v2_sync.SyncMetadata.fresh(),
    );
    final store = _store(goals: [goal], contributions: [contribution]);

    await tester.pumpWidget(
      MoneyTallyApp(store: FinanceStore.seeded(), dataStore: store),
    );
    await tester.tap(find.text('Scheduled').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('calendar-activity-filter-picker')),
    );
    await tester.tap(
      find.byKey(const ValueKey('calendar-activity-filter-picker')),
    );
    await tester.pumpAndSettle();
    final goalsOption = find.byKey(const ValueKey('calendar-filter-goals'));
    await tester.ensureVisible(goalsOption);
    await tester.pumpAndSettle();
    await tester.tap(goalsOption);
    await tester.pumpAndSettle();

    expect(find.text('Emergency Fund'), findsNothing);
    expect(find.text(r'$20,000.00'), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-filter-empty-state')),
      findsOneWidget,
    );
  });
}

Future<void> _setPhoneSize(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _selectCheckingFundingAccount(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('goal-funding-account')),
  );
  await tester.tap(find.byKey(const ValueKey('goal-funding-account')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Checking').last);
  await tester.pumpAndSettle();
}

Widget _testApp(FinanceDataStore store, Widget child) {
  return MaterialApp(
    home: FinanceDataStoreScope(
      store: store,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: Scaffold(body: SafeArea(child: child)),
      ),
    ),
  );
}

FinanceDataStore _store({
  List<GoalRecord> goals = const [],
  List<GoalContributionRecord> contributions = const [],
  List<GoalFundingEventRecord> fundingEvents = const [],
  LocalFinanceDataSetRepository? localRepository,
}) {
  return FinanceDataStore(
    dataSet: FinanceDataSet(
      accounts: [
        v2_account.AccountRecord(
          id: 'checking',
          name: 'Checking',
          type: v2_account.AccountType.checking,
          openingBalanceMinor: 250000,
          sync: v2_sync.SyncMetadata.fresh(now: DateTime.utc(2026, 7, 1)),
        ),
      ],
      categories: const [],
      transactions: const [],
      scheduledTransactions: const [],
      budgets: const [],
      goals: goals,
      goalContributions: contributions,
      goalFundingEvents: fundingEvents,
      preferences: const UserPreferences(),
    ),
    localRepository: localRepository,
  );
}

class _BlockingLocalFinanceRepository extends LocalFinanceDataSetRepository {
  Completer<void>? _pendingSave;

  void blockNextSave() {
    expect(_pendingSave, isNull);
    _pendingSave = Completer<void>();
  }

  void releaseSave() {
    final pending = _pendingSave;
    expect(pending, isNotNull);
    _pendingSave = null;
    pending!.complete();
  }

  @override
  Future<void> save(FinanceDataSet dataSet) async {
    final pending = _pendingSave;
    if (pending != null) await pending.future;
  }
}

GoalRecord _goal({
  required String id,
  required String name,
  DateTime? targetDate,
  GoalStatus status = GoalStatus.active,
  GoalFundingMethod fundingMethod = GoalFundingMethod.trackingOnly,
  String? defaultFundingAccountId,
  int startingAmountMinor = 0,
  int targetAmountMinor = 100000,
  GoalType goalType = GoalType.reachTarget,
}) {
  return GoalRecord(
    id: id,
    name: name,
    targetAmountMinor: targetAmountMinor,
    startingAmountMinor: startingAmountMinor,
    targetDate: targetDate,
    status: status,
    fundingMethod: fundingMethod,
    goalType: goalType,
    defaultFundingAccountId: defaultFundingAccountId,
    sync: v2_sync.SyncMetadata.fresh(now: DateTime.utc(2026, 7, 1)),
  );
}

GoalFundingEventRecord _fundingEvent({
  List<GoalFundingAllocation> allocations = const [],
}) {
  return GoalFundingEventRecord(
    id: 'funding-event',
    sourceAccountId: 'checking',
    totalAmountMinor: allocations.fold(
      0,
      (total, allocation) => total + allocation.amountMinor,
    ),
    date: DateTime(2026, 7, 24),
    allocations: allocations,
    sync: v2_sync.SyncMetadata.fresh(now: DateTime.utc(2026, 7, 24)),
  );
}

GoalFundingAllocation _fundingAllocation(
  String goalId,
  int amountMinor, {
  int order = 0,
}) {
  return GoalFundingAllocation(
    id: 'allocation-$goalId',
    fundingEventId: 'funding-event',
    goalId: goalId,
    amountMinor: amountMinor,
    order: order,
  );
}
