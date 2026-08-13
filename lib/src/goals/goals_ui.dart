part of '../../main.dart';

const _goalBlue = Color(0xFF367BF5);

Color goalStatusColor(GoalProgressStatus status) {
  return switch (status) {
    GoalProgressStatus.ahead ||
    GoalProgressStatus.onTrack ||
    GoalProgressStatus.aboveReserveTarget ||
    GoalProgressStatus.fullyFunded => AppColors.accent,
    GoalProgressStatus.behind ||
    GoalProgressStatus.slightlyBelowTarget ||
    GoalProgressStatus.replenishing => const Color(0xFFE58A27),
    GoalProgressStatus.seriouslyBehind ||
    GoalProgressStatus.needsAttention ||
    GoalProgressStatus.restoreOverdue => AppColors.danger,
    GoalProgressStatus.completed => _goalBlue,
    GoalProgressStatus.noTargetDate ||
    GoalProgressStatus.noRestoreDate ||
    GoalProgressStatus.archived => AppColors.muted,
  };
}

String goalTypeLabel(GoalType type) {
  return switch (type) {
    GoalType.reachTarget => 'Reach a Target',
    GoalType.maintainBalance => 'Maintain a Balance',
  };
}

String goalTypeBadgeLabel(GoalType type) {
  return switch (type) {
    GoalType.reachTarget => 'Target',
    GoalType.maintainBalance => 'Replenishing',
  };
}

String goalDateLabel(GoalRecord goal) {
  return goal.goalType == GoalType.maintainBalance
      ? 'Replenish by date'
      : 'Target date';
}

String goalFundingMethodLabel(GoalFundingMethod method) {
  return 'Goal account';
}

class GoalsPreviewCard extends StatelessWidget {
  const GoalsPreviewCard({this.onViewAll, this.onCreate, super.key});

  final VoidCallback? onViewAll;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final goals = [...store.activeGoals]
      ..sort((left, right) {
        final leftMetrics = store.goalMetrics(left.id);
        final rightMetrics = store.goalMetrics(right.id);
        final statusOrder = {
          GoalProgressStatus.seriouslyBehind: 0,
          GoalProgressStatus.restoreOverdue: 0,
          GoalProgressStatus.needsAttention: 0,
          GoalProgressStatus.behind: 1,
          GoalProgressStatus.replenishing: 1,
          GoalProgressStatus.slightlyBelowTarget: 1,
          GoalProgressStatus.onTrack: 2,
          GoalProgressStatus.fullyFunded: 2,
          GoalProgressStatus.ahead: 3,
          GoalProgressStatus.aboveReserveTarget: 3,
          GoalProgressStatus.noTargetDate: 4,
          GoalProgressStatus.noRestoreDate: 4,
          GoalProgressStatus.completed: 5,
          GoalProgressStatus.archived: 6,
        };
        final byStatus = statusOrder[leftMetrics.status]!.compareTo(
          statusOrder[rightMetrics.status]!,
        );
        if (byStatus != 0) return byStatus;
        final leftDate = left.targetDate ?? DateTime(9999);
        final rightDate = right.targetDate ?? DateTime(9999);
        return leftDate.compareTo(rightDate);
      });
    final preview = goals.take(2).toList(growable: false);
    return AppCard(
      title: 'Goals',
      padding: EdgeInsets.all(AppSpacing.sm),
      child: preview.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CompactEmptyRow(icon: AppIcon.goal, label: 'No goals yet'),
                Padding(
                  padding: const EdgeInsets.only(left: 32, top: AppSpacing.xxs),
                  child: Text(
                    'Create a goal to start tracking your progress.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: ValueKey('dashboard-create-goal'),
                    onPressed: onCreate ?? () => showCreateGoalSheet(context),
                    icon: Icon(AppIcon.add, size: AppIconSize.inline),
                    label: const Text('Create Goal'),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                for (var index = 0; index < preview.length; index++) ...[
                  GoalPreviewRow(goal: preview[index]),
                  if (index != preview.length - 1)
                    Divider(
                      height: 14,
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.24),
                    ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: ValueKey('dashboard-view-all-goals'),
                    onPressed: onViewAll ?? () => openGoalsPage(context),
                    iconAlignment: IconAlignment.end,
                    icon: Icon(AppIcon.arrowForward, size: AppIconSize.inline),
                    label: const Text('View All Goals'),
                  ),
                ),
              ],
            ),
    );
  }
}

class GoalPreviewRow extends StatelessWidget {
  const GoalPreviewRow({required this.goal, super.key});

  final GoalRecord goal;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final metrics = store.goalMetrics(goal.id);
    final statusColor = goalStatusColor(metrics.status);
    return Semantics(
      button: true,
      label:
          '${goal.name}, ${metrics.status.label}, ${money(metrics.currentAmountMinor, store.preferences.currency)} of ${money(goal.targetAmountMinor, store.preferences.currency)}',
      child: InkWell(
        key: ValueKey('dashboard-goal-${goal.id}'),
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: () => showGoalDetails(context, goal.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    metrics.status.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${money(metrics.currentAmountMinor, store.preferences.currency)} of ${money(goal.targetAmountMinor, store.preferences.currency)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFeatures: const [AppTextStyles.tabularFigures],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (goal.goalType == GoalType.maintainBalance &&
                  metrics.remainingAmountMinor > 0)
                Text(
                  '${money(metrics.remainingAmountMinor, store.preferences.currency)} needed to restore',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFeatures: const [AppTextStyles.tabularFigures],
                  ),
                ),
              GoalProgressBar(
                progress: metrics.percentageComplete,
                color: statusColor,
                semanticsLabel:
                    '${(metrics.percentageComplete * 100).clamp(0, 999).round()} percent complete',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openGoalsPage(BuildContext context) {
  HapticFeedback.selectionClick();
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (context) => const GoalsPage()));
}

Future<void> openInactiveGoalsPage(BuildContext context) {
  HapticFeedback.selectionClick();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const InactiveGoalsPage()),
  );
}

class InactiveGoalsPage extends StatelessWidget {
  const InactiveGoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final completed = store.goals.where((goal) => goal.isCompleted).toList()
      ..sort(
        (left, right) => (right.completedAt ?? right.updatedDate).compareTo(
          left.completedAt ?? left.updatedDate,
        ),
      );
    final archived = store.goals.where((goal) => goal.isArchived).toList()
      ..sort(
        (left, right) => (right.archivedAt ?? right.updatedDate).compareTo(
          left.archivedAt ?? left.updatedDate,
        ),
      );
    return Scaffold(
      appBar: AppBar(title: const Text('Inactive Goals')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (completed.isEmpty && archived.isEmpty)
              AppCard(
                child: Column(
                  children: [
                    TransactionFormIcon(AppIcon.archive),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No inactive Goals',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Completed and archived Goals will appear here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (completed.isNotEmpty) ...[
              _InactiveGoalSection(title: 'Completed', goals: completed),
              if (archived.isNotEmpty) const SizedBox(height: AppSpacing.md),
            ],
            if (archived.isNotEmpty)
              _InactiveGoalSection(title: 'Archived', goals: archived),
          ],
        ),
      ),
    );
  }
}

class _InactiveGoalSection extends StatelessWidget {
  const _InactiveGoalSection({required this.title, required this.goals});

  final String title;
  final List<GoalRecord> goals;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$title (${goals.length})',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final goal in goals) ...[
          InactiveGoalCard(goal: goal),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class InactiveGoalCard extends StatelessWidget {
  const InactiveGoalCard({required this.goal, super.key});

  final GoalRecord goal;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final metrics = store.goalMetrics(goal.id);
    final isCompleted = goal.isCompleted;
    final date = isCompleted ? goal.completedAt : goal.archivedAt;
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        key: ValueKey('inactive-goal-${goal.id}'),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        leading: TransactionFormIcon(
          isCompleted ? AppIcon.success : AppIcon.archive,
          color: isCompleted ? _goalBlue : AppColors.muted,
        ),
        title: Text(
          goal.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${money(metrics.currentAmountMinor, store.preferences.currency)} of ${money(goal.targetAmountMinor, store.preferences.currency)}\n'
          '${isCompleted ? 'Completed' : 'Archived'}${date == null ? '' : ' ${fullMonthDateLabel(date)}'} · ${goalTypeBadgeLabel(goal.goalType)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFeatures: const [AppTextStyles.tabularFigures],
          ),
        ),
        trailing: Icon(AppIcon.chevronRight),
        onTap: () => showGoalDetails(context, goal.id),
        onLongPress: goal.isArchived
            ? () {
                AppHaptics.longPressAction();
                unawaited(showArchivedGoalActions(context, goal.id));
              }
            : null,
      ),
    );
  }
}

