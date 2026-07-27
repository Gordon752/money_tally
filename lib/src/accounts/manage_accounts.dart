part of '../../main.dart';

const _lastUsedAccountChoice = 'lastUsed';
const _noDefaultAccountChoice = 'none';
const _transactionDefaultAccountChoice = 'transactionDefault';
const _specificAccountChoicePrefix = 'account:';

bool accountIsAsset(v2_account.AccountRecord account) {
  return switch (account.type) {
    v2_account.AccountType.checking ||
    v2_account.AccountType.savings ||
    v2_account.AccountType.cash ||
    v2_account.AccountType.otherBanking => true,
    v2_account.AccountType.creditCard || v2_account.AccountType.loan => false,
  };
}

Future<bool> confirmAssetAccountOverdraw(
  BuildContext context, {
  required v2_account.AccountRecord account,
  required int projectedBalanceMinor,
}) async {
  final currency = FinanceDataStoreScope.read(context).preferences.currency;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Overdraw this account?'),
      content: Text(
        'Saving this transaction will leave ${account.name} with a balance of ${money(projectedBalanceMinor, currency)}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Save Anyway'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

v2_account.AccountRecord? activeAccountForId(
  FinanceDataStore store,
  String? accountId,
) {
  if (accountId == null || accountId.isEmpty) return null;
  return store.activeAccountsInDisplayOrder
      .where((account) => account.id == accountId)
      .firstOrNull;
}

String? resolvedDefaultTransactionAccountId(FinanceDataStore store) {
  final preferences = store.preferences;
  return switch (preferences.defaultTransactionAccountMode) {
    AccountDefaultMode.none => null,
    AccountDefaultMode.specific =>
      activeAccountForId(store, preferences.defaultTransactionAccountId)?.id ??
          activeAccountForId(
            store,
            preferences.lastUsedTransactionAccountId,
          )?.id,
    AccountDefaultMode.lastUsed || AccountDefaultMode.useTransactionDefault =>
      activeAccountForId(store, preferences.lastUsedTransactionAccountId)?.id,
  };
}

String? resolvedDefaultTransferSourceAccountId(FinanceDataStore store) {
  final preferences = store.preferences;
  return switch (preferences.defaultTransferSourceMode) {
    AccountDefaultMode.none => null,
    AccountDefaultMode.specific =>
      activeAccountForId(
            store,
            preferences.defaultTransferSourceAccountId,
          )?.id ??
          activeAccountForId(
            store,
            preferences.lastUsedTransferSourceAccountId,
          )?.id,
    AccountDefaultMode.useTransactionDefault =>
      resolvedDefaultTransactionAccountId(store),
    AccountDefaultMode.lastUsed => activeAccountForId(
      store,
      preferences.lastUsedTransferSourceAccountId,
    )?.id,
  };
}

String accountDefaultLabel(FinanceDataStore store, {required bool transfer}) {
  final preferences = store.preferences;
  final mode = transfer
      ? preferences.defaultTransferSourceMode
      : preferences.defaultTransactionAccountMode;
  if (mode == AccountDefaultMode.none) return 'None';
  if (mode == AccountDefaultMode.useTransactionDefault) {
    return 'Use default transaction account';
  }
  if (mode == AccountDefaultMode.lastUsed) return 'Last used';
  final configuredId = transfer
      ? preferences.defaultTransferSourceAccountId
      : preferences.defaultTransactionAccountId;
  final configured = activeAccountForId(store, configuredId);
  if (configured != null) return configured.name;
  final fallbackId = transfer
      ? preferences.lastUsedTransferSourceAccountId
      : preferences.lastUsedTransactionAccountId;
  return activeAccountForId(store, fallbackId)?.name ?? 'None';
}

class ManageAccountsScreen extends StatelessWidget {
  const ManageAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final preferences = store.preferences;
    final archivedCount = store.accounts
        .where((account) => account.isArchived && !account.isDeleted)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Accounts'),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            40,
          ),
          children: [
            SettingsSectionCard(
              title: 'Defaults',
              children: [
                SettingsActionRow(
                  icon: AppIcon.receipt,
                  title: 'Default transaction account',
                  subtitle: accountDefaultLabel(store, transfer: false),
                  onTap: () => _chooseDefaultAccount(
                    context,
                    store: store,
                    transfer: false,
                  ),
                ),
                SettingsActionRow(
                  icon: AppIcon.transfer,
                  title: 'Default transfer source',
                  subtitle: accountDefaultLabel(store, transfer: true),
                  showDivider: false,
                  onTap: () => _chooseDefaultAccount(
                    context,
                    store: store,
                    transfer: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsSectionCard(
              title: 'New Account Defaults',
              children: [
                SettingsSwitch(
                  icon: AppIcon.bank,
                  label: 'Include in group balance',
                  subtitle:
                      'Automatically include new accounts in their account-type total.',
                  value: preferences.newAccountIncludeInGroupBalance,
                  onChanged: (value) => store.savePreferences(
                    preferences.copyWith(
                      newAccountIncludeInGroupBalance: value,
                    ),
                  ),
                ),
                SettingsSwitch(
                  icon: AppIcon.pieChart,
                  label: 'Include in net worth',
                  subtitle:
                      'Automatically include new accounts in net-worth calculations.',
                  value: preferences.newAccountIncludeInNetWorth,
                  onChanged: (value) => store.savePreferences(
                    preferences.copyWith(newAccountIncludeInNetWorth: value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsSectionCard(
              title: 'Display & Totals',
              children: [
                SettingsActionRow(
                  icon: AppIcon.pieChart,
                  title: 'Account inclusion',
                  subtitle:
                      'Choose which accounts are included in totals and net worth.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountInclusionScreen(),
                    ),
                  ),
                ),
                SettingsActionRow(
                  icon: AppIcon.numberedList,
                  title: 'Account order',
                  subtitle: 'Reorder active accounts within each account type.',
                  showDivider: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountOrderScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsSectionCard(
              title: 'Archived Accounts',
              children: [
                SettingsActionRow(
                  icon: AppIcon.archive,
                  title: 'Archived Accounts',
                  subtitle:
                      'View, restore, or permanently delete archived accounts.',
                  trailingText: archivedCount == 0 ? null : '$archivedCount',
                  showDivider: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ArchivedAccountsScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsSectionCard(
              title: 'Warnings',
              children: [
                SettingsSwitch(
                  icon: AppIcon.error,
                  label: 'Warn before an account goes below \$0.00',
                  subtitle:
                      'Show a confirmation before saving a transaction that would overdraw an asset account.',
                  value: preferences.warnBeforeNegativeAssetBalance,
                  onChanged: (value) => store.savePreferences(
                    preferences.copyWith(warnBeforeNegativeAssetBalance: value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _chooseDefaultAccount(
  BuildContext context, {
  required FinanceDataStore store,
  required bool transfer,
}) async {
  final preferences = store.preferences;
  final mode = transfer
      ? preferences.defaultTransferSourceMode
      : preferences.defaultTransactionAccountMode;
  final specificId = transfer
      ? preferences.defaultTransferSourceAccountId
      : preferences.defaultTransactionAccountId;
  final currentChoice = switch (mode) {
    AccountDefaultMode.none => _noDefaultAccountChoice,
    AccountDefaultMode.useTransactionDefault =>
      _transactionDefaultAccountChoice,
    AccountDefaultMode.specific when specificId != null =>
      '$_specificAccountChoicePrefix$specificId',
    _ => _lastUsedAccountChoice,
  };
  final choice = await showPolishedChoicePicker<String>(
    context,
    title: transfer ? 'Default transfer source' : 'Default transaction account',
    selected: currentChoice,
    choices: [
      PolishedChoice(
        value: _lastUsedAccountChoice,
        label: 'Last used',
        leading: Icon(AppIcon.history),
      ),
      PolishedChoice(
        value: _noDefaultAccountChoice,
        label: 'None',
        leading: Icon(AppIcon.hidden),
      ),
      if (transfer)
        PolishedChoice(
          value: _transactionDefaultAccountChoice,
          label: 'Use default transaction account',
          leading: Icon(AppIcon.receipt),
        ),
      for (final account in store.activeAccountsInDisplayOrder)
        PolishedChoice(
          value: '$_specificAccountChoicePrefix${account.id}',
          label: account.name,
          leading: Icon(v2AccountIcon(account.type)),
        ),
    ],
  );
  if (choice == null) return;
  final selectedMode = switch (choice) {
    _lastUsedAccountChoice => AccountDefaultMode.lastUsed,
    _noDefaultAccountChoice => AccountDefaultMode.none,
    _transactionDefaultAccountChoice =>
      AccountDefaultMode.useTransactionDefault,
    _ => AccountDefaultMode.specific,
  };
  final accountId = choice.startsWith(_specificAccountChoicePrefix)
      ? choice.substring(_specificAccountChoicePrefix.length)
      : null;
  await store.savePreferences(
    transfer
        ? preferences.copyWith(
            defaultTransferSourceMode: selectedMode,
            defaultTransferSourceAccountId: accountId,
          )
        : preferences.copyWith(
            defaultTransactionAccountMode: selectedMode,
            defaultTransactionAccountId: accountId,
          ),
  );
}

class AccountInclusionScreen extends StatelessWidget {
  const AccountInclusionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final accounts = store.activeAccountsInDisplayOrder;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Inclusion'),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            40,
          ),
          children: [
            for (final group in store.accountGroupsInDisplayOrder)
              if (accounts.any((account) => account.group == group)) ...[
                SettingsSectionCard(
                  title: store.accountGroupLabel(group),
                  children: [
                    for (final account in accounts.where(
                      (account) => account.group == group,
                    ))
                      _AccountInclusionRow(account: account),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
        ),
      ),
    );
  }
}

class _AccountInclusionRow extends StatelessWidget {
  const _AccountInclusionRow({required this.account});

  final v2_account.AccountRecord account;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.read(context);
    return Padding(
      key: ValueKey('account-inclusion-${account.id}'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          SettingsRowIcon(icon: v2AccountIcon(account.type)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  v2AccountTypeLabel(account.type),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _CompactInclusionSwitch(
            tooltip: 'Include ${account.name} in group balance',
            value: account.includeInGroupBalance,
            onChanged: (value) => store.saveAccount(
              account.copyWith(includeInGroupBalance: value),
            ),
          ),
          _CompactInclusionSwitch(
            tooltip: 'Include ${account.name} in net worth',
            value: account.includeInNetWorth,
            onChanged: (value) =>
                store.saveAccount(account.copyWith(includeInNetWorth: value)),
          ),
        ],
      ),
    );
  }
}

class _CompactInclusionSwitch extends StatelessWidget {
  const _CompactInclusionSwitch({
    required this.tooltip,
    required this.value,
    required this.onChanged,
  });

  final String tooltip;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Switch.adaptive(value: value, onChanged: onChanged),
    );
  }
}

class AccountOrderScreen extends StatelessWidget {
  const AccountOrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final accounts = store.activeAccountsInDisplayOrder;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Order'),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            40,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Drag accounts within their account type. Account types stay in their current order.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final group in store.accountGroupsInDisplayOrder)
              if (accounts.any((account) => account.group == group)) ...[
                _AccountOrderGroup(
                  group: group,
                  accounts: accounts
                      .where((account) => account.group == group)
                      .toList(growable: false),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
        ),
      ),
    );
  }
}

class _AccountOrderGroup extends StatelessWidget {
  const _AccountOrderGroup({required this.group, required this.accounts});

  final v2_account.AccountGroup group;
  final List<v2_account.AccountRecord> accounts;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.read(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              store.accountGroupLabel(group),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          ReorderableListView.builder(
            key: ValueKey('account-order-${group.name}'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: accounts.length,
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...accounts];
              final moving = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moving);
              HapticFeedback.selectionClick();
              store.reorderAccountsWithinGroup(
                group: group,
                orderedAccountIds: [
                  for (final account in reordered) account.id,
                ],
              );
            },
            itemBuilder: (context, index) {
              final account = accounts[index];
              return ListTile(
                key: ValueKey('account-order-row-${account.id}'),
                leading: SettingsRowIcon(icon: v2AccountIcon(account.type)),
                title: Text(
                  account.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(v2AccountTypeLabel(account.type)),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Icon(Icons.drag_handle_rounded),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ArchivedAccountsScreen extends StatelessWidget {
  const ArchivedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final archived =
        store.accounts
            .where((account) => account.isArchived && !account.isDeleted)
            .toList(growable: false)
          ..sort(
            (a, b) => compareAccountDisplayOrder(
              a,
              b,
              groupOrder: store.accountGroupDisplayOrderIndexes,
            ),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Archived Accounts'),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: archived.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    'No archived accounts',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  40,
                ),
                children: [
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var index = 0; index < archived.length; index++)
                          _ArchivedAccountRow(
                            account: archived[index],
                            showDivider: index != archived.length - 1,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ArchivedAccountRow extends StatelessWidget {
  const _ArchivedAccountRow({required this.account, required this.showDivider});

  final v2_account.AccountRecord account;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.read(context);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
              )
            : null,
      ),
      child: ListTile(
        key: ValueKey('archived-account-${account.id}'),
        minTileHeight: 72,
        leading: SettingsRowIcon(icon: v2AccountIcon(account.type)),
        title: Text(
          account.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${v2AccountTypeLabel(account.type)} · ${money(store.balanceForAccount(account.id), store.preferences.currency)}',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Actions for ${account.name}',
          onSelected: (action) async {
            if (action == 'restore') {
              await store.restoreAccount(account.id);
            } else if (action == 'delete' && context.mounted) {
              await _permanentlyDeleteArchivedAccount(context, account);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'restore', child: Text('Restore')),
            PopupMenuItem(
              value: 'delete',
              child: Text(
                'Delete Permanently',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _permanentlyDeleteArchivedAccount(
  BuildContext context,
  v2_account.AccountRecord account,
) async {
  final store = FinanceDataStoreScope.read(context);
  final links = store.accountLinkedRecordSummary(account.id);
  if (links.hasLinks) {
    final descriptions = <String>[
      if (links.transactionCount > 0)
        '${links.transactionCount} ledger ${links.transactionCount == 1 ? 'transaction' : 'transactions'}',
      if (links.scheduledTransactionCount > 0)
        '${links.scheduledTransactionCount} scheduled ${links.scheduledTransactionCount == 1 ? 'transaction' : 'transactions'}',
      if (links.goalFundingEventCount > 0)
        '${links.goalFundingEventCount} Goal funding ${links.goalFundingEventCount == 1 ? 'event' : 'events'}',
      if (links.defaultGoalCount > 0)
        '${links.defaultGoalCount} ${links.defaultGoalCount == 1 ? 'Goal uses' : 'Goals use'} this default account',
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account still has linked records'),
        content: Text(
          '${account.name} cannot be permanently deleted while it is linked to ${descriptions.join(', ')}. Restore the account or resolve those records first.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete account permanently?'),
      content: Text(
        'This permanently deletes ${account.name}. This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete Permanently'),
        ),
      ],
    ),
  );
  if (confirmed == true) await store.deleteAccount(account.id);
}
