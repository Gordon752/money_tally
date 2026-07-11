part of '../main.dart';

enum FinanceSection {
  dashboard(Icons.dashboard_outlined, 'Dashboard'),
  accounts(Icons.account_balance_wallet_outlined, 'Accounts'),
  ledger(Icons.receipt_long_outlined, 'Ledger'),
  budgets(Icons.pie_chart_outline, 'Budgets'),
  scheduled(Icons.event_repeat_outlined, 'Scheduled'),
  reports(Icons.insights_outlined, 'Reports'),
  categories(Icons.sell_outlined, 'Categories'),
  settings(Icons.settings_outlined, 'Settings');

  const FinanceSection(this.icon, this.label);
  final IconData icon;
  final String label;

  bool get supportsFloatingAdd => this != FinanceSection.reports;
}

class FinanceHome extends StatefulWidget {
  const FinanceHome({this.syncLabel = 'Synced', this.onSignOut, super.key});

  final String syncLabel;
  final VoidCallback? onSignOut;

  @override
  State<FinanceHome> createState() => _FinanceHomeState();
}

class _FinanceHomeState extends State<FinanceHome> {
  static const compactSections = [
    FinanceSection.dashboard,
    FinanceSection.accounts,
    FinanceSection.ledger,
    FinanceSection.budgets,
    FinanceSection.scheduled,
  ];

  var selected = FinanceSection.dashboard;
  String? ledgerAccountFilterId;
  var _appliedLaunchPreference = false;
  var _isScrolling = false;
  Timer? _scrollSettleTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedLaunchPreference) return;
    selected = financeSectionForLaunchScreen(
      FinanceDataStoreScope.read(context).preferences.launchScreen,
    );
    _appliedLaunchPreference = true;
  }

  @override
  void dispose() {
    _scrollSettleTimer?.cancel();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _scrollSettleTimer?.cancel();
      if (!_isScrolling) setState(() => _isScrolling = true);
    } else if (notification is ScrollEndNotification) {
      _scrollSettleTimer?.cancel();
      _scrollSettleTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted && _isScrolling) {
          setState(() => _isScrolling = false);
        }
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 880;
    final dataStore = FinanceDataStoreScope.watch(context);
    final preferences = dataStore.preferences;
    final dueScheduledCount = dataStore.scheduledDueOrOverdueCount();

    return Scaffold(
      body: SafeArea(child: isWide ? _wideLayout() : _compactLayout()),
      floatingActionButton: selected.supportsFloatingAdd
          ? Builder(
              builder: (context) {
                final reduceMotion = MediaQuery.of(context).disableAnimations;
                final duration = reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180);
                return IgnorePointer(
                  ignoring: _isScrolling,
                  child: AnimatedScale(
                    scale: _isScrolling ? 0.78 : 1,
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _isScrolling ? 0.18 : 1,
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      child: MoneyTallyFloatingActionButton(
                        tooltip: 'Add',
                        onPressed: () => showFloatingAddMenu(context),
                        child: const Icon(Icons.add),
                      ),
                    ),
                  ),
                );
              },
            )
          : null,
      floatingActionButtonLocation:
          switch (preferences.floatingAddButtonPosition) {
            FloatingAddButtonPosition.left =>
              FloatingActionButtonLocation.startFloat,
            FloatingAddButtonPosition.center =>
              FloatingActionButtonLocation.centerFloat,
            FloatingAddButtonPosition.right =>
              FloatingActionButtonLocation.endFloat,
          },
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: compactSections.contains(selected)
                  ? compactSections.indexOf(selected)
                  : 0,
              onDestinationSelected: (index) =>
                  setState(() => selected = compactSections[index]),
              destinations: [
                for (final section in compactSections)
                  NavigationDestination(
                    icon: FinanceSectionIcon(
                      section: section,
                      dueScheduledCount: dueScheduledCount,
                    ),
                    label: section.label,
                  ),
              ],
            ),
    );
  }

  Widget _wideLayout() {
    final dueScheduledCount = FinanceDataStoreScope.watch(
      context,
    ).scheduledDueOrOverdueCount();
    return Row(
      children: [
        NavigationRail(
          extended: MediaQuery.sizeOf(context).width >= 1100,
          selectedIndex: FinanceSection.values.indexOf(selected),
          onDestinationSelected: (index) =>
              setState(() => selected = FinanceSection.values[index]),
          leading: const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Icon(Icons.account_balance, color: AppTheme.accent),
          ),
          destinations: [
            for (final section in FinanceSection.values)
              NavigationRailDestination(
                icon: FinanceSectionIcon(
                  section: section,
                  dueScheduledCount: dueScheduledCount,
                ),
                label: Text(section.label),
              ),
          ],
        ),
        const VerticalDivider(width: 1, color: AppTheme.line),
        Expanded(child: _sectionBody()),
      ],
    );
  }

  Widget _compactLayout() {
    return _sectionBody();
  }

  Widget _sectionBody() {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: CustomScrollView(
        slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            section: selected,
            syncLabel: widget.syncLabel,
            onSignOut: widget.onSignOut,
            onOpenSettings: () =>
                setState(() => selected = FinanceSection.settings),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            selected.supportsFloatingAdd ? 112 : 24,
          ),
          sliver: SliverToBoxAdapter(
            child: switch (selected) {
              FinanceSection.dashboard => const DashboardView(),
              FinanceSection.accounts => AccountsView(
                onOpenLedgerForAccount: (accountId) => setState(() {
                  ledgerAccountFilterId = accountId;
                  selected = FinanceSection.ledger;
                }),
              ),
              FinanceSection.ledger => LedgerView(
                initialAccountFilterId: ledgerAccountFilterId,
              ),
              FinanceSection.budgets => const BudgetsView(),
              FinanceSection.scheduled => const ScheduledView(),
              FinanceSection.reports => const ReportsView(),
              FinanceSection.categories => const CategoriesView(),
              FinanceSection.settings => SettingsView(
                onSelectSection: (section) => setState(() {
                  selected = section;
                }),
              ),
            },
          ),
        ),
        ],
      ),
    );
  }
}

class FinanceSectionIcon extends StatelessWidget {
  const FinanceSectionIcon({
    required this.section,
    required this.dueScheduledCount,
    super.key,
  });

  final FinanceSection section;
  final int dueScheduledCount;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(section.icon);
    if (section != FinanceSection.scheduled || dueScheduledCount == 0) {
      return icon;
    }
    return CountBadge(count: dueScheduledCount, child: icon);
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge({required this.count, required this.child, super.key});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: child),
          Positioned(
            top: -1,
            right: -1,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.rose,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.section,
    required this.syncLabel,
    required this.onOpenSettings,
    this.onSignOut,
    super.key,
  });

  final FinanceSection section;
  final String syncLabel;
  final VoidCallback onOpenSettings;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Money Tally',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SyncPill(label: syncLabel, onSignOut: onSignOut),
                    SizedBox(
                      height: 26,
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      visualDensity: VisualDensity.compact,
                      onPressed: onOpenSettings,
                      icon: const Icon(Icons.settings_outlined, size: 21),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            section.label,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class SyncPill extends StatelessWidget {
  const SyncPill({required this.label, this.onSignOut, super.key});

  final String label;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayLabel = switch (label) {
      'Local only' => 'Local only',
      'Sync issue' => 'Sync issue',
      _ => 'Synced',
    };
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_queue, color: AppTheme.accent, size: 15),
            const SizedBox(width: 6),
            SizedBox(
              width: 62,
              child: Text(
                displayLabel,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (onSignOut != null) ...[
              const SizedBox(width: 2),
              Tooltip(
                message: 'Sign out',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(24, 24),
                    fixedSize: const Size(24, 24),
                  ),
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout, size: 15),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DialogFieldGroup extends StatelessWidget {
  const DialogFieldGroup({
    required this.label,
    required this.child,
    this.helperText,
    super.key,
  });

  final String label;
  final Widget child;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

InputDecoration dialogFieldDecoration({String? hintText}) {
  return InputDecoration(
    hintText: hintText,
    floatingLabelBehavior: FloatingLabelBehavior.never,
  );
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final scheduled = [...store.scheduledTransactions]
      ..removeWhere((item) => item.isDeleted)
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    final incomeThisMonth = store.incomeThisMonthMinor();
    final expensesThisMonth = store.expensesThisMonthMinor();
    final currency = store.preferences.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NetWorthHeroCard(
          netWorthMinor: store.netWorthMinor,
          assetsMinor: store.totalAssetsMinor,
          liabilitiesMinor: store.totalLiabilitiesMinor,
          currency: currency,
        ),
        const SizedBox(height: AppSpacing.sm),
        DashboardCardFlow(
          children: [
            CashSummaryCard(
              availableCashMinor: store.availableCashMinor,
              currency: currency,
            ),
            ThisMonthSummaryCard(
              incomeMinor: incomeThisMonth,
              expensesMinor: expensesThisMonth,
              currency: currency,
            ),
            NextScheduledCard(scheduled: scheduled, currency: currency),
            const AccountBalancePanel(
              title: 'Accounts Preview',
              maxRows: 4,
              compact: true,
            ),
            const BudgetPanel(
              title: 'Budgets Preview',
              maxRows: 3,
              compact: true,
            ),
            const RecentTransactionsPanel(
              title: 'Recent Transactions',
              maxRows: 3,
              compact: true,
            ),
          ],
        ),
      ],
    );
  }
}

class NetWorthHeroCard extends StatelessWidget {
  const NetWorthHeroCard({
    required this.netWorthMinor,
    required this.assetsMinor,
    required this.liabilitiesMinor,
    required this.currency,
    super.key,
  });

  final int netWorthMinor;
  final int assetsMinor;
  final int liabilitiesMinor;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: AppTheme.accent,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'NET WORTH',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            MoneyText(
              amountMinor: netWorthMinor,
              currency: currency,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: HeroMetric(
                    label: 'Assets',
                    amountMinor: assetsMinor,
                    currency: currency,
                    color: Colors.white,
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: colors.onPrimary.withValues(alpha: 0.18),
                ),
                Expanded(
                  child: HeroMetric(
                    label: 'Liabilities',
                    amountMinor: liabilitiesMinor,
                    currency: currency,
                    color: Colors.white,
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

class HeroMetric extends StatelessWidget {
  const HeroMetric({
    required this.label,
    required this.amountMinor,
    required this.currency,
    required this.color,
    super.key,
  });

  final String label;
  final int amountMinor;
  final CurrencyFormatSettings currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.74),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          MoneyText(
            amountMinor: amountMinor,
            currency: currency,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ],
      ),
    );
  }
}

class CashSummaryCard extends StatelessWidget {
  const CashSummaryCard({
    required this.availableCashMinor,
    required this.currency,
    super.key,
  });

  final int availableCashMinor;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Cash Summary',
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: CompactMetricRow(
        label: 'Available Cash',
        amountMinor: availableCashMinor,
        currency: currency,
        icon: Icons.payments_outlined,
      ),
    );
  }
}

class ThisMonthSummaryCard extends StatelessWidget {
  const ThisMonthSummaryCard({
    required this.incomeMinor,
    required this.expensesMinor,
    required this.currency,
    super.key,
  });

  final int incomeMinor;
  final int expensesMinor;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'This Month',
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          CompactMetricRow(
            label: 'Income',
            amountMinor: incomeMinor,
            currency: currency,
            icon: Icons.add_circle_outline,
            showPositiveSign: true,
          ),
          CompactMetricRow(
            label: 'Expenses',
            amountMinor: -expensesMinor.abs(),
            currency: currency,
            icon: Icons.remove_circle_outline,
          ),
          CompactMetricRow(
            label: 'Remaining',
            amountMinor: incomeMinor - expensesMinor,
            currency: currency,
            icon: Icons.savings_outlined,
            showPositiveSign: incomeMinor - expensesMinor > 0,
          ),
        ],
      ),
    );
  }
}

class NextScheduledCard extends StatelessWidget {
  const NextScheduledCard({
    required this.scheduled,
    required this.currency,
    super.key,
  });

  final List<v2_scheduled.ScheduledTransactionRecord> scheduled;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final next = scheduled.isEmpty ? null : scheduled.first;
    return AppCard(
      title: 'Next Scheduled',
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: next == null
          ? const CompactEmptyRow(
              icon: Icons.event_repeat_outlined,
              label: 'No scheduled transactions',
            )
          : Row(
              children: [
                const Icon(Icons.event_repeat_outlined, color: AppTheme.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        next.payee,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        shortDate(next.nextDate),
                        style: TextStyle(
                          color: AppTheme.ink.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                MoneyText(
                  amountMinor: next.type.name == 'expense'
                      ? -next.amountMinor.abs()
                      : next.amountMinor,
                  currency: currency,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: next.type.name == 'expense'
                      ? AppTheme.rose
                      : AppTheme.ink,
                  showPositiveSign: next.type.name == 'income',
                ),
              ],
            ),
    );
  }
}

class CompactMetricRow extends StatelessWidget {
  const CompactMetricRow({
    required this.label,
    required this.amountMinor,
    required this.currency,
    required this.icon,
    this.showPositiveSign = false,
    super.key,
  });

  final String label;
  final int amountMinor;
  final CurrencyFormatSettings currency;
  final IconData icon;
  final bool showPositiveSign;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          MoneyText(
            amountMinor: amountMinor,
            currency: currency,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: amountMinor < 0 ? AppTheme.rose : AppTheme.ink,
            showPositiveSign: showPositiveSign,
          ),
        ],
      ),
    );
  }
}