/// Uses the same inactive-Goal actions already available from Goal Details.
/// This is intentionally limited to archived cards: it is a quick action
/// entry point, not a second editing surface.
Future<void> showArchivedGoalActions(
  BuildContext context,
  String goalId,
) async {
  final store = FinanceDataStoreScope.read(context);
  final goal = store.goals
      .where((item) => item.id == goalId && item.isArchived)
      .firstOrNull;
  if (goal == null) return;
  final eligibility = store.goalDeleteEligibility(goal.id);
  final action = await showPolishedChoicePicker<String>(
    context,
    title: goal.name,
    selected: '',
    choices: [
      PolishedChoice(
        value: 'restore',
        label: 'Restore',
        leading: Icon(AppIcon.unarchive),
      ),
      PolishedChoice(
        value: 'duplicate',
        label: 'Duplicate',
        leading: Icon(AppIcon.copy),
      ),
      if (eligibility.canDelete)
        PolishedChoice(
          value: 'delete',
          label: 'Delete Permanently',
          leading: Icon(AppIcon.delete),
        ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'restore':
      await store.restoreGoal(goal.id);
    case 'duplicate':
      await store.duplicateGoal(goal.id);
    case 'delete':
      final confirmed = await showGoalConfirmation(
        context,
        title: 'Delete this Goal permanently?',
        message:
            'This Goal has no remaining balance or pending scheduled activity. Ledger history, if any, will remain available.',
        confirmLabel: 'Delete Permanently',
        destructive: true,
      );
      if (confirmed) await store.deleteGoalPermanently(goal.id);
  }
}

/// Archiving is optional organization, not a prerequisite for removing an
/// empty Goal. Active cards use this same long-press action language as
/// account and Ledger rows.
Future<void> showActiveGoalActions(BuildContext context, String goalId) async {
  final store = FinanceDataStoreScope.read(context);
  final goal = store.goals
      .where((item) => item.id == goalId && item.isActive)
      .firstOrNull;
  if (goal == null) return;

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Goal Actions',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          ListTile(
            leading: Icon(AppIcon.savings),
            title: const Text('Goal Activity'),
            onTap: () => Navigator.pop(sheetContext, 'activity'),
          ),
          ListTile(
            leading: Icon(AppIcon.edit),
            title: const Text('Edit'),
            onTap: () => Navigator.pop(sheetContext, 'edit'),
          ),
          ListTile(
            leading: Icon(AppIcon.archive),
            title: const Text('Archive'),
            onTap: () => Navigator.pop(sheetContext, 'archive'),
          ),
          ListTile(
            leading: Icon(AppIcon.delete),
            title: const Text('Delete'),
            textColor: Theme.of(sheetContext).colorScheme.error,
            iconColor: Theme.of(sheetContext).colorScheme.error,
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('Cancel'),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'activity':
      await showGoalActivitySheet(context, goal.id);
    case 'edit':
      await showGoalEditor(context, initialGoal: goal);
    case 'archive':
      final confirmed = await showGoalConfirmation(
        context,
        title: 'Archive Goal?',
        message:
            'This hides the Goal from active planning. Its balance and activity remain unchanged.',
        confirmLabel: 'Archive Goal',
        destructive: true,
      );
      if (confirmed) await store.archiveGoal(goal.id);
    case 'delete':
      final eligibility = store.goalDeleteEligibility(goal.id);
      if (!eligibility.canDelete) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Goal can’t be deleted yet'),
            content: Text(
              goalDeletionBlockedMessage(
                eligibility,
                store.preferences.currency,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }
      final confirmed = await showGoalConfirmation(
        context,
        title: 'Delete this Goal permanently?',
        message:
            'This Goal has no remaining balance or pending scheduled activity. Ledger history, if any, will remain available.',
        confirmLabel: 'Delete Permanently',
        destructive: true,
      );
      if (confirmed) await store.deleteGoalPermanently(goal.id);
  }
}

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class GoalsPlanContent extends StatelessWidget {
  const GoalsPlanContent({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final active = store.goals.where((goal) => goal.isActive).toList()
      ..sort(compareGoalUrgency);
    final inactiveCount = store.inactiveGoals.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: ValueKey('plan-create-goal'),
                  onPressed: () => showCreateGoalSheet(context),
                  icon: Icon(AppIcon.goal),
                  label: const Text('Create Goal'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('plan-fund-goals'),
                  onPressed: active.any((goal) => goal.isAccountBacked)
                      ? () => showFundGoalsSheet(context)
                      : null,
                  icon: Icon(AppIcon.savings),
                  label: const Text('Fund Goals'),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        if (active.isEmpty)
          ActiveGoalsEmptyState(hasInactiveGoals: inactiveCount > 0)
        else ...[
          for (final goal in active) ...[
            GoalCard(goal: goal),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
        if (inactiveCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          InactiveGoalsNavigationRow(count: inactiveCount),
        ],
      ],
    );
  }
}

class _GoalsPageState extends State<GoalsPage> {
  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final active = store.goals.where((goal) => goal.isActive).toList()
      ..sort(compareGoalUrgency);
    final inactiveCount = store.inactiveGoals.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goals'),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            key: ValueKey('goals-add'),
            tooltip: 'Add Goal',
            onPressed: () => showCreateGoalSheet(context),
            icon: Icon(AppIcon.add),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (active.isEmpty)
              ActiveGoalsEmptyState(
                hasInactiveGoals: inactiveCount > 0,
                showCreateButton: true,
              )
            else ...[
              for (final goal in active) ...[
                GoalCard(goal: goal),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
            if (inactiveCount > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              InactiveGoalsNavigationRow(count: inactiveCount),
            ],
          ],
        ),
      ),
    );
  }
}

class ActiveGoalsEmptyState extends StatelessWidget {
  const ActiveGoalsEmptyState({
    required this.hasInactiveGoals,
    this.showCreateButton = false,
    super.key,
  });

  final bool hasInactiveGoals;
  final bool showCreateButton;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          TransactionFormIcon(AppIcon.goal, color: _goalBlue),
          const SizedBox(height: AppSpacing.sm),
          Text(
            hasInactiveGoals ? 'No active Goals' : 'No Goals yet',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hasInactiveGoals
                ? 'Create a Goal to start planning, or view your completed and archived Goals.'
                : 'Create a Goal to start saving toward something important.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (showCreateButton) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: const ValueKey('goals-empty-create'),
              onPressed: () => showCreateGoalSheet(context),
              icon: Icon(AppIcon.add),
              label: const Text('Create Goal'),
            ),
          ],
        ],
      ),
    );
  }
}

class InactiveGoalsNavigationRow extends StatelessWidget {
  const InactiveGoalsNavigationRow({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        key: const ValueKey('view-inactive-goals'),
        leading: TransactionFormIcon(AppIcon.archive),
        title: Text(
          'View Inactive Goals ($count)',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        trailing: Icon(AppIcon.chevronRight),
        onTap: () => openInactiveGoalsPage(context),
      ),
    );
  }
}

int compareGoalUrgency(GoalRecord left, GoalRecord right) {
  final leftDate = left.targetDate ?? DateTime(9999);
  final rightDate = right.targetDate ?? DateTime(9999);
  return leftDate.compareTo(rightDate);
}

