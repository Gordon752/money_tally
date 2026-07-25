import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/account.dart' as v2_account;
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  testWidgets('Create Goal validates and persists a funded Goal', (
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
    expect(store.goals.single.goalType, GoalType.reachTarget);
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

    expect(find.text('Restore-by date'), findsOneWidget);
    expect(find.text('No restore-by date'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('goal-name')),
      'Truck Maintenance',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-amount')),
      '100000',
    );
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

  testWidgets('Goals page separates active, completed, and archived Goals', (
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
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.text('Done'), findsNothing);

    await tester.tap(find.text('Completed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsOneWidget);
  });

  testWidgets(
    'Maintain a Balance card stays active and details omit Mark Complete',
    (tester) async {
      await _setPhoneSize(tester);
      final goal = _goal(
        id: 'reserve',
        name: 'Truck Maintenance',
        goalType: GoalType.maintainBalance,
        startingAmountMinor: 100000,
        targetAmountMinor: 100000,
        targetDate: DateTime(2027, 6, 20),
      );
      final store = _store(goals: [goal]);
      await tester.pumpWidget(_testApp(store, const GoalsPage()));

      expect(find.text('Truck Maintenance'), findsOneWidget);
      expect(find.text('Fully funded'), findsOneWidget);
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
      expect(find.text('Restore-by date'), findsOneWidget);
      expect(find.text('Mark Complete'), findsNothing);
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

  testWidgets('account-funded Goal opens the dedicated Fund Goals sheet', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final goal = _goal(
      id: 'funded-goal',
      name: 'Emergency Fund',
      fundingMethod: GoalFundingMethod.accountFunded,
      defaultFundingAccountId: 'checking',
      targetAmountMinor: 1000000,
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
    final goal = _goal(
      id: 'funding-goal',
      name: 'Emergency Fund',
      fundingMethod: GoalFundingMethod.accountFunded,
      defaultFundingAccountId: 'checking',
      targetAmountMinor: 1000000,
    );
    final store = _store(goals: [goal]);
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
    expect(store.balanceForAccount('checking'), 200000);
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
    expect(store.netWorthMinor, 250000);
  });

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
    expect(find.text(r'-$500.00'), findsOneWidget);
    await tester.tap(find.text('Funded Goals'));
    await tester.pumpAndSettle();

    expect(find.text('Goal Funding Details'), findsOneWidget);
    expect(find.text('Emergency'), findsOneWidget);
    expect(find.text('Vacation'), findsOneWidget);
  });

  testWidgets(
    'Goal Details opens and closes in the nested app navigator without errors',
    (tester) async {
      await _setPhoneSize(tester);
      final goal = _goal(
        id: 'details',
        name: 'Emergency Fund',
        fundingMethod: GoalFundingMethod.accountFunded,
        defaultFundingAccountId: 'missing-account',
        targetDate: DateTime(2027, 8, 20),
      );
      final store = _store(goals: [goal]);
      await tester.pumpWidget(_testApp(store, GoalCard(goal: goal)));

      await tester.tap(find.byKey(const ValueKey('goal-card-details')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Goal Details'), findsOneWidget);
      expect(find.text('Move money from an account'), findsWidgets);
      expect(
        find.text('Based on the remaining amount and target date'),
        findsOneWidget,
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Goal Details'), findsNothing);
    },
  );

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
      find.byKey(const ValueKey('calendar-filter-goals')),
    );
    await tester.tap(find.byKey(const ValueKey('calendar-filter-goals')));
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
  );
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
