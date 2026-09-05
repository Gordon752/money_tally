part of '../../main.dart';

class FundTargetPresentation {
  const FundTargetPresentation({
    required this.status,
    required this.barProgress,
    required this.completedCycles,
    required this.activeCycleProgress,
    required this.showsMovingCycleBoundary,
    this.secondaryStatus,
    this.fundingDeadline,
  });

  final String status;
  final String? secondaryStatus;
  final DateTime? fundingDeadline;
  final double barProgress;
  final int completedCycles;
  final double activeCycleProgress;
  final bool showsMovingCycleBoundary;
}

FundTargetPresentation fundTargetPresentation({
  required FundRecord fund,
  required int currentMinor,
  required CurrencyFormatSettings currency,
  DateTime? asOf,
  RecurringFundCycleProgress? recurringCycleProgress,
}) {
  final target = fund.targetBalanceMinor;
  if (target <= 0) {
    return const FundTargetPresentation(
      status: 'No target set',
      barProgress: 0,
      completedCycles: 0,
      activeCycleProgress: 0,
      showsMovingCycleBoundary: false,
    );
  }
  final current = currentMinor.clamp(0, 0x7FFFFFFFFFFFFFFF).toInt();
  if (fund.targetCadence != FundTargetCadence.monthly) {
    if (current < target) {
      return FundTargetPresentation(
        status: '${money(target - current, currency)} needed to fully fund',
        barProgress: current / target,
        completedCycles: 0,
        activeCycleProgress: current / target,
        showsMovingCycleBoundary: false,
      );
    }
    if (current == target) {
      return const FundTargetPresentation(
        status: 'Target met',
        barProgress: 1,
        completedCycles: 0,
        activeCycleProgress: 0,
        showsMovingCycleBoundary: false,
      );
    }
    return FundTargetPresentation(
      status: '${money(current - target, currency)} above target',
      barProgress: 1,
      completedCycles: 0,
      activeCycleProgress: 0,
      showsMovingCycleBoundary: false,
    );
  }

  final cycle =
      recurringCycleProgress ??
      RecurringFundCycleProgress.fromReservation(
        fund: fund,
        reservedMinor: current,
        asOf: asOf,
      );
  final completedCycles = cycle.completedCycles;
  FundTargetPresentation presentation(String status, {String? secondary}) =>
      FundTargetPresentation(
        status: status,
        secondaryStatus: secondary,
        // There is no partial next cycle to label in an exact-funded state.
        fundingDeadline: cycle.isExactlyFunded
            ? null
            : cycle.activeCycleFundingDeadline,
        barProgress: cycle.barProgress,
        completedCycles: completedCycles,
        activeCycleProgress: cycle.activeCycleProgress,
        showsMovingCycleBoundary: cycle.showsMovingCycleBoundary,
      );
  if (completedCycles == 0) {
    return presentation(
      '${money(cycle.activeCycleRemainingMinor, currency)} needed to fully fund',
    );
  }
  if (completedCycles == 1 && cycle.isExactlyFunded) {
    return presentation('Target met');
  }

  final targetDate = cycle.currentCycleTargetDate;
  final currentCycle = targetDate == null
      ? 'Current cycle'
      : _fundMonthName(targetDate);
  if (cycle.isExactlyFunded) {
    return presentation('$completedCycles months fully funded');
  }
  final activeCycleDate = cycle.activeCycleTargetDate;
  final activeCycle = activeCycleDate == null
      ? 'Next cycle'
      : _fundMonthName(activeCycleDate);
  final activeCyclePercent = cycle.activeCyclePercent;
  final activeCycleRemaining = cycle.activeCycleRemainingMinor;
  final status = completedCycles == 1
      ? '$currentCycle fully funded · ${money(activeCycleRemaining, currency)} needed for $activeCycle'
      : '$completedCycles months fully funded · ${money(activeCycleRemaining, currency)} needed for $activeCycle';
  return presentation(
    status,
    secondary: '$activeCycle $activeCyclePercent% funded',
  );
}

String _fundMonthName(DateTime date) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][date.month - 1];

class FundTargetProgressBar extends StatelessWidget {
  const FundTargetProgressBar({
    required this.presentation,
    required this.color,
    this.minHeight = 6,
    super.key,
  });