class GoalCollapsibleSection extends StatelessWidget {
  const GoalCollapsibleSection({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.goals,
    super.key,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final List<GoalRecord> goals;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            onTap: onToggle,
            title: Text(
              '$title ($count)',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            trailing: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: Duration(milliseconds: 160),
              child: Icon(AppIcon.chevronDown),
            ),
          ),
          if (expanded)
            for (final goal in goals)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: GoalCard(goal: goal, compact: true),
              ),
        ],
      ),
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({required this.goal, this.compact = false, super.key});

  final GoalRecord goal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final metrics = store.goalMetrics(goal.id);
    final statusColor = goalStatusColor(metrics.status);
    final needsAttention = !store.hasUsableGoalAccount(goal.id);
    return Card(
      child: InkWell(
        key: ValueKey('goal-card-${goal.id}'),
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () => showGoalDetails(context, goal.id),
        onLongPress: goal.isActive
            ? () {
                AppHaptics.longPressAction();
                unawaited(showActiveGoalActions(context, goal.id));
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(AppIcon.chevronRight),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${money(metrics.currentAmountMinor, store.preferences.currency)} of ${money(goal.targetAmountMinor, store.preferences.currency)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [AppTextStyles.tabularFigures],
                ),
              ),
              Text(
                '${(metrics.percentageComplete * 100).clamp(0, 999).round()}% ${goal.goalType == GoalType.maintainBalance ? 'funded' : 'complete'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [AppTextStyles.tabularFigures],
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Align(
                alignment: Alignment.centerLeft,
                child: _GoalTypeBadge(type: goal.goalType),
              ),
              const SizedBox(height: AppSpacing.sm),
              GoalProgressBar(
                progress: metrics.percentageComplete,
                color: statusColor,
                semanticsLabel: metrics.status.label,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      needsAttention
                          ? 'Goal account unavailable'
                          : metrics.status.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: needsAttention ? AppColors.danger : statusColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (!compact && goal.isActive)
                    TextButton(
                      key: ValueKey('goal-add-contribution-${goal.id}'),
                      onPressed: needsAttention
                          ? null
                          : () => showGoalActivitySheet(context, goal.id),
                      child: const Text('Goal Activity'),
                    ),
                ],
              ),
              if (!compact) ...[
                if (goal.targetDate != null)
                  Text(
                    '${goal.goalType == GoalType.maintainBalance ? 'Replenish by' : 'Target'}: ${fullMonthDateLabel(goal.targetDate!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (goal.targetDate != null && goal.isActive)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${money(metrics.requiredWeeklyMinor, store.preferences.currency)}/week ${goal.goalType == GoalType.maintainBalance ? 'to restore' : 'needed'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'About ${money(metrics.requiredMonthlyMinor, store.preferences.currency)}/month ${goal.goalType == GoalType.maintainBalance ? 'to restore' : 'needed'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalTypeBadge extends StatelessWidget {
  const _GoalTypeBadge({required this.type});

  final GoalType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        goalTypeBadgeLabel(type),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({
    required this.progress,
    required this.color,
    required this.semanticsLabel,
    super.key,
  });

  final double progress;
  final Color color;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      value: '${(progress * 100).clamp(0, 999).round()} percent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: LinearProgressIndicator(
          minHeight: 8,
          value: progress.clamp(0.0, 1.0).toDouble(),
          color: color,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

Future<void> showCreateGoalSheet(BuildContext context) {
  return showGoalEditor(context);
}

/// Presents only Goal-relevant money actions.  Each action delegates to the
/// existing transfer/expense forms, so Goal balances use the exact same
/// transaction path as every other account.
Future<void> showGoalActivitySheet(BuildContext context, String goalId) async {
  final store = FinanceDataStoreScope.read(context);
  final goal = store.goals
      .where(
        (item) => item.id == goalId && item.isActive && item.isAccountBacked,
      )
      .firstOrNull;
  if (goal == null) return;
  final action = await showPolishedChoicePicker<String>(
    context,
    title: 'Goal Activity',
    selected: '',
    choices: [
      PolishedChoice(
        value: 'fund',
        label: 'Fund Goal',
        leading: Icon(AppIcon.savings),
      ),
      PolishedChoice(
        value: 'scheduleFunding',
        label: 'Schedule Funding',
        leading: Icon(AppIcon.schedule),
      ),
      PolishedChoice(
        value: 'spend',
        label: 'Spend from Goal',
        leading: Icon(AppIcon.expense),
      ),
      PolishedChoice(
        value: 'between',
        label: 'Transfer Between Goals',
        leading: Icon(AppIcon.transfer),
      ),
      PolishedChoice(
        value: 'withdraw',
        label: 'Withdraw to Account',
        leading: Icon(AppIcon.transfer),
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'fund':
      await showFundGoalsSheet(context, initialGoalId: goal.id);
    case 'scheduleFunding':
      await showScheduledGoalFundingDialog(context, initialGoalId: goal.id);
    case 'spend':
      await showTransactionDialog(
        context,
        initialIsExpense: true,
        initialAccountId: goal.accountId,
      );
    case 'between':
      await showTransferDialog(
        context,
        initialFromAccountId: goal.accountId,
        includeGoalAccounts: true,
      );
    case 'withdraw':
      await showTransferDialog(context, initialFromAccountId: goal.accountId);
  }
}

Future<void> showGoalEditor(
  BuildContext context, {
  GoalRecord? initialGoal,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final nameController = TextEditingController(text: initialGoal?.name ?? '');
  final descriptionController = TextEditingController(
    text: initialGoal?.description ?? '',
  );
  var targetMinor = initialGoal?.targetAmountMinor ?? 0;
  var targetDate = initialGoal?.targetDate;
  var goalType = initialGoal?.goalType ?? GoalType.reachTarget;
  final accountId = initialGoal?.defaultFundingAccountId;
  var isSaving = false;
  String? errorText;

  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final isEditing = initialGoal != null;
        final validDate =
            isEditing ||
            targetDate == null ||
            !targetDate!.isBefore(
              DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day + (isEditing ? 0 : 1),
              ),
            );
        final canSave =
            nameController.text.trim().isNotEmpty &&
            targetMinor > 0 &&
            validDate;

        return _GoalControllerOwner(
          controllers: [nameController, descriptionController],
          child: TransactionSheetFrame(
            title: isEditing ? 'Edit Goal' : 'Create Goal',
            actions: TransactionFormActions(
              onCancel: () => Navigator.pop(dialogContext),
              canSave: canSave,
              isSaving: isSaving,
              saveKey: const ValueKey('goal-save'),
              onSave: () async {
                if (isSaving || !canSave) return;
                setDialogState(() {
                  isSaving = true;
                  errorText = null;
                });
                try {
                  if (initialGoal == null) {
                    await store.createGoal(
                      name: nameController.text,
                      targetAmountMinor: targetMinor,
                      // New Goals never create money. Funding begins with an
                      // ordinary transfer from a visible source account.
                      startingAmountMinor: 0,
                      targetDate: targetDate,
                      fundingMethod: GoalFundingMethod.accountFunded,
                      goalType: goalType,
                      defaultFundingAccountId: accountId,
                      description: descriptionController.text,
                    );
                  } else {
                    await store.saveGoal(
                      initialGoal.copyWith(
                        name: nameController.text.trim(),
                        description: descriptionController.text.trim(),
                        targetAmountMinor: targetMinor,
                        targetDate: targetDate,
                        goalType: goalType,
                        fundingMethod: GoalFundingMethod.accountFunded,
                        defaultFundingAccountId: accountId,
                        clearTargetDate: targetDate == null,
                        reservationsReleased: initialGoal.reservationsReleased,
                        sync: initialGoal.sync.touched(
                          deviceId: store.deviceId,
                        ),
                      ),
                    );
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    isSaving = false;
                    errorText = error.toString();
                  });
                }
              },
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TransactionFormLabel('Goal name'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.goal, color: _goalBlue),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('goal-name'),
                        controller: nameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Emergency Fund',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                  ],
                ),
                TransactionFormDivider(),
                TransactionFormLabel('Goal type'),
                PolishedFormValueRow(
                  key: ValueKey('goal-type'),
                  icon: goalType == GoalType.reachTarget
                      ? AppIcon.goal
                      : AppIcon.shield,
                  value: goalTypeLabel(goalType),
                  secondary: goalType == GoalType.reachTarget
                      ? 'Save toward a target amount'
                      : 'Build and replenish a reusable reserve',
                  onTap: () async {
                    final selected = await showPolishedChoicePicker<GoalType>(
                      dialogContext,
                      title: 'Goal type',
                      selected: goalType,
                      choices: [
                        for (final option in GoalType.values)
                          PolishedChoice(
                            value: option,
                            label: goalTypeLabel(option),
                            leading: Icon(
                              option == GoalType.reachTarget
                                  ? AppIcon.goal
                                  : AppIcon.shield,
                            ),
                          ),
                      ],
                    );
                    if (selected == null || selected == goalType) return;
                    if (!dialogContext.mounted) return;
                    if (initialGoal != null) {
                      final hasHistory =
                          store
                              .activeContributionsForGoal(initialGoal.id)
                              .isNotEmpty ||
                          store
                              .activeFundingEventsForGoal(initialGoal.id)
                              .isNotEmpty ||
                          initialGoal.startingAmountMinor > 0;
                      if (hasHistory) {
                        final confirmed = await showGoalConfirmation(
                          dialogContext,
                          title: 'Change Goal type?',
                          message:
                              'This keeps the Goal balance and funding history but changes how progress, dates, and completion are calculated.',
                          confirmLabel: 'Change Type',
                        );
                        if (!confirmed || !dialogContext.mounted) return;
                      }
                    }
                    setDialogState(() => goalType = selected);
                  },
                ),
                TransactionFormDivider(),
                TransactionFormLabel('Target amount'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.target),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AmountEntryField(
                        fieldKey: const ValueKey('goal-target-amount'),
                        initialMinor: targetMinor,
                        currency: store.preferences.currency,
                        labelText: null,
                        onChanged: (value) =>
                            setDialogState(() => targetMinor = value.abs()),
                      ),
                    ),
                  ],
                ),
                const TransactionFormDivider(),
                TransactionFormLabel(
                  goalType == GoalType.maintainBalance
                      ? 'Replenish by date'
                      : 'Target date',
                ),
                PolishedFormValueRow(
                  key: ValueKey('goal-target-date'),
                  icon: AppIcon.calendar,
                  value: targetDate == null
                      ? goalType == GoalType.maintainBalance
                            ? 'No replenishment deadline'
                            : 'No deadline'
                      : fullMonthDateLabel(targetDate!),
                  secondary: goalType == GoalType.maintainBalance
                      ? 'Optional date to replenish this balance below its target'
                      : 'Optional date to reach the target amount',
                  onTap: () async {
                    final selected = await pickDateForField(
                      dialogContext,
                      targetDate ??
                          DateTime.now().add(const Duration(days: 30)),
                    );
                    if (selected != null) {
                      setDialogState(() => targetDate = selected);
                    }
                  },
                ),
                if (targetDate != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setDialogState(() => targetDate = null),
                      child: const Text('Remove date'),
                    ),
                  ),
                TransactionFormDivider(),
                TransactionFormLabel('Description'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TransactionFormIcon(AppIcon.notes),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('goal-description'),
                        controller: descriptionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Add a description (optional)',
                        ),
                      ),
                    ),
                  ],
                ),
                if (errorText != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    errorText!,
                    key: const ValueKey('goal-error'),
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _GoalControllerOwner extends StatefulWidget {
  const _GoalControllerOwner({required this.controllers, required this.child});

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_GoalControllerOwner> createState() => _GoalControllerOwnerState();
}

class _GoalControllerOwnerState extends State<_GoalControllerOwner> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class PolishedFormValueRow extends StatelessWidget {
  const PolishedFormValueRow({
    required this.icon,
    required this.value,
    required this.onTap,
    this.secondary,
    super.key,
  });

  final IconData icon;
  final String value;
  final String? secondary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.control),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            TransactionFormIcon(icon),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (secondary != null)
                    Text(
                      secondary!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null) Icon(AppIcon.chevronDown),
          ],
        ),
      ),
    );
  }
}

class _GoalAllocationDraft {
  _GoalAllocationDraft({required this.id, this.goalId}) : amountMinor = 0;

  final String id;
  String? goalId;
  int amountMinor;
  int revision = 0;
}

