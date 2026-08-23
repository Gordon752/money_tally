part of '../../main.dart';

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
    final current = store.currentFundAmountMinor(fund.id);
    final target = fund.targetBalanceMinor;
    final difference = current - target;
    final progress = target <= 0 ? 0.0 : (current / target).clamp(0.0, 1.0);
    final effectiveTargetDate = effectiveFundTargetDate(fund);
    final accountName = store.accounts
        .where((account) => account.id == fund.fundingAccountId)
        .map((account) => account.name)
        .firstOrNull;
    final status = target <= 0
        ? 'No target set'
        : difference >= 0
        ? '${money(difference, store.preferences.currency)} above target'
        : '${money(difference.abs(), store.preferences.currency)} needed to fully fund';
    return Semantics(
      button: true,
      label:
          '${fund.name}, ${money(current, store.preferences.currency)} available, $status',
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: progress,
                      color: AppTheme.accent,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
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
                if (effectiveTargetDate != null)
                  Text(
                    'Next target ${shortDate(effectiveTargetDate)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
            leading: Icon(AppIcon.add),
            title: const Text('Allocate'),
            subtitle: const Text('Reserve more money from the funding account'),
            onTap: () => Navigator.pop(sheetContext, 'allocate'),
          ),
          ListTile(
            enabled: current > 0,
            leading: Icon(AppIcon.expense),
            title: const Text('Spend from Fund'),
            subtitle: const Text('Record a real transaction using this money'),
            onTap: current > 0
                ? () => Navigator.pop(sheetContext, 'spend')
                : null,
          ),
          ListTile(
            enabled: current > 0,
            leading: Icon(AppIcon.transfer),
            title: const Text('Return Funds'),
            subtitle: const Text('Release reserved money back to available'),
            onTap: current > 0
                ? () => Navigator.pop(sheetContext, 'return')
                : null,
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
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case 'allocate':
      await showFundAmountDialog(context, fundId: fundId, isReturn: false);
    case 'return':
      await showFundAmountDialog(context, fundId: fundId, isReturn: true);
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
      await store.archiveFund(fundId);
    case 'delete':
      await _confirmAndDeleteFund(context, fundId);
  }
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
            final reservedMinor = store.reservationAmountMinor(
              containerType: containerType,
              containerId: containerId,
            );
            final availableMinor = store.availableToSpendForAccount(
              fundingAccountId,
            );
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
                isSaving: false,
                saveLabel: isReturn ? 'Return' : 'Allocate',
                onSave: () async {
                  try {
                    if (isReturn) {
                      await store.returnReservation(
                        containerType: containerType,
                        containerId: containerId,
                        amountMinor: amountMinor,
                        date: DateTime.now(),
                      );
                    } else {
                      await store.allocateReservation(
                        containerType: containerType,
                        containerId: containerId,
                        amountMinor: amountMinor,
                        date: DateTime.now(),
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
  var nextTargetDate = initialFund?.nextTargetDate;
  String? error;
  await showDialog<void>(
    context: context,
    useRootNavigator: false,
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
                TransactionFormLabel('Target date'),
                PolishedFormValueRow(
                  key: const ValueKey('fund-target-date'),
                  icon: AppIcon.calendar,
                  value: nextTargetDate == null
                      ? 'Choose date'
                      : fullMonthDateLabel(nextTargetDate!),
                  secondary: 'The balance rolls over after every checkpoint',
                  onTap: () async {
                    final now = DateTime.now();
                    final selected = await pickDateForField(
                      dialogContext,
                      nextTargetDate ?? DateTime(now.year, now.month + 1, 0),
                    );
                    if (selected != null && dialogContext.mounted) {
                      setState(() => nextTargetDate = selected);
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
                    ? 'Monthly target balance'
                    : 'No recurring target',
                secondary: 'Money rolls over and never resets',
                onTap: () async {
                  final selected =
                      await showPolishedChoicePicker<FundTargetCadence>(
                        dialogContext,
                        title: 'Target timing',
                        selected: cadence,
                        choices: const [
                          PolishedChoice(
                            value: FundTargetCadence.none,
                            label: 'No recurring target',
                          ),
                          PolishedChoice(
                            value: FundTargetCadence.monthly,
                            label: 'Monthly target balance',
                          ),
                        ],
                      );
                  if (selected != null && dialogContext.mounted) {
                    setState(() {
                      cadence = selected;
                      if (cadence == FundTargetCadence.monthly &&
                          nextTargetDate == null) {
                        final now = DateTime.now();
                        nextTargetDate = DateTime(now.year, now.month + 1, 0);
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
  name.dispose();
  description.dispose();
}
