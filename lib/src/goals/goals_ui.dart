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

String goalDateLabel(GoalRecord goal) {
  return goal.goalType == GoalType.maintainBalance
      ? 'Restore-by date'
      : 'Target date';
}

String goalFundingMethodLabel(GoalFundingMethod method) {
  return switch (method) {
    GoalFundingMethod.accountFunded => 'Move money from an account',
    GoalFundingMethod.trackingOnly => 'Track progress only',
  };
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
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: preview.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CompactEmptyRow(
                  icon: Icons.flag_outlined,
                  label: 'No goals yet',
                ),
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
                    key: const ValueKey('dashboard-create-goal'),
                    onPressed: onCreate ?? () => showCreateGoalSheet(context),
                    icon: const Icon(Icons.add, size: 17),
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
                    key: const ValueKey('dashboard-view-all-goals'),
                    onPressed: onViewAll ?? () => openGoalsPage(context),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward, size: 17),
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

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class GoalsPlanContent extends StatelessWidget {
  const GoalsPlanContent({
    required this.completedExpanded,
    required this.archivedExpanded,
    required this.onCompletedToggle,
    required this.onArchivedToggle,
    super.key,
  });

  final bool completedExpanded;
  final bool archivedExpanded;
  final VoidCallback onCompletedToggle;
  final VoidCallback onArchivedToggle;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final active = store.goals.where((goal) => goal.isActive).toList()
      ..sort(compareGoalUrgency);
    final completed = store.goals.where((goal) => goal.isCompleted).toList()
      ..sort((a, b) => b.updatedDate.compareTo(a.updatedDate));
    final archived = store.goals.where((goal) => goal.isArchived).toList()
      ..sort((a, b) => b.updatedDate.compareTo(a.updatedDate));
    final hasGoals =
        active.isNotEmpty || completed.isNotEmpty || archived.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('plan-create-goal'),
                  onPressed: () => showCreateGoalSheet(context),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Create Goal'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('plan-fund-goals'),
                  onPressed:
                      active.any(
                        (goal) =>
                            goal.fundingMethod ==
                                GoalFundingMethod.accountFunded &&
                            !goal.requiresFundingMigration,
                      )
                      ? () => showFundGoalsSheet(context)
                      : null,
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Fund Goals'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (!hasGoals)
          AppCard(
            child: Column(
              children: [
                const TransactionFormIcon(
                  Icons.flag_outlined,
                  color: _goalBlue,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'No goals yet',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Set a target and track your progress over time.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else ...[
          for (final goal in active) ...[
            GoalCard(goal: goal),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (completed.isNotEmpty)
            GoalCollapsibleSection(
              key: const ValueKey('plan-completed-goals-section'),
              title: 'Completed',
              count: completed.length,
              expanded: completedExpanded,
              onToggle: onCompletedToggle,
              goals: completed,
            ),
          if (archived.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            GoalCollapsibleSection(
              key: const ValueKey('plan-archived-goals-section'),
              title: 'Archived',
              count: archived.length,
              expanded: archivedExpanded,
              onToggle: onArchivedToggle,
              goals: archived,
            ),
          ],
        ],
      ],
    );
  }
}

class _GoalsPageState extends State<GoalsPage> {
  var _completedExpanded = false;
  var _archivedExpanded = false;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final active = store.goals.where((goal) => goal.isActive).toList()
      ..sort(compareGoalUrgency);
    final completed = store.goals.where((goal) => goal.isCompleted).toList()
      ..sort((a, b) => b.updatedDate.compareTo(a.updatedDate));
    final archived = store.goals.where((goal) => goal.isArchived).toList()
      ..sort((a, b) => b.updatedDate.compareTo(a.updatedDate));
    final hasGoals =
        active.isNotEmpty || completed.isNotEmpty || archived.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goals'),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            key: const ValueKey('goals-add'),
            tooltip: 'Add Goal',
            onPressed: () => showCreateGoalSheet(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (!hasGoals)
              AppCard(
                child: Column(
                  children: [
                    const TransactionFormIcon(
                      Icons.flag_outlined,
                      color: _goalBlue,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No goals yet',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Set a target and track your progress over time.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      key: const ValueKey('goals-empty-create'),
                      onPressed: () => showCreateGoalSheet(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Goal'),
                    ),
                  ],
                ),
              )
            else ...[
              for (final goal in active) ...[
                GoalCard(goal: goal),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (completed.isNotEmpty)
                GoalCollapsibleSection(
                  key: const ValueKey('completed-goals-section'),
                  title: 'Completed',
                  count: completed.length,
                  expanded: _completedExpanded,
                  onToggle: () =>
                      setState(() => _completedExpanded = !_completedExpanded),
                  goals: completed,
                ),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                GoalCollapsibleSection(
                  key: const ValueKey('archived-goals-section'),
                  title: 'Archived',
                  count: archived.length,
                  expanded: _archivedExpanded,
                  onToggle: () =>
                      setState(() => _archivedExpanded = !_archivedExpanded),
                  goals: archived,
                ),
              ],
            ],
          ],
        ),
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
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            trailing: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 160),
              child: const Icon(Icons.keyboard_arrow_down),
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
    final account = goal.defaultFundingAccountId == null
        ? null
        : store.accounts
              .where((item) => item.id == goal.defaultFundingAccountId)
              .firstOrNull;
    final needsAttention =
        goal.fundingMethod == GoalFundingMethod.accountFunded &&
        (account == null ||
            !account.isVisible ||
            goal.requiresFundingMigration);
    return Card(
      child: InkWell(
        key: ValueKey('goal-card-${goal.id}'),
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () => showGoalDetails(context, goal.id),
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
                  const Icon(Icons.chevron_right),
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
                      needsAttention ? 'Needs attention' : metrics.status.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: needsAttention ? AppColors.danger : statusColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (!compact && goal.isActive)
                    TextButton(
                      key: ValueKey('goal-add-contribution-${goal.id}'),
                      onPressed: goal.requiresFundingMigration
                          ? () => showLegacyGoalMigrationSheet(context, goal.id)
                          : needsAttention
                          ? null
                          : () =>
                                goal.fundingMethod ==
                                    GoalFundingMethod.accountFunded
                                ? showFundGoalsSheet(
                                    context,
                                    initialGoalId: goal.id,
                                  )
                                : showAddGoalContributionSheet(
                                    context,
                                    goal.id,
                                  ),
                      child: Text(
                        goal.requiresFundingMigration
                            ? 'Convert'
                            : goal.fundingMethod ==
                                  GoalFundingMethod.accountFunded
                            ? 'Fund Goal'
                            : 'Add Progress',
                      ),
                    ),
                ],
              ),
              if (!compact) ...[
                if (goal.targetDate != null)
                  Text(
                    '${goal.goalType == GoalType.maintainBalance ? 'Restore by' : 'Target'}: ${fullMonthDateLabel(goal.targetDate!)}',
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
                Text(
                  account == null
                      ? goalFundingMethodLabel(goal.fundingMethod)
                      : '${goalFundingMethodLabel(goal.fundingMethod)} · ${account.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
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
  var startingMinor = initialGoal?.startingAmountMinor ?? 0;
  var targetDate = initialGoal?.targetDate;
  var goalType = initialGoal?.goalType ?? GoalType.reachTarget;
  var method = initialGoal?.fundingMethod ?? GoalFundingMethod.accountFunded;
  var accountId =
      initialGoal?.defaultFundingAccountId ??
      store.activeAccountsInDisplayOrder.firstOrNull?.id;
  var isSaving = false;
  String? errorText;

  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final activeAccounts = store.activeAccountsInDisplayOrder;
        final account = activeAccounts
            .where((item) => item.id == accountId)
            .firstOrNull;
        final isEditing = initialGoal != null;
        final validDate =
            isEditing ||
            targetDate == null ||
            startingMinor >= targetMinor ||
            !targetDate!.isBefore(
              DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day + (isEditing ? 0 : 1),
              ),
            );
        final startingAmountFits =
            method == GoalFundingMethod.trackingOnly ||
            account == null ||
            isEditing ||
            startingMinor <= store.balanceForAccount(account.id);
        final canSave =
            nameController.text.trim().isNotEmpty &&
            targetMinor > 0 &&
            startingMinor >= 0 &&
            startingMinor <= targetMinor &&
            validDate &&
            startingAmountFits &&
            (method == GoalFundingMethod.trackingOnly || account != null);

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
                      startingAmountMinor: startingMinor,
                      targetDate: targetDate,
                      fundingMethod: method,
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
                        startingAmountMinor: startingMinor,
                        targetDate: targetDate,
                        goalType: goalType,
                        fundingMethod: method,
                        defaultFundingAccountId: accountId,
                        clearTargetDate: targetDate == null,
                        clearDefaultFundingAccount:
                            method == GoalFundingMethod.trackingOnly,
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
                const TransactionFormLabel('Goal name'),
                Row(
                  children: [
                    const TransactionFormIcon(
                      Icons.flag_outlined,
                      color: _goalBlue,
                    ),
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
                const TransactionFormDivider(),
                const TransactionFormLabel('Goal type'),
                PolishedFormValueRow(
                  key: const ValueKey('goal-type'),
                  icon: goalType == GoalType.reachTarget
                      ? Icons.flag_outlined
                      : Icons.shield_outlined,
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
                                  ? Icons.flag_outlined
                                  : Icons.shield_outlined,
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
                const TransactionFormDivider(),
                const TransactionFormLabel('Target amount'),
                Row(
                  children: [
                    const TransactionFormIcon(Icons.track_changes_outlined),
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
                const TransactionFormLabel('Starting amount'),
                Row(
                  children: [
                    const TransactionFormIcon(Icons.savings_outlined),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AmountEntryField(
                        fieldKey: const ValueKey('goal-starting-amount'),
                        initialMinor: startingMinor,
                        currency: store.preferences.currency,
                        labelText: null,
                        onChanged: (value) =>
                            setDialogState(() => startingMinor = value.abs()),
                      ),
                    ),
                  ],
                ),
                const TransactionFormDivider(),
                TransactionFormLabel(
                  goalType == GoalType.maintainBalance
                      ? 'Restore-by date'
                      : 'Target date',
                ),
                PolishedFormValueRow(
                  key: const ValueKey('goal-target-date'),
                  icon: Icons.calendar_today_outlined,
                  value: targetDate == null
                      ? goalType == GoalType.maintainBalance
                            ? 'No restore-by date'
                            : 'No target date'
                      : fullMonthDateLabel(targetDate!),
                  secondary: goalType == GoalType.maintainBalance
                      ? 'Optional date to replenish a reserve below target'
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
                const TransactionFormDivider(),
                const TransactionFormLabel('Funding method'),
                PolishedFormValueRow(
                  key: const ValueKey('goal-funding-method'),
                  icon: Icons.account_balance_wallet_outlined,
                  value: goalFundingMethodLabel(method),
                  onTap: () async {
                    final selected =
                        await showPolishedChoicePicker<GoalFundingMethod>(
                          dialogContext,
                          title: 'Funding method',
                          selected: method,
                          choices: [
                            for (final option in GoalFundingMethod.values)
                              PolishedChoice(
                                value: option,
                                label: goalFundingMethodLabel(option),
                                leading: Icon(
                                  option == GoalFundingMethod.accountFunded
                                      ? Icons.account_balance_outlined
                                      : Icons.insights_outlined,
                                ),
                              ),
                          ],
                        );
                    if (selected == null || selected == method) return;
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
                        setDialogState(() {
                          errorText =
                              'Undo existing funding or progress before changing the funding method.';
                        });
                        return;
                      }
                    }
                    setDialogState(() {
                      method = selected;
                      if (method == GoalFundingMethod.accountFunded) {
                        accountId ??= activeAccounts.firstOrNull?.id;
                      }
                    });
                  },
                ),
                if (method == GoalFundingMethod.accountFunded) ...[
                  const TransactionFormDivider(),
                  const TransactionFormLabel('Funding account'),
                  PolishedFormValueRow(
                    key: const ValueKey('goal-funding-account'),
                    icon: Icons.account_balance_outlined,
                    value: account?.name ?? 'Choose account',
                    secondary: account == null
                        ? null
                        : 'Balance ${money(store.balanceForAccount(account.id), store.preferences.currency)}',
                    onTap: () async {
                      final selected = await showTransactionAccountPicker(
                        dialogContext,
                        accounts: activeAccounts,
                        selectedAccountId: accountId ?? '',
                      );
                      if (selected != null) {
                        setDialogState(() => accountId = selected);
                      }
                    },
                  ),
                ],
                if (!isEditing &&
                    method == GoalFundingMethod.accountFunded &&
                    startingMinor > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${money(startingMinor, store.preferences.currency)} will be moved from ${account?.name ?? 'the selected account'} when this Goal is created.',
                    key: const ValueKey('goal-starting-funding-explanation'),
                    style: Theme.of(dialogContext).textTheme.bodySmall
                        ?.copyWith(
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const TransactionFormDivider(),
                const TransactionFormLabel('Description'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TransactionFormIcon(Icons.notes_outlined),
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
                if (!startingAmountFits) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Starting amount exceeds this account’s current balance.',
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
            if (onTap != null) const Icon(Icons.keyboard_arrow_down),
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
          .where(
            (goal) =>
                goal.isActive &&
                goal.fundingMethod == GoalFundingMethod.accountFunded &&
                !goal.requiresFundingMigration,
          )
          .toList(growable: false)
        ..sort(compareGoalUrgency);
  if (eligibleGoals.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Create or convert an account-funded Goal first.'),
      ),
    );
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
                const TransactionFormLabel('From Account'),
                PolishedFormValueRow(
                  key: const ValueKey('fund-goals-account'),
                  icon: Icons.account_balance_outlined,
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
                const TransactionFormDivider(),
                const TransactionFormLabel('Total Amount'),
                Row(
                  children: [
                    const TransactionFormIcon(
                      Icons.savings_outlined,
                      color: _goalBlue,
                    ),
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
                          flex: 6,
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
                                            leading: const Icon(
                                              Icons.flag_outlined,
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
                                style: Theme.of(
                                  dialogContext,
                                ).textTheme.bodyLarge,
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
                              'fund-goals-amount-${allocations[index].id}',
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
                        if (allocations.length > 1)
                          IconButton(
                            tooltip: 'Remove Goal allocation',
                            onPressed: () => setDialogState(() {
                              allocations.removeAt(index);
                              rebalanceFirst();
                            }),
                            icon: const Icon(Icons.remove_circle_outline),
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
                    icon: const Icon(Icons.add),
                    label: const Text('Add Goal'),
                  ),
                ),
                GoalAllocationSummary(
                  totalAmountMinor: totalAmountMinor,
                  allocatedAmountMinor: allocatedTotal,
                  currency: store.preferences.currency,
                ),
                const TransactionFormDivider(),
                const TransactionFormLabel('Date'),
                PolishedFormValueRow(
                  key: const ValueKey('fund-goals-date'),
                  icon: Icons.calendar_today_outlined,
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
                const TransactionFormDivider(),
                const TransactionFormLabel('Note'),
                Row(
                  children: [
                    const TransactionFormIcon(Icons.notes_outlined),
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
  if (goal.fundingMethod == GoalFundingMethod.accountFunded) {
    await showFundGoalsSheet(context, initialGoalId: goal.id);
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
                const TransactionFormDivider(),
                const TransactionFormLabel('Progress amount'),
                Row(
                  children: [
                    const TransactionFormIcon(
                      Icons.add_circle_outline,
                      color: _goalBlue,
                    ),
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
                const TransactionFormDivider(),
                const TransactionFormLabel('Contribution date'),
                PolishedFormValueRow(
                  key: const ValueKey('goal-contribution-date'),
                  icon: Icons.calendar_today_outlined,
                  value: fullMonthDateLabel(date),
                  onTap: () async {
                    final selected = await pickDateForField(
                      dialogContext,
                      date,
                    );
                    if (selected != null) setDialogState(() => date = selected);
                  },
                ),
                const TransactionFormDivider(),
                const TransactionFormLabel('Note'),
                Row(
                  children: [
                    const TransactionFormIcon(Icons.notes_outlined),
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
      final contributions = [...store.activeContributionsForGoal(goal.id)]
        ..sort((a, b) => b.date.compareTo(a.date));
      final fundingEvents = [...store.activeFundingEventsForGoal(goal.id)]
        ..sort((a, b) => b.date.compareTo(a.date));
      final account = goal.defaultFundingAccountId == null
          ? null
          : store.accounts
                .where((item) => item.id == goal.defaultFundingAccountId)
                .firstOrNull;
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
            if (!goal.isDeleted)
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
                  if (goal.requiresFundingMigration) {
                    await showLegacyGoalMigrationSheet(context, goal.id);
                  } else if (goal.fundingMethod ==
                      GoalFundingMethod.accountFunded) {
                    await showFundGoalsSheet(context, initialGoalId: goal.id);
                  } else {
                    await showAddGoalContributionSheet(context, goal.id);
                  }
                },
                child: Text(
                  goal.requiresFundingMigration
                      ? 'Convert'
                      : goal.fundingMethod == GoalFundingMethod.accountFunded
                      ? 'Fund Goal'
                      : 'Add Progress',
                ),
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
            const SizedBox(height: AppSpacing.md),
            GoalDetailValue(
              label: 'Goal type',
              value: goalTypeLabel(goal.goalType),
              icon: goal.goalType == GoalType.maintainBalance
                  ? Icons.shield_outlined
                  : Icons.flag_outlined,
            ),
            GoalDetailValue(
              label: 'Status',
              value: metrics.status.label,
              icon: Icons.insights_outlined,
            ),
            if (goal.targetDate != null)
              GoalDetailValue(
                label: goalDateLabel(goal),
                value: fullMonthDateLabel(goal.targetDate!),
                icon: Icons.calendar_today_outlined,
              ),
            if (goal.targetDate != null && goal.isActive)
              GoalDetailValue(
                label: 'Required',
                value:
                    '${money(metrics.requiredWeeklyMinor, store.preferences.currency)}/week ${goal.goalType == GoalType.maintainBalance ? 'to restore' : 'needed'}\nAbout ${money(metrics.requiredMonthlyMinor, store.preferences.currency)}/month ${goal.goalType == GoalType.maintainBalance ? 'to restore' : 'needed'}',
                helperText:
                    'Based on the remaining amount and ${goal.goalType == GoalType.maintainBalance ? 'restore-by' : 'target'} date',
                icon: Icons.trending_up_outlined,
              ),
            GoalDetailValue(
              label: goal.goalType == GoalType.maintainBalance
                  ? 'Reserve position'
                  : 'Ahead / behind',
              value: goal.goalType == GoalType.maintainBalance
                  ? metrics.aheadBehindMinor >= 0
                        ? '${money(metrics.aheadBehindMinor, store.preferences.currency)} above reserve target'
                        : '${money(metrics.aheadBehindMinor.abs(), store.preferences.currency)} below reserve target'
                  : metrics.aheadBehindMinor >= 0
                  ? '${money(metrics.aheadBehindMinor, store.preferences.currency)} ahead'
                  : '${money(metrics.aheadBehindMinor.abs(), store.preferences.currency)} behind',
              icon: Icons.compare_arrows_outlined,
            ),
            GoalDetailValue(
              label: 'Funding',
              value: account == null
                  ? goalFundingMethodLabel(goal.fundingMethod)
                  : '${goalFundingMethodLabel(goal.fundingMethod)} · ${account.name}',
              icon: Icons.account_balance_wallet_outlined,
            ),
            if (goal.description.trim().isNotEmpty)
              GoalDetailValue(
                label: 'Description',
                value: goal.description,
                icon: Icons.notes_outlined,
              ),
            const TransactionFormDivider(),
            Text(
              'Funding and progress history',
              style: Theme.of(
                dialogContext,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (contributions.isEmpty && fundingEvents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('No activity yet'),
              )
            else ...[
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
            if (!goal.isArchived) ...[
              const TransactionFormDivider(),
              Row(
                children: [
                  if (goal.isActive && goal.goalType == GoalType.reachTarget)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          final confirmed = await showGoalConfirmation(
                            context,
                            title: 'Mark Goal complete?',
                            message:
                                'This marks the Goal complete and preserves its contribution history.',
                            confirmLabel: 'Mark Complete',
                          );
                          if (confirmed) {
                            await store.markGoalComplete(goal.id);
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline),
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
                          message: store.currentGoalAmountMinor(goal.id) > 0
                              ? 'The Goal balance will remain an asset in this archived Goal. Restore it later to manage or fund it again.'
                              : 'This preserves the Goal history and stops new funding or progress.',
                          confirmLabel: 'Keep Balance & Archive',
                          destructive: true,
                        );
                        if (confirmed) await store.archiveGoal(goal.id);
                      },
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Archive'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const TransactionFormDivider(),
              TextButton.icon(
                key: const ValueKey('goal-details-restore'),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final confirmed = await showGoalConfirmation(
                    context,
                    title: 'Restore Goal?',
                    message:
                        'This restores the Goal and allows new funding or progress again.',
                    confirmLabel: 'Restore Goal',
                  );
                  if (!confirmed) return;
                  try {
                    await store.restoreArchivedGoal(goal.id);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                icon: const Icon(Icons.unarchive_outlined),
                label: const Text('Restore Goal'),
              ),
            ],
          ],
        ),
      );
    },
  );
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
      leading: const TransactionFormIcon(
        Icons.add_circle_outline,
        color: _goalBlue,
      ),
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
      trailing: const Icon(Icons.chevron_right),
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
    if (allocation == null) return const SizedBox.shrink();
    return ListTile(
      key: ValueKey('goal-funding-history-${event.id}-$goalId'),
      contentPadding: EdgeInsets.zero,
      leading: const TransactionFormIcon(
        Icons.savings_outlined,
        color: _goalBlue,
      ),
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
      trailing: const Icon(Icons.chevron_right),
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
            icon: Icons.account_balance_outlined,
          ),
          GoalDetailValue(
            label: 'Total',
            value: money(event.totalAmountMinor, store.preferences.currency),
            icon: Icons.savings_outlined,
          ),
          GoalDetailValue(
            label: 'Date',
            value: fullMonthDateLabel(event.date),
            icon: Icons.calendar_today_outlined,
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
              leading: const Icon(Icons.flag_outlined, color: _goalBlue),
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
              icon: Icons.notes_outlined,
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
              icon: const Icon(Icons.account_balance_outlined),
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
              icon: const Icon(Icons.insights_outlined),
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
              icon: Icons.flag_outlined,
            ),
            GoalDetailValue(
              label: 'Amount',
              value: money(
                contribution.amountMinor,
                store.preferences.currency,
              ),
              icon: Icons.add_circle_outline,
            ),
            GoalDetailValue(
              label: 'Date',
              value: fullMonthDateLabel(contribution.date),
              icon: Icons.calendar_today_outlined,
            ),
            GoalDetailValue(
              label: 'Type',
              value: account == null
                  ? 'Tracked progress'
                  : 'Legacy progress · ${account.name}',
              icon: Icons.insights_outlined,
            ),
            if (contribution.note.trim().isNotEmpty)
              GoalDetailValue(
                label: 'Note',
                value: contribution.note,
                icon: Icons.notes_outlined,
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
      leading: const TransactionFormIcon(Icons.flag_outlined, color: _goalBlue),
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