Future<void> showFundGoalsSheet(
  BuildContext context, {
  String? initialGoalId,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final eligibleGoals =
      store.goals
          .where((goal) => goal.isActive && goal.isAccountBacked)
          .toList(growable: false)
        ..sort(compareGoalUrgency);
  if (eligibleGoals.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Create a Goal first.')));
    return;
  }
  final initialGoal = eligibleGoals
      .where((goal) => goal.id == initialGoalId)
      .firstOrNull;
  var accountId =
      initialGoal?.defaultFundingAccountId ??
      store.activeAccountsInDisplayOrder.firstOrNull?.id;
  var totalAmountMinor = 0;
  var date = DateTime.now();
  var isSaving = false;
  String? errorText;
  var draftSequence = 0;
  final noteController = TextEditingController();
  final allocations = <_GoalAllocationDraft>[
    _GoalAllocationDraft(
      id: 'goal-allocation-draft-${draftSequence++}',
      goalId: initialGoal?.id,
    ),
  ];

  void rebalanceFirst() {
    if (allocations.isEmpty) return;
    final otherTotal = allocations
        .skip(1)
        .fold<int>(0, (total, row) => total + row.amountMinor.abs());
    allocations.first.amountMinor = (totalAmountMinor - otherTotal)
        .clamp(0, totalAmountMinor)
        .toInt();
    allocations.first.revision += 1;
  }

  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final accounts = store.activeAccountsInDisplayOrder;
        final account = accounts
            .where((item) => item.id == accountId)
            .firstOrNull;
        final allocatedTotal = allocations.fold<int>(
          0,
          (total, row) => total + row.amountMinor.abs(),
        );
        final remaining = totalAmountMinor - allocatedTotal;
        final selectedGoalIds = allocations
            .map((row) => row.goalId)
            .whereType<String>()
            .toSet();
        final rowsValid =
            allocations.isNotEmpty &&
            allocations.every(
              (row) => row.goalId != null && row.amountMinor > 0,
            ) &&
            selectedGoalIds.length == allocations.length;
        final amountFits =
            account != null &&
            totalAmountMinor <= store.balanceForAccount(account.id);
        final canSave =
            totalAmountMinor > 0 && remaining == 0 && rowsValid && amountFits;

        return _GoalControllerOwner(
          controllers: [noteController],
          child: TransactionSheetFrame(
            title: 'Fund Goals',
            actions: TransactionFormActions(
              onCancel: () => Navigator.pop(dialogContext),
              canSave: canSave,
              isSaving: isSaving,
              saveLabel: 'Fund Goals',
              saveKey: const ValueKey('fund-goals-save'),
              onSave: () async {
                if (isSaving || !canSave) return;
                setDialogState(() {
                  isSaving = true;
                  errorText = null;
                });
                try {
                  await store.fundGoals(
                    sourceAccountId: accountId!,
                    totalAmountMinor: totalAmountMinor,
                    date: date,
                    note: noteController.text,
                    allocations: [
                      for (
                        var index = 0;
                        index < allocations.length;
                        index += 1
                      )
                        GoalFundingAllocation(
                          id: '',
                          fundingEventId: '',
                          goalId: allocations[index].goalId!,
                          amountMinor: allocations[index].amountMinor,
                          order: index,
                        ),
                    ],
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    isSaving = false;
                    errorText = error.toString();
                  });
                }
              },
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TransactionFormLabel('From Account'),
                PolishedFormValueRow(
                  key: ValueKey('fund-goals-account'),
                  icon: AppIcon.bank,
                  value: account?.name ?? 'Choose account',
                  secondary: account == null
                      ? null
                      : 'Balance ${money(store.balanceForAccount(account.id), store.preferences.currency)}',
                  onTap: () async {
                    final selected = await showTransactionAccountPicker(
                      dialogContext,
                      accounts: accounts,
                      selectedAccountId: accountId ?? '',
                    );
                    if (selected != null) {
                      setDialogState(() => accountId = selected);
                    }
                  },
                ),
                TransactionFormDivider(),
                TransactionFormLabel('Total Amount'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.savings, color: _goalBlue),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AmountEntryField(
                        fieldKey: const ValueKey('fund-goals-total'),
                        initialMinor: totalAmountMinor,
                        autofocus: true,
                        replaceZeroOnFirstInput: true,
                        currency: store.preferences.currency,
                        labelText: null,
                        onChanged: (value) => setDialogState(() {
                          totalAmountMinor = value.abs();
                          rebalanceFirst();
                        }),
                      ),
                    ),
                  ],
                ),
                const TransactionFormDivider(),
                Text(
                  'Goal Allocations',
                  style: Theme.of(dialogContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (var index = 0; index < allocations.length; index += 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      key: ValueKey(allocations[index].id),
                      children: [
                        Expanded(
                          flex: 10,
                          child: InkWell(
                            key: ValueKey(
                              'fund-goals-goal-${allocations[index].id}',
                            ),
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                            onTap: () async {
                              final selected =
                                  await showPolishedChoicePicker<String>(
                                    dialogContext,
                                    title: 'Choose Goal',
                                    selected: allocations[index].goalId ?? '',
                                    choices: [
                                      for (final goal in eligibleGoals)
                                        if (!selectedGoalIds.contains(
                                              goal.id,
                                            ) ||
                                            allocations[index].goalId ==
                                                goal.id)
                                          PolishedChoice(
                                            value: goal.id,
                                            label: goal.name,
                                            leading: Icon(AppIcon.goal),
                                          ),
                                    ],
                                  );
                              if (selected != null) {
                                setDialogState(
                                  () => allocations[index].goalId = selected,
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                eligibleGoals
                                        .where(
                                          (goal) =>
                                              goal.id ==
                                              allocations[index].goalId,
                                        )
                                        .firstOrNull
                                        ?.name ??
                                    'Choose Goal',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(
                                  dialogContext,
                                ).textTheme.bodyLarge,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          flex: 10,
                          child: AmountEntryField(
                            key: ValueKey(
                              '${allocations[index].id}-${allocations[index].revision}',
                            ),
                            fieldKey: ValueKey(
                              'fund-goals-amount-${allocations[index].id}',
                            ),
                            initialMinor: allocations[index].amountMinor,
                            replaceZeroOnFirstInput: true,
                            currency: store.preferences.currency,
                            labelText: null,
                            decoration: const InputDecoration(
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.never,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.sm,
                              ),
                            ),
                            onChanged: (value) => setDialogState(() {
                              allocations[index].amountMinor = value.abs();
                              if (index > 0) rebalanceFirst();
                            }),
                          ),
                        ),
                        if (allocations.length > 1)
                          SizedBox(
                            width: 40,
                            child: IconButton(
                              padding: const EdgeInsets.all(AppSpacing.xxs),
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              tooltip: 'Remove Goal allocation',
                              onPressed: () => setDialogState(() {
                                allocations.removeAt(index);
                                rebalanceFirst();
                              }),
                              icon: Icon(AppIcon.expense),
                            ),
                          ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('fund-goals-add-allocation'),
                    onPressed: allocations.length >= eligibleGoals.length
                        ? null
                        : () => setDialogState(() {
                            allocations.add(
                              _GoalAllocationDraft(
                                id: 'goal-allocation-draft-${draftSequence++}',
                              ),
                            );
                            rebalanceFirst();
                          }),
                    icon: Icon(AppIcon.add),
                    label: const Text(
                      'Add Goal',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                GoalAllocationSummary(
                  totalAmountMinor: totalAmountMinor,
                  allocatedAmountMinor: allocatedTotal,
                  currency: store.preferences.currency,
                ),
                TransactionFormDivider(),
                TransactionFormLabel('Date'),
                PolishedFormValueRow(
                  key: ValueKey('fund-goals-date'),
                  icon: AppIcon.calendar,
                  value: fullMonthDateLabel(date),
                  onTap: () async {
                    final selected = await pickDateForField(
                      dialogContext,
                      date,
                    );
                    if (selected != null) {
                      setDialogState(() => date = selected);
                    }
                  },
                ),
                TransactionFormDivider(),
                TransactionFormLabel('Note'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.notes),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('fund-goals-note'),
                        controller: noteController,
                        decoration: const InputDecoration(
                          hintText: 'Add a note (optional)',
                        ),
                      ),
                    ),
                  ],
                ),
                if (!amountFits && totalAmountMinor > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Funding exceeds the selected account balance.',
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    errorText!,
                    key: const ValueKey('fund-goals-error'),
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// The scheduled counterpart to [showFundGoalsSheet]. It deliberately stores a
/// plan only; completing the occurrence later invokes the same Goal Funding
/// domain operation as the manual sheet.
Future<bool> showScheduledGoalFundingDialog(
  BuildContext context, {
  v2_scheduled.ScheduledTransactionRecord? existing,
  DateTime? initialDate,
  String? initialGoalId,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final eligibleGoals =
      store.goals
          .where((goal) => goal.isActive && goal.isAccountBacked)
          .toList(growable: false)
        ..sort(compareGoalUrgency);
  if (eligibleGoals.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Create an active account-funded Goal before scheduling funding.',
        ),
      ),
    );
    return false;
  }
  final accounts = store.activeAccountsInDisplayOrder;
  if (accounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Add an active source account before scheduling funding.',
        ),
      ),
    );
    return false;
  }

  var accountId =
      accounts
          .where((account) => account.id == existing?.accountId)
          .firstOrNull
          ?.id ??
      eligibleGoals
          .where((goal) => goal.defaultFundingAccountId != null)
          .map((goal) => goal.defaultFundingAccountId!)
          .where((id) => accounts.any((account) => account.id == id))
          .firstOrNull ??
      accounts.first.id;
  var totalAmountMinor = existing?.amountMinor.abs() ?? 0;
  var startDate = existing?.nextDate ?? initialDate ?? DateTime.now();
  var frequency =
      existing?.frequency ?? v2_scheduled.RecurrenceFrequency.monthly;
  var alertPreference =
      existing?.alertPreference ?? v2_scheduled.AlertPreference.none;
  var customAlertTimeMinutes = existing?.customAlertTimeMinutes ?? 9 * 60;
  var repeatAlertUntilResolved = existing?.repeatAlertUntilResolved ?? false;
  var isSaving = false;
  String? errorText;
  var draftSequence = 0;
  final note = TextEditingController(text: existing?.note ?? '');
  final allocations = <_GoalAllocationDraft>[
    for (final allocation in existing?.goalFundingAllocations ?? const [])
      _GoalAllocationDraft(id: allocation.id, goalId: allocation.goalId)
        ..amountMinor = allocation.amountMinor,
  ];
  if (allocations.isEmpty) {
    allocations.add(
      _GoalAllocationDraft(
        id: 'scheduled-goal-${draftSequence++}',
        goalId: eligibleGoals.any((goal) => goal.id == initialGoalId)
            ? initialGoalId
            : null,
      ),
    );
  }

  void rebalanceFirst() {
    if (allocations.isEmpty) return;
    final others = allocations
        .skip(1)
        .fold<int>(0, (total, row) => total + row.amountMinor.abs());
    allocations.first.amountMinor = (totalAmountMinor - others)
        .clamp(0, totalAmountMinor)
        .toInt();
    allocations.first.revision += 1;
  }

  final saved = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final account = accounts
            .where((item) => item.id == accountId)
            .firstOrNull;
        final allocated = allocations.fold<int>(
          0,
          (total, row) => total + row.amountMinor.abs(),
        );
        final remaining = totalAmountMinor - allocated;
        final selectedGoalIds = allocations
            .map((row) => row.goalId)
            .whereType<String>()
            .toSet();
        final validRows =
            allocations.length == 1 &&
            allocations.every(
              (row) => row.goalId != null && row.amountMinor > 0,
            ) &&
            selectedGoalIds.length == allocations.length;
        final canSave =
            account != null &&
            totalAmountMinor > 0 &&
            remaining == 0 &&
            validRows;
        return _GoalControllerOwner(
          controllers: [note],
          child: TransactionSheetFrame(
            title: existing == null
                ? 'Create Scheduled Goal Funding'
                : 'Edit Scheduled Goal Funding',
            actions: TransactionFormActions(
              onCancel: () => Navigator.pop(dialogContext, false),
              canSave: canSave,
              isSaving: isSaving,
              saveLabel: 'Save',
              saveKey: const ValueKey('scheduled-goal-funding-save'),
              onSave: () async {
                if (isSaving || !canSave) return;
                setDialogState(() {
                  isSaving = true;
                  errorText = null;
                });
                try {
                  final selectedGoal = eligibleGoals
                      .where((goal) => goal.id == allocations.single.goalId)
                      .first;
                  final record = v2_scheduled.ScheduledTransactionRecord(
                    id:
                        existing?.id ??
                        'scheduled_goal_${DateTime.now().microsecondsSinceEpoch}',
                    // New schedules are normal scheduled transfers. Legacy
                    // multi-allocation schedules remain readable until the
                    // user intentionally replaces them.
                    type: existing?.type == TransactionType.goalFunding
                        ? TransactionType.goalFunding
                        : TransactionType.transfer,
                    accountId: accountId,
                    transferAccountId:
                        existing?.type == TransactionType.goalFunding
                        ? null
                        : selectedGoal.accountId,
                    goalId: existing?.type == TransactionType.goalFunding
                        ? null
                        : selectedGoal.id,
                    payee: 'Fund ${selectedGoal.name}',
                    note: note.text.trim(),
                    amountMinor: totalAmountMinor,
                    nextDate: DateTime(
                      startDate.year,
                      startDate.month,
                      startDate.day,
                    ),
                    frequency: frequency,
                    endDate: existing?.endDate,
                    alertPreference: alertPreference,
                    customAlertTimeMinutes: customAlertTimeMinutes,
                    repeatAlertUntilResolved: repeatAlertUntilResolved,
                    goalFundingAllocations:
                        existing?.type == TransactionType.goalFunding
                        ? [
                            for (
                              var index = 0;
                              index < allocations.length;
                              index += 1
                            )
                              v2_scheduled.ScheduledGoalFundingAllocation(
                                id: allocations[index].id.isEmpty
                                    ? 'scheduled_goal_allocation_${DateTime.now().microsecondsSinceEpoch}_$index'
                                    : allocations[index].id,
                                goalId: allocations[index].goalId!,
                                amountMinor: allocations[index].amountMinor
                                    .abs(),
                                order: index,
                              ),
                          ]
                        : const [],
                    occurrences: existing?.occurrences ?? const [],
                    lastAction:
                        existing?.lastAction ??
                        v2_scheduled.ScheduledAction.none,
                    scheduledNotificationIds: const [],
                    sync:
                        existing?.sync ??
                        v2_sync.SyncMetadata.fresh(deviceId: store.deviceId),
                  );
                  await store.saveScheduledTransaction(record);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    isSaving = false;
                    errorText = error.toString();
                  });
                }
              },
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TransactionFormLabel('From Account'),
                PolishedFormValueRow(
                  key: const ValueKey('scheduled-goal-funding-account'),
                  icon: AppIcon.bank,
                  value: account?.name ?? 'Choose account',
                  secondary: account == null
                      ? null
                      : 'Balance ${money(store.balanceForAccount(account.id), store.preferences.currency)}',
                  onTap: () async {
                    final selected = await showTransactionAccountPicker(
                      dialogContext,
                      accounts: accounts,
                      selectedAccountId: accountId,
                    );
                    if (selected != null) {
                      setDialogState(() => accountId = selected);
                    }
                  },
                ),
                const TransactionFormDivider(),
                TransactionFormLabel('Total Amount'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.savings, color: _goalBlue),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AmountEntryField(
                        fieldKey: const ValueKey(
                          'scheduled-goal-funding-total',
                        ),
                        initialMinor: totalAmountMinor,
                        replaceZeroOnFirstInput: true,
                        currency: store.preferences.currency,
                        labelText: null,
                        onChanged: (value) => setDialogState(() {
                          totalAmountMinor = value.abs();
                          rebalanceFirst();
                        }),
                      ),
                    ),
                  ],
                ),
                const TransactionFormDivider(),
                Text(
                  'Goal',
                  style: Theme.of(dialogContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (var index = 0; index < allocations.length; index += 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      key: ValueKey(allocations[index].id),
                      children: [
                        Expanded(
                          flex: 6,
                          child: InkWell(
                            onTap: () async {
                              final selected =
                                  await showPolishedChoicePicker<String>(
                                    dialogContext,
                                    title: 'Choose Goal',
                                    selected: allocations[index].goalId ?? '',
                                    choices: [
                                      for (final goal in eligibleGoals)
                                        if (!selectedGoalIds.contains(
                                              goal.id,
                                            ) ||
                                            allocations[index].goalId ==
                                                goal.id)
                                          PolishedChoice(
                                            value: goal.id,
                                            label: goal.name,
                                            leading: Icon(
                                              AppIcon.goal,
                                              color: _goalBlue,
                                            ),
                                          ),
                                    ],
                                  );
                              if (selected != null) {
                                setDialogState(
                                  () => allocations[index].goalId = selected,
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                eligibleGoals
                                        .where(
                                          (goal) =>
                                              goal.id ==
                                              allocations[index].goalId,
                                        )
                                        .firstOrNull
                                        ?.name ??
                                    'Choose Goal',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          flex: 4,
                          child: AmountEntryField(
                            key: ValueKey(
                              '${allocations[index].id}-${allocations[index].revision}',
                            ),
                            fieldKey: ValueKey(
                              'scheduled-goal-funding-amount-${allocations[index].id}',
                            ),
                            initialMinor: allocations[index].amountMinor,
                            replaceZeroOnFirstInput: true,
                            currency: store.preferences.currency,
                            labelText: null,
                            onChanged: (value) => setDialogState(() {
                              allocations[index].amountMinor = value.abs();
                              if (index > 0) rebalanceFirst();
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                GoalAllocationSummary(
                  totalAmountMinor: totalAmountMinor,
                  allocatedAmountMinor: allocated,
                  currency: store.preferences.currency,
                ),
                const TransactionFormDivider(),
                TransactionFormLabel('Start Date'),
                PolishedFormValueRow(
                  icon: AppIcon.calendar,
                  value: fullMonthDateLabel(startDate),
                  onTap: () async {
                    final date = await pickDateForField(
                      dialogContext,
                      startDate,
                    );
                    if (date != null) setDialogState(() => startDate = date);
                  },
                ),
                const TransactionFormDivider(),
                TransactionFormLabel('Frequency'),
                PolishedFormValueRow(
                  icon: AppIcon.recurrence,
                  value: recurrenceFrequencyLabel(frequency),
                  onTap: () async {
                    final selected = await showScheduledChoicePicker(
                      dialogContext,
                      title: 'Frequency',
                      values: v2_scheduled.RecurrenceFrequency.values,
                      selected: frequency,
                      label: recurrenceFrequencyLabel,
                    );
                    if (selected != null) {
                      setDialogState(() => frequency = selected);
                    }
                  },
                ),
                const TransactionFormDivider(),
                TransactionFormLabel('Reminder'),
                PolishedFormValueRow(
                  icon: alertPreference == v2_scheduled.AlertPreference.none
                      ? AppIcon.notificationNone
                      : AppIcon.notificationActive,
                  value: alertPreferenceLabel(alertPreference),
                  onTap: () async {
                    final selected = await showScheduledChoicePicker(
                      dialogContext,
                      title: 'Reminder',
                      values: v2_scheduled.AlertPreference.values,
                      selected: alertPreference,
                      label: alertPreferenceLabel,
                    );
                    if (selected != null) {
                      setDialogState(() => alertPreference = selected);
                    }
                  },
                ),
                if (alertPreference != v2_scheduled.AlertPreference.none) ...[
                  const TransactionFormDivider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Repeat until funded or skipped'),
                    value: repeatAlertUntilResolved,
                    onChanged: AppHaptics.toggleHandler(
                      (value) => setDialogState(
                        () => repeatAlertUntilResolved = value,
                      ),
                    ),
                  ),
                ],
                const TransactionFormDivider(),
                TransactionFormLabel('Note'),
                TextField(
                  controller: note,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Add a note (optional)',
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
  return saved == true;
}

class GoalAllocationSummary extends StatelessWidget {
  const GoalAllocationSummary({
    required this.totalAmountMinor,
    required this.allocatedAmountMinor,
    required this.currency,
    super.key,
  });

  final int totalAmountMinor;
  final int allocatedAmountMinor;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final remaining = totalAmountMinor - allocatedAmountMinor;
    final balanced = totalAmountMinor > 0 && remaining == 0;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Total\n${money(allocatedAmountMinor, currency)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              balanced
                  ? 'Remaining\nBalanced'
                  : 'Remaining\n${money(remaining.abs(), currency)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: balanced ? AppTheme.accent : AppColors.danger,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showAddGoalContributionSheet(
  BuildContext context,
  String goalId,
) async {
  final store = FinanceDataStoreScope.read(context);
  final goal = store.goalById(goalId);
  if (!goal.isActive) return;
  if (goal.isAccountBacked) {
    await showGoalActivitySheet(context, goal.id);
    return;
  }
  final metrics = store.goalMetrics(goalId);
  var amountMinor = 0;
  var date = DateTime.now();
  final noteController = TextEditingController();
  var isSaving = false;
  String? errorText;

  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final canSave = amountMinor > 0;
        return _GoalControllerOwner(
          controllers: [noteController],
          child: TransactionSheetFrame(
            title: 'Add Progress',
            actions: TransactionFormActions(
              onCancel: () => Navigator.pop(dialogContext),
              canSave: canSave,
              isSaving: isSaving,
              saveLabel: 'Add Progress',
              saveKey: const ValueKey('goal-contribution-save'),
              onSave: () async {
                if (isSaving || !canSave) return;
                setDialogState(() {
                  isSaving = true;
                  errorText = null;
                });
                try {
                  await store.addGoalContribution(
                    goalId: goal.id,
                    amountMinor: amountMinor,
                    date: date,
                    note: noteController.text,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    isSaving = false;
                    errorText = error.toString();
                  });
                }
              },
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GoalContributionHeader(
                  goal: goal,
                  metrics: metrics,
                  currency: store.preferences.currency,
                ),
                TransactionFormDivider(),
                TransactionFormLabel('Progress amount'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.income, color: _goalBlue),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AmountEntryField(
                        fieldKey: const ValueKey('goal-contribution-amount'),
                        autofocus: true,
                        replaceZeroOnFirstInput: true,
                        initialMinor: amountMinor,
                        currency: store.preferences.currency,
                        labelText: null,
                        onChanged: (value) =>
                            setDialogState(() => amountMinor = value.abs()),
                      ),
                    ),
                  ],
                ),
                TransactionFormDivider(),
                TransactionFormLabel('Contribution date'),
                PolishedFormValueRow(
                  key: ValueKey('goal-contribution-date'),
                  icon: AppIcon.calendar,
                  value: fullMonthDateLabel(date),
                  onTap: () async {
                    final selected = await pickDateForField(
                      dialogContext,
                      date,
                    );
                    if (selected != null) setDialogState(() => date = selected);
                  },
                ),
                TransactionFormDivider(),
                TransactionFormLabel('Note'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.notes),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('goal-contribution-note'),
                        controller: noteController,
                        decoration: const InputDecoration(
                          hintText: 'Add a note (optional)',
                        ),
                      ),
                    ),
                  ],
                ),
                if (errorText != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    errorText!,
                    key: const ValueKey('goal-contribution-error'),
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class GoalContributionHeader extends StatelessWidget {
  const GoalContributionHeader({
    required this.goal,
    required this.metrics,
    required this.currency,
    super.key,
  });

  final GoalRecord goal;
  final GoalProgressMetrics metrics;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          goal.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${money(metrics.currentAmountMinor, currency)} of ${money(goal.targetAmountMinor, currency)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w900,
            fontFeatures: const [AppTextStyles.tabularFigures],
          ),
        ),
        Text(
          goal.goalType == GoalType.maintainBalance
              ? metrics.aheadBehindMinor > 0
                    ? '${money(metrics.aheadBehindMinor, currency)} above reserve target'
                    : metrics.remainingAmountMinor == 0
                    ? 'Reserve target met'
                    : '${money(metrics.remainingAmountMinor, currency)} needed to restore'
              : '${money(metrics.remainingAmountMinor, currency)} remaining',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFeatures: const [AppTextStyles.tabularFigures],
          ),
        ),
      ],
    );
  }
}

Future<void> showGoalDetails(BuildContext context, String goalId) async {
  final store = FinanceDataStoreScope.read(context);
  final goal = store.goals
      .where((item) => item.id == goalId && !item.isDeleted)
      .firstOrNull;
  if (goal == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This Goal is no longer available.')),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) {
      final metrics = store.goalMetrics(goal.id);
      final goalTransactions = goal.accountId == null
          ? const <TransactionRecord>[]
          : (store.transactions
                .where(
                  (transaction) =>
                      !transaction.isDeleted &&
                      (transaction.accountId == goal.accountId ||
                          transaction.transferAccountId == goal.accountId),
                )
                .toList()
              ..sort((left, right) => right.date.compareTo(left.date)));
      // Legacy records remain available for unmigrated data only. Once a Goal
      // has its linked account, the ordinary transaction ledger is the sole
      // user-visible activity history.
      final contributions = goal.isAccountBacked
          ? const <GoalContributionRecord>[]
          : ([...store.activeContributionsForGoal(goal.id)]
              ..sort((a, b) => b.date.compareTo(a.date)));
      final fundingEvents = goal.isAccountBacked
          ? const <GoalFundingEventRecord>[]
          : ([...store.activeFundingEventsForGoal(goal.id)]
              ..sort((a, b) => b.date.compareTo(a.date)));
      return TransactionSheetFrame(
        title: 'Goal Details',
        actions: Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.xs,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            if (goal.isActive)
              OutlinedButton(
                key: const ValueKey('goal-details-edit'),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await showGoalEditor(context, initialGoal: goal);
                },
                child: const Text('Edit'),
              ),
            if (goal.isActive)
              FilledButton(
                key: const ValueKey('goal-details-add-contribution'),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await showGoalActivitySheet(context, goal.id);
                },
                child: const Text('Goal Activity'),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GoalContributionHeader(
              goal: goal,
              metrics: metrics,
              currency: store.preferences.currency,
            ),
            const SizedBox(height: AppSpacing.md),
            GoalProgressBar(
              progress: metrics.percentageComplete,
              color: goalStatusColor(metrics.status),
              semanticsLabel: metrics.status.label,
            ),
            SizedBox(height: AppSpacing.md),
            GoalDetailValue(
              label: 'Goal type',
              value: goalTypeLabel(goal.goalType),
              icon: goal.goalType == GoalType.maintainBalance
                  ? AppIcon.shield
                  : AppIcon.goal,
            ),
            GoalDetailValue(
              label: 'Status',
              value: goal.isCompleted
                  ? 'Completed'
                  : goal.isArchived
                  ? 'Archived'
                  : metrics.status.label,
              icon: AppIcon.insights,
            ),
            if (goal.isCompleted && goal.completedAt != null)
              GoalDetailValue(
                label: 'Completed',
                value: fullMonthDateLabel(goal.completedAt!),
                icon: AppIcon.success,
              ),
            if (goal.isArchived && goal.archivedAt != null)
              GoalDetailValue(
                label: 'Archived',
                value: fullMonthDateLabel(goal.archivedAt!),
                icon: AppIcon.archive,
              ),
            if (goal.targetDate != null)
              GoalDetailValue(
                label: goalDateLabel(goal),
                value: fullMonthDateLabel(goal.targetDate!),
                icon: AppIcon.calendar,
              ),
            if (goal.targetDate != null && goal.isActive)
              GoalDetailValue(
                label: 'Required',
                value:
                    '${money(metrics.requiredWeeklyMinor, store.preferences.currency)}/week ${goal.goalType == GoalType.maintainBalance ? 'to restore' : 'needed'}\nAbout ${money(metrics.requiredMonthlyMinor, store.preferences.currency)}/month ${goal.goalType == GoalType.maintainBalance ? 'to restore' : 'needed'}',
                helperText:
                    'Based on the remaining amount and ${goal.goalType == GoalType.maintainBalance ? 'restore-by' : 'target'} date',
                icon: AppIcon.trend,
              ),
            GoalDetailValue(
              label: goal.goalType == GoalType.maintainBalance
                  ? 'Reserve balance'
                  : 'Ahead / behind',
              value: goal.goalType == GoalType.maintainBalance
                  ? metrics.aheadBehindMinor >= 0
                        ? '${money(metrics.aheadBehindMinor, store.preferences.currency)} above reserve target'
                        : '${money(metrics.aheadBehindMinor.abs(), store.preferences.currency)} below reserve target'
                  : metrics.aheadBehindMinor >= 0
                  ? '${money(metrics.aheadBehindMinor, store.preferences.currency)} ahead'
                  : '${money(metrics.aheadBehindMinor.abs(), store.preferences.currency)} behind',
              icon: AppIcon.adjustment,
            ),
            if (goal.description.trim().isNotEmpty)
              GoalDetailValue(
                label: 'Description',
                value: goal.description,
                icon: AppIcon.notes,
              ),
            const TransactionFormDivider(),
            Text(
              'Activity',
              style: Theme.of(
                dialogContext,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (goalTransactions.isEmpty &&
                contributions.isEmpty &&
                fundingEvents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('No activity yet'),
              )
            else ...[
              for (final transaction in goalTransactions.take(20))
                LedgerJournalRow(
                  projection: LedgerTransactionProjection(
                    transaction: transaction,
                    // Goal activity is an account-specific view. A transfer
                    // into a Goal is positive here; a transfer out is
                    // negative, regardless of which side owns the original
                    // transaction record.
                    displayedAmountMinor: transaction.deltaForAccount(
                      goal.accountId!,
                    ),
                    matchingAllocations: const [],
                  ),
                  currency: store.preferences.currency,
                  account:
                      goalTransactionCounterpartyAccount(
                        transaction,
                        goal.accountId!,
                        store.accounts,
                      ) ??
                      store.accounts
                          .where(
                            (account) => account.id == transaction.accountId,
                          )
                          .firstOrNull,
                  category: transaction.categoryId == null
                      ? null
                      : store.categories
                            .where(
                              (category) =>
                                  category.id == transaction.categoryId,
                            )
                            .firstOrNull,
                  categoryName: transaction.categoryId == null
                      ? null
                      : store.categories
                            .where(
                              (category) =>
                                  category.id == transaction.categoryId,
                            )
                            .firstOrNull
                            ?.name,
                  onTap: () =>
                      showTransactionDetails(dialogContext, transaction.id),
                  onLongPress: () {
                    AppHaptics.longPressAction();
                    unawaited(
                      showTransactionOptions(dialogContext, transaction.id),
                    );
                  },
                ),
              for (final event in fundingEvents.take(20))
                GoalFundingHistoryRow(
                  event: event,
                  goalId: goal.id,
                  onTap: () => showGoalFundingDetails(context, event.id),
                ),
              for (final contribution in contributions.take(20))
                GoalContributionRow(
                  contribution: contribution,
                  onTap: () =>
                      showGoalContributionDetails(context, contribution.id),
                ),
            ],
            if (goal.isActive) ...[
              const TransactionFormDivider(),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('goal-details-complete'),
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        final replenishing =
                            goal.goalType == GoalType.maintainBalance;
                        final confirmed = await showGoalConfirmation(
                          context,
                          title: replenishing
                              ? 'Complete this replenishing Goal?'
                              : 'Mark Goal complete?',
                          message: replenishing
                              ? 'This Goal is designed to be maintained and replenished. Completing it will remove it from active Goals, but its history will remain available.'
                              : 'This marks the Goal complete and preserves its contribution history.',
                          confirmLabel: 'Mark Complete',
                        );
                        if (confirmed) await store.markGoalComplete(goal.id);
                      },
                      icon: Icon(AppIcon.success),
                      label: const Text('Mark Complete'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('goal-details-archive'),
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        final confirmed = await showGoalConfirmation(
                          context,
                          title: 'Archive Goal?',
                          message:
                              store.scheduledGoalFundingNeedsAttention(goal.id)
                              ? 'This Goal has scheduled future funding. Archiving it will block those occurrences until you restore this Goal or update the schedule. Existing history remains unchanged.'
                              : store.currentGoalAmountMinor(goal.id) > 0
                              ? 'The Goal balance will remain an asset in this archived Goal. Restore it later to manage or fund it again.'
                              : 'This preserves the Goal history and stops new funding or progress.',
                          confirmLabel: 'Archive Goal',
                          destructive: true,
                        );
                        if (confirmed) await store.archiveGoal(goal.id);
                      },
                      icon: Icon(AppIcon.archive),
                      label: const Text('Archive'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const TransactionFormDivider(),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                children: [
                  TextButton.icon(
                    key: const ValueKey('goal-details-restore'),
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      final confirmed = await showGoalConfirmation(
                        context,
                        title: 'Restore Goal?',
                        message:
                            'This restores the Goal as active. Its balance and history remain unchanged; scheduled funding is not reactivated automatically.',
                        confirmLabel: 'Restore as Active',
                      );
                      if (!confirmed) return;
                      try {
                        await store.restoreGoal(goal.id);
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    },
                    icon: Icon(AppIcon.unarchive),
                    label: Text(
                      goal.isCompleted ? 'Restore as Active' : 'Restore',
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('goal-details-duplicate'),
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await store.duplicateGoal(goal.id);
                    },
                    icon: Icon(AppIcon.copy),
                    label: const Text('Duplicate'),
                  ),
                  if (store.goalDeleteEligibility(goal.id).canDelete)
                    TextButton.icon(
                      key: const ValueKey('goal-details-delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        final confirmed = await showGoalConfirmation(
                          context,
                          title: 'Delete this Goal permanently?',
                          message:
                              'This Goal has no remaining balance or pending scheduled activity. Ledger history, if any, will remain available.',
                          confirmLabel: 'Delete Permanently',
                          destructive: true,
                        );
                        if (confirmed) {
                          await store.deleteGoalPermanently(goal.id);
                        }
                      },
                      icon: Icon(AppIcon.delete),
                      label: const Text('Delete Permanently'),
                    ),
                  if (!store.goalDeleteEligibility(goal.id).canDelete)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        goalDeletionBlockedMessage(
                          store.goalDeleteEligibility(goal.id),
                          store.preferences.currency,
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

String goalDeletionBlockedMessage(
  GoalDeleteEligibility eligibility,
  CurrencyFormatSettings currency,
) {
  if (eligibility.hasNonZeroBalance) {
    if (eligibility.remainingBalanceMinor < 0) {
      return 'This Goal is ${money(eligibility.remainingBalanceMinor.abs(), currency)} below zero. Resolve or delete the related transactions before deleting this Goal.';
    }
    return 'Withdraw the remaining ${money(eligibility.remainingBalanceMinor.abs(), currency)} before deleting this Goal.';
  }
  if (eligibility.hasScheduledReference) {
    return 'Cancel the pending scheduled transfer before deleting this Goal.';
  }
  return 'This Goal cannot be deleted yet.';
}

v2_account.AccountRecord? goalTransactionCounterpartyAccount(
  TransactionRecord transaction,
  String goalAccountId,
  Iterable<v2_account.AccountRecord> accounts,
) {
  if (transaction.type != TransactionType.transfer) return null;
  final counterpartyId = transaction.accountId == goalAccountId
      ? transaction.transferAccountId
      : transaction.accountId;
  return accounts.where((account) => account.id == counterpartyId).firstOrNull;
}

class GoalDetailValue extends StatelessWidget {
  const GoalDetailValue({
    required this.label,
    required this.value,
    required this.icon,
    this.helperText,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TransactionFormIcon(icon, color: _goalBlue),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(value, style: Theme.of(context).textTheme.bodyLarge),
                if (helperText != null)
                  Text(
                    helperText!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GoalContributionRow extends StatelessWidget {
  const GoalContributionRow({
    required this.contribution,
    required this.onTap,
    super.key,
  });

  final GoalContributionRecord contribution;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final account = contribution.sourceAccountId == null
        ? null
        : store.accounts
              .where((item) => item.id == contribution.sourceAccountId)
              .firstOrNull;
    return ListTile(
      key: ValueKey('goal-contribution-${contribution.id}'),
      contentPadding: EdgeInsets.zero,
      leading: TransactionFormIcon(AppIcon.income, color: _goalBlue),
      title: Text(
        money(contribution.amountMinor, store.preferences.currency),
        style: const TextStyle(color: _goalBlue, fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        [
          compactDate(contribution.date),
          if (account != null) account.name,
          if (contribution.note.trim().isNotEmpty) contribution.note.trim(),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(AppIcon.chevronRight),
      onTap: onTap,
    );
  }
}

class GoalFundingHistoryRow extends StatelessWidget {
  const GoalFundingHistoryRow({
    required this.event,
    required this.goalId,
    required this.onTap,
    super.key,
  });

  final GoalFundingEventRecord event;
  final String goalId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final allocation = event.allocations
        .where((item) => item.goalId == goalId)
        .firstOrNull;
    final account = store.accounts
        .where((item) => item.id == event.sourceAccountId)
        .firstOrNull;
    if (allocation == null) return SizedBox.shrink();
    return ListTile(
      key: ValueKey('goal-funding-history-${event.id}-$goalId'),
      contentPadding: EdgeInsets.zero,
      leading: TransactionFormIcon(AppIcon.savings, color: _goalBlue),
      title: Text(
        money(allocation.amountMinor, store.preferences.currency),
        style: const TextStyle(color: _goalBlue, fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        [
          compactDate(event.date),
          if (account != null) account.name,
          if (event.allocations.length > 1) '${event.allocations.length} Goals',
          if (event.note.trim().isNotEmpty) event.note.trim(),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(AppIcon.chevronRight),
      onTap: onTap,
    );
  }
}

Future<void> showGoalFundingDetails(
  BuildContext context,
  String fundingEventId,
) async {
  final store = FinanceDataStoreScope.read(context);
  final event = store.goalFundingEvents
      .where((item) => item.id == fundingEventId && item.isActive)
      .firstOrNull;
  if (event == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This Goal funding is unavailable.')),
    );
    return;
  }
  final account = store.accounts
      .where((item) => item.id == event.sourceAccountId)
      .firstOrNull;
  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => TransactionSheetFrame(
      title: 'Goal Funding Details',
      actions: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton(
              key: const ValueKey('undo-goal-funding'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: account == null
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      final confirmed = await showGoalConfirmation(
                        context,
                        title: 'Undo goal funding?',
                        message:
                            'This restores ${money(event.totalAmountMinor, store.preferences.currency)} to ${account.name} and removes the linked allocations from the selected Goals.',
                        confirmLabel: 'Undo Funding',
                        destructive: true,
                      );
                      if (!confirmed) return;
                      try {
                        await store.undoGoalFunding(event.id);
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    },
              child: const Text('Undo Funding'),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GoalDetailValue(
            label: 'From Account',
            value: account?.name ?? 'Account unavailable',
            icon: AppIcon.bank,
          ),
          GoalDetailValue(
            label: 'Total',
            value: money(event.totalAmountMinor, store.preferences.currency),
            icon: AppIcon.savings,
          ),
          GoalDetailValue(
            label: 'Date',
            value: fullMonthDateLabel(event.date),
            icon: AppIcon.calendar,
          ),
          if (event.scheduledTransactionId != null)
            GoalDetailValue(
              label: 'Origin',
              value: 'Scheduled Goal Funding',
              icon: AppIcon.recurrence,
            ),
          const TransactionFormDivider(),
          Text(
            'Goal Allocations',
            style: Theme.of(
              dialogContext,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          for (final allocation in [
            ...event.allocations,
          ]..sort((left, right) => left.order.compareTo(right.order)))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(AppIcon.goal, color: _goalBlue),
              title: Text(
                store.goals
                        .where((goal) => goal.id == allocation.goalId)
                        .firstOrNull
                        ?.name ??
                    'Goal unavailable',
              ),
              trailing: Text(
                money(allocation.amountMinor, store.preferences.currency),
                style: const TextStyle(
                  color: _goalBlue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          if (event.note.trim().isNotEmpty)
            GoalDetailValue(
              label: 'Note',
              value: event.note,
              icon: AppIcon.notes,
            ),
          if (account == null)
            Text(
              'Restore the source account before undoing this funding.',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> showLegacyGoalMigrationSheet(
  BuildContext context,
  String goalId,
) async {
  final store = FinanceDataStoreScope.read(context);
  final goal = store.goals
      .where(
        (item) =>
            item.id == goalId &&
            !item.isDeleted &&
            item.requiresFundingMigration,
      )
      .firstOrNull;
  if (goal == null) return;
  var isSaving = false;
  String? errorText;
  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => TransactionSheetFrame(
        title: 'Convert Goal Funding',
        actions: OutlinedButton(
          onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
          child: const Text('Not Now'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              goal.name,
              style: Theme.of(
                dialogContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This Goal was created with the previous reservation model. Choose how its existing progress should work now.',
              style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: const ValueKey('migrate-goal-to-funding'),
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await store.migrateLegacyGoalToAccountFunding(goal.id);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              icon: Icon(AppIcon.bank),
              label: const Text('Move Saved Amount From Account'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Creates Goal funding and decreases each previously linked account exactly once.',
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('migrate-goal-to-tracking'),
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await store.migrateLegacyGoalToTrackingOnly(goal.id);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              icon: Icon(AppIcon.insights),
              label: const Text('Keep as Tracked Progress'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Keeps progress without changing any account or net worth.',
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              ),
            ),
            if (isSaving) ...[
              const SizedBox(height: AppSpacing.md),
              const Center(child: CircularProgressIndicator()),
            ],
            if (errorText != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                errorText!,
                key: const ValueKey('goal-migration-error'),
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> showGoalContributionDetails(
  BuildContext context,
  String contributionId,
) async {
  final store = FinanceDataStoreScope.read(context);
  final contribution = store.goalContributions
      .where((item) => item.id == contributionId && item.isActive)
      .firstOrNull;
  if (contribution == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This contribution is no longer available.'),
      ),
    );
    return;
  }
  final goal = store.goals
      .where((item) => item.id == contribution.goalId && !item.isDeleted)
      .firstOrNull;
  if (goal == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The linked Goal is no longer available.')),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) {
      final account = contribution.sourceAccountId == null
          ? null
          : store.accounts
                .where((item) => item.id == contribution.sourceAccountId)
                .firstOrNull;
      return TransactionSheetFrame(
        title: 'Progress Details',
        actions: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FilledButton(
                key: const ValueKey('undo-goal-contribution'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final confirmed = await showGoalConfirmation(
                    context,
                    title: 'Undo Goal progress?',
                    message:
                        'This removes ${money(contribution.amountMinor, store.preferences.currency)} of tracked progress from ${goal.name}.',
                    confirmLabel: 'Undo Progress',
                    destructive: true,
                  );
                  if (!confirmed) return;
                  try {
                    await store.undoGoalContribution(contribution.id);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                child: const Text('Undo Progress'),
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GoalDetailValue(
              label: 'Goal',
              value: goal.name,
              icon: AppIcon.goal,
            ),
            GoalDetailValue(
              label: 'Amount',
              value: money(
                contribution.amountMinor,
                store.preferences.currency,
              ),
              icon: AppIcon.income,
            ),
            GoalDetailValue(
              label: 'Date',
              value: fullMonthDateLabel(contribution.date),
              icon: AppIcon.calendar,
            ),
            GoalDetailValue(
              label: 'Type',
              value: account == null
                  ? 'Tracked progress'
                  : 'Legacy progress · ${account.name}',
              icon: AppIcon.insights,
            ),
            if (contribution.note.trim().isNotEmpty)
              GoalDetailValue(
                label: 'Note',
                value: contribution.note,
                icon: AppIcon.notes,
              ),
          ],
        ),
      );
    },
  );
}

Future<bool> showGoalConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  return await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(
                        dialogContext,
                      ).colorScheme.error,
                    )
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> confirmDeleteGoalFundingAccount(
  BuildContext context, {
  required v2_account.AccountRecord account,
  required int fundedMinor,
}) {
  final store = FinanceDataStoreScope.read(context);
  return showGoalConfirmation(
    context,
    title: 'Delete funding account?',
    message:
        '${account.name} is linked to Goal funding${fundedMinor > 0 ? ' totaling ${money(fundedMinor, store.preferences.currency)}' : ''}. Goal balances and history will remain, but this funding cannot be undone and new funding will need another account until the Goal is repaired.',
    confirmLabel: 'Delete Account',
    destructive: true,
  );
}

enum CalendarActivityType { income, expense, transfer, goal }

class GoalCalendarActivity {
  const GoalCalendarActivity.progress({
    required GoalRecord this.goal,
    required GoalContributionRecord this.contribution,
  }) : fundingEvent = null;

  const GoalCalendarActivity.funding({
    required GoalFundingEventRecord this.fundingEvent,
  }) : goal = null,
       contribution = null;

  final GoalRecord? goal;
  final GoalContributionRecord? contribution;
  final GoalFundingEventRecord? fundingEvent;

  DateTime get date => fundingEvent?.date ?? contribution!.date;
  CalendarActivityType get type => CalendarActivityType.goal;
}

List<GoalCalendarActivity> goalCalendarActivitiesForMonth(
  Iterable<GoalRecord> goals,
  Iterable<GoalContributionRecord> contributions,
  Iterable<GoalFundingEventRecord> fundingEvents,
  DateTime month,
) {
  final start = calendarDateKey(DateTime(month.year, month.month));
  final end = calendarDateKey(DateTime(month.year, month.month + 1));
  final goalsById = {
    for (final goal in goals)
      if (!goal.isDeleted) goal.id: goal,
  };
  final activities = <GoalCalendarActivity>[
    for (final contribution in contributions)
      if (contribution.isActive &&
          goalsById.containsKey(contribution.goalId) &&
          !calendarDateKey(contribution.date).isBefore(start) &&
          calendarDateKey(contribution.date).isBefore(end))
        GoalCalendarActivity.progress(
          goal: goalsById[contribution.goalId]!,
          contribution: contribution,
        ),
    for (final event in fundingEvents)
      if (event.isActive &&
          !calendarDateKey(event.date).isBefore(start) &&
          calendarDateKey(event.date).isBefore(end))
        GoalCalendarActivity.funding(fundingEvent: event),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return activities;
}

Map<DateTime, List<GoalCalendarActivity>> goalActivitiesByDate(
  Iterable<GoalCalendarActivity> activities,
) {
  final grouped = <DateTime, List<GoalCalendarActivity>>{};
  for (final activity in activities) {
    final date = calendarDateKey(activity.date);
    grouped.putIfAbsent(date, () => []).add(activity);
  }
  return grouped;
}

class GoalCalendarActivityRow extends StatelessWidget {
  const GoalCalendarActivityRow({
    required this.activity,
    required this.currency,
    super.key,
  });

  final GoalCalendarActivity activity;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final isFunding = activity.fundingEvent != null;
    final id = activity.fundingEvent?.id ?? activity.contribution!.id;
    final amount =
        activity.fundingEvent?.totalAmountMinor ??
        activity.contribution!.amountMinor;
    return ListTile(
      key: ValueKey('goal-calendar-$id'),
      leading: TransactionFormIcon(AppIcon.goal, color: _goalBlue),
      title: Text(
        isFunding ? 'Funded Goals' : activity.goal!.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        isFunding
            ? '${activity.fundingEvent!.allocations.length} Goal${activity.fundingEvent!.allocations.length == 1 ? '' : 's'}'
            : 'Goal progress',
      ),
      trailing: Text(
        money(amount, currency),
        style: const TextStyle(
          color: _goalBlue,
          fontSize: 17,
          fontWeight: FontWeight.w900,
          fontFeatures: [AppTextStyles.tabularFigures],
        ),
      ),
      onTap: () => isFunding
          ? showGoalFundingDetails(context, activity.fundingEvent!.id)
          : showGoalContributionDetails(context, activity.contribution!.id),
    );
  }
}