class CompactEmptyRow extends StatelessWidget {
  const CompactEmptyRow({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.ink.withValues(alpha: 0.68),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class AccountsView extends StatelessWidget {
  const AccountsView({this.onOpenLedgerForAccount, super.key});

  final ValueChanged<String>? onOpenLedgerForAccount;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final accounts = store.activeAccountsInDisplayOrder;
    if (accounts.isEmpty) {
      return const AppCard(
        child: Text(
          'No accounts yet',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in store.accountGroupsInDisplayOrder)
          if (accounts.any((account) => account.group == group))
            AccountGroupCard(
              group: group,
              accounts: accounts
                  .where((account) => account.group == group)
                  .toList(growable: false),
              store: store,
              onOpenLedgerForAccount: onOpenLedgerForAccount,
            ),
      ],
    );
  }
}

class AccountGroupCard extends StatelessWidget {
  const AccountGroupCard({
    required this.group,
    required this.accounts,
    required this.store,
    this.onOpenLedgerForAccount,
    super.key,
  });

  final v2_account.AccountGroup group;
  final List<v2_account.AccountRecord> accounts;
  final FinanceDataStore store;
  final ValueChanged<String>? onOpenLedgerForAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCollapsed = store.preferences.collapsedAccountGroupNames.contains(
      group.name,
    );
    final label = store.accountGroupLabel(group);
    final balanceMinor = accounts
        .where((account) => account.includeInGroupBalance)
        .fold(
          0,
          (total, account) => total + store.balanceForAccount(account.id),
        );
    final progress = accountGroupProgress(context, store, group);
    final headerTextStyle = theme.textTheme.titleMedium?.copyWith(
      color: AppTheme.accentStrong,
      fontSize: 19,
      fontWeight: FontWeight.w700,
    );

    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Tooltip(
              message: isCollapsed ? 'Expand $label' : 'Collapse $label',
              child: InkWell(
                key: ValueKey('account-group-${group.name}'),
                borderRadius: BorderRadius.circular(AppRadii.card),
                onTap: () => toggleAccountGroupCollapsed(
                  context,
                  group,
                  isCollapsed: isCollapsed,
                ),
                onLongPress: () => showAccountGroupActions(context, group),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedRotation(
                        turns: isCollapsed ? -0.25 : 0,
                        duration: MediaQuery.of(context).disableAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.arrow_drop_down_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: headerTextStyle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        height: 28,
                        constraints: const BoxConstraints(minWidth: 112),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: MoneyText(
                          amountMinor: balanceMinor,
                          currency: store.preferences.currency,
                          color: balanceMinor < 0 ? AppColors.danger : null,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 175),
              reverseDuration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 145),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: isCollapsed
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (progress != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          progress,
                        ],
                        const SizedBox(height: AppSpacing.xs),
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.55,
                          ),
                        ),
                        for (
                          var index = 0;
                          index < accounts.length;
                          index++
                        )
                          AccountCard(
                            account: accounts[index],
                            balanceMinor: store.balanceForAccount(
                              accounts[index].id,
                            ),
                            currency: store.preferences.currency,
                            subtitle: lastAccountActivitySubtitle(
                              store,
                              accounts[index].id,
                            ),
                            balanceFontSize: 17,
                            framed: false,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            leading: Icon(
                              accountGroupIcon(group.name),
                              color: AppTheme.accent,
                              size: 22,
                            ),
                            onTap: onOpenLedgerForAccount == null
                                ? null
                                : () => onOpenLedgerForAccount!(
                                    accounts[index].id,
                                  ),
                            onLongPress: () => showAccountOptions(
                              context,
                              accounts[index].id,
                            ),
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

String lastAccountActivitySubtitle(
  FinanceDataStore store,
  String accountId,
) {
  final activity = store.transactions
      .where(
        (transaction) =>
            !transaction.isDeleted &&
            (transaction.accountId == accountId ||
                transaction.transferAccountId == accountId),
      )
      .toList(growable: false)
    ..sort((a, b) => b.date.compareTo(a.date));
  if (activity.isEmpty) return 'No transactions yet';

  final latest = activity.first;
  final payee = latest.payee.trim().isEmpty
      ? transactionTypeLabel(latest.type)
      : latest.payee.trim();
  return '$payee · ${compactDate(latest.date)}';
}

Widget? accountGroupProgress(
  BuildContext context,
  FinanceDataStore store,
  v2_account.AccountGroup group,
) {
  switch (group) {
    case v2_account.AccountGroup.creditCards:
      final limit = store.creditLimitMinorForGroup(group);
      if (limit <= 0) return null;
      final used = store.creditUsedMinorForGroup(group);
      return AccountGroupProgressStrip(
        label:
            'Credit used ${money(used, store.preferences.currency)} of ${money(limit, store.preferences.currency)}',
        progress: used / limit,
        isOver: used > limit,
      );
    case v2_account.AccountGroup.loans:
      final original = store.originalLoanAmountMinorForGroup(group);
      if (original <= 0) return null;
      final remaining = store.remainingLoanMinorForGroup(group);
      final rawPaidDown = original - remaining;
      final paidDown = rawPaidDown < 0
          ? 0
          : rawPaidDown > original
          ? original
          : rawPaidDown;
      return AccountGroupProgressStrip(
        label:
            'Paid down ${money(paidDown, store.preferences.currency)} of ${money(original, store.preferences.currency)}',
        progress: paidDown / original,
      );
    case v2_account.AccountGroup.banking:
    case v2_account.AccountGroup.cash:
      return null;
  }
}

class AccountGroupProgressStrip extends StatelessWidget {
  const AccountGroupProgressStrip({
    required this.label,
    required this.progress,
    this.isOver = false,
    super.key,
  });

  final String label;
  final double progress;
  final bool isOver;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFeatures: const [AppTextStyles.tabularFigures],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: SizedBox(
              height: 5,
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.75),
                color: isOver ? AppColors.danger : AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> toggleAccountGroupCollapsed(
  BuildContext context,
  v2_account.AccountGroup group, {
  required bool isCollapsed,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final collapsedNames = {...store.preferences.collapsedAccountGroupNames};
  if (isCollapsed) {
    collapsedNames.remove(group.name);
  } else {
    collapsedNames.add(group.name);
  }
  await store.savePreferences(
    store.preferences.copyWith(collapsedAccountGroupNames: collapsedNames),
  );
}

Future<void> showAccountGroupActions(
  BuildContext context,
  v2_account.AccountGroup group,
) async {
  final store = FinanceDataStoreScope.read(context);
  final groups = store.accountGroupsInDisplayOrder;
  final groupIndex = groups.indexOf(group);
  final canMoveUp = groupIndex > 0;
  final canMoveDown = groupIndex >= 0 && groupIndex < groups.length - 1;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(sheetContext, 'rename'),
          ),
          ListTile(
            enabled: canMoveUp,
            leading: const Icon(Icons.arrow_upward),
            title: const Text('Move Up'),
            onTap: canMoveUp
                ? () => Navigator.pop(sheetContext, 'moveUp')
                : null,
          ),
          ListTile(
            enabled: canMoveDown,
            leading: const Icon(Icons.arrow_downward),
            title: const Text('Move Down'),
            onTap: canMoveDown
                ? () => Navigator.pop(sheetContext, 'moveDown')
                : null,
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  switch (action) {
    case 'rename':
      await showRenameAccountGroupDialog(context, group);
    case 'moveUp':
      await store.moveAccountGroup(group: group, direction: -1);
    case 'moveDown':
      await store.moveAccountGroup(group: group, direction: 1);
  }
}

Future<void> showRenameAccountGroupDialog(
  BuildContext context,
  v2_account.AccountGroup group,
) async {
  final store = FinanceDataStoreScope.read(context);
  final controller = TextEditingController(
    text: store.accountGroupLabel(group),
  );
  final label = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Rename account group'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'Group name',
          hintText: group.defaultLabel,
        ),
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (!context.mounted || label == null) return;
  await store.renameAccountGroup(group: group, label: label);
}

class LedgerView extends StatefulWidget {
  const LedgerView({this.initialAccountFilterId, super.key});

  final String? initialAccountFilterId;

  @override
  State<LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends State<LedgerView> {
  var query = '';
  var typeFilterName = '';
  var accountFilterId = '';
  var categoryFilterId = '';
  var dateFilter = LedgerDateFilter.all;

  @override
  void initState() {
    super.initState();
    accountFilterId = widget.initialAccountFilterId ?? '';
  }

  @override
  void didUpdateWidget(covariant LedgerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAccountFilterId != oldWidget.initialAccountFilterId &&
        widget.initialAccountFilterId != null) {
      accountFilterId = widget.initialAccountFilterId!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final activeAccounts = store.activeAccountsInDisplayOrder;
    final activeCategories = store.categories
        .where((category) => category.isVisible)
        .toList(growable: false);
    final accountsById = {
      for (final account in store.accounts) account.id: account,
    };
    final categoriesById = {
      for (final category in store.categories) category.id: category,
    };
    final normalizedQuery = query.trim().toLowerCase();
    final transactions =
        store.transactions
            .where((transaction) => !transaction.isDeleted)
            .where(
              (transaction) => transactionMatchesSearch(
                transaction,
                normalizedQuery,
                accountName: accountsById[transaction.accountId]?.name,
                categoryName: transaction.categoryId == null
                    ? null
                    : categoriesById[transaction.categoryId]?.name,
              ),
            )
            .where(
              (transaction) => transactionMatchesLedgerFilters(
                transaction,
                typeFilterName: typeFilterName,
                accountFilterId: accountFilterId,
                categoryFilterId: categoryFilterId,
                dateFilter: dateFilter,
                now: DateTime.now(),
              ),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final hasFilters =
        typeFilterName.isNotEmpty ||
        accountFilterId.isNotEmpty ||
        categoryFilterId.isNotEmpty ||
        dateFilter != LedgerDateFilter.all;
    final selectedTypeLabel = typeFilterName.isEmpty
        ? 'Type'
        : transactionTypeLabel(
            TransactionType.values.firstWhere(
              (type) => type.name == typeFilterName,
              orElse: () => TransactionType.expense,
            ),
          );
    final selectedAccountLabel = accountFilterId.isEmpty
        ? 'Account'
        : accountsById[accountFilterId]?.name ?? 'Account';
    final selectedCategoryLabel = categoryFilterId.isEmpty
        ? 'Category'
        : categoriesById[categoryFilterId]?.name ?? 'Category';
    final selectedDateLabel = dateFilter == LedgerDateFilter.all
        ? 'Date'
        : ledgerDateFilterLabel(dateFilter);
    final activeFilterCount = [
      typeFilterName.isNotEmpty,
      accountFilterId.isNotEmpty,
      categoryFilterId.isNotEmpty,
      dateFilter != LedgerDateFilter.all,
    ].where((isActive) => isActive).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search transactions',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('ledger-filter-button'),
                onPressed: () => showLedgerFilters(
                  context: context,
                  activeAccounts: activeAccounts,
                  activeCategories: activeCategories,
                  selectedTypeLabel: selectedTypeLabel,
                  selectedAccountLabel: selectedAccountLabel,
                  selectedCategoryLabel: selectedCategoryLabel,
                  selectedDateLabel: selectedDateLabel,
                ),
                icon: const Icon(Icons.tune_outlined),
                label: Text(
                  activeFilterCount == 0
                      ? 'Filters'
                      : 'Filters ($activeFilterCount)',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: 'Clear filters',
              child: TextButton.icon(
                onPressed: hasFilters ? clearFilters : null,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Clear'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (transactions.isEmpty)
          AppCard(
            child: Center(
              child: Text(
                'No transactions match',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final transaction in transactions) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TransactionRow(
                transaction: transaction,
                currency: store.preferences.currency,
                accountName: accountsById[transaction.accountId]?.name,
                categoryName: transaction.categoryId == null
                    ? null
                    : categoriesById[transaction.categoryId]?.name,
                dateLabel: compactDate(transaction.date),
                onTap: () => showTransactionDetails(context, transaction.id),
                onLongPress: () =>
                    showTransactionOptions(context, transaction.id),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
      ],
    );
  }

  void clearFilters() {
    setState(() {
      typeFilterName = '';
      accountFilterId = '';
      categoryFilterId = '';
      dateFilter = LedgerDateFilter.all;
    });
  }

  Future<void> showLedgerFilters({
    required BuildContext context,
    required List<v2_account.AccountRecord> activeAccounts,
    required List<v2_category.CategoryRecord> activeCategories,
    required String selectedTypeLabel,
    required String selectedAccountLabel,
    required String selectedCategoryLabel,
    required String selectedDateLabel,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Filters',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  LedgerFilterButton<String>(
                    buttonKey: ValueKey('ledger-type-$typeFilterName'),
                    icon: Icons.tune_outlined,
                    label: selectedTypeLabel,
                    isActive: typeFilterName.isNotEmpty,
                    items: [
                      const PopupMenuItem(value: '', child: Text('All types')),
                      for (final type in TransactionType.values)
                        PopupMenuItem(
                          value: type.name,
                          child: Text(transactionTypeLabel(type)),
                        ),
                    ],
                    onSelected: (value) {
                      setState(() => typeFilterName = value);
                      Navigator.pop(sheetContext);
                    },
                  ),
                  LedgerFilterButton<String>(
                    buttonKey: ValueKey('ledger-account-$accountFilterId'),
                    icon: Icons.account_balance_wallet_outlined,
                    label: selectedAccountLabel,
                    isActive: accountFilterId.isNotEmpty,
                    items: [
                      const PopupMenuItem(
                        value: '',
                        child: Text('All accounts'),
                      ),
                      for (final account in activeAccounts)
                        PopupMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onSelected: (value) {
                      setState(() => accountFilterId = value);
                      Navigator.pop(sheetContext);
                    },
                  ),
                  LedgerFilterButton<String>(
                    buttonKey: ValueKey('ledger-category-$categoryFilterId'),
                    icon: Icons.sell_outlined,
                    label: selectedCategoryLabel,
                    isActive: categoryFilterId.isNotEmpty,
                    items: [
                      const PopupMenuItem(
                        value: '',
                        child: Text('All categories'),
                      ),
                      for (final category in activeCategories)
                        PopupMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onSelected: (value) {
                      setState(() => categoryFilterId = value);
                      Navigator.pop(sheetContext);
                    },
                  ),
                  LedgerFilterButton<LedgerDateFilter>(
                    buttonKey: ValueKey('ledger-date-${dateFilter.name}'),
                    icon: Icons.calendar_today_outlined,
                    label: selectedDateLabel,
                    isActive: dateFilter != LedgerDateFilter.all,
                    items: [
                      for (final filter in LedgerDateFilter.values)
                        PopupMenuItem(
                          value: filter,
                          child: Text(ledgerDateFilterLabel(filter)),
                        ),
                    ],
                    onSelected: (value) {
                      setState(() => dateFilter = value);
                      Navigator.pop(sheetContext);
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: () {
                  clearFilters();
                  Navigator.pop(sheetContext);
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Clear filters'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LedgerFilterButton<T> extends StatelessWidget {
  const LedgerFilterButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.items,
    required this.onSelected,
    this.isActive = false,
    super.key,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isActive ? Colors.white : AppTheme.accent;
    final background = isActive
        ? AppTheme.accent
        : AppTheme.accent.withValues(alpha: 0.08);
    final border = isActive
        ? AppTheme.accent
        : AppTheme.accent.withValues(alpha: 0.18);

    return PopupMenuButton<T>(
      key: buttonKey,
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: Container(
        height: 40,
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Icon(Icons.keyboard_arrow_down, size: 18, color: foreground),
          ],
        ),
      ),
    );
  }
}

bool transactionMatchesSearch(
  TransactionRecord transaction,
  String query, {
  String? accountName,
  String? categoryName,
}) {
  if (query.isEmpty) return true;
  return [
    transaction.payee,
    transaction.note,
    accountName,
    categoryName,
    transaction.type.name,
  ].whereType<String>().any((value) => value.toLowerCase().contains(query));
}

enum LedgerDateFilter { all, today, thisMonth, last30Days }

bool transactionMatchesLedgerFilters(
  TransactionRecord transaction, {
  required String typeFilterName,
  required String accountFilterId,
  required String categoryFilterId,
  required LedgerDateFilter dateFilter,
  required DateTime now,
}) {
  if (typeFilterName.isNotEmpty && transaction.type.name != typeFilterName) {
    return false;
  }
  if (accountFilterId.isNotEmpty &&
      transaction.accountId != accountFilterId &&
      transaction.transferAccountId != accountFilterId) {
    return false;
  }
  if (categoryFilterId.isNotEmpty &&
      transaction.categoryId != categoryFilterId &&
      !transaction.splitLines.any(
        (line) => line.categoryId == categoryFilterId,
      )) {
    return false;
  }

  final transactionDay = DateTime(
    transaction.date.year,
    transaction.date.month,
    transaction.date.day,
  );
  final today = DateTime(now.year, now.month, now.day);
  return switch (dateFilter) {
    LedgerDateFilter.all => true,
    LedgerDateFilter.today => transactionDay == today,
    LedgerDateFilter.thisMonth =>
      transaction.date.year == now.year && transaction.date.month == now.month,
    LedgerDateFilter.last30Days =>
      !transactionDay.isBefore(today.subtract(const Duration(days: 30))) &&
          !transactionDay.isAfter(today),
  };
}

String transactionTypeLabel(TransactionType type) {
  return switch (type) {
    TransactionType.expense => 'Expense',
    TransactionType.income => 'Income',
    TransactionType.transfer => 'Transfer',
    TransactionType.adjustment => 'Adjustment',
  };
}

Future<void> showDefaultTransactionDialog(
  BuildContext context, {
  String? initialAccountId,
}) async {
  final preferences = FinanceDataStoreScope.read(context).preferences;
  final shouldOpenTransfer = switch (preferences.defaultTransactionType) {
    DefaultTransactionType.transfer => true,
    DefaultTransactionType.lastUsed =>
      preferences.lastUsedTransactionType == TransactionType.transfer,
    DefaultTransactionType.expense || DefaultTransactionType.income => false,
  };

  if (shouldOpenTransfer) {
    await showTransferDialog(context, initialFromAccountId: initialAccountId);
    return;
  }

  await showTransactionDialog(
    context,
    initialIsExpense: isExpenseDefault(preferences),
    initialAccountId: initialAccountId,
  );
}

String ledgerDateFilterLabel(LedgerDateFilter filter) {
  return switch (filter) {
    LedgerDateFilter.all => 'All dates',
    LedgerDateFilter.today => 'Today',
    LedgerDateFilter.thisMonth => 'This month',
    LedgerDateFilter.last30Days => 'Last 30 days',
  };
}

Future<void> showTransactionOptions(
  BuildContext context,
  String transactionId,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final transaction = dataStore.transactions.firstWhere(
    (item) => item.id == transactionId,
  );
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            enabled:
                transaction.type == TransactionType.expense ||
                transaction.type == TransactionType.income ||
                transaction.type == TransactionType.transfer,
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap:
                transaction.type == TransactionType.expense ||
                    transaction.type == TransactionType.income ||
                    transaction.type == TransactionType.transfer
                ? () => Navigator.pop(sheetContext, 'edit')
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Duplicate'),
            onTap: () => Navigator.pop(sheetContext, 'duplicate'),
          ),
          ListTile(
            enabled:
                transaction.type == TransactionType.expense ||
                transaction.type == TransactionType.income,
            leading: const Icon(Icons.call_split_outlined),
            title: const Text('Split'),
            onTap:
                transaction.type == TransactionType.expense ||
                    transaction.type == TransactionType.income
                ? () => Navigator.pop(sheetContext, 'split')
                : null,
          ),
          ListTile(
            enabled: transaction.type != TransactionType.adjustment,
            leading: const Icon(Icons.event_repeat_outlined),
            title: const Text('Make Scheduled'),
            onTap: transaction.type != TransactionType.adjustment
                ? () => Navigator.pop(sheetContext, 'schedule')
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            textColor: AppTheme.rose,
            iconColor: AppTheme.rose,
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  switch (action) {
    case 'edit':
      if (transaction.type == TransactionType.transfer) {
        await showTransferDialog(context, transfer: transaction);
      } else {
        await showTransactionDialog(context, transaction: transaction);
      }
    case 'duplicate':
      await duplicateTransaction(context, transaction);
    case 'split':
      await showSplitTransactionDialog(context, transaction);
    case 'schedule':
      await makeTransactionScheduled(context, transaction);
    case 'delete':
      await deleteTransaction(context, transaction);
  }
}

Future<void> showTransactionDetails(
  BuildContext context,
  String transactionId,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final transaction = dataStore.transactions.firstWhere(
    (item) => item.id == transactionId,
  );
  final accountsById = {
    for (final account in dataStore.accounts) account.id: account,
  };
  final categoriesById = {
    for (final category in dataStore.categories) category.id: category,
  };
  final canEdit =
      transaction.type == TransactionType.expense ||
      transaction.type == TransactionType.income ||
      transaction.type == TransactionType.transfer;
  final signedAmount = switch (transaction.type) {
    TransactionType.expense => -transaction.amountMinor.abs(),
    TransactionType.income => transaction.amountMinor.abs(),
    TransactionType.transfer => transaction.amountMinor.abs(),
    TransactionType.adjustment => transaction.amountMinor,
  };
  final amountColor = signedAmount < 0
      ? AppColors.danger
      : transaction.type == TransactionType.income
      ? AppTheme.accent
      : null;
  final detailBackground = Theme.of(context).brightness == Brightness.dark
      ? AppColors.panelDark
      : AppTheme.panel;

  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Transaction details',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadii.control),
                      ),
                      child: Icon(
                        transactionDetailIcon(transaction.type),
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transaction.payee,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            '${transactionTypeLabel(transaction.type)} • ${dateInput(transaction.date)}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppTheme.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: detailBackground,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.35
                            : 0.55,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Amount',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppTheme.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        money(signedAmount, dataStore.preferences.currency),
                        style: AppTextStyles.money(
                          context,
                          fontSize: 34,
                          color: amountColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TransactionDetailRow(
                  label: 'Account',
                  value: accountsById[transaction.accountId]?.name ?? 'Unknown',
                ),
                if (transaction.transferAccountId != null)
                  TransactionDetailRow(
                    label: 'Transfer to',
                    value:
                        accountsById[transaction.transferAccountId]?.name ??
                        'Unknown',
                  ),
                if (transaction.categoryId != null)
                  TransactionDetailRow(
                    label: 'Category',
                    value:
                        categoriesById[transaction.categoryId]?.name ??
                        'Unknown',
                  ),
                if (transaction.note.trim().isNotEmpty)
                  TransactionDetailRow(label: 'Note', value: transaction.note),
                if (transaction.splitLines.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Splits',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.muted,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final split in transaction.splitLines)
                    TransactionDetailRow(
                      label:
                          categoriesById[split.categoryId]?.name ?? 'Category',
                      value: money(
                        split.amountMinor,
                        dataStore.preferences.currency,
                      ),
                    ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: canEdit
                          ? () => Navigator.pop(dialogContext, 'edit')
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (!context.mounted || action != 'edit') return;
  if (transaction.type == TransactionType.transfer) {
    await showTransferDialog(context, transfer: transaction);
  } else {
    await showTransactionDialog(context, transaction: transaction);
  }
}

IconData transactionDetailIcon(TransactionType type) {
  return switch (type) {
    TransactionType.expense => Icons.remove_circle_outline,
    TransactionType.income => Icons.add_circle_outline,
    TransactionType.transfer => Icons.swap_horiz,
    TransactionType.adjustment => Icons.tune_outlined,
  };
}

class TransactionDetailRow extends StatelessWidget {
  const TransactionDetailRow({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTheme.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: label == 'Amount'
                    ? const [AppTextStyles.tabularFigures]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> duplicateTransaction(
  BuildContext context,
  TransactionRecord transaction,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  await dataStore.saveTransaction(
    TransactionRecord(
      id: 'txn_${DateTime.now().microsecondsSinceEpoch}',
      type: transaction.type,
      accountId: transaction.accountId,
      transferAccountId: transaction.transferAccountId,
      categoryId: transaction.categoryId,
      date: transaction.date,
      payee: '${transaction.payee} copy',
      amountMinor: transaction.amountMinor,
      note: transaction.note,
      status: transaction.status,
      splitLines: transaction.splitLines,
      scheduledTransactionId: transaction.scheduledTransactionId,
      sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
    ),
  );
}

Future<void> deleteTransaction(
  BuildContext context,
  TransactionRecord transaction,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  await dataStore.saveTransaction(
    transaction.copyWith(
      sync: transaction.sync.deleted(deviceId: dataStore.deviceId),
    ),
  );
}

Future<void> showSplitTransactionDialog(
  BuildContext context,
  TransactionRecord transaction,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final categories = categoriesForTransactionKind(
    dataStore,
    transaction.type == TransactionType.expense,
  );
  if (categories.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a category before splitting')),
    );
    return;
  }

  final defaultCategoryId = transaction.categoryId ?? categories.first.id;
  final drafts = transaction.splitLines.isEmpty
      ? [
          SplitLineDraft(
            categoryId: defaultCategoryId,
            amountMinor: transaction.amountMinor.abs(),
          ),
          SplitLineDraft(categoryId: categories.first.id, amountMinor: 0),
        ]
      : [
          for (final line in transaction.splitLines)
            SplitLineDraft(
              categoryId: line.categoryId,
              amountMinor: line.amountMinor,
              noteText: line.note,
            ),
        ];
  var errorText = '';

  final splitLines = await showDialog<List<TransactionSplitLine>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Split transaction'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < drafts.length; index += 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: drafts[index].categoryId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                            ),
                            items: [
                              for (final category in categories)
                                DropdownMenuItem(
                                  value: category.id,
                                  child: Text(category.name),
                                ),
                            ],
                            onChanged: (value) => setDialogState(
                              () => drafts[index].categoryId =
                                  value ?? drafts[index].categoryId,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: AmountEntryField(
                            fieldKey: ValueKey('split-amount-$index'),
                            initialMinor: drafts[index].amountMinor,
                            currency: dataStore.preferences.currency,
                            labelText: 'Amount',
                            onChanged: (value) =>
                                drafts[index].amountMinor = value,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove split line',
                          onPressed: drafts.length > 1
                              ? () =>
                                    setDialogState(() => drafts.removeAt(index))
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setDialogState(
                      () => drafts.add(
                        SplitLineDraft(
                          categoryId: categories.first.id,
                          amountMinor: 0,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add line'),
                  ),
                ),
                if (errorText.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorText,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final lines = [
                for (var index = 0; index < drafts.length; index += 1)
                  if (drafts[index].amountMinor.abs() > 0)
                    TransactionSplitLine(
                      id: 'split_${DateTime.now().microsecondsSinceEpoch}_$index',
                      categoryId: drafts[index].categoryId,
                      amountMinor: drafts[index].amountMinor.abs(),
                      note: drafts[index].note.text,
                    ),
              ];
              final total = lines.fold(
                0,
                (runningTotal, line) => runningTotal + line.amountMinor,
              );
              if (lines.isEmpty) {
                setDialogState(() => errorText = 'Add at least one split line');
                return;
              }
              if (total != transaction.amountMinor.abs()) {
                setDialogState(
                  () => errorText =
                      'Split total must equal ${money(transaction.amountMinor.abs(), dataStore.preferences.currency)}',
                );
                return;
              }
              Navigator.pop(context, lines);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  if (splitLines == null) return;
  await dataStore.saveTransaction(transaction.copyWith(splitLines: splitLines));
}

class SplitLineDraft {
  SplitLineDraft({
    required this.categoryId,
    required this.amountMinor,
    String noteText = '',
  }) : note = TextEditingController(text: noteText);

  String categoryId;
  int amountMinor;
  final TextEditingController note;
}

Future<void> makeTransactionScheduled(
  BuildContext context,
  TransactionRecord transaction,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final schedule = v2_scheduled.ScheduledTransactionRecord(
    id: 'sched_${DateTime.now().microsecondsSinceEpoch}',
    type: transaction.type,
    accountId: transaction.accountId,
    transferAccountId: transaction.type == TransactionType.transfer
        ? transaction.transferAccountId
        : null,
    categoryId: transaction.type == TransactionType.transfer
        ? null
        : transaction.categoryId,
    payee: transaction.payee,
    amountMinor: transaction.amountMinor.abs(),
    nextDate: firstMonthlyDateAfter(transaction.date, DateTime.now()),
    frequency: v2_scheduled.RecurrenceFrequency.monthly,
    sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
  );
  await dataStore.saveScheduledTransaction(schedule);
  await dataStore.saveTransaction(
    transaction.copyWith(scheduledTransactionId: schedule.id),
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Scheduled ${transaction.payee} monthly')),
  );
}

DateTime firstMonthlyDateAfter(DateTime sourceDate, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  var candidate = DateTime(
    sourceDate.year,
    sourceDate.month + 1,
    sourceDate.day,
  );
  while (!candidate.isAfter(today)) {
    candidate = DateTime(candidate.year, candidate.month + 1, candidate.day);
  }
  return candidate;
}

class BudgetsView extends StatelessWidget {
  const BudgetsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const BudgetPanel(showAll: true);
  }
}

class ScheduledView extends StatefulWidget {
  const ScheduledView({super.key});

  @override
  State<ScheduledView> createState() => _ScheduledViewState();
}

class _ScheduledViewState extends State<ScheduledView> {
  var _calendarCollapsed = false;
  late DateTime _visibleMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  DateTime? _selectedDate;
  var _hasAlignedVisibleMonth = false;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final scheduled = [...store.scheduledTransactions]
      ..removeWhere((item) => item.isDeleted)
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    if (!_hasAlignedVisibleMonth &&
        scheduled.isNotEmpty &&
        scheduled.every(
          (item) =>
              item.nextDate.year != _visibleMonth.year ||
              item.nextDate.month != _visibleMonth.month,
        )) {
      _visibleMonth = DateTime(
        scheduled.first.nextDate.year,
        scheduled.first.nextDate.month,
      );
    }
    _hasAlignedVisibleMonth = true;
    final visibleScheduled = _selectedDate == null
        ? scheduled
        : scheduled
              .where((item) => isSameDay(item.nextDate, _selectedDate!))
              .toList(growable: false);
    final groupedScheduled = scheduledByDate(visibleScheduled);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            ScheduledCalendarPreview(
              month: _visibleMonth,
              scheduledTransactions: scheduled,
              isCollapsed: _calendarCollapsed,
              onToggleCollapsed: () =>
                  setState(() => _calendarCollapsed = !_calendarCollapsed),
              onPreviousMonth: () => setState(
                () => _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month - 1,
                ),
              ),
              onNextMonth: () => setState(
                () => _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month + 1,
                ),
              ),
              selectedDate: _selectedDate,
              onSelectDate: (date) => setState(() {
                _selectedDate = date;
                _visibleMonth = DateTime(date.year, date.month);
              }),
            ),
            const Divider(height: 1),
            if (visibleScheduled.isEmpty)
              ListTile(
                leading: const Icon(
                  Icons.event_busy_outlined,
                  color: AppTheme.muted,
                ),
                title: Text(
                  _selectedDate == null
                      ? 'No scheduled transactions'
                      : 'No scheduled transactions for ${shortDate(_selectedDate!)}',
                ),
              )
            else
              for (final entry in groupedScheduled.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      shortDate(entry.key),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                for (final item in entry.value)
                  ScheduledTransactionRow(
                    scheduledTransaction: item,
                    currency: store.preferences.currency,
                    onLongPress: () =>
                        showScheduledTransactionActions(context, item),
                  ),
              ],
            const Divider(height: 1),
            const ListTile(
              leading: Icon(
                Icons.notifications_outlined,
                color: AppTheme.accent,
              ),
              title: Text('Local alerts'),
              subtitle: Text(
                'Enabled alerts are scheduled locally for this device.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScheduledCalendarPreview extends StatelessWidget {
  const ScheduledCalendarPreview({
    required this.month,
    required this.scheduledTransactions,
    required this.isCollapsed,
    required this.onToggleCollapsed,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.selectedDate,
    required this.onSelectDate,
    super.key,
  });

  final DateTime month;
  final List<v2_scheduled.ScheduledTransactionRecord> scheduledTransactions;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transactionCountByDay = <int, int>{};
    for (final item in scheduledTransactions) {
      if (item.nextDate.year != month.year ||
          item.nextDate.month != month.month) {
        continue;
      }
      transactionCountByDay[item.nextDate.day] =
          (transactionCountByDay[item.nextDate.day] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  monthLabel(month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: isCollapsed ? 'Expand calendar' : 'Collapse calendar',
                onPressed: onToggleCollapsed,
                icon: AnimatedRotation(
                  turns: isCollapsed ? 0 : 0.5,
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: isCollapsed
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: ScheduledCalendarGrid(
              month: month,
              transactionCountByDay: transactionCountByDay,
              selectedDate: selectedDate,
              onSelectDate: onSelectDate,
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class ScheduledCalendarGrid extends StatelessWidget {
  const ScheduledCalendarGrid({
    required this.month,
    required this.transactionCountByDay,
    required this.selectedDate,
    required this.onSelectDate,
    super.key,
  });

  final DateTime month;
  final Map<int, int> transactionCountByDay;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = daysInMonth(month);
    final firstWeekdayOffset = DateTime(month.year, month.month).weekday % 7;
    final rows = ((firstWeekdayOffset + days) / 7).ceil();
    return Column(
      children: [
        Row(
          children: [
            for (final label in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Builder(
                  builder: (context) {
                    final day = dayForCalendarCell(
                      row: row,
                      column: column,
                      firstWeekdayOffset: firstWeekdayOffset,
                      daysInMonth: days,
                    );
                    return Expanded(
                      child: ScheduledCalendarDayCell(
                        day: day,
                        month: month,
                        transactionCount: day == null
                            ? 0
                            : transactionCountByDay[day] ?? 0,
                        isSelected:
                            selectedDate != null &&
                            selectedDate!.year == month.year &&
                            selectedDate!.month == month.month &&
                            selectedDate!.day == day,
                        onSelectDate: onSelectDate,
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class ScheduledCalendarDayCell extends StatelessWidget {
  const ScheduledCalendarDayCell({
    required this.day,
    required this.month,
    required this.transactionCount,
    required this.isSelected,
    required this.onSelectDate,
    super.key,
  });

  final int? day;
  final DateTime month;
  final int transactionCount;
  final bool isSelected;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (day == null) {
      return const SizedBox(height: 48);
    }
    final isMarked = transactionCount > 0;
    return SizedBox(
      height: 48,
      child: Center(
        child: InkWell(
          key: ValueKey(
            'scheduled-calendar-day-${month.year}-${month.month}-$day',
          ),
          borderRadius: BorderRadius.circular(18),
          onTap: () => onSelectDate(DateTime(month.year, month.month, day!)),
          child: SizedBox(
            width: 40,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent
                          : isMarked
                          ? AppTheme.accent.withValues(alpha: 0.10)
                          : null,
                      borderRadius: BorderRadius.circular(18),
                      border: isMarked && !isSelected
                          ? Border.all(
                              color: AppTheme.accent.withValues(alpha: 0.30),
                            )
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isMarked || isSelected
                              ? FontWeight.w900
                              : FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : isMarked
                              ? AppTheme.accent
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                if (transactionCount > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 17,
                        minHeight: 17,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.surface
                            : AppTheme.accent,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        transactionCount > 99 ? '99+' : '$transactionCount',
                        style: TextStyle(
                          color: isSelected
                              ? AppTheme.accent
                              : theme.colorScheme.onPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
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

class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final categories = store.categories
        .where((category) => category.isVisible)
        .toList(growable: false);
    final displayCategories = categoriesInDisplayOrder(categories);
    final categoriesById = {
      for (final category in categories) category.id: category,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => showCategoryDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add category'),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final category in displayCategories)
                Padding(
                  padding: EdgeInsets.only(
                    left: category.parentCategoryId == null ? 0 : 20,
                  ),
                  child: ListTile(
                    onLongPress: () => showCategoryActions(context, category),
                    leading: CircleAvatar(
                      backgroundColor: category.colorValue == null
                          ? AppTheme.line
                          : Color(category.colorValue!),
                      child: Icon(
                        categoryIcon(category),
                        color: AppTheme.ink,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      category.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(categorySubtitle(category, categoriesById)),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () =>
                          showCategoryDialog(context, categoryId: category.id),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({this.onSelectSection, super.key});

  final ValueChanged<FinanceSection>? onSelectSection;

  static const _currencyOptions = [
    CurrencyFormatSettings(currencyCode: 'USD', symbol: r'$'),
    CurrencyFormatSettings(currencyCode: 'PHP', symbol: 'PHP '),
    CurrencyFormatSettings(currencyCode: 'EUR', symbol: 'EUR '),
    CurrencyFormatSettings(currencyCode: 'GBP', symbol: 'GBP '),
    CurrencyFormatSettings(currencyCode: 'CAD', symbol: r'C$'),
    CurrencyFormatSettings(currencyCode: 'AUD', symbol: r'A$'),
    CurrencyFormatSettings(currencyCode: 'JPY', symbol: 'JPY '),
  ];

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final preferences = store.preferences;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          title: 'App Preferences',
          child: Column(
            children: [
              SettingsDropdown<LaunchScreen>(
                label: 'Launch screen',
                value: preferences.launchScreen,
                values: LaunchScreen.values,
                labelOf: launchScreenLabel,
                onChanged: (value) => store.savePreferences(
                  preferences.copyWith(launchScreen: value),
                ),
              ),
              const SizedBox(height: 12),
              SettingsDropdown<AppearanceMode>(
                label: 'Appearance',
                value: preferences.appearanceMode,
                values: AppearanceMode.values,
                labelOf: appearanceModeLabel,
                onChanged: (value) => store.savePreferences(
                  preferences.copyWith(appearanceMode: value),
                ),
              ),
              const SizedBox(height: 12),
              SettingsDropdown<FloatingAddButtonPosition>(
                label: 'Floating add button',
                value: preferences.floatingAddButtonPosition,
                values: FloatingAddButtonPosition.values,
                labelOf: floatingAddButtonPositionLabel,
                onChanged: (value) => store.savePreferences(
                  preferences.copyWith(floatingAddButtonPosition: value),
                ),
              ),
              const SizedBox(height: 12),
              SettingsDropdown<DefaultTransactionType>(
                label: 'Default transaction type',
                value: preferences.defaultTransactionType,
                values: DefaultTransactionType.values,
                labelOf: defaultTransactionTypeLabel,
                onChanged: (value) => store.savePreferences(
                  preferences.copyWith(defaultTransactionType: value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Money Format',
          child: Column(
            children: [
              SettingsDropdown<CurrencyFormatSettings>(
                label: 'Currency',
                value: _currencyFor(preferences.currency.currencyCode),
                values: _currencyOptions,
                labelOf: (value) => value.currencyCode,
                onChanged: (value) => store.savePreferences(
                  preferences.copyWith(
                    currency: value.copyWith(
                      decimalPlaces: preferences.currency.decimalPlaces,
                      thousandsSeparator:
                          preferences.currency.thousandsSeparator,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SettingsActionRow(
                icon: Icons.edit_outlined,
                title: 'Custom currency',
                trailingText:
                    '${preferences.currency.currencyCode} ${preferences.currency.symbol}',
                onTap: () => showCustomCurrencyDialog(context),
              ),
              const SizedBox(height: 12),
              SettingsDropdown<int>(
                label: 'Decimal places',
                value: preferences.currency.decimalPlaces,
                values: const [0, 2],
                labelOf: (value) => '$value',
                onChanged: (value) => store.savePreferences(
                  preferences.copyWith(
                    currency: preferences.currency.copyWith(
                      decimalPlaces: value,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SettingsDropdown<String>(
                label: 'Thousands separator',
                value: preferences.currency.thousandsSeparator,
                values: const [',', '.', ' ', ''],
                labelOf: thousandsSeparatorLabel,
                onChanged: (value) => store.savePreferences(
                  preferences.copyWith(
                    currency: preferences.currency.copyWith(
                      thousandsSeparator: value,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Notifications',
          child: SettingsSwitch(
            label: 'Scheduled transaction alerts',
            value: preferences.notificationsEnabled,
            onChanged: (value) => store.savePreferences(
              preferences.copyWith(notificationsEnabled: value),
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Manage',
          child: Column(
            children: [
              SettingsActionRow(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Manage accounts',
                trailingText: 'Open',
                onTap: () => onSelectSection?.call(FinanceSection.accounts),
              ),
              SettingsActionRow(
                icon: Icons.sell_outlined,
                title: 'Manage categories',
                trailingText: 'Open',
                onTap: () => onSelectSection?.call(FinanceSection.categories),
              ),
              SettingsActionRow(
                icon: Icons.person_outline,
                title: 'Manage payees',
                trailingText: 'Open',
                onTap: () => showPayeesSheet(context),
              ),
              SettingsActionRow(
                icon: Icons.pie_chart_outline,
                title: 'Manage budgets',
                trailingText: 'Open',
                onTap: () => onSelectSection?.call(FinanceSection.budgets),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'More',
          child: Column(
            children: [
              SettingsActionRow(
                icon: Icons.insights_outlined,
                title: 'Reports',
                trailingText: 'Open',
                onTap: () => onSelectSection?.call(FinanceSection.reports),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Data Ownership',
          child: Column(
            children: [
              SettingsActionRow(
                icon: Icons.file_download_outlined,
                title: 'Export CSV',
                trailingText: 'Copy',
                onTap: () => copyExportToClipboard(
                  context,
                  title: 'CSV export copied',
                  payload: const BackupCodec().encodeTransactionsCsv(
                    store.dataSet,
                  ),
                ),
              ),
              SettingsActionRow(
                icon: Icons.data_object_outlined,
                title: 'Export JSON',
                trailingText: 'Copy',
                onTap: () => copyExportToClipboard(
                  context,
                  title: 'JSON backup copied',
                  payload: const BackupCodec().encodeJson(store.dataSet),
                ),
              ),
              SettingsActionRow(
                icon: Icons.restore_outlined,
                title: 'Backup and restore',
                trailingText: 'Restore JSON',
                onTap: () => restoreJsonBackupFromClipboard(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static CurrencyFormatSettings _currencyFor(String code) {
    return _currencyOptions.firstWhere(
      (option) => option.currencyCode == code,
      orElse: () => _currencyOptions.first,
    );
  }
}

Future<void> showPayeesSheet(BuildContext context) async {
  final payees = savedPayees(FinanceDataStoreScope.read(context));
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Saved payees',
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (payees.isEmpty)
              Text(
                'Payees appear here after transactions are saved.',
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: payees.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) => ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(payees[index]),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showCustomCurrencyDialog(BuildContext context) async {
  final store = FinanceDataStoreScope.read(context);
  final preferences = store.preferences;
  final code = TextEditingController(text: preferences.currency.currencyCode);
  final symbol = TextEditingController(text: preferences.currency.symbol);
  final result = await showDialog<({String currencyCode, String symbol})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Custom currency'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Currency code'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: symbol,
              decoration: const InputDecoration(labelText: 'Symbol'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, (
            currencyCode: code.text.trim().toUpperCase(),
            symbol: symbol.text,
          )),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (result == null) return;
  final currencyCode = result.currencyCode.isEmpty
      ? preferences.currency.currencyCode
      : result.currencyCode;
  final currencySymbol = result.symbol.trim().isEmpty
      ? preferences.currency.symbol
      : result.symbol;
  await store.savePreferences(
    preferences.copyWith(
      currency: preferences.currency.copyWith(
        currencyCode: currencyCode,
        symbol: currencySymbol,
      ),
    ),
  );
}

class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final currency = store.preferences.currency;
    final now = DateTime.now();
    final income = store.incomeThisMonthMinor(now: now);
    final expenses = store.expensesThisMonthMinor(now: now);
    final categoryTotals = spendingByCategoryThisMonth(store, now: now);
    final categoriesById = {
      for (final category in store.categories) category.id: category,
    };
    final budgets = store.budgets.where((budget) => budget.isVisible);

    return Column(
      children: [
        ResponsiveGrid(
          minTileWidth: 320,
          children: [
            AppCard(
              title: 'Monthly spending',
              child: Column(
                children: [
                  ReportMetricRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'Expenses',
                    value: money(expenses, currency),
                  ),
                  ReportMetricRow(
                    icon: Icons.compare_arrows_outlined,
                    label: 'Income',
                    value: money(income, currency),
                  ),
                ],
              ),
            ),
            AppCard(
              title: 'Income vs expenses',
              child: Column(
                children: [
                  ReportMetricRow(
                    icon: Icons.add_circle_outline,
                    label: 'Income',
                    value: money(income, currency),
                  ),
                  ReportMetricRow(
                    icon: Icons.remove_circle_outline,
                    label: 'Expenses',
                    value: money(expenses, currency),
                    isWarning: expenses > income,
                  ),
                ],
              ),
            ),
            AppCard(
              title: 'Cash flow',
              child: ReportMetricRow(
                icon: Icons.waterfall_chart_outlined,
                label: 'This month',
                value: money(income - expenses, currency),
                isWarning: income - expenses < 0,
              ),
            ),
            AppCard(
              title: 'Net worth history',
              child: Column(
                children: [
                  ReportMetricRow(
                    icon: Icons.flag_outlined,
                    label: 'Opening',
                    value: money(store.openingNetWorthMinor, currency),
                  ),
                  ReportMetricRow(
                    icon: Icons.timeline_outlined,
                    label: 'Ledger change',
                    value: money(store.netWorthLedgerChangeMinor, currency),
                    isWarning: store.netWorthLedgerChangeMinor < 0,
                  ),
                  ReportMetricRow(
                    icon: Icons.show_chart_outlined,
                    label: 'Current',
                    value: money(store.netWorthMinor, currency),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Category breakdown',
          child: Column(
            children: [
              if (categoryTotals.isEmpty)
                const ReportMetricRow(
                  icon: Icons.pie_chart_outline,
                  label: 'No spending this month',
                  value: '',
                ),
              for (final entry in sortedCategoryTotals(categoryTotals).take(6))
                ReportMetricRow(
                  icon: categoryIconForId(entry.key, categoriesById),
                  label: categoriesById[entry.key]?.name ?? 'Uncategorized',
                  value: money(entry.value, currency),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Budget history',
          child: Column(
            children: [
              if (budgets.isEmpty)
                const ReportMetricRow(
                  icon: Icons.ssid_chart_outlined,
                  label: 'No active budgets',
                  value: '',
                ),
              for (final budget in budgets.take(6))
                ReportMetricRow(
                  icon: Icons.ssid_chart_outlined,
                  label: budget.name,
                  value:
                      '${money(store.spentThisMonthForBudget(budget, now: now), currency)} / ${money(budget.amountMinor, currency)}',
                  isWarning: budget.isOverBudget(
                    store.spentThisMonthForBudget(budget, now: now),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReportMetricRow extends StatelessWidget {
  const ReportMetricRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isWarning = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: isWarning ? AppTheme.rose : AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: TextStyle(
                color: isWarning ? AppTheme.rose : AppTheme.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      borderRadius: BorderRadius.circular(8),
      items: [
        for (final item in values)
          DropdownMenuItem<T>(value: item, child: Text(labelOf(item))),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      value: value,
      activeThumbColor: AppTheme.accent,
      onChanged: onChanged,
    );
  }
}

class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    required this.icon,
    required this.title,
    required this.trailingText,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String trailingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      trailing: Text(
        trailingText,
        style: const TextStyle(color: AppTheme.muted),
      ),
      onTap: onTap,
    );
  }
}

Future<void> copyExportToClipboard(
  BuildContext context, {
  required String title,
  required String payload,
}) async {
  await Clipboard.setData(ClipboardData(text: payload));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(title)));
}

Future<void> restoreJsonBackupFromClipboard(BuildContext context) async {
  final store = FinanceDataStoreScope.read(context);
  final clipboardData = await Clipboard.getData('text/plain');
  final rawJson = clipboardData?.text;
  if (rawJson == null || rawJson.trim().isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clipboard does not contain a JSON backup')),
    );
    return;
  }

  try {
    final restored = const BackupCodec().decodeJson(rawJson);
    await store.replaceDataSet(restored);
    await store.refreshScheduledNotifications();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('JSON backup restored')));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not restore JSON backup')),
    );
  }
}

class AccountBalancePanel extends StatelessWidget {
  const AccountBalancePanel({
    this.title = 'Accounts',
    this.maxRows,
    this.compact = false,
    super.key,
  });

  final String title;
  final int? maxRows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final currency = store.preferences.currency;
    final accounts = store.accounts
        .where((account) => account.isVisible)
        .take(maxRows ?? store.accounts.length);
    return AppCard(
      title: title,
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      child: Column(
        children: [
          if (accounts.isEmpty)
            const CompactEmptyRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'No accounts yet',
            ),
          for (final account in accounts)
            MetricRow(
              label: account.name,
              value: money(store.balanceForAccount(account.id), currency),
              icon: accountGroupIcon(account.group.name),
              compact: compact,
            ),
        ],
      ),
    );
  }
}

class UpcomingPanel extends StatelessWidget {
  const UpcomingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final currency = store.preferences.currency;
    final scheduled = [...store.scheduledTransactions]
      ..removeWhere((item) => item.isDeleted)
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    final dueCount = store.scheduledDueOrOverdueCount();
    return AppCard(
      title: 'Scheduled',
      child: Column(
        children: [
          if (dueCount > 0)
            MetricRow(
              label: 'Due today',
              value: '$dueCount',
              icon: Icons.notification_important_outlined,
            ),
          for (final item in scheduled.take(3))
            MetricRow(
              label: item.payee,
              value:
                  '${money(item.type.name == 'expense' ? -item.amountMinor.abs() : item.amountMinor, currency)} · ${dateShort(item.nextDate)}',
              icon: Icons.event_repeat_outlined,
            ),
        ],
      ),
    );
  }
}

class BudgetPanel extends StatelessWidget {
  const BudgetPanel({
    this.showAll = false,
    this.title = 'Budgets',
    this.maxRows,
    this.compact = false,
    super.key,
  });

  final bool showAll;
  final String title;
  final int? maxRows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final budgets = store.budgets
        .where((budget) => budget.isVisible)
        .toList(growable: false);
    final visibleBudgets = showAll ? budgets : budgets.take(maxRows ?? 3);
    return AppCard(
      title: title,
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      child: Column(
        children: [
          if (showAll) ...[
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => showBudgetDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add budget'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (visibleBudgets.isEmpty)
            const CompactEmptyRow(
              icon: Icons.pie_chart_outline,
              label: 'No budgets yet',
            ),
          for (final budget in visibleBudgets)
            BudgetProgressRow(budget: budget),
        ],
      ),
    );
  }
}

class RecentTransactionsPanel extends StatelessWidget {
  const RecentTransactionsPanel({
    this.title = 'Recent ledger',
    this.maxRows = 3,
    this.compact = false,
    super.key,
  });

  final String title;
  final int maxRows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final transactions = [...store.transactions]
      ..removeWhere((transaction) => transaction.isDeleted)
      ..sort((a, b) => b.date.compareTo(a.date));
    final accountsById = {
      for (final account in store.accounts) account.id: account,
    };
    final categoriesById = {
      for (final category in store.categories) category.id: category,
    };
    return AppCard(
      title: title,
      padding: EdgeInsets.fromLTRB(
        compact ? AppSpacing.sm : AppSpacing.md,
        compact ? AppSpacing.sm : AppSpacing.md,
        compact ? AppSpacing.sm : AppSpacing.md,
        compact ? AppSpacing.xs : AppSpacing.sm,
      ),
      child: Column(
        children: [
          if (transactions.isEmpty)
            const CompactEmptyRow(
              icon: Icons.receipt_long_outlined,
              label: 'No recent transactions',
            ),
          for (final transaction in transactions.take(maxRows))
            TransactionRow(
              transaction: transaction,
              currency: store.preferences.currency,
              accountName: accountsById[transaction.accountId]?.name,
              categoryName: transaction.categoryId == null
                  ? null
                  : categoriesById[transaction.categoryId]?.name,
            ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    this.isPrimary = false,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final color = isPrimary ? Colors.white : AppTheme.ink;
    return Card(
      color: isPrimary ? AppTheme.accent : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: isPrimary ? Colors.white : AppTheme.accent),
            const SizedBox(height: 18),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: color.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.title,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: title == null
            ? child
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    child,
                  ],
                ),
              ),
      ),
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    required this.children,
    this.minTileWidth = 240,
    super.key,
  });

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(
          1,
          4,
        );
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: minTileWidth >= 340 ? 1.18 : 1.35,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class DashboardCardFlow extends StatelessWidget {
  const DashboardCardFlow({
    required this.children,
    this.minTileWidth = 320,
    super.key,
  });

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(
          1,
          3,
        );
        final itemWidth =
            (constraints.maxWidth - ((columns - 1) * AppSpacing.sm)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class MetricRow extends StatelessWidget {
  const MetricRow({
    required this.label,
    required this.value,
    required this.icon,
    this.compact = false,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? AppSpacing.xs : AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent, size: compact ? 18 : 20),
          SizedBox(width: compact ? AppSpacing.xs : AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 14 : null,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: compact ? 14 : null,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.transaction, super.key});

  final LedgerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final store = FinanceStoreScope.watch(context);
    final category = store.categoryById(transaction.categoryId);
    final account = store.accountById(transaction.accountId);
    final currency = currencyForContext(context);

    return ListTile(
      leading: Container(
        width: 10,
        height: 42,
        decoration: BoxDecoration(
          color: category.color,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      title: Text(
        transaction.payee,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        '${dateShort(transaction.date)} · ${category.name} · ${account.name}',
      ),
      trailing: Text(
        money(transaction.amountCents, currency),
        style: TextStyle(
          color: transaction.amountCents < 0 ? AppTheme.rose : AppTheme.accent,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class ScheduledTile extends StatelessWidget {
  const ScheduledTile({required this.item, super.key});

  final ScheduledTransaction item;

  @override
  Widget build(BuildContext context) {
    final store = FinanceStoreScope.watch(context);
    final category = store.categoryById(item.categoryId);
    final account = store.accountById(item.accountId);
    final currency = currencyForContext(context);

    return ListTile(
      leading: const Icon(Icons.event_repeat_outlined, color: AppTheme.accent),
      title: Text(
        item.payee,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        '${category.name} · ${account.name} · ${item.frequency.name}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            money(item.amountCents, currency),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          Text(
            dateShort(item.nextDate),
            style: const TextStyle(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class BudgetProgressRow extends StatelessWidget {
  const BudgetProgressRow({required this.budget, super.key});

  final BudgetRecord budget;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final currency = store.preferences.currency;
    final spent = store.spentThisMonthForBudget(budget);
    final remaining = budget.remainingMinor(spent);
    final isOver = budget.isOverBudget(spent);
    final categorySummary = budgetCategorySummary(store, budget);

    return InkWell(
      onLongPress: () => showBudgetActions(context, budget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    budget.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  isOver
                      ? 'Over by ${money(remaining.abs(), currency)}'
                      : '${money(remaining, currency)} left',
                  style: TextStyle(
                    color: isOver ? AppTheme.rose : AppTheme.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Spent ${money(spent, currency)} of ${money(budget.amountMinor, currency)}',
              style: const TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 4),
            Text(
              categorySummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: const TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 8),
            BudgetProgressBar(
              spentMinor: spent,
              budgetMinor: budget.amountMinor,
            ),
          ],
        ),
      ),
    );
  }
}

String budgetCategorySummary(FinanceDataStore store, BudgetRecord budget) {
  if (budget.categoryIds.isEmpty) return 'No categories selected';
  final categoriesById = {
    for (final category in store.categories) category.id: category,
  };
  final names = [
    for (final categoryId in budget.categoryIds)
      categoriesById[categoryId]?.name ?? 'Unknown category',
  ];
  final visibleNames = names.take(3).join(', ');
  final hiddenCount = names.length - 3;
  if (hiddenCount <= 0) return 'Categories: $visibleNames';
  return 'Categories: $visibleNames, +$hiddenCount more';
}

Future<void> showBudgetDialog(
  BuildContext context, {
  BudgetRecord? budget,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final name = TextEditingController(text: budget?.name ?? '');
  var amountMinor = budget?.amountMinor ?? 0;
  final selectedCategoryIds = {...?budget?.categoryIds};
  final categories = dataStore.categories
      .where(
        (category) =>
            category.isVisible &&
            category.kind == v2_category.CategoryKind.expense,
      )
      .toList(growable: false);

  final result =
      await showDialog<
        ({String name, int amountMinor, List<String> categoryIds})
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(budget == null ? 'Add budget' : 'Edit budget'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Name'),
                      textCapitalization: TextCapitalization.words,
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    AmountEntryField(
                      initialMinor: amountMinor,
                      currency: dataStore.preferences.currency,
                      labelText: 'Budget amount',
                      onChanged: (value) => amountMinor = value,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Categories',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final category in categories)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(category.name),
                        value: selectedCategoryIds.contains(category.id),
                        activeColor: AppTheme.accent,
                        onChanged: (value) => setDialogState(() {
                          if (value ?? false) {
                            selectedCategoryIds.add(category.id);
                          } else {
                            selectedCategoryIds.remove(category.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  name: name.text.trim(),
                  amountMinor: amountMinor.abs(),
                  categoryIds: selectedCategoryIds.toList(),
                )),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );

  if (result == null || result.name.isEmpty) return;
  if (budget == null) {
    await dataStore.saveBudget(
      BudgetRecord(
        id: 'budget_${DateTime.now().microsecondsSinceEpoch}',
        name: result.name,
        amountMinor: result.amountMinor,
        categoryIds: result.categoryIds,
        sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
      ),
    );
    return;
  }

  await dataStore.saveBudget(
    budget.copyWith(
      name: result.name,
      amountMinor: result.amountMinor,
      categoryIds: result.categoryIds,
    ),
  );
}

Future<void> showBudgetActions(
  BuildContext context,
  BudgetRecord budget,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () => Navigator.pop(sheetContext, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archive'),
            onTap: () => Navigator.pop(sheetContext, 'archive'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            textColor: AppTheme.rose,
            iconColor: AppTheme.rose,
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  switch (action) {
    case 'edit':
      await showBudgetDialog(context, budget: budget);
    case 'archive':
      await FinanceDataStoreScope.read(context).archiveBudget(budget.id);
    case 'delete':
      await FinanceDataStoreScope.read(context).deleteBudget(budget.id);
  }
}

Future<void> showAdjustBalanceDialog(
  BuildContext context,
  v2_account.AccountRecord account,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  var targetBalanceMinor = dataStore.balanceForAccount(account.id);
  final value = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Adjust ${account.name}'),
      content: SizedBox(
        width: 360,
        child: AmountEntryField(
          fieldKey: const ValueKey('account-adjust-balance'),
          initialMinor: targetBalanceMinor,
          currency: dataStore.preferences.currency,
          labelText: 'Target balance',
          autofocus: true,
          allowNegative: true,
          keyboardType: TextInputType.number,
          onChanged: (value) => targetBalanceMinor = value,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, targetBalanceMinor),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (value == null) return;
  await dataStore.adjustAccountBalance(
    accountId: account.id,
    targetBalanceMinor: value,
    date: DateTime.now(),
  );
}

Future<void> showAccountOptions(BuildContext context, String accountId) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final account = dataStore.accountById(accountId);
  final groupAccounts = dataStore.activeAccountsInDisplayOrder
      .where((item) => item.group == account.group)
      .toList(growable: false);
  final accountIndex = groupAccounts.indexWhere((item) => item.id == accountId);
  final canMoveUp = accountIndex > 0;
  final canMoveDown =
      accountIndex >= 0 && accountIndex < groupAccounts.length - 1;
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Add Expense'),
              onTap: () => Navigator.pop(context, 'expense'),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add Income'),
              onTap: () => Navigator.pop(context, 'income'),
            ),
            ListTile(
              enabled: dataStore.activeAccountsInDisplayOrder.length > 1,
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transfer'),
              onTap: dataStore.activeAccountsInDisplayOrder.length > 1
                  ? () => Navigator.pop(context, 'transfer')
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Adjust Balance'),
              onTap: () => Navigator.pop(context, 'adjust'),
            ),
            ListTile(
              enabled: canMoveUp,
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Move Up'),
              onTap: canMoveUp ? () => Navigator.pop(context, 'moveUp') : null,
            ),
            ListTile(
              enabled: canMoveDown,
              leading: const Icon(Icons.arrow_downward),
              title: const Text('Move Down'),
              onTap: canMoveDown
                  ? () => Navigator.pop(context, 'moveDown')
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Change Type'),
              onTap: () => Navigator.pop(context, 'changeType'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              onTap: () => Navigator.pop(context, 'archive'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              textColor: AppTheme.rose,
              iconColor: AppTheme.rose,
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    ),
  );

  if (action == 'expense' && context.mounted) {
    await showTransactionDialog(
      context,
      initialIsExpense: true,
      initialAccountId: account.id,
    );
  } else if (action == 'income' && context.mounted) {
    await showTransactionDialog(
      context,
      initialIsExpense: false,
      initialAccountId: account.id,
    );
  } else if (action == 'transfer' && context.mounted) {
    await showTransferDialog(context, initialFromAccountId: account.id);
  } else if (action == 'adjust' && context.mounted) {
    await showAdjustBalanceDialog(context, account);
  } else if (action == 'moveUp') {
    await dataStore.moveAccountWithinGroup(accountId: accountId, direction: -1);
  } else if (action == 'moveDown') {
    await dataStore.moveAccountWithinGroup(accountId: accountId, direction: 1);
  } else if (action == 'changeType' && context.mounted) {
    await showChangeAccountTypeDialog(context, account);
  } else if (action == 'edit' && context.mounted) {
    await showEditAccountDialog(context, account);
  } else if (action == 'archive' && context.mounted) {
    await dataStore.archiveAccount(account.id);
  } else if (action == 'delete' && context.mounted) {
    await dataStore.deleteAccount(account.id);
  }
}

Future<void> showChangeAccountTypeDialog(
  BuildContext context,
  v2_account.AccountRecord account,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final selectedType = await showModalBottomSheet<v2_account.AccountType>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in v2_account.AccountType.values)
            ListTile(
              leading: Icon(v2AccountIcon(type)),
              title: Text(v2AccountTypeLabel(type)),
              trailing: type == account.type
                  ? const Icon(Icons.check, color: AppTheme.accent)
                  : null,
              onTap: () => Navigator.pop(sheetContext, type),
            ),
        ],
      ),
    ),
  );
  if (selectedType == null || selectedType == account.type) return;
  await dataStore.saveAccount(
    account.copyWith(
      type: selectedType,
      clearCreditLimit: selectedType != v2_account.AccountType.creditCard,
      clearOriginalLoanAmount: selectedType != v2_account.AccountType.loan,
    ),
  );
}

Future<void> showEditAccountDialog(
  BuildContext context,
  v2_account.AccountRecord account,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final name = TextEditingController(text: account.name);
  var creditLimitMinor = account.creditLimitMinor ?? 0;
  var originalLoanAmountMinor = account.originalLoanAmountMinor ?? 0;
  var type = account.type;
  var includeInGroupBalance = account.includeInGroupBalance;
  var includeInNetWorth = account.includeInNetWorth;

  final result =
      await showDialog<
        ({
          String name,
          v2_account.AccountType type,
          int? creditLimitMinor,
          int? originalLoanAmountMinor,
          bool includeInGroupBalance,
          bool includeInNetWorth,
        })
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit account'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<v2_account.AccountType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final item in v2_account.AccountType.values)
                        DropdownMenuItem(
                          value: item,
                          child: Text(v2AccountTypeLabel(item)),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => type = value ?? type),
                  ),
                  if (type == v2_account.AccountType.creditCard) ...[
                    const SizedBox(height: 12),
                    AmountEntryField(
                      fieldKey: const ValueKey('account-credit-limit'),
                      initialMinor: creditLimitMinor,
                      currency: dataStore.preferences.currency,
                      labelText: 'Credit limit',
                      onChanged: (value) => creditLimitMinor = value.abs(),
                    ),
                  ],
                  if (type == v2_account.AccountType.loan) ...[
                    const SizedBox(height: 12),
                    AmountEntryField(
                      fieldKey: const ValueKey('account-original-loan-amount'),
                      initialMinor: originalLoanAmountMinor,
                      currency: dataStore.preferences.currency,
                      labelText: 'Original loan amount',
                      onChanged: (value) =>
                          originalLoanAmountMinor = value.abs(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include in group balance'),
                    value: includeInGroupBalance,
                    onChanged: (value) =>
                        setDialogState(() => includeInGroupBalance = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include in net worth'),
                    value: includeInNetWorth,
                    onChanged: (value) =>
                        setDialogState(() => includeInNetWorth = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  name: name.text.trim().isEmpty
                      ? account.name
                      : name.text.trim(),
                  type: type,
                  creditLimitMinor: type == v2_account.AccountType.creditCard
                      ? optionalPositiveMinor(creditLimitMinor)
                      : null,
                  originalLoanAmountMinor: type == v2_account.AccountType.loan
                      ? optionalPositiveMinor(originalLoanAmountMinor)
                      : null,
                  includeInGroupBalance: includeInGroupBalance,
                  includeInNetWorth: includeInNetWorth,
                )),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );

  if (result == null) return;
  await dataStore.saveAccount(
    account.copyWith(
      name: result.name,
      type: result.type,
      creditLimitMinor: result.creditLimitMinor,
      originalLoanAmountMinor: result.originalLoanAmountMinor,
      clearCreditLimit: result.creditLimitMinor == null,
      clearOriginalLoanAmount: result.originalLoanAmountMinor == null,
      includeInGroupBalance: result.includeInGroupBalance,
      includeInNetWorth: result.includeInNetWorth,
    ),
  );
}

Future<void> showFloatingAddMenu(BuildContext context) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: MoneyTallyFloatingActionMenu(
        items: [
          FloatingActionMenuItem(
            label: 'Expense',
            leading: const Icon(Icons.remove_circle_outline),
            onSelected: () => Navigator.pop(sheetContext, 'expense'),
          ),
          FloatingActionMenuItem(
            label: 'Income',
            leading: const Icon(Icons.add_circle_outline),
            onSelected: () => Navigator.pop(sheetContext, 'income'),
          ),
          FloatingActionMenuItem(
            label: 'Transfer',
            leading: const Icon(Icons.swap_horiz),
            onSelected: () => Navigator.pop(sheetContext, 'transfer'),
          ),
          FloatingActionMenuItem(
            label: 'Account',
            leading: const Icon(Icons.account_balance_wallet_outlined),
            onSelected: () => Navigator.pop(sheetContext, 'account'),
          ),
          FloatingActionMenuItem(
            label: 'Category',
            leading: const Icon(Icons.sell_outlined),
            onSelected: () => Navigator.pop(sheetContext, 'category'),
          ),
          FloatingActionMenuItem(
            label: 'Scheduled Transaction',
            leading: const Icon(Icons.event_repeat_outlined),
            onSelected: () => Navigator.pop(sheetContext, 'scheduled'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || selected == null) return;
  switch (selected) {
    case 'expense':
      await showTransactionDialog(context, initialIsExpense: true);
    case 'income':
      await showTransactionDialog(context, initialIsExpense: false);
    case 'category':
      await showCategoryDialog(context);
    case 'account':
      await showAccountDialog(context);
    case 'transfer':
      await showTransferDialog(context);
    case 'scheduled':
      await showScheduledTransactionDialog(context);
  }
}

Future<void> showAccountDialog(BuildContext context) async {
  final store = FinanceStoreScope.watch(context);
  final dataStore = FinanceDataStoreScope.read(context);
  final name = TextEditingController();
  var creditLimitMinor = 0;
  var originalLoanAmountMinor = 0;
  var type = AccountType.checking;
  var openingBalanceCents = 0;

  final result =
      await showDialog<
        ({
          String name,
          AccountType type,
          int openingBalanceCents,
          int? creditLimitMinor,
          int? originalLoanAmountMinor,
        })
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add account'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AccountType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final item in AccountType.values)
                        DropdownMenuItem(
                          value: item,
                          child: Text(accountTypeLabel(item)),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => type = value ?? type),
                  ),
                  if (type == AccountType.creditCard) ...[
                    const SizedBox(height: 12),
                    AmountEntryField(
                      fieldKey: const ValueKey('account-credit-limit'),
                      initialMinor: creditLimitMinor,
                      currency: dataStore.preferences.currency,
                      labelText: 'Credit limit',
                      onChanged: (value) => creditLimitMinor = value.abs(),
                    ),
                  ],
                  if (type == AccountType.loan) ...[
                    const SizedBox(height: 12),
                    AmountEntryField(
                      fieldKey: const ValueKey('account-original-loan-amount'),
                      initialMinor: originalLoanAmountMinor,
                      currency: dataStore.preferences.currency,
                      labelText: 'Original loan amount',
                      onChanged: (value) =>
                          originalLoanAmountMinor = value.abs(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AmountEntryField(
                    initialMinor: openingBalanceCents,
                    currency: dataStore.preferences.currency,
                    labelText: 'Opening balance',
                    allowNegative: true,
                    onChanged: (value) => openingBalanceCents = value,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  name: name.text.trim().isEmpty
                      ? accountTypeLabel(type)
                      : name.text.trim(),
                  type: type,
                  openingBalanceCents: openingBalanceCents,
                  creditLimitMinor: type == AccountType.creditCard
                      ? optionalPositiveMinor(creditLimitMinor)
                      : null,
                  originalLoanAmountMinor: type == AccountType.loan
                      ? optionalPositiveMinor(originalLoanAmountMinor)
                      : null,
                )),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      );

  if (result == null) return;
  final normalizedOpeningBalanceCents = switch (result.type) {
    AccountType.creditCard ||
    AccountType.loan => -result.openingBalanceCents.abs(),
    _ => result.openingBalanceCents,
  };
  final account = store.addAccount(
    name: result.name,
    type: result.type,
    balanceCents: normalizedOpeningBalanceCents,
  );
  if (!context.mounted) return;
  await saveLegacyAccountToV2(
    context,
    account,
    dataStore: dataStore,
    creditLimitMinor: result.creditLimitMinor,
    originalLoanAmountMinor: result.originalLoanAmountMinor,
    updateCreditLimit: true,
    updateOriginalLoanAmount: true,
  );
}

Future<void> saveLegacyAccountToV2(
  BuildContext context,
  Account account, {
  FinanceDataStore? dataStore,
  int? creditLimitMinor,
  int? originalLoanAmountMinor,
  bool updateCreditLimit = false,
  bool updateOriginalLoanAmount = false,
  bool? includeInGroupBalance,
  bool? includeInNetWorth,
}) async {
  final targetStore = dataStore ?? FinanceDataStoreScope.read(context);
  v2_account.AccountRecord record;
  try {
    record = targetStore
        .accountById(account.id)
        .copyWith(
          name: account.name,
          type: v2AccountTypeFor(account.type),
          creditLimitMinor: updateCreditLimit ? creditLimitMinor : null,
          originalLoanAmountMinor: updateOriginalLoanAmount
              ? originalLoanAmountMinor
              : null,
          clearCreditLimit:
              account.type != AccountType.creditCard ||
              (updateCreditLimit && creditLimitMinor == null),
          clearOriginalLoanAmount:
              account.type != AccountType.loan ||
              (updateOriginalLoanAmount && originalLoanAmountMinor == null),
          isArchived: account.isArchived,
          includeInGroupBalance: includeInGroupBalance,
          includeInNetWorth: includeInNetWorth,
        );
  } on StateError {
    final v2Type = v2AccountTypeFor(account.type);
    final nextSortOrder = targetStore.activeAccountsInDisplayOrder
        .where((item) => item.group == v2Type.group)
        .fold(0, (highest, item) => max(highest, item.sortOrder + 100));
    record = v2_account.AccountRecord(
      id: account.id,
      name: account.name,
      type: v2Type,
      openingBalanceMinor: account.balanceCents,
      creditLimitMinor: v2Type == v2_account.AccountType.creditCard
          ? creditLimitMinor
          : null,
      originalLoanAmountMinor: v2Type == v2_account.AccountType.loan
          ? originalLoanAmountMinor ?? account.balanceCents.abs()
          : null,
      isArchived: account.isArchived,
      includeInGroupBalance: includeInGroupBalance ?? true,
      includeInNetWorth: includeInNetWorth ?? true,
      sortOrder: nextSortOrder,
      sync: v2_sync.SyncMetadata.fresh(),
    );
  }
  await targetStore.saveAccount(record);
}

Future<void> showTransferDialog(
  BuildContext context, {
  String? initialFromAccountId,
  TransactionRecord? transfer,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final accounts = dataStore.accounts
      .where((account) => account.isVisible)
      .toList(growable: false);
  if (accounts.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('At least two accounts are required')),
    );
    return;
  }

  final payeeOptions = savedPayees(dataStore);
  final payee = TextEditingController(text: transfer?.payee ?? 'Transfer');
  final date = TextEditingController(
    text: dateInput(transfer?.date ?? DateTime.now()),
  );
  final note = TextEditingController(text: transfer?.note ?? '');
  var amountMinor = transfer?.amountMinor.abs() ?? 0;
  var fromAccountId =
      accounts.any(
        (account) =>
            account.id == (transfer?.accountId ?? initialFromAccountId),
      )
      ? (transfer?.accountId ?? initialFromAccountId)!
      : accounts.first.id;
  var toAccountId =
      accounts.any((account) => account.id == transfer?.transferAccountId) &&
          transfer?.transferAccountId != fromAccountId
      ? transfer!.transferAccountId!
      : accounts.firstWhere((account) => account.id != fromAccountId).id;
  TransactionType? switchToType;

  final result =
      await showDialog<
        ({
          String fromAccountId,
          String toAccountId,
          String payee,
          DateTime date,
          String note,
          int amountMinor,
        })
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              transfer == null ? 'Add transaction' : 'Edit transaction',
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<TransactionType>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: TransactionType.expense,
                          label: Text('Expense'),
                        ),
                        ButtonSegment(
                          value: TransactionType.income,
                          label: Text('Income'),
                        ),
                        ButtonSegment(
                          value: TransactionType.transfer,
                          label: Text('Transfer'),
                        ),
                      ],
                      selected: const {TransactionType.transfer},
                      onSelectionChanged: (values) {
                        final selectedType = values.first;
                        if (selectedType == TransactionType.transfer) return;
                        switchToType = selectedType;
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 12),
                    DialogFieldGroup(
                      label: 'Payee',
                      child: TextField(
                        key: const ValueKey('transfer-payee'),
                        controller: payee,
                        textCapitalization: TextCapitalization.words,
                        decoration: dialogFieldDecoration().copyWith(
                          suffixIcon: payeeOptions.isEmpty
                              ? null
                              : PopupMenuButton<String>(
                                  tooltip: 'Saved payees',
                                  icon: const Icon(
                                    Icons.history_outlined,
                                    size: 20,
                                  ),
                                  onSelected: (value) => payee.text = value,
                                  itemBuilder: (context) => [
                                    for (final option in payeeOptions.take(12))
                                      PopupMenuItem(
                                        value: option,
                                        child: Text(option),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DialogFieldGroup(
                      label: 'Date',
                      child: TextField(
                        key: const ValueKey('transfer-date'),
                        controller: date,
                        readOnly: true,
                        showCursor: false,
                        enableInteractiveSelection: false,
                        decoration: dialogFieldDecoration(),
                        onTap: () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          final picked = await pickDateForField(
                            context,
                            parseDateInput(date.text, DateTime.now()),
                          );
                          if (picked != null) {
                            date.text = dateInput(picked);
                          }
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    DialogFieldGroup(
                      label: 'Note',
                      child: TextField(
                        key: const ValueKey('transfer-note'),
                        controller: note,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: dialogFieldDecoration(),
                        minLines: 1,
                        maxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DialogFieldGroup(
                      label: 'Amount',
                      child: AmountEntryField(
                        fieldKey: const ValueKey('transfer-amount'),
                        initialMinor: amountMinor,
                        currency: dataStore.preferences.currency,
                        labelText: null,
                        onChanged: (value) => amountMinor = value,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DialogFieldGroup(
                      label: 'From',
                      child: DropdownButtonFormField<String>(
                        initialValue: fromAccountId,
                        decoration: dialogFieldDecoration(),
                        items: [
                          for (final account in accounts)
                            DropdownMenuItem(
                              value: account.id,
                              child: Text(account.name),
                            ),
                        ],
                        onChanged: (value) => setDialogState(() {
                          fromAccountId = value ?? fromAccountId;
                          if (toAccountId == fromAccountId) {
                            toAccountId = accounts
                                .firstWhere(
                                  (account) => account.id != fromAccountId,
                                )
                                .id;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DialogFieldGroup(
                      label: 'To',
                      child: DropdownButtonFormField<String>(
                        initialValue: toAccountId,
                        decoration: dialogFieldDecoration(),
                        items: [
                          for (final account in accounts)
                            if (account.id != fromAccountId)
                              DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                        ],
                        onChanged: (value) => setDialogState(
                          () => toAccountId = value ?? toAccountId,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  fromAccountId: fromAccountId,
                  toAccountId: toAccountId,
                  payee: payee.text.trim().isEmpty
                      ? 'Transfer'
                      : payee.text.trim(),
                  date: parseDateInput(date.text, DateTime.now()),
                  note: note.text.trim(),
                  amountMinor: amountMinor.abs(),
                )),
                child: Text(transfer == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        ),
      );

  if (switchToType != null && context.mounted) {
    await showTransactionDialog(
      context,
      initialIsExpense: switchToType == TransactionType.expense,
      initialAccountId: fromAccountId,
      transaction: transfer,
    );
    return;
  }
  if (result == null) return;
  if (transfer == null) {
    await dataStore.addTransfer(
      fromAccountId: result.fromAccountId,
      toAccountId: result.toAccountId,
      date: result.date,
      payee: result.payee,
      amountMinor: result.amountMinor,
      note: result.note,
    );
  } else {
    await dataStore.saveTransaction(
      transfer.copyWith(
        type: TransactionType.transfer,
        accountId: result.fromAccountId,
        transferAccountId: result.toAccountId,
        date: result.date,
        payee: result.payee,
        amountMinor: result.amountMinor,
        note: result.note,
        clearCategory: true,
      ),
    );
  }
  await dataStore.savePreferences(
    dataStore.preferences.copyWith(
      lastUsedTransactionType: TransactionType.transfer,
    ),
  );
}

Future<void> showScheduledTransactionDialog(
  BuildContext context, {
  v2_scheduled.ScheduledTransactionRecord? existing,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final isEditing = existing != null;
  final accounts = dataStore.accounts
      .where(
        (account) =>
            account.isVisible ||
            account.id == existing?.accountId ||
            account.id == existing?.transferAccountId,
      )
      .toList(growable: false);
  if (accounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add an account before scheduling')),
    );
    return;
  }

  final payee = TextEditingController(text: existing?.payee ?? '');
  var amountMinor = existing?.amountMinor ?? 0;
  final nextDate = TextEditingController(
    text: dateInput(existing?.nextDate ?? DateTime.now()),
  );
  final customAlertTime = TextEditingController(
    text: alertTimeInput(existing?.customAlertTimeMinutes ?? 9 * 60),
  );
  var type = existing?.type ?? TransactionType.expense;
  var accountId = accounts.any((account) => account.id == existing?.accountId)
      ? existing!.accountId
      : accounts.first.id;
  var transferAccountId =
      existing?.transferAccountId ??
      (accounts.length > 1 ? accounts[1].id : null);
  var categoryId =
      existing?.categoryId ??
      defaultCategoryIdForScheduledTransaction(dataStore, type);
  var frequency =
      existing?.frequency ?? v2_scheduled.RecurrenceFrequency.monthly;
  var alertPreference =
      existing?.alertPreference ?? v2_scheduled.AlertPreference.none;
  var repeatAlertUntilResolved = existing?.repeatAlertUntilResolved ?? false;

  final result =
      await showDialog<
        ({
          TransactionType type,
          String accountId,
          String? transferAccountId,
          String? categoryId,
          String payee,
          int amountMinor,
          DateTime nextDate,
          v2_scheduled.RecurrenceFrequency frequency,
          v2_scheduled.AlertPreference alertPreference,
          int? customAlertTimeMinutes,
          bool repeatAlertUntilResolved,
        })
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final categories = scheduledCategoriesForType(dataStore, type);
            if (categoryId != null &&
                !categories.any((category) => category.id == categoryId)) {
              categoryId = categories.isEmpty ? null : categories.first.id;
            }
            if (transferAccountId == accountId) {
              transferAccountId = firstDestinationAccountId(
                accounts,
                accountId,
              );
            }

            return AlertDialog(
              title: Text(
                isEditing
                    ? 'Edit scheduled transaction'
                    : 'Add scheduled transaction',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<TransactionType>(
                        segments: [
                          const ButtonSegment(
                            value: TransactionType.expense,
                            label: Text('Expense'),
                          ),
                          const ButtonSegment(
                            value: TransactionType.income,
                            label: Text('Income'),
                          ),
                          if (accounts.length > 1)
                            const ButtonSegment(
                              value: TransactionType.transfer,
                              label: Text('Transfer'),
                            ),
                        ],
                        selected: {type},
                        onSelectionChanged: (values) => setDialogState(() {
                          type = values.first;
                          categoryId = defaultCategoryIdForScheduledTransaction(
                            dataStore,
                            type,
                          );
                          if (type == TransactionType.transfer) {
                            transferAccountId = accounts
                                .where((account) => account.id != accountId)
                                .first
                                .id;
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Payee',
                        child: TextField(
                          controller: payee,
                          textCapitalization: TextCapitalization.words,
                          decoration: dialogFieldDecoration(),
                          autofocus: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Amount',
                        child: AmountEntryField(
                          initialMinor: amountMinor,
                          currency: dataStore.preferences.currency,
                          labelText: null,
                          onChanged: (value) => amountMinor = value,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Next date',
                        child: TextField(
                          controller: nextDate,
                          keyboardType: TextInputType.datetime,
                          decoration: dialogFieldDecoration(),
                          onTap: () async {
                            final picked = await pickDateForField(
                              context,
                              parseDateInput(nextDate.text, DateTime.now()),
                            );
                            if (picked != null) {
                              nextDate.text = dateInput(picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: type == TransactionType.transfer
                            ? 'From'
                            : 'Account',
                        child: DropdownButtonFormField<String>(
                          initialValue: accountId,
                          decoration: dialogFieldDecoration(),
                          items: [
                            for (final account in accounts)
                              DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                          ],
                          onChanged: (value) => setDialogState(() {
                            accountId = value ?? accountId;
                            if (transferAccountId == accountId) {
                              transferAccountId = firstDestinationAccountId(
                                accounts,
                                accountId,
                              );
                            }
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (type == TransactionType.transfer)
                        DialogFieldGroup(
                          label: 'To',
                          child: DropdownButtonFormField<String>(
                            initialValue: transferAccountId,
                            decoration: dialogFieldDecoration(),
                            items: [
                              for (final account in accounts)
                                if (account.id != accountId)
                                  DropdownMenuItem(
                                    value: account.id,
                                    child: Text(account.name),
                                  ),
                            ],
                            onChanged: (value) =>
                                setDialogState(() => transferAccountId = value),
                          ),
                        )
                      else
                        DialogFieldGroup(
                          label: 'Category',
                          child: DropdownButtonFormField<String>(
                            initialValue: categoryId,
                            decoration: dialogFieldDecoration(),
                            items: [
                              for (final category in categories)
                                DropdownMenuItem(
                                  value: category.id,
                                  child: Text(category.name),
                                ),
                            ],
                            onChanged: (value) =>
                                setDialogState(() => categoryId = value),
                          ),
                        ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Repeat',
                        child:
                            DropdownButtonFormField<
                              v2_scheduled.RecurrenceFrequency
                            >(
                              initialValue: frequency,
                              decoration: dialogFieldDecoration(),
                              items: [
                                for (final item
                                    in v2_scheduled.RecurrenceFrequency.values)
                                  DropdownMenuItem(
                                    value: item,
                                    child: Text(recurrenceFrequencyLabel(item)),
                                  ),
                              ],
                              onChanged: (value) => setDialogState(
                                () => frequency = value ?? frequency,
                              ),
                            ),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Alert',
                        child:
                            DropdownButtonFormField<
                              v2_scheduled.AlertPreference
                            >(
                              initialValue: alertPreference,
                              decoration: dialogFieldDecoration(),
                              items: [
                                for (final item
                                    in v2_scheduled.AlertPreference.values)
                                  DropdownMenuItem(
                                    value: item,
                                    child: Text(alertPreferenceLabel(item)),
                                  ),
                              ],
                              onChanged: (value) => setDialogState(
                                () =>
                                    alertPreference = value ?? alertPreference,
                              ),
                            ),
                      ),
                      if (alertPreference ==
                          v2_scheduled.AlertPreference.custom) ...[
                        const SizedBox(height: 12),
                        DialogFieldGroup(
                          label: 'Custom alert time',
                          helperText: 'Use AM or PM, for example 9:00 AM',
                          child: TextField(
                            controller: customAlertTime,
                            keyboardType: TextInputType.datetime,
                            decoration: dialogFieldDecoration(
                              hintText: '9:00 AM',
                            ),
                          ),
                        ),
                      ],
                      if (alertPreference !=
                          v2_scheduled.AlertPreference.none) ...[
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: repeatAlertUntilResolved,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Repeat alert until marked paid/skipped',
                          ),
                          onChanged: (value) => setDialogState(
                            () => repeatAlertUntilResolved = value ?? false,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, (
                    type: type,
                    accountId: accountId,
                    transferAccountId: type == TransactionType.transfer
                        ? transferAccountId
                        : null,
                    categoryId: type == TransactionType.transfer
                        ? null
                        : categoryId,
                    payee: payee.text.trim().isEmpty
                        ? scheduledPayeeFallback(type)
                        : payee.text.trim(),
                    amountMinor: amountMinor.abs(),
                    nextDate: parseDateInput(nextDate.text, DateTime.now()),
                    frequency: frequency,
                    alertPreference: alertPreference,
                    customAlertTimeMinutes:
                        alertPreference == v2_scheduled.AlertPreference.custom
                        ? parseAlertTimeMinutes(customAlertTime.text, 9 * 60)
                        : null,
                    repeatAlertUntilResolved:
                        alertPreference != v2_scheduled.AlertPreference.none &&
                        repeatAlertUntilResolved,
                  )),
                  child: Text(isEditing ? 'Save' : 'Add'),
                ),
              ],
            );
          },
        ),
      );

  if (result == null) return;
  if (result.type == TransactionType.transfer &&
      result.transferAccountId == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Choose a destination account')),
    );
    return;
  }

  final scheduledTransaction = existing == null
      ? v2_scheduled.ScheduledTransactionRecord(
          id: 'sched_${DateTime.now().microsecondsSinceEpoch}',
          type: result.type,
          accountId: result.accountId,
          transferAccountId: result.transferAccountId,
          categoryId: result.categoryId,
          payee: result.payee,
          amountMinor: result.amountMinor,
          nextDate: result.nextDate,
          frequency: result.frequency,
          alertPreference: result.alertPreference,
          customAlertTimeMinutes: result.customAlertTimeMinutes,
          repeatAlertUntilResolved: result.repeatAlertUntilResolved,
          sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
        )
      : existing.copyWith(
          type: result.type,
          accountId: result.accountId,
          transferAccountId: result.transferAccountId,
          categoryId: result.categoryId,
          payee: result.payee,
          amountMinor: result.amountMinor,
          nextDate: result.nextDate,
          frequency: result.frequency,
          alertPreference: result.alertPreference,
          customAlertTimeMinutes: result.customAlertTimeMinutes,
          repeatAlertUntilResolved: result.repeatAlertUntilResolved,
          scheduledNotificationIds: const [],
          lastAction: v2_scheduled.ScheduledAction.none,
          sync: existing.sync.touched(deviceId: dataStore.deviceId),
          clearTransferAccount: result.transferAccountId == null,
          clearCategory: result.categoryId == null,
          clearCustomAlertTime: result.customAlertTimeMinutes == null,
          clearLastReminderScheduledAt: true,
        );
  await dataStore.saveScheduledTransaction(scheduledTransaction);
}

Future<void> showScheduledTransactionActions(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Mark Paid'),
            onTap: () => Navigator.pop(sheetContext, 'paid'),
          ),
          ListTile(
            leading: const Icon(Icons.skip_next_outlined),
            title: const Text('Skip Once'),
            onTap: () => Navigator.pop(sheetContext, 'skip'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () => Navigator.pop(sheetContext, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Duplicate'),
            onTap: () => Navigator.pop(sheetContext, 'duplicate'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            textColor: AppTheme.rose,
            iconColor: AppTheme.rose,
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  switch (action) {
    case 'paid':
      await markScheduledTransactionPaid(context, item);
    case 'skip':
      await skipScheduledTransactionOnce(context, item);
    case 'edit':
      await showScheduledTransactionDialog(context, existing: item);
    case 'duplicate':
      await duplicateScheduledTransaction(context, item);
    case 'delete':
      await deleteScheduledTransaction(context, item);
  }
}

Future<void> markScheduledTransactionPaid(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  TransactionRecord paidTransaction;
  switch (item.type) {
    case TransactionType.expense:
      if (item.categoryId == null) {
        showMissingScheduledCategoryMessage(context);
        return;
      }
      paidTransaction = await dataStore.addExpense(
        accountId: item.accountId,
        categoryId: item.categoryId!,
        date: item.nextDate,
        payee: item.payee,
        amountMinor: item.amountMinor,
      );
    case TransactionType.income:
      if (item.categoryId == null) {
        showMissingScheduledCategoryMessage(context);
        return;
      }
      paidTransaction = await dataStore.addIncome(
        accountId: item.accountId,
        categoryId: item.categoryId!,
        date: item.nextDate,
        payee: item.payee,
        amountMinor: item.amountMinor,
      );
    case TransactionType.transfer:
      if (item.transferAccountId == null) {
        showMissingScheduledTransferMessage(context);
        return;
      }
      paidTransaction = await dataStore.addTransfer(
        fromAccountId: item.accountId,
        toAccountId: item.transferAccountId!,
        date: item.nextDate,
        payee: item.payee,
        amountMinor: item.amountMinor,
      );
    case TransactionType.adjustment:
      showMissingScheduledCategoryMessage(context);
      return;
  }

  await dataStore.saveTransaction(
    paidTransaction.copyWith(scheduledTransactionId: item.id),
  );
  await advanceOrCloseScheduledTransaction(
    dataStore,
    item,
    v2_scheduled.ScheduledAction.paid,
  );
}

Future<void> skipScheduledTransactionOnce(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  await advanceOrCloseScheduledTransaction(
    dataStore,
    item,
    v2_scheduled.ScheduledAction.skipped,
  );
}

Future<void> duplicateScheduledTransaction(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  await dataStore.saveScheduledTransaction(
    v2_scheduled.ScheduledTransactionRecord(
      id: 'sched_${DateTime.now().microsecondsSinceEpoch}',
      type: item.type,
      accountId: item.accountId,
      transferAccountId: item.transferAccountId,
      categoryId: item.categoryId,
      payee: '${item.payee} copy',
      amountMinor: item.amountMinor,
      nextDate: item.nextDate,
      frequency: item.frequency,
      endDate: item.endDate,
      alertPreference: item.alertPreference,
      customAlertTimeMinutes: item.customAlertTimeMinutes,
      repeatAlertUntilResolved: item.repeatAlertUntilResolved,
      scheduledNotificationIds: const [],
      lastAction: v2_scheduled.ScheduledAction.none,
      sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
    ),
  );
}

Future<void> deleteScheduledTransaction(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  await dataStore.saveScheduledTransaction(
    item.copyWith(sync: item.sync.deleted(deviceId: dataStore.deviceId)),
  );
}

Future<void> advanceOrCloseScheduledTransaction(
  FinanceDataStore dataStore,
  v2_scheduled.ScheduledTransactionRecord item,
  v2_scheduled.ScheduledAction action,
) async {
  final nextDate = nextScheduledDate(item);
  if (nextDate == null || nextDate.isAfter(item.endDate ?? DateTime(9999))) {
    await dataStore.saveScheduledTransaction(
      item.copyWith(
        lastAction: action,
        sync: item.sync.deleted(deviceId: dataStore.deviceId),
      ),
    );
    return;
  }
  await dataStore.saveScheduledTransaction(
    item.copyWith(
      nextDate: nextDate,
      lastAction: v2_scheduled.ScheduledAction.none,
      sync: item.sync.touched(deviceId: dataStore.deviceId),
    ),
  );
}

DateTime? nextScheduledDate(v2_scheduled.ScheduledTransactionRecord item) {
  final date = item.nextDate;
  return switch (item.frequency) {
    v2_scheduled.RecurrenceFrequency.once => null,
    v2_scheduled.RecurrenceFrequency.weekly => date.add(
      const Duration(days: 7),
    ),
    v2_scheduled.RecurrenceFrequency.biweekly => date.add(
      const Duration(days: 14),
    ),
    v2_scheduled.RecurrenceFrequency.monthly => DateTime(
      date.year,
      date.month + 1,
      date.day,
    ),
    v2_scheduled.RecurrenceFrequency.yearly => DateTime(
      date.year + 1,
      date.month,
      date.day,
    ),
  };
}

void showMissingScheduledCategoryMessage(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Choose a category before marking paid')),
  );
}

void showMissingScheduledTransferMessage(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Choose a destination before marking paid')),
  );
}

Future<void> showTransactionDialog(
  BuildContext context, {
  bool? initialIsExpense,
  String? initialAccountId,
  TransactionRecord? transaction,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final activeAccounts = dataStore.activeAccountsInDisplayOrder;
  if (activeAccounts.isEmpty) return;
  final payeeOptions = savedPayees(dataStore);
  final payee = TextEditingController(text: transaction?.payee ?? '');
  final note = TextEditingController(text: transaction?.note ?? '');
  final date = TextEditingController(
    text: dateInput(transaction?.date ?? DateTime.now()),
  );
  var amountMinor = transaction?.amountMinor.abs() ?? 0;
  var accountId =
      activeAccounts.any(
        (account) => account.id == (transaction?.accountId ?? initialAccountId),
      )
      ? (transaction?.accountId ?? initialAccountId)!
      : activeAccounts.first.id;
  var isExpense =
      transaction?.type == TransactionType.expense ||
      (transaction?.type == TransactionType.transfer &&
          (initialIsExpense ?? true)) ||
      (transaction == null &&
          (initialIsExpense ?? isExpenseDefault(dataStore.preferences)));
  var categoryId =
      transaction?.categoryId ??
      defaultV2CategoryIdForTransactionKind(dataStore, isExpense);
  var switchToTransfer = false;

  final result =
      await showDialog<
        ({
          String accountId,
          String categoryId,
          String payee,
          String note,
          DateTime date,
          int amountMinor,
          bool isExpense,
        })
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final categoryOptions = categoriesForTransactionKind(
              dataStore,
              isExpense,
            );
            if (!categoryOptions.any((category) => category.id == categoryId)) {
              categoryId = categoryOptions.isEmpty
                  ? ''
                  : categoryOptions.first.id;
            }

            return AlertDialog(
              title: Text(
                transaction == null ? 'Add transaction' : 'Edit transaction',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<TransactionType>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: TransactionType.expense,
                            label: Text('Expense'),
                          ),
                          ButtonSegment(
                            value: TransactionType.income,
                            label: Text('Income'),
                          ),
                          ButtonSegment(
                            value: TransactionType.transfer,
                            label: Text('Transfer'),
                          ),
                        ],
                        selected: {
                          isExpense
                              ? TransactionType.expense
                              : TransactionType.income,
                        },
                        onSelectionChanged: (values) {
                          final selectedType = values.first;
                          if (selectedType == TransactionType.transfer) {
                            switchToTransfer = true;
                            Navigator.pop(context);
                            return;
                          }
                          setDialogState(() {
                            isExpense = selectedType == TransactionType.expense;
                            categoryId = defaultV2CategoryIdForTransactionKind(
                              dataStore,
                              isExpense,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Payee',
                        child: TextField(
                          key: const ValueKey('transaction-payee'),
                          controller: payee,
                          textCapitalization: TextCapitalization.words,
                          decoration: dialogFieldDecoration().copyWith(
                            suffixIcon: payeeOptions.isEmpty
                                ? null
                                : PopupMenuButton<String>(
                                    tooltip: 'Saved payees',
                                    icon: const Icon(
                                      Icons.history_outlined,
                                      size: 20,
                                    ),
                                    onSelected: (value) => payee.text = value,
                                    itemBuilder: (context) => [
                                      for (final option in payeeOptions.take(
                                        12,
                                      ))
                                        PopupMenuItem(
                                          value: option,
                                          child: Text(option),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Date',
                        child: TextField(
                          key: const ValueKey('transaction-date'),
                          controller: date,
                          readOnly: true,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          decoration: dialogFieldDecoration(),
                          onTap: () async {
                            FocusManager.instance.primaryFocus?.unfocus();
                            final picked = await pickDateForField(
                              context,
                              parseDateInput(date.text, DateTime.now()),
                            );
                            if (picked != null) {
                              date.text = dateInput(picked);
                            }
                            FocusManager.instance.primaryFocus?.unfocus();
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Note',
                        child: TextField(
                          key: const ValueKey('transaction-note'),
                          controller: note,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: dialogFieldDecoration(),
                          minLines: 1,
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Amount',
                        child: AmountEntryField(
                          fieldKey: const ValueKey('transaction-amount'),
                          initialMinor: amountMinor,
                          currency: dataStore.preferences.currency,
                          labelText: null,
                          onChanged: (value) => amountMinor = value,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Account',
                        child: DropdownButtonFormField<String>(
                          initialValue: accountId,
                          decoration: dialogFieldDecoration(),
                          items: [
                            for (final account in activeAccounts)
                              DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                          ],
                          onChanged: (value) => accountId = value ?? accountId,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DialogFieldGroup(
                        label: 'Category',
                        child: DropdownButtonFormField<String>(
                          initialValue: categoryId.isEmpty ? null : categoryId,
                          decoration: dialogFieldDecoration(),
                          items: [
                            for (final category in categoryOptions)
                              DropdownMenuItem(
                                value: category.id,
                                child: Text(category.name),
                              ),
                            const DropdownMenuItem(
                              value: newCategoryDropdownValue,
                              child: Text('New category...'),
                            ),
                          ],
                          onChanged: (value) async {
                            if (value == null) return;
                            if (value == newCategoryDropdownValue) {
                              final newId = await showCategoryDialog(
                                context,
                                initialKind: isExpense
                                    ? v2_category.CategoryKind.expense
                                    : v2_category.CategoryKind.income,
                              );
                              if (newId != null) {
                                setDialogState(() => categoryId = newId);
                              }
                              return;
                            }
                            setDialogState(() => categoryId = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: categoryId.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context, (
                            accountId: accountId,
                            categoryId: categoryId,
                            payee: payee.text.trim().isEmpty
                                ? 'Transaction'
                                : payee.text.trim(),
                            note: note.text.trim(),
                            date: parseDateInput(
                              date.text,
                              transaction?.date ?? DateTime.now(),
                            ),
                            amountMinor: amountMinor.abs(),
                            isExpense: isExpense,
                          ));
                        },
                  child: Text(transaction == null ? 'Add' : 'Save'),
                ),
              ],
            );
          },
        ),
      );

  if (switchToTransfer && context.mounted) {
    await showTransferDialog(
      context,
      initialFromAccountId: accountId,
      transfer: transaction,
    );
    return;
  }
  if (result == null) return;
  if (transaction == null) {
    if (result.isExpense) {
      await dataStore.addExpense(
        accountId: result.accountId,
        categoryId: result.categoryId,
        date: result.date,
        payee: result.payee,
        amountMinor: result.amountMinor,
        note: result.note,
      );
    } else {
      await dataStore.addIncome(
        accountId: result.accountId,
        categoryId: result.categoryId,
        date: result.date,
        payee: result.payee,
        amountMinor: result.amountMinor,
        note: result.note,
      );
    }
  } else {
    await dataStore.saveTransaction(
      transaction.copyWith(
        type: result.isExpense
            ? TransactionType.expense
            : TransactionType.income,
        accountId: result.accountId,
        categoryId: result.categoryId,
        date: result.date,
        payee: result.payee,
        note: result.note,
        amountMinor: result.amountMinor,
        clearTransferAccount: true,
      ),
    );
  }
  await dataStore.savePreferences(
    dataStore.preferences.copyWith(
      lastUsedTransactionType: result.isExpense
          ? TransactionType.expense
          : TransactionType.income,
    ),
  );
}

Future<String?> showCategoryDialog(
  BuildContext context, {
  LedgerCategory? category,
  String? categoryId,
  v2_category.CategoryKind? initialKind,
}) async {
  final legacyStore = FinanceStoreScope.read(context);
  final dataStore = FinanceDataStoreScope.read(context);
  final existingCategory = categoryId == null
      ? null
      : dataStore.categoryById(categoryId);
  final name = TextEditingController(
    text: existingCategory?.name ?? category?.name ?? '',
  );
  var kind =
      existingCategory?.kind ?? initialKind ?? v2_category.CategoryKind.expense;
  var parentCategoryId = existingCategory?.parentCategoryId;
  var iconName = sanitizedCategoryIconName(existingCategory?.iconName);
  var colorValue = sanitizedCategoryColorValue(existingCategory?.colorValue);

  final result =
      await showDialog<
        ({
          String name,
          v2_category.CategoryKind kind,
          String? parentCategoryId,
          String? iconName,
          int? colorValue,
        })
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final parentOptions = dataStore.categories
                .where(
                  (item) =>
                      item.isVisible &&
                      item.kind == kind &&
                      item.id != existingCategory?.id &&
                      (existingCategory == null ||
                          !v2_category.wouldCreateCategoryParentCycle(
                            dataStore.categories,
                            categoryId: existingCategory.id,
                            parentCategoryId: item.id,
                          )),
                )
                .toList(growable: false);
            final parentDropdownValue =
                parentCategoryId != null &&
                    parentOptions.any((item) => item.id == parentCategoryId)
                ? parentCategoryId
                : null;
            parentCategoryId = parentDropdownValue;

            return AlertDialog(
              title: Text(
                existingCategory == null ? 'Add category' : 'Edit category',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Category name',
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<v2_category.CategoryKind>(
                        initialValue: kind,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: [
                          for (final item in v2_category.CategoryKind.values)
                            if (item != v2_category.CategoryKind.system)
                              DropdownMenuItem(
                                value: item,
                                child: Text(categoryKindLabel(item.name)),
                              ),
                        ],
                        onChanged: (value) => setDialogState(() {
                          kind = value ?? kind;
                          parentCategoryId = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: parentDropdownValue,
                        decoration: const InputDecoration(
                          labelText: 'Parent category',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(child: Text('None')),
                          for (final item in parentOptions)
                            DropdownMenuItem<String?>(
                              value: item.id,
                              child: Text(item.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => parentCategoryId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: iconName,
                        decoration: const InputDecoration(labelText: 'Icon'),
                        items: [
                          const DropdownMenuItem<String?>(
                            child: Text('No icon'),
                          ),
                          for (final item in v2_category.curatedCategoryIcons)
                            DropdownMenuItem<String?>(
                              value: item.sfSymbolName,
                              child: Text(item.label),
                            ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => iconName = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: colorValue,
                        decoration: const InputDecoration(labelText: 'Color'),
                        items: [
                          const DropdownMenuItem<int?>(child: Text('Default')),
                          for (final item in categoryColorOptions)
                            DropdownMenuItem<int?>(
                              value: item.value,
                              child: Text(item.label),
                            ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => colorValue = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, (
                    name: name.text.trim(),
                    kind: kind,
                    parentCategoryId: parentCategoryId,
                    iconName: iconName,
                    colorValue: colorValue,
                  )),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ),
      );

  if (result == null || result.name.isEmpty) return null;
  final sanitizedParentCategoryId =
      existingCategory != null &&
          v2_category.wouldCreateCategoryParentCycle(
            dataStore.categories,
            categoryId: existingCategory.id,
            parentCategoryId: result.parentCategoryId,
          )
      ? null
      : result.parentCategoryId;
  if (existingCategory == null) {
    final legacyCategory = legacyStore.addCategory(
      result.name,
      kind: legacyCategoryKindFor(result.kind),
    );
    final categoryId =
        legacyCategory?.id ?? 'cat_${DateTime.now().microsecondsSinceEpoch}';
    await dataStore.saveCategory(
      v2_category.CategoryRecord(
        id: categoryId,
        name: result.name,
        kind: result.kind,
        parentCategoryId: sanitizedParentCategoryId,
        iconName: result.iconName,
        colorValue: result.colorValue,
        sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
      ),
    );
    return categoryId;
  }

  try {
    legacyStore.renameCategory(existingCategory.id, result.name);
  } on StateError {
    // V2-only categories are expected while category management is migrated.
  }
  await dataStore.saveCategory(
    existingCategory.copyWith(
      name: result.name,
      kind: result.kind,
      parentCategoryId: sanitizedParentCategoryId,
      iconName: result.iconName,
      colorValue: result.colorValue,
      clearParentCategory: sanitizedParentCategoryId == null,
      clearIcon: result.iconName == null,
      clearColor: result.colorValue == null,
    ),
  );
  return existingCategory.id;
}

Future<void> showCategoryActions(
  BuildContext context,
  v2_category.CategoryRecord category,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () => Navigator.pop(sheetContext, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archive'),
            onTap: () => Navigator.pop(sheetContext, 'archive'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            textColor: AppTheme.rose,
            iconColor: AppTheme.rose,
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  switch (action) {
    case 'edit':
      await showCategoryDialog(context, categoryId: category.id);
    case 'archive':
      await FinanceDataStoreScope.read(context).archiveCategory(category.id);
    case 'delete':
      await FinanceDataStoreScope.read(context).deleteCategory(category.id);
  }
}

IconData accountIcon(AccountType type) {
  return switch (type) {
    AccountType.cash => Icons.payments_outlined,
    AccountType.checking => Icons.account_balance_outlined,
    AccountType.savings => Icons.savings_outlined,
    AccountType.creditCard => Icons.credit_card_outlined,
    AccountType.loan => Icons.request_quote_outlined,
  };
}

String accountTypeLabel(AccountType type) {
  return switch (type) {
    AccountType.cash => 'Cash',
    AccountType.checking => 'Checking',
    AccountType.savings => 'Savings',
    AccountType.creditCard => 'Credit Card',
    AccountType.loan => 'Loan',
  };
}

v2_account.AccountType v2AccountTypeFor(AccountType type) {
  return switch (type) {
    AccountType.cash => v2_account.AccountType.cash,
    AccountType.checking => v2_account.AccountType.checking,
    AccountType.savings => v2_account.AccountType.savings,
    AccountType.creditCard => v2_account.AccountType.creditCard,
    AccountType.loan => v2_account.AccountType.loan,
  };
}

String v2AccountTypeLabel(v2_account.AccountType type) {
  return switch (type) {
    v2_account.AccountType.cash => 'Cash',
    v2_account.AccountType.checking => 'Checking',
    v2_account.AccountType.savings => 'Savings',
    v2_account.AccountType.creditCard => 'Credit Card',
    v2_account.AccountType.loan => 'Loan',
    v2_account.AccountType.otherBanking => 'Other Banking',
  };
}

IconData v2AccountIcon(v2_account.AccountType type) {
  return switch (type) {
    v2_account.AccountType.cash => Icons.payments_outlined,
    v2_account.AccountType.checking => Icons.account_balance_outlined,
    v2_account.AccountType.savings => Icons.savings_outlined,
    v2_account.AccountType.creditCard => Icons.credit_card_outlined,
    v2_account.AccountType.loan => Icons.request_quote_outlined,
    v2_account.AccountType.otherBanking => Icons.account_balance_wallet_outlined,
  };
}

IconData accountGroupIcon(String groupName) {
  return switch (groupName) {
    'cash' => Icons.payments_outlined,
    'creditCards' => Icons.credit_card_outlined,
    'loans' => Icons.request_quote_outlined,
    _ => Icons.account_balance_outlined,
  };
}

IconData categoryKindIcon(String kindName) {
  return switch (kindName) {
    'income' => Icons.trending_up,
    'transfer' => Icons.swap_horiz,
    'system' => Icons.settings_outlined,
    _ => Icons.sell_outlined,
  };
}

List<v2_category.CategoryRecord> categoriesInDisplayOrder(
  List<v2_category.CategoryRecord> categories,
) {
  final categoriesById = {for (final category in categories) category.id};
  final childrenByParent = <String?, List<v2_category.CategoryRecord>>{};
  for (final category in categories) {
    final parentId = categoriesById.contains(category.parentCategoryId)
        ? category.parentCategoryId
        : null;
    childrenByParent.putIfAbsent(parentId, () => []).add(category);
  }
  for (final children in childrenByParent.values) {
    children.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  final ordered = <v2_category.CategoryRecord>[];
  final visited = <String>{};

  void visit(String? parentId) {
    for (final category in childrenByParent[parentId] ?? const []) {
      if (!visited.add(category.id)) continue;
      ordered.add(category);
      visit(category.id);
    }
  }

  visit(null);
  for (final category in [
    ...categories,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))) {
    if (!visited.add(category.id)) continue;
    ordered.add(category);
  }
  return ordered;
}

IconData categoryIcon(v2_category.CategoryRecord category) {
  return switch (category.iconName) {
    'fork.knife' => Icons.restaurant_outlined,
    'cart' => Icons.shopping_cart_outlined,
    'car' => Icons.directions_car_outlined,
    'fuelpump' => Icons.local_gas_station_outlined,
    'film' => Icons.movie_outlined,
    'house' => Icons.home_outlined,
    'cross.case' => Icons.medical_services_outlined,
    'phone' => Icons.phone_outlined,
    'bolt' => Icons.bolt_outlined,
    'shield' => Icons.shield_outlined,
    'wrench.adjustable' => Icons.build_outlined,
    'tag' => Icons.sell_outlined,
    _ => categoryKindIcon(category.kind.name),
  };
}

IconData categoryIconForId(
  String categoryId,
  Map<String, v2_category.CategoryRecord> categoriesById,
) {
  final category = categoriesById[categoryId];
  return category == null ? Icons.pie_chart_outline : categoryIcon(category);
}

String categorySubtitle(
  v2_category.CategoryRecord category,
  Map<String, v2_category.CategoryRecord> categoriesById,
) {
  final kind = categoryKindLabel(category.kind.name);
  final parent = categoriesById[category.parentCategoryId];
  return parent == null ? kind : '$kind · ${parent.name}';
}

Map<String, int> spendingByCategoryThisMonth(
  FinanceDataStore store, {
  DateTime? now,
}) {
  final anchor = now ?? DateTime.now();
  final periodStart = DateTime(anchor.year, anchor.month);
  final periodEnd = DateTime(anchor.year, anchor.month + 1);
  final totals = <String, int>{};
  for (final transaction in store.transactions) {
    if (transaction.isDeleted ||
        transaction.type != TransactionType.expense ||
        transaction.date.isBefore(periodStart) ||
        !transaction.date.isBefore(periodEnd)) {
      continue;
    }
    if (transaction.isSplit) {
      for (final split in transaction.splitLines) {
        totals[split.categoryId] =
            (totals[split.categoryId] ?? 0) + split.amountMinor.abs();
      }
      continue;
    }
    final categoryId = transaction.categoryId ?? '';
    totals[categoryId] =
        (totals[categoryId] ?? 0) + transaction.amountMinor.abs();
  }
  return totals;
}

List<MapEntry<String, int>> sortedCategoryTotals(Map<String, int> totals) {
  return totals.entries.toList()..sort((a, b) {
    final amountComparison = b.value.compareTo(a.value);
    return amountComparison == 0 ? a.key.compareTo(b.key) : amountComparison;
  });
}

String categoryKindLabel(String kindName) {
  return switch (kindName) {
    'income' => 'Income',
    'transfer' => 'Transfer',
    'system' => 'System',
    _ => 'Expense',
  };
}

CategoryKind legacyCategoryKindFor(v2_category.CategoryKind kind) {
  return switch (kind) {
    v2_category.CategoryKind.income => CategoryKind.income,
    v2_category.CategoryKind.transfer => CategoryKind.transfer,
    _ => CategoryKind.expense,
  };
}

class CategoryColorOption {
  const CategoryColorOption({required this.label, required this.value});

  final String label;
  final int value;
}

const categoryColorOptions = [
  CategoryColorOption(label: 'Teal', value: 0xFF0F766E),
  CategoryColorOption(label: 'Blue', value: 0xFF2563EB),
  CategoryColorOption(label: 'Green', value: 0xFF16A34A),
  CategoryColorOption(label: 'Amber', value: 0xFFD97706),
  CategoryColorOption(label: 'Rose', value: 0xFFE11D48),
  CategoryColorOption(label: 'Slate', value: 0xFF475569),
];

String launchScreenLabel(LaunchScreen screen) {
  return switch (screen) {
    LaunchScreen.dashboard => 'Dashboard',
    LaunchScreen.ledger => 'Ledger',
    LaunchScreen.accounts => 'Accounts',
    LaunchScreen.budgets => 'Budgets',
    LaunchScreen.scheduled => 'Scheduled',
    LaunchScreen.reports => 'Reports',
  };
}

FinanceSection financeSectionForLaunchScreen(LaunchScreen screen) {
  return switch (screen) {
    LaunchScreen.dashboard => FinanceSection.dashboard,
    LaunchScreen.ledger => FinanceSection.ledger,
    LaunchScreen.accounts => FinanceSection.accounts,
    LaunchScreen.budgets => FinanceSection.budgets,
    LaunchScreen.scheduled => FinanceSection.scheduled,
    LaunchScreen.reports => FinanceSection.reports,
  };
}

String appearanceModeLabel(AppearanceMode mode) {
  return switch (mode) {
    AppearanceMode.system => 'System',
    AppearanceMode.light => 'Light',
    AppearanceMode.dark => 'Dark',
  };
}

String floatingAddButtonPositionLabel(FloatingAddButtonPosition position) {
  return switch (position) {
    FloatingAddButtonPosition.left => 'Left',
    FloatingAddButtonPosition.center => 'Center',
    FloatingAddButtonPosition.right => 'Right',
  };
}

String defaultTransactionTypeLabel(DefaultTransactionType type) {
  return switch (type) {
    DefaultTransactionType.expense => 'Expense',
    DefaultTransactionType.income => 'Income',
    DefaultTransactionType.transfer => 'Transfer',
    DefaultTransactionType.lastUsed => 'Last used',
  };
}

const newCategoryDropdownValue = '__new_category__';

List<String> savedPayees(FinanceDataStore store) {
  final seen = <String>{};
  final payees = <String>[];
  final transactions = store.transactions.where((item) => !item.isDeleted);
  for (final transaction in transactions) {
    final payee = transaction.payee.trim();
    if (payee.isEmpty || !seen.add(payee.toLowerCase())) continue;
    payees.add(payee);
  }
  payees.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return payees;
}

String? sanitizedCategoryIconName(String? iconName) {
  if (iconName == null) return null;
  final trimmed = iconName.trim();
  if (trimmed.isEmpty) return null;
  final isCuratedIcon = v2_category.curatedCategoryIcons.any(
    (option) => option.sfSymbolName == trimmed,
  );
  return isCuratedIcon ? trimmed : null;
}

int? sanitizedCategoryColorValue(int? colorValue) {
  if (colorValue == null) return null;
  final isCuratedColor = categoryColorOptions.any(
    (option) => option.value == colorValue,
  );
  return isCuratedColor ? colorValue : null;
}

String recurrenceFrequencyLabel(v2_scheduled.RecurrenceFrequency frequency) {
  return switch (frequency) {
    v2_scheduled.RecurrenceFrequency.once => 'Once',
    v2_scheduled.RecurrenceFrequency.weekly => 'Weekly',
    v2_scheduled.RecurrenceFrequency.biweekly => 'Biweekly',
    v2_scheduled.RecurrenceFrequency.monthly => 'Monthly',
    v2_scheduled.RecurrenceFrequency.yearly => 'Yearly',
  };
}

String alertPreferenceLabel(v2_scheduled.AlertPreference preference) {
  return switch (preference) {
    v2_scheduled.AlertPreference.none => 'No alert',
    v2_scheduled.AlertPreference.sameDay => 'Same day',
    v2_scheduled.AlertPreference.oneDayBefore => '1 day before',
    v2_scheduled.AlertPreference.threeDaysBefore => '3 days before',
    v2_scheduled.AlertPreference.oneWeekBefore => '1 week before',
    v2_scheduled.AlertPreference.custom => 'Custom',
  };
}

String alertTimeInput(int minutesAfterMidnight) {
  final normalized = minutesAfterMidnight.clamp(0, 23 * 60 + 59);
  final hours24 = normalized ~/ 60;
  final minutes = normalized % 60;
  final period = hours24 >= 12 ? 'PM' : 'AM';
  final hours12 = hours24 % 12 == 0 ? 12 : hours24 % 12;
  return '$hours12:${minutes.toString().padLeft(2, '0')} $period';
}

int parseAlertTimeMinutes(String value, int fallback) {
  final trimmed = value.trim();
  final amPmMatch = RegExp(
    r'^(\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])$',
  ).firstMatch(trimmed);
  if (amPmMatch != null) {
    final rawHours = int.tryParse(amPmMatch.group(1) ?? '');
    final minutes = int.tryParse(amPmMatch.group(2) ?? '0');
    if (rawHours == null ||
        minutes == null ||
        rawHours < 1 ||
        rawHours > 12 ||
        minutes < 0 ||
        minutes > 59) {
      return fallback;
    }
    final isPm = amPmMatch.group(3)!.toUpperCase() == 'PM';
    final hours24 = rawHours == 12
        ? (isPm ? 12 : 0)
        : rawHours + (isPm ? 12 : 0);
    return hours24 * 60 + minutes;
  }

  final parts = trimmed.split(':');
  if (parts.length != 2) return fallback;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null || minutes == null) return fallback;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return fallback;
  return hours * 60 + minutes;
}

String scheduledPayeeFallback(TransactionType type) {
  return switch (type) {
    TransactionType.income => 'Scheduled income',
    TransactionType.transfer => 'Scheduled transfer',
    _ => 'Scheduled expense',
  };
}

bool isExpenseDefault(UserPreferences preferences) {
  return switch (preferences.defaultTransactionType) {
    DefaultTransactionType.expense => true,
    DefaultTransactionType.income => false,
    DefaultTransactionType.transfer => true,
    DefaultTransactionType.lastUsed =>
      preferences.lastUsedTransactionType != TransactionType.income,
  };
}

String defaultCategoryIdForTransactionKind(FinanceStore store, bool isExpense) {
  final kind = isExpense ? CategoryKind.expense : CategoryKind.income;
  return store.categories
      .firstWhere(
        (category) => category.kind == kind,
        orElse: () => store.categories.first,
      )
      .id;
}

String defaultV2CategoryIdForTransactionKind(
  FinanceDataStore store,
  bool isExpense,
) {
  final categories = categoriesForTransactionKind(store, isExpense);
  if (categories.isNotEmpty) return categories.first.id;
  return store.categories.isEmpty ? '' : store.categories.first.id;
}

List<v2_category.CategoryRecord> categoriesForTransactionKind(
  FinanceDataStore store,
  bool isExpense,
) {
  final kind = isExpense
      ? v2_category.CategoryKind.expense
      : v2_category.CategoryKind.income;
  return store.categories
      .where((category) => category.isVisible && category.kind == kind)
      .toList(growable: false);
}

List<v2_category.CategoryRecord> scheduledCategoriesForType(
  FinanceDataStore dataStore,
  TransactionType type,
) {
  final kindName = type == TransactionType.income ? 'income' : 'expense';
  return dataStore.categories
      .where((category) => category.isVisible && category.kind.name == kindName)
      .toList(growable: false);
}

String? defaultCategoryIdForScheduledTransaction(
  FinanceDataStore dataStore,
  TransactionType type,
) {
  final categories = scheduledCategoriesForType(dataStore, type);
  return categories.isEmpty ? null : categories.first.id;
}

String? firstDestinationAccountId(
  List<v2_account.AccountRecord> accounts,
  String fromAccountId,
) {
  for (final account in accounts) {
    if (account.id != fromAccountId) return account.id;
  }
  return null;
}

String thousandsSeparatorLabel(String value) {
  return switch (value) {
    ',' => 'Comma',
    '.' => 'Period',
    ' ' => 'Space',
    _ => 'None',
  };
}

CurrencyFormatSettings currencyForContext(BuildContext context) {
  return FinanceDataStoreScope.read(context).preferences.currency;
}

String money(
  int cents, [
  CurrencyFormatSettings currency = const CurrencyFormatSettings(),
]) {
  return MoneyFormatter(currency).formatMinor(cents);
}

String dollars(int cents) => (cents / 100).toStringAsFixed(2);

int parseCents(String value) {
  final cleaned = value.replaceAll(RegExp(r'[$,\s]'), '');
  final parsed = double.tryParse(cleaned) ?? 0;
  return (parsed * 100).round();
}

int? parseOptionalCents(String value) {
  final cleaned = value.replaceAll(RegExp(r'[$,\s]'), '');
  if (cleaned.isEmpty) return null;
  final parsed = double.tryParse(cleaned);
  if (parsed == null) return null;
  return (parsed * 100).round();
}

int? optionalPositiveMinor(int value) => value > 0 ? value : null;

String dateInput(DateTime date) {
  return compactDate(date);
}

DateTime parseDateInput(String value, DateTime fallback) {
  final trimmed = value.trim();
  final compactMatch = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})$',
  ).firstMatch(trimmed);
  if (compactMatch != null) {
    final month = int.tryParse(compactMatch.group(1)!);
    final day = int.tryParse(compactMatch.group(2)!);
    final rawYear = int.tryParse(compactMatch.group(3)!);
    if (month != null && day != null && rawYear != null) {
      final year = rawYear < 100 ? 2000 + rawYear : rawYear;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }
  }

  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) {
    return DateTime(fallback.year, fallback.month, fallback.day);
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

Future<DateTime?> pickDateForField(BuildContext context, DateTime initialDate) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(1970),
    lastDate: DateTime(2100),
  );
}

int scheduledDueCount(
  Iterable<v2_scheduled.ScheduledTransactionRecord> scheduledTransactions,
  DateTime now,
) {
  return scheduledTransactions.where((item) {
    return isScheduledDueOrOverdue(item, now);
  }).length;
}

String monthLabel(DateTime date) {
  const months = [
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
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String compactDate(DateTime date) {
  final year = (date.year % 100).toString().padLeft(2, '0');
  return '${date.month}/${date.day}/$year';
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

Map<DateTime, List<v2_scheduled.ScheduledTransactionRecord>> scheduledByDate(
  Iterable<v2_scheduled.ScheduledTransactionRecord> scheduled,
) {
  final grouped = <DateTime, List<v2_scheduled.ScheduledTransactionRecord>>{};
  for (final item in scheduled) {
    final date = DateTime(
      item.nextDate.year,
      item.nextDate.month,
      item.nextDate.day,
    );
    grouped.putIfAbsent(date, () => []).add(item);
  }
  return grouped;
}

int daysInMonth(DateTime month) {
  return DateTime(month.year, month.month + 1, 0).day;
}

int? dayForCalendarCell({
  required int row,
  required int column,
  required int firstWeekdayOffset,
  required int daysInMonth,
}) {
  final day = row * 7 + column - firstWeekdayOffset + 1;
  return day < 1 || day > daysInMonth ? null : day;
}

String dateShort(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}