  final FundTargetPresentation presentation;
  final Color color;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surfaceContainerHighest;
    if (!presentation.showsMovingCycleBoundary) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: LinearProgressIndicator(
          minHeight: minHeight,
          value: presentation.barProgress.clamp(0.0, 1.0),
          color: color,
          backgroundColor: background,
        ),
      );
    }
    return Semantics(
      label: presentation.status,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: SizedBox(
          height: minHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(key: const ValueKey('fund-cycle-base'), color: color),
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  key: const ValueKey('fund-active-cycle-segment'),
                  widthFactor: presentation.activeCycleProgress.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color.lerp(color, background, 0.62),
                      border: Border(
                        left: BorderSide(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FundsPreviewCard extends StatelessWidget {
  const FundsPreviewCard({this.onViewAll, this.onCreate, super.key});

  final VoidCallback? onViewAll;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final funds = [...store.activeFunds]
      ..sort((left, right) => left.name.compareTo(right.name));
    final preview = funds.take(2).toList(growable: false);
    return AppCard(
      title: 'Funds',
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: preview.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CompactEmptyRow(icon: AppIcon.savings, label: 'No funds yet'),
                Padding(
                  padding: const EdgeInsets.only(left: 32, top: AppSpacing.xxs),
                  child: Text(
                    'Create a Fund to reserve money for upcoming needs.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('dashboard-create-fund'),
                    onPressed: onCreate ?? () => showFundEditor(context),
                    icon: Icon(AppIcon.add, size: AppIconSize.inline),
                    label: const Text('Create Fund'),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                for (var index = 0; index < preview.length; index++) ...[
                  FundPreviewRow(fund: preview[index]),
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
                    key: const ValueKey('dashboard-view-all-funds'),
                    onPressed: onViewAll,
                    iconAlignment: IconAlignment.end,
                    icon: Icon(AppIcon.arrowForward, size: AppIconSize.inline),
                    label: const Text('View All Funds'),
                  ),
                ),
              ],
            ),
    );
  }
}

class FundPreviewRow extends StatelessWidget {
  const FundPreviewRow({required this.fund, super.key});

  final FundRecord fund;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final cycleProgress = store.recurringFundCycleProgress(fund.id);
    final current = cycleProgress.reservedMinor;
    final target = fund.targetBalanceMinor;
    final targetPresentation = fundTargetPresentation(
      fund: fund,
      currentMinor: current,
      currency: store.preferences.currency,
      recurringCycleProgress: cycleProgress,
    );
    final status = targetPresentation.status;
    final secondaryStatus = targetPresentation.secondaryStatus;
    final accent = Color(fund.accentColorValue);
    return Semantics(
      button: true,
      label:
          '${fund.name}, ${money(current, store.preferences.currency)} available, $status${secondaryStatus == null ? '' : ', $secondaryStatus'}',
      child: InkWell(
        key: ValueKey('dashboard-fund-${fund.id}'),
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: () => showFundActions(context, fund.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fund.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${money(current, store.preferences.currency)} available',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFeatures: const [AppTextStyles.tabularFigures],
                ),
              ),
              if (target > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                FundTargetProgressBar(
                  presentation: targetPresentation,
                  color: accent,
                  minHeight: 5,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FundsPlanContent extends StatelessWidget {
  const FundsPlanContent({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final active = store.activeFunds;
    final archived = store.inactiveFunds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active.isEmpty)
          _FundsEmptyState(onCreate: () => showFundEditor(context))
        else ...[
          for (final fund in active) ...[
            FundPlanCard(fund: fund),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
        if (archived.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Archived',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final fund in archived)
            ListTile(
              onTap: () => showArchivedFundActions(context, fund.id),
              onLongPress: () {
                AppHaptics.longPressAction();
                unawaited(showArchivedFundActions(context, fund.id));
              },
              title: Text(fund.name),
              subtitle: Text(
                money(
                  store.currentFundAmountMinor(fund.id),
                  store.preferences.currency,
                ),
              ),
              trailing: Icon(AppIcon.chevronRight),
            ),
        ],
      ],
    );
  }
}

class _FundsEmptyState extends StatelessWidget {
  const _FundsEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        children: [
          Icon(AppIcon.savings, size: 32, color: AppTheme.accent),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Give existing money a job',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Funds reserve money inside a real account without changing its balance.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            key: const ValueKey('create-first-fund'),
            onPressed: onCreate,
            icon: Icon(AppIcon.add),
            label: const Text('Create Fund'),
          ),
        ],
      ),
    );
  }
}

class FundPlanCard extends StatelessWidget {
  const FundPlanCard({required this.fund, super.key});

  final FundRecord fund;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final cycleProgress = store.recurringFundCycleProgress(fund.id);
    final current = cycleProgress.reservedMinor;
    final target = fund.targetBalanceMinor;
    final accountName = store.accounts
        .where((account) => account.id == fund.fundingAccountId)
        .map((account) => account.name)
        .firstOrNull;
    final targetPresentation = fundTargetPresentation(
      fund: fund,
      currentMinor: current,
      currency: store.preferences.currency,
      recurringCycleProgress: cycleProgress,
    );
    final status = targetPresentation.status;
    final secondaryStatus = targetPresentation.secondaryStatus;
    final fundingDeadline = targetPresentation.fundingDeadline;
    final secondaryParts = <String>[
      ?secondaryStatus,
      if (fundingDeadline != null) 'Fund by ${shortDate(fundingDeadline)}',
    ];
    return Semantics(
      button: true,
      label:
          '${fund.name}, ${money(current, store.preferences.currency)} available, $status${secondaryStatus == null ? '' : ', $secondaryStatus'}',
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: InkWell(
          key: ValueKey('fund-card-${fund.id}'),
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: () => showFundActions(context, fund.id),
          onLongPress: () {
            AppHaptics.longPressAction();
            unawaited(showFundActions(context, fund.id));
          },
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(
                          fund.accentColorValue,
                        ).withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        AppIcon.savings,
                        color: Color(fund.accentColorValue),
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fund.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (accountName != null)
                            Text(
                              'Reserved from $accountName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    Icon(AppIcon.arrowForward, size: AppIconSize.inline),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${money(current, store.preferences.currency)} available',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [AppTextStyles.tabularFigures],
                  ),
                ),
                if (target > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  FundTargetProgressBar(
                    presentation: targetPresentation,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (secondaryParts.isNotEmpty)
                  Text(
                    secondaryParts.join(' · '),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showFundActions(BuildContext context, String fundId) async {
  final store = FinanceDataStoreScope.read(context);
  final fund = store.fundById(fundId);
  final current = store.currentFundAmountMinor(fundId);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                fund.name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                '${money(current, store.preferences.currency)} available',
              ),
            ),
            ListTile(
              leading: Icon(AppIcon.history),
              title: const Text('View Activity'),
              onTap: () => Navigator.pop(sheetContext, 'viewActivity'),
            ),
            ListTile(
              leading: Icon(AppIcon.add),
              title: const Text('Allocate'),
              subtitle: const Text(
                'Reserve more money from the funding account',
              ),
              onTap: () => Navigator.pop(sheetContext, 'allocate'),
            ),
            ListTile(
              enabled: current > 0,
              leading: Icon(AppIcon.expense),
              title: const Text('Spend from Fund'),
              subtitle: const Text(
                'Record a real transaction using this reserved money',
              ),
              onTap: current > 0
                  ? () => Navigator.pop(sheetContext, 'spend')
                  : null,
            ),
            ListTile(
              enabled: current > 0,
              leading: Icon(AppIcon.transfer),
              title: const Text('Return Reserved Money'),
              subtitle: const Text('Release reserved money back to available'),
              onTap: current > 0
                  ? () => Navigator.pop(sheetContext, 'return')
                  : null,
            ),
            ListTile(
              leading: Icon(AppIcon.schedule),
              title: const Text('Schedule Funding'),
              subtitle: const Text(
                'Allocate money automatically on a schedule',
              ),
              onTap: () => Navigator.pop(sheetContext, 'scheduleFunding'),
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
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case 'viewActivity':
      await showFundDetails(context, fundId);
    case 'allocate':
      await showFundAmountDialog(context, fundId: fundId, isReturn: false);
    case 'return':
      await showFundAmountDialog(context, fundId: fundId, isReturn: true);
    case 'scheduleFunding':
      await showScheduledFundFundingDialog(context, initialFundId: fundId);
    case 'spend':
      await showTransactionDialog(
        context,
        initialIsExpense: true,
        initialAccountId: fund.fundingAccountId,
        initialReservationContainerType: ReservationContainerType.fund,
        initialReservationContainerId: fund.id,
      );
    case 'edit':
      await showFundEditor(context, initialFund: fund);
    case 'archive':
      final linkedFunding = store.activeScheduledFundFundingForFund(fundId);
      if (linkedFunding.isNotEmpty) {
        await _showFundScheduledFundingBlocker(
          context,
          action: 'archived',
          linkedFunding: linkedFunding,
        );
        return;
      }
      try {
        await store.archiveFund(fundId);
      } on FinanceDataValidationException {
        final newlyLinkedFunding = store.activeScheduledFundFundingForFund(
          fundId,
        );
        if (newlyLinkedFunding.isEmpty || !context.mounted) rethrow;
        await _showFundScheduledFundingBlocker(
          context,
          action: 'archived',
          linkedFunding: newlyLinkedFunding,
        );
      }
    case 'delete':
      await _confirmAndDeleteFund(context, fundId);
  }
}

class _FundAllocationDraft {
  _FundAllocationDraft({required this.id, this.fundId}) : amountMinor = 0;

  final String id;
  String? fundId;
  int amountMinor;
  int revision = 0;
}

Future<void> showAllocateFundsSheet(BuildContext context) async {
  final store = FinanceDataStoreScope.read(context);
  final eligibleFunds = store.activeFunds.toList()
    ..sort((left, right) => left.name.compareTo(right.name));
  if (eligibleFunds.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Create a Fund first.')));
    return;
  }

  final fundingAccountIds = eligibleFunds
      .map((fund) => fund.fundingAccountId)
      .toSet();
  final eligibleAccounts = store.activeAccountsInDisplayOrder
      .where(
        (account) =>
            fundingAccountIds.contains(account.id) &&
            accountIsAsset(account) &&
            !account.isInternalGoalAccount,
      )
      .toList(growable: false);
  if (eligibleAccounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No active Fund funding account is available.'),
      ),
    );
    return;
  }

  var accountId = eligibleAccounts.first.id;
  var totalAmountMinor = 0;
  var date = DateTime.now();
  var isSaving = false;
  int? savingAvailableMinor;
  String? errorText;
  var draftSequence = 0;
  final noteController = TextEditingController();

  String? initialFundIdForAccount(String selectedAccountId) {
    final matches = eligibleFunds
        .where((fund) => fund.fundingAccountId == selectedAccountId)
        .toList(growable: false);
    return matches.length == 1 ? matches.single.id : null;
  }

  final allocations = <_FundAllocationDraft>[
    _FundAllocationDraft(
      id: 'allocate-funds-draft-${draftSequence++}',
      fundId: initialFundIdForAccount(accountId),
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
        final account = eligibleAccounts
            .where((candidate) => candidate.id == accountId)
            .firstOrNull;
        final accountFunds = eligibleFunds
            .where((fund) => fund.fundingAccountId == accountId)
            .toList(growable: false);
        final liveAccountAvailableMinor = account == null
            ? 0
            : store.availableToSpendForAccount(account.id);
        final accountAvailableMinor = isSaving && savingAvailableMinor != null
            ? savingAvailableMinor!
            : liveAccountAvailableMinor;
        final availableAfterAllocationMinor =
            accountAvailableMinor - totalAmountMinor;
        final allocatedTotal = allocations.fold<int>(
          0,
          (total, row) => total + row.amountMinor.abs(),
        );
        final remaining = totalAmountMinor - allocatedTotal;
        final selectedFundIds = allocations
            .map((row) => row.fundId)
            .whereType<String>()
            .toSet();
        final rowsValid =
            allocations.isNotEmpty &&
            allocations.every(
              (row) =>
                  row.fundId != null &&
                  row.amountMinor > 0 &&
                  accountFunds.any((fund) => fund.id == row.fundId),
            ) &&
            selectedFundIds.length == allocations.length;
        final amountFits =
            account != null && totalAmountMinor <= accountAvailableMinor;
        final canSave =
            totalAmountMinor > 0 && remaining == 0 && rowsValid && amountFits;

        return _GoalControllerOwner(
          controllers: [noteController],
          child: TransactionSheetFrame(
            title: 'Allocate to Funds',
            actions: TransactionFormActions(
              onCancel: () => Navigator.pop(dialogContext),
              canSave: canSave,
              isSaving: isSaving,
              saveLabel: 'Allocate',
              saveKey: const ValueKey('allocate-funds-save'),
              onSave: () async {
                if (isSaving || !canSave) return;
                setDialogState(() {
                  isSaving = true;
                  savingAvailableMinor = accountAvailableMinor;
                  errorText = null;
                });
                try {
                  await store.allocateFunds(
                    sourceAccountId: accountId,
                    totalAmountMinor: totalAmountMinor,
                    date: date,
                    note: noteController.text,
                    waitForRemote: false,
                    allocations: [
                      for (final allocation in allocations)
                        FundAllocation(
                          fundId: allocation.fundId!,
                          amountMinor: allocation.amountMinor,
                        ),
                    ],
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    isSaving = false;
                    savingAvailableMinor = null;
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
                  key: const ValueKey('allocate-funds-account'),
                  icon: AppIcon.bank,
                  value: account?.name ?? 'Choose account',
                  secondary: account == null
                      ? null
                      : 'Available to Spend ${money(accountAvailableMinor, store.preferences.currency)}',
                  onTap: eligibleAccounts.length < 2
                      ? null
                      : () async {
                          final selected = await showTransactionAccountPicker(
                            dialogContext,
                            accounts: eligibleAccounts,
                            selectedAccountId: accountId,
                          );
                          if (selected == null || selected == accountId) return;
                          setDialogState(() {
                            accountId = selected;
                            for (final allocation in allocations) {
                              final selectedFund = eligibleFunds
                                  .where((fund) => fund.id == allocation.fundId)
                                  .firstOrNull;
                              if (selectedFund?.fundingAccountId != selected) {
                                allocation.fundId = null;
                              }
                            }
                            if (allocations.length == 1 &&
                                allocations.first.fundId == null) {
                              allocations.first.fundId =
                                  initialFundIdForAccount(selected);
                            }
                            errorText = null;
                          });
                        },
                ),
                const TransactionFormDivider(),
                TransactionFormLabel('Total Amount'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.money),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AmountEntryField(
                        fieldKey: const ValueKey('allocate-funds-total'),
                        initialMinor: totalAmountMinor,
                        autofocus: true,
                        replaceZeroOnFirstInput: true,
                        currency: store.preferences.currency,
                        labelText: null,
                        onChanged: (value) => setDialogState(() {
                          totalAmountMinor = value.abs();
                          errorText = null;
                          rebalanceFirst();
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'After allocation · ${money(availableAfterAllocationMinor, store.preferences.currency)} available',
                  key: const ValueKey('allocate-funds-live-result'),
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    color: availableAfterAllocationMinor < 0
                        ? AppColors.warning
                        : Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (availableAfterAllocationMinor < 0) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'This exceeds the account’s available money.',
                    key: const ValueKey('allocate-funds-overcommit-warning'),
                    style: Theme.of(dialogContext).textTheme.bodySmall
                        ?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
                const TransactionFormDivider(),
                Text(
                  'Fund Allocations',
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
                              'allocate-funds-fund-${allocations[index].id}',
                            ),
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                            onTap: () async {
                              final selected =
                                  await showPolishedChoicePicker<String>(
                                    dialogContext,
                                    title: 'Choose Fund',
                                    selected: allocations[index].fundId ?? '',
                                    choices: [
                                      for (final fund in accountFunds)
                                        if (!selectedFundIds.contains(
                                              fund.id,
                                            ) ||
                                            allocations[index].fundId ==
                                                fund.id)
                                          PolishedChoice(
                                            value: fund.id,
                                            label: fund.name,
                                            leading: Icon(AppIcon.savings),
                                          ),
                                    ],
                                  );
                              if (selected != null) {
                                setDialogState(() {
                                  allocations[index].fundId = selected;
                                  errorText = null;
                                });
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                accountFunds
                                        .where(
                                          (fund) =>
                                              fund.id ==
                                              allocations[index].fundId,
                                        )
                                        .firstOrNull
                                        ?.name ??
                                    'Choose Fund',
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
                              'allocate-funds-amount-${allocations[index].id}',
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
                              errorText = null;
                              if (index > 0) rebalanceFirst();
                            }),
                          ),
                        ),
                        if (allocations.length > 1)
                          SizedBox(
                            width: 40,
                            child: IconButton(
                              key: ValueKey(
                                'allocate-funds-remove-${allocations[index].id}',
                              ),
                              padding: const EdgeInsets.all(AppSpacing.xxs),
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              tooltip: 'Remove Fund allocation',
                              onPressed: () => setDialogState(() {
                                allocations.removeAt(index);
                                errorText = null;
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
                    key: const ValueKey('allocate-funds-add-allocation'),
                    onPressed: allocations.length >= accountFunds.length
                        ? null
                        : () => setDialogState(() {
                            allocations.add(
                              _FundAllocationDraft(
                                id: 'allocate-funds-draft-${draftSequence++}',
                              ),
                            );
                            errorText = null;
                            rebalanceFirst();
                          }),
                    icon: Icon(AppIcon.add),
                    label: const Text(
                      'Add Fund',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                KeyedSubtree(
                  key: const ValueKey('allocate-funds-summary'),
                  child: GoalAllocationSummary(
                    totalAmountMinor: totalAmountMinor,
                    allocatedAmountMinor: allocatedTotal,
                    currency: store.preferences.currency,
                  ),
                ),
                const TransactionFormDivider(),
                TransactionFormLabel('Date'),
                PolishedFormValueRow(
                  key: const ValueKey('allocate-funds-date'),
                  icon: AppIcon.calendar,
                  value: fullMonthDateLabel(date),
                  onTap: () async {
                    final selected = await pickDateForField(
                      dialogContext,
                      date,
                    );
                    if (selected != null) {
                      setDialogState(() {
                        date = selected;
                        errorText = null;
                      });
                    }
                  },
                ),
                const TransactionFormDivider(),
                TransactionFormLabel('Note'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.notes),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('allocate-funds-note'),
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
                    'Allocation exceeds the selected account’s available money.',
                    key: const ValueKey('allocate-funds-amount-error'),
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
                    key: const ValueKey('allocate-funds-error'),
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

/// Stores a recurring reservation allocation for one Fund. Completing an
/// occurrence allocates money through the reservation engine; it does not
/// create a Ledger transaction or alter the funding account balance.
Future<bool> showScheduledFundFundingDialog(
  BuildContext context, {
  v2_scheduled.ScheduledTransactionRecord? existing,
  DateTime? initialDate,
  String? initialFundId,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final funds = store.activeFunds.toList(growable: false);
  final existingFundId =
      existing?.reservationFundingContainerType == ReservationContainerType.fund
      ? existing?.reservationFundingContainerId
      : null;
  var fundId =
      funds
          .where((item) => item.id == (existingFundId ?? initialFundId))
          .firstOrNull
          ?.id ??
      funds.firstOrNull?.id;
  if (fundId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create an active Fund first.')),
    );
    return false;
  }

  var amountMinor = existing?.amountMinor.abs() ?? 0;
  var startDate = existing?.nextDate ?? initialDate ?? DateTime.now();
  var frequency =
      existing?.frequency ?? v2_scheduled.RecurrenceFrequency.monthly;
  var alertPreference =
      existing?.alertPreference ?? v2_scheduled.AlertPreference.none;
  var customAlertTimeMinutes = existing?.customAlertTimeMinutes ?? 9 * 60;
  var repeatAlertUntilResolved = existing?.repeatAlertUntilResolved ?? false;
  var isSaving = false;
  String? errorText;
  final note = TextEditingController(text: existing?.note ?? '');

  final saved = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final fund = funds.where((item) => item.id == fundId).firstOrNull;
        final account = fund == null
            ? null
            : store.activeAccountsInDisplayOrder
                  .where(
                    (item) =>
                        item.id == fund.fundingAccountId &&
                        accountIsAsset(item) &&
                        !item.isInternalGoalAccount,
                  )
                  .firstOrNull;
        final canSave = fund != null && account != null && amountMinor > 0;
        return _GoalControllerOwner(
          controllers: [note],
          child: TransactionSheetFrame(
            title: existing == null
                ? 'Schedule Funding'
                : 'Edit Scheduled Funding',
            actions: TransactionFormActions(
              onCancel: () => Navigator.pop(dialogContext, false),
              canSave: canSave,
              isSaving: isSaving,
              saveLabel: 'Save',
              saveKey: const ValueKey('scheduled-fund-funding-save'),
              onSave: () async {
                if (isSaving || !canSave) return;
                setDialogState(() {
                  isSaving = true;
                  errorText = null;
                });
                try {
                  final record = v2_scheduled.ScheduledTransactionRecord(
                    id:
                        existing?.id ??
                        'scheduled_fund_${DateTime.now().microsecondsSinceEpoch}',
                    type: TransactionType.goalFunding,
                    accountId: account.id,
                    payee: fund.name,
                    note: note.text.trim(),
                    amountMinor: amountMinor,
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
                    goalFundingAllocations: const [],
                    reservationFundingContainerType:
                        ReservationContainerType.fund,
                    reservationFundingContainerId: fund.id,
                    occurrences: existing?.occurrences ?? const [],
                    occurrenceStates: existing?.occurrenceStates ?? const {},
                    occurrenceHistoryEpoch: existing?.occurrenceHistoryEpoch,
                    lastAction:
                        existing?.lastAction ??
                        v2_scheduled.ScheduledAction.none,
                    scheduledNotificationIds: const [],
                    sync: existing == null
                        ? v2_sync.SyncMetadata.fresh(deviceId: store.deviceId)
                        : existing.sync.touched(deviceId: store.deviceId),
                  );
                  await store.saveScheduledTransaction(record);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
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
                  key: const ValueKey('scheduled-fund-funding-account'),
                  icon: AppIcon.bank,
                  value: account?.name ?? 'Funding account unavailable',
                  secondary: account == null
                      ? null
                      : 'Available to Spend ${money(store.availableToSpendForAccount(account.id), store.preferences.currency)}',
                  onTap: null,
                ),
                const TransactionFormDivider(),
                TransactionFormLabel('Fund'),
                PolishedFormValueRow(
                  key: const ValueKey('scheduled-fund-funding-fund'),
                  icon: AppIcon.savings,
                  value: fund?.name ?? 'Choose Fund',
                  secondary: fund == null
                      ? null
                      : '${money(store.currentFundAmountMinor(fund.id), store.preferences.currency)} available',
                  onTap: existing != null || funds.length < 2
                      ? null
                      : () async {
                          final selected =
                              await showPolishedChoicePicker<String>(
                                dialogContext,
                                title: 'Choose Fund',
                                selected: fundId!,
                                choices: [
                                  for (final candidate in funds)
                                    PolishedChoice(
                                      value: candidate.id,
                                      label: candidate.name,
                                      leading: Icon(AppIcon.savings),
                                    ),
                                ],
                              );
                          if (selected != null) {
                            setDialogState(() => fundId = selected);
                          }
                        },
                ),
                const TransactionFormDivider(),
                TransactionFormLabel('Amount'),
                Row(
                  children: [
                    TransactionFormIcon(AppIcon.savings),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AmountEntryField(
                        fieldKey: const ValueKey(
                          'scheduled-fund-funding-amount',
                        ),
                        initialMinor: amountMinor,
                        replaceZeroOnFirstInput: true,
                        currency: store.preferences.currency,
                        labelText: null,
                        onChanged: (value) =>
                            setDialogState(() => amountMinor = value.abs()),
                      ),
                    ),
                  ],
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
                  TrackmarkSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Repeat until allocated or skipped'),
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

Future<void> showFundDetails(BuildContext context, String fundId) async {
  final store = FinanceDataStoreScope.read(context);
  final fund = store.funds
      .where((item) => item.id == fundId && !item.isDeleted)
      .firstOrNull;
  if (fund == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This Fund is no longer available.')),
    );
    return;
  }
  final cycleProgress = store.recurringFundCycleProgress(fund.id);
  final current = cycleProgress.reservedMinor;
  final target = fund.targetBalanceMinor;
  final targetPresentation = fundTargetPresentation(
    fund: fund,
    currentMinor: current,
    currency: store.preferences.currency,
    recurringCycleProgress: cycleProgress,
  );
  final fundingAccountName = store.accounts
      .where((account) => account.id == fund.fundingAccountId)
      .firstOrNull
      ?.name;
  final activity = store.reservationActivity(
    containerType: ReservationContainerType.fund,
    containerId: fund.id,
  );
  final fundingDeadline = targetPresentation.fundingDeadline;
  await showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => TransactionSheetFrame(
      title: 'Fund Details',
      actions: TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Close'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            fund.name,
            style: Theme.of(
              dialogContext,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${money(current, store.preferences.currency)} available',
            style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: Color(fund.accentColorValue),
              fontFeatures: const [AppTextStyles.tabularFigures],
            ),
          ),
          if (target > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            FundTargetProgressBar(
              presentation: targetPresentation,
              color: Color(fund.accentColorValue),
              minHeight: 8,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              targetPresentation.status,
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (targetPresentation.secondaryStatus != null)
              Text(
                targetPresentation.secondaryStatus!,
                style: Theme.of(dialogContext).textTheme.labelSmall?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (fundingAccountName != null)
            GoalDetailValue(
              label: 'Funding account',
              value: fundingAccountName,
              icon: AppIcon.wallet,
            ),
          if (target > 0)
            GoalDetailValue(
              label: 'Target balance',
              value: money(target, store.preferences.currency),
              icon: AppIcon.goal,
            ),
          if (fundingDeadline != null)
            GoalDetailValue(
              label: 'Fund by',
              value: fullMonthDateLabel(fundingDeadline),
              icon: AppIcon.calendar,
            ),
          if (fund.description.trim().isNotEmpty)
            GoalDetailValue(
              label: 'Description',
              value: fund.description,
              icon: AppIcon.notes,
            ),
          const TransactionFormDivider(),
          Text(
            'Activity',
            style: Theme.of(
              dialogContext,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          if (activity.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('No activity yet'),
            )
          else
            for (final operation in activity.take(20))
              ReservationActivityRow(
                operation: operation,
                currency: store.preferences.currency,
                linkedTransaction: operation.transactionId == null
                    ? null
                    : store.transactions
                          .where(
                            (transaction) =>
                                transaction.id == operation.transactionId &&
                                !transaction.isDeleted,
                          )
                          .firstOrNull,
                reversedOperation: operation.reversesOperationId == null
                    ? null
                    : store.reservationOperations
                          .where(
                            (candidate) =>
                                candidate.id == operation.reversesOperationId,
                          )
                          .firstOrNull,
                fundingAccountName: store.accounts
                    .where(
                      (account) => account.id == operation.fundingAccountId,
                    )
                    .firstOrNull
                    ?.name,
                accentColor: Color(fund.accentColorValue),
                keyPrefix: 'fund-reservation-activity',
              ),
        ],
      ),
    ),
  );
}

Future<void> showArchivedFundActions(
  BuildContext context,
  String fundId,
) async {
  final store = FinanceDataStoreScope.read(context);
  final fund = store.fundById(fundId);
  final eligibility = store.fundDeleteEligibility(fundId);
  final action = await showPolishedChoicePicker<String>(
    context,
    title: fund.name,
    selected: '',
    choices: [
      PolishedChoice(
        value: 'restore',
        label: 'Restore',
        leading: Icon(AppIcon.unarchive),
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
  if (action == 'restore') {
    await store.restoreFund(fundId);
  } else if (action == 'delete') {
    await _confirmAndDeleteFund(context, fundId);
  }
}

Future<void> _confirmAndDeleteFund(BuildContext context, String fundId) async {
  final store = FinanceDataStoreScope.read(context);
  final eligibility = store.fundDeleteEligibility(fundId);
  if (!eligibility.canDelete) {
    final linkedFunding = store.activeScheduledFundFundingForFund(fundId);
    if (!eligibility.hasNonZeroBalance && linkedFunding.isNotEmpty) {
      await _showFundScheduledFundingBlocker(
        context,
        action: 'deleted',
        linkedFunding: linkedFunding,
      );
      return;
    }
    final linkedSchedules = store.scheduledTransactions
        .where(
          (scheduled) =>
              !scheduled.isDeleted &&
              scheduled.reservationContainerType ==
                  ReservationContainerType.fund &&
              scheduled.reservationContainerId == fundId,
        )
        .toList(growable: false);
    final message = eligibility.hasNonZeroBalance
        ? 'Return the remaining ${money(eligibility.remainingBalanceMinor.abs(), store.preferences.currency)} before deleting this Fund.'
        : linkedSchedules.length == 1
        ? '${linkedSchedules.single.payee} still uses this Fund. Undo Payment restores the scheduled occurrence and its Fund selection. Edit that scheduled transaction and set Use reserved money to None before deleting the Fund.'
        : '${linkedSchedules.length} scheduled transactions still use this Fund. Undo Payment restores each occurrence and its Fund selection. Edit those scheduled transactions and set Use reserved money to None before deleting the Fund.';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fund can’t be deleted yet'),
        content: Text(message),
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
    title: 'Delete this Fund permanently?',
    message:
        'This Fund has no remaining balance or pending scheduled activity. Ledger history, if any, will remain available.',
    confirmLabel: 'Delete Permanently',
    destructive: true,
  );
  if (confirmed) await store.deleteFundPermanently(fundId);
}

Future<void> _showFundScheduledFundingBlocker(
  BuildContext context, {
  required String action,
  required List<v2_scheduled.ScheduledTransactionRecord> linkedFunding,
}) {
  final description = linkedFunding.length == 1
      ? '${linkedFunding.single.payee} still schedules funding for this Fund. Edit or delete that scheduled funding before the Fund can be $action.'
      : '${linkedFunding.length} scheduled funding items still allocate to this Fund. Edit or delete them before the Fund can be $action.';
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Fund can\u2019t be $action yet'),
      content: Text(description),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showFundAmountDialog(
  BuildContext context, {
  required String fundId,
  required bool isReturn,
}) {
  final store = FinanceDataStoreScope.read(context);
  final fund = store.fundById(fundId);
  return showReservationAmountDialog(
    context,
    containerType: ReservationContainerType.fund,
    containerId: fundId,
    containerName: fund.name,
    isReturn: isReturn,
  );
}

Future<void> showReservationAmountDialog(
  BuildContext context, {
  required ReservationContainerType containerType,
  required String containerId,
  required String containerName,
  required bool isReturn,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final isGoal = containerType == ReservationContainerType.goal;
  final fundingAccountId = switch (containerType) {
    ReservationContainerType.fund =>
      store.fundById(containerId).fundingAccountId,
    ReservationContainerType.goal =>
      store.goalById(containerId).reservationFundingAccountId!,
  };
  final fundingAccount = store.accountById(fundingAccountId);
  var amountMinor = 0;
  var isSaving = false;
  int? savingReservedMinor;
  int? savingAvailableMinor;
  String? error;
  final amountFocusNode = FocusNode();
  var requestedInitialFocus = false;
  try {
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        if (!requestedInitialFocus) {
          requestedInitialFocus = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (dialogContext.mounted) amountFocusNode.requestFocus();
          });
        }
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final liveReservedMinor = store.reservationAmountMinor(
              containerType: containerType,
              containerId: containerId,
            );
            final liveAvailableMinor = store.availableToSpendForAccount(
              fundingAccountId,
            );
            // Once Save begins, keep the preview anchored to its pre-submit
            // baseline. The store notifies listeners immediately after the
            // successful mutation; using that new value while the draft is
            // still visible would apply the amount twice for one frame.
            final reservedMinor = isSaving && savingReservedMinor != null
                ? savingReservedMinor!
                : liveReservedMinor;
            final availableMinor = isSaving && savingAvailableMinor != null
                ? savingAvailableMinor!
                : liveAvailableMinor;
            final resultMinor = isReturn
                ? reservedMinor - amountMinor
                : availableMinor - amountMinor;
            final exceedsReservation = isReturn && amountMinor > reservedMinor;
            final overcommitted = !isReturn && resultMinor < 0;
            final theme = Theme.of(dialogContext);
            final contextStyle = theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.25,
            );
            return TransactionSheetFrame(
              title: isReturn
                  ? isGoal
                        ? 'Return Goal Reservation'
                        : 'Return Funds'
                  : 'Allocate to $containerName',
              actions: TransactionFormActions(
                onCancel: () => Navigator.pop(dialogContext),
                canSave: amountMinor > 0 && !exceedsReservation,
                isSaving: isSaving,
                saveLabel: isReturn ? 'Return' : 'Allocate',
                onSave: () async {
                  if (isSaving) return;
                  setState(() {
                    isSaving = true;
                    savingReservedMinor = reservedMinor;
                    savingAvailableMinor = availableMinor;
                    error = null;
                  });
                  try {
                    if (isReturn) {
                      await store.returnReservation(
                        containerType: containerType,
                        containerId: containerId,
                        amountMinor: amountMinor,
                        date: DateTime.now(),
                        waitForRemote: false,
                      );
                    } else {
                      await store.allocateReservation(
                        containerType: containerType,
                        containerId: containerId,
                        amountMinor: amountMinor,
                        date: DateTime.now(),
                        waitForRemote: false,
                      );
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (exception) {
                    if (!dialogContext.mounted) return;
                    setState(() {
                      isSaving = false;
                      savingReservedMinor = null;
                      savingAvailableMinor = null;
                      error = exception.toString();
                    });
                  }
                },
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isReturn) ...[
                    Text(
                      '$containerName ${isGoal ? 'Goal' : 'Fund'}',
                      key: const ValueKey('reservation-container-context'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reserved ${money(reservedMinor, store.preferences.currency)}',
                      key: const ValueKey('reservation-current-context'),
                      style: contextStyle,
                    ),
                    Text(
                      'Returns to ${fundingAccount.name}',
                      key: const ValueKey('reservation-funding-account'),
                      style: contextStyle,
                    ),
                  ] else ...[
                    Text(
                      'From ${fundingAccount.name}',
                      key: const ValueKey('reservation-funding-account'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Available to Spend ${money(availableMinor, store.preferences.currency)}',
                      key: const ValueKey('reservation-current-context'),
                      style: contextStyle,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  TransactionFormLabel('Amount'),
                  Row(
                    children: [
                      TransactionFormIcon(AppIcon.money),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AmountEntryField(
                          fieldKey: const ValueKey('fund-operation-amount'),
                          initialMinor: 0,
                          autofocus: true,
                          focusNode: amountFocusNode,
                          replaceZeroOnFirstInput: true,
                          currency: store.preferences.currency,
                          onChanged: (value) => setState(() {
                            amountMinor = value.abs();
                            error = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    isReturn
                        ? 'After return · ${money(resultMinor, store.preferences.currency)} reserved'
                        : 'After allocation · ${money(resultMinor, store.preferences.currency)} available',
                    key: const ValueKey('reservation-live-result'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: exceedsReservation
                          ? AppColors.danger
                          : overcommitted
                          ? AppColors.warning
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (exceedsReservation) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Return cannot exceed the currently reserved amount.',
                      key: const ValueKey('reservation-return-exceeds'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else if (overcommitted) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'This exceeds the account’s available money.',
                      key: const ValueKey('reservation-overcommit-warning'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  } finally {
    amountFocusNode.dispose();
  }
}

enum _FundTargetTiming { none, endOfMonth, fixedDay }

Future<void> showFundEditor(
  BuildContext context, {
  FundRecord? initialFund,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final name = TextEditingController(text: initialFund?.name ?? '');
  final description = TextEditingController(
    text: initialFund?.description ?? '',
  );
  var fundingAccountId = initialFund?.fundingAccountId;
  var targetMinor = initialFund?.targetBalanceMinor ?? 0;
  var cadence = initialFund?.targetCadence ?? FundTargetCadence.none;
  var dayRule = initialFund?.targetDayRule ?? FundTargetDayRule.fixedDay;
  var nextTargetDate = initialFund?.nextTargetDate;
  String? error;
  final navigator = Navigator.of(context);
  final route = DialogRoute<void>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final accounts = store.activeAccountsInDisplayOrder
            .where(
              (account) =>
                  account.type == v2_account.AccountType.checking ||
                  account.type == v2_account.AccountType.savings ||
                  account.type == v2_account.AccountType.cash ||
                  account.type == v2_account.AccountType.otherBanking,
            )
            .toList(growable: false);
        final selectedAccount = accounts
            .where((account) => account.id == fundingAccountId)
            .firstOrNull;
        final canSave = name.text.trim().isNotEmpty && fundingAccountId != null;
        return TransactionSheetFrame(
          title: initialFund == null ? 'Create Fund' : 'Edit Fund',
          actions: TransactionFormActions(
            onCancel: () => Navigator.pop(dialogContext),
            canSave: canSave,
            isSaving: false,
            onSave: () async {
              try {
                if (initialFund == null) {
                  await store.createFund(
                    name: name.text,
                    description: description.text,
                    fundingAccountId: fundingAccountId!,
                    targetBalanceMinor: targetMinor,
                    targetCadence: cadence,
                    targetDayRule: dayRule,
                    nextTargetDate: nextTargetDate,
                  );
                } else {
                  await store.saveFund(
                    initialFund.copyWith(
                      name: name.text.trim(),
                      description: description.text.trim(),
                      fundingAccountId: fundingAccountId,
                      targetBalanceMinor: targetMinor,
                      targetCadence: cadence,
                      targetDayRule: dayRule,
                      nextTargetDate: nextTargetDate,
                      clearNextTargetDate: cadence == FundTargetCadence.none,
                      sync: initialFund.sync.touched(deviceId: store.deviceId),
                    ),
                  );
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (exception) {
                if (!dialogContext.mounted) return;
                setState(() => error = exception.toString());
              }
            },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TransactionFormLabel('Fund name'),
              Row(
                children: [
                  TransactionFormIcon(AppIcon.savings),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('fund-name'),
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Bills'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              TransactionFormDivider(),
              TransactionFormLabel('Funding account'),
              PolishedFormValueRow(
                key: const ValueKey('fund-funding-account'),
                icon: selectedAccount == null
                    ? AppIcon.wallet
                    : v2AccountIcon(selectedAccount.type),
                value: selectedAccount?.name ?? 'Choose account',
                secondary: 'Reserved money remains in this real account',
                onTap: () async {
                  final selected = await showTransactionAccountPicker(
                    dialogContext,
                    accounts: accounts,
                    selectedAccountId: fundingAccountId ?? '',
                  );
                  if (selected != null && dialogContext.mounted) {
                    setState(() => fundingAccountId = selected);
                  }
                },
              ),
              if (cadence == FundTargetCadence.monthly) ...[
                TransactionFormDivider(),
                TransactionFormLabel('First target date'),
                PolishedFormValueRow(
                  key: const ValueKey('fund-target-date'),
                  icon: AppIcon.calendar,
                  value: nextTargetDate == null
                      ? 'Choose date'
                      : fullMonthDateLabel(nextTargetDate!),
                  secondary: dayRule == FundTargetDayRule.endOfMonth
                      ? 'Last day of every month'
                      : nextTargetDate == null
                      ? 'Choose the day to repeat each month'
                      : 'Repeats on day ${nextTargetDate?.day ?? ''} each month; '
                            'uses the last day in shorter months',
                  onTap: () async {
                    final now = DateTime.now();
                    final selected = await pickDateForField(
                      dialogContext,
                      nextTargetDate ?? DateTime(now.year, now.month + 1, 0),
                    );
                    if (selected != null && dialogContext.mounted) {
                      setState(() {
                        nextTargetDate = dayRule == FundTargetDayRule.endOfMonth
                            ? DateTime(selected.year, selected.month + 1, 0)
                            : selected;
                      });
                    }
                  },
                ),
              ],
              TransactionFormDivider(),
              TransactionFormLabel('Target balance (optional)'),
              Row(
                children: [
                  TransactionFormIcon(AppIcon.target),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AmountEntryField(
                      fieldKey: const ValueKey('fund-target-amount'),
                      initialMinor: targetMinor,
                      currency: store.preferences.currency,
                      onChanged: (value) =>
                          setState(() => targetMinor = value.abs()),
                    ),
                  ),
                ],
              ),
              TransactionFormDivider(),
              TransactionFormLabel('Target timing'),
              PolishedFormValueRow(
                key: const ValueKey('fund-target-cadence'),
                icon: AppIcon.recurrence,
                value: cadence == FundTargetCadence.monthly
                    ? dayRule == FundTargetDayRule.endOfMonth
                          ? 'End of every month'
                          : nextTargetDate == null
                          ? 'Choose date'
                          : 'Monthly on day ${nextTargetDate!.day}'
                    : 'No recurring target',
                secondary: 'Money rolls over and never resets',
                onTap: () async {
                  final selected =
                      await showPolishedChoicePicker<_FundTargetTiming>(
                        dialogContext,
                        title: 'Target timing',
                        selected: cadence != FundTargetCadence.monthly
                            ? _FundTargetTiming.none
                            : dayRule == FundTargetDayRule.endOfMonth
                            ? _FundTargetTiming.endOfMonth
                            : _FundTargetTiming.fixedDay,
                        choices: const [
                          PolishedChoice(
                            value: _FundTargetTiming.none,
                            label: 'No recurring target',
                          ),
                          PolishedChoice(
                            value: _FundTargetTiming.endOfMonth,
                            label: 'End of every month',
                          ),
                          PolishedChoice(
                            value: _FundTargetTiming.fixedDay,
                            label: 'Choose date — repeat monthly on that day',
                          ),
                        ],
                      );
                  if (selected != null && dialogContext.mounted) {
                    final now = DateTime.now();
                    final initialDate =
                        nextTargetDate ?? DateTime(now.year, now.month + 1, 0);
                    DateTime? chosenDate;
                    if (selected == _FundTargetTiming.fixedDay) {
                      chosenDate = await pickDateForField(
                        dialogContext,
                        initialDate,
                      );
                      // Cancelling the date picker preserves the existing rule.
                      if (chosenDate == null || !dialogContext.mounted) return;
                    }
                    setState(() {
                      switch (selected) {
                        case _FundTargetTiming.none:
                          cadence = FundTargetCadence.none;
                        case _FundTargetTiming.endOfMonth:
                          cadence = FundTargetCadence.monthly;
                          dayRule = FundTargetDayRule.endOfMonth;
                          nextTargetDate = DateTime(
                            initialDate.year,
                            initialDate.month + 1,
                            0,
                          );
                        case _FundTargetTiming.fixedDay:
                          cadence = FundTargetCadence.monthly;
                          dayRule = FundTargetDayRule.fixedDay;
                          nextTargetDate = chosenDate;
                      }
                    });
                  }
                },
              ),
              TransactionFormDivider(),
              TransactionFormLabel('Notes'),
              Row(
                children: [
                  TransactionFormIcon(AppIcon.notes),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: description,
                      decoration: const InputDecoration(
                        hintText: 'Optional description',
                      ),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(error!, style: const TextStyle(color: AppColors.danger)),
              ],
            ],
          ),
        );
      },
    ),
  );
  await navigator.push(route);
  // Popping resolves push before the reverse animation unmounts the fields.
  await route.completed;
  name.dispose();
  description.dispose();
}
