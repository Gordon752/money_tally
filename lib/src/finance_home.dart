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
  const FinanceHome({this.syncLabel = 'Sync ready', this.onSignOut, super.key});

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
  var _appliedLaunchPreference = false;

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
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 880;
    final preferences = FinanceDataStoreScope.watch(context).preferences;

    return Scaffold(
      body: SafeArea(child: isWide ? _wideLayout() : _compactLayout()),
      floatingActionButton: selected.supportsFloatingAdd
          ? MoneyTallyFloatingActionButton(
              tooltip: 'Add',
              onPressed: () => showFloatingAddMenu(context),
              child: const Icon(Icons.add),
            )
          : null,
      floatingActionButtonLocation:
          preferences.floatingAddButtonPosition ==
              FloatingAddButtonPosition.left
          ? FloatingActionButtonLocation.startFloat
          : FloatingActionButtonLocation.endFloat,
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
                    icon: Icon(section.icon),
                    label: section.label,
                  ),
              ],
            ),
    );
  }

  Widget _wideLayout() {
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
                icon: Icon(section.icon),
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
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            section: selected,
            syncLabel: widget.syncLabel,
            onSignOut: widget.onSignOut,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverToBoxAdapter(
            child: switch (selected) {
              FinanceSection.dashboard => const DashboardView(),
              FinanceSection.accounts => const AccountsView(),
              FinanceSection.ledger => const LedgerView(),
              FinanceSection.budgets => const BudgetsView(),
              FinanceSection.scheduled => const ScheduledView(),
              FinanceSection.reports => const ReportsView(),
              FinanceSection.categories => const CategoriesView(),
              FinanceSection.settings => const SettingsView(),
            },
          ),
        ),
      ],
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.section,
    required this.syncLabel,
    this.onSignOut,
    super.key,
  });

  final FinanceSection section;
  final String syncLabel;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Money Tally',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  section.label,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          SyncPill(label: syncLabel, onSignOut: onSignOut),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_queue, color: AppTheme.accent, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (onSignOut != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Sign out',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout, size: 18),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
      children: [
        ResponsiveGrid(
          children: [
            SummaryCard(
              label: 'Net worth',
              value: money(store.netWorthMinor, currency),
              icon: Icons.account_balance_wallet_outlined,
              isPrimary: true,
            ),
            SummaryCard(
              label: 'Total assets',
              value: money(store.totalAssetsMinor, currency),
              icon: Icons.trending_up,
            ),
            SummaryCard(
              label: 'Total liabilities',
              value: money(store.totalLiabilitiesMinor.abs(), currency),
              icon: Icons.request_quote_outlined,
            ),
            SummaryCard(
              label: 'Available cash',
              value: money(store.availableCashMinor, currency),
              icon: Icons.payments_outlined,
            ),
            SummaryCard(
              label: 'Month income',
              value: money(incomeThisMonth, currency),
              icon: Icons.add_circle_outline,
            ),
            SummaryCard(
              label: 'Month expenses',
              value: money(expensesThisMonth, currency),
              icon: Icons.remove_circle_outline,
            ),
            SummaryCard(
              label: 'Month remaining',
              value: money(incomeThisMonth - expensesThisMonth, currency),
              icon: Icons.savings_outlined,
            ),
            SummaryCard(
              label: 'Next scheduled',
              value: scheduled.isEmpty
                  ? 'None'
                  : dateShort(scheduled.first.nextDate),
              icon: Icons.notifications_active_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ResponsiveGrid(
          minTileWidth: 360,
          children: const [
            AccountBalancePanel(),
            UpcomingPanel(),
            BudgetPanel(),
            RecentTransactionsPanel(),
          ],
        ),
      ],
    );
  }
}

class AccountsView extends StatelessWidget {
  const AccountsView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    return ResponsiveGrid(
      minTileWidth: 300,
      children: [
        for (final account in store.accounts.where(
          (account) => !account.isArchived,
        ))
          AccountCard(
            account: account,
            balanceMinor: store.balanceForAccount(account.id),
            currency: store.preferences.currency,
            leading: Icon(
              accountGroupIcon(account.group.name),
              color: AppTheme.accent,
            ),
            onLongPress: () => showAccountOptions(context, account.id),
          ),
      ],
    );
  }
}

class LedgerView extends StatelessWidget {
  const LedgerView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final transactions = [...store.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final accountsById = {
      for (final account in store.accounts) account.id: account,
    };
    final categoriesById = {
      for (final category in store.categories) category.id: category,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => showTransactionDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add transaction'),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final transaction in transactions)
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
          ),
        ),
      ],
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final scheduled = [...store.scheduledTransactions]
      ..removeWhere((item) => item.isDeleted)
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    if (scheduled.isNotEmpty &&
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
            ),
            const Divider(height: 1),
            for (final item in scheduled)
              ScheduledTransactionRow(
                scheduledTransaction: item,
                currency: store.preferences.currency,
                onLongPress: () =>
                    showScheduledTransactionActions(context, item),
              ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(
                Icons.notifications_outlined,
                color: AppTheme.accent,
              ),
              title: Text('Alerts are required'),
              subtitle: Text(
                'Local notification wiring will be added before device builds.',
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
    super.key,
  });

  final DateTime month;
  final List<v2_scheduled.ScheduledTransactionRecord> scheduledTransactions;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markedDays = {
      for (final item in scheduledTransactions)
        if (item.nextDate.year == month.year &&
            item.nextDate.month == month.month)
          item.nextDate.day,
    };
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
                icon: Icon(
                  isCollapsed
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
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
              markedDays: markedDays,
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
    required this.markedDays,
    super.key,
  });

  final DateTime month;
  final Set<int> markedDays;

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
                Expanded(
                  child: ScheduledCalendarDayCell(
                    day: dayForCalendarCell(
                      row: row,
                      column: column,
                      firstWeekdayOffset: firstWeekdayOffset,
                      daysInMonth: days,
                    ),
                    markedDays: markedDays,
                  ),
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
    required this.markedDays,
    super.key,
  });

  final int? day;
  final Set<int> markedDays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (day == null) {
      return const SizedBox(height: 36);
    }
    final isMarked = markedDays.contains(day);
    return SizedBox(
      height: 36,
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isMarked ? AppTheme.accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(15),
            border: isMarked
                ? Border.all(color: AppTheme.accent.withValues(alpha: 0.35))
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '$day',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isMarked ? FontWeight.w900 : FontWeight.w600,
                  color: isMarked ? AppTheme.accent : null,
                ),
              ),
              if (isMarked)
                Positioned(
                  bottom: 3,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
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

class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
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
              for (final category in store.categories)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: category.colorValue == null
                        ? AppTheme.line
                        : Color(category.colorValue!),
                    child: Icon(
                      categoryKindIcon(category.kind.name),
                      color: AppTheme.ink,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    category.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(categoryKindLabel(category.kind.name)),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () =>
                        showCategoryDialog(context, categoryId: category.id),
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
  const SettingsView({super.key});

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
                  preferences.copyWith(currency: value),
                ),
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
        const AppCard(
          title: 'Data Ownership',
          child: Column(
            children: [
              SettingsPlaceholderRow(
                icon: Icons.file_download_outlined,
                title: 'Export CSV',
              ),
              SettingsPlaceholderRow(
                icon: Icons.data_object_outlined,
                title: 'Export JSON',
              ),
              SettingsPlaceholderRow(
                icon: Icons.restore_outlined,
                title: 'Backup and restore',
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

class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      title: 'Reports',
      child: Column(
        children: [
          SettingsPlaceholderRow(
            icon: Icons.calendar_month_outlined,
            title: 'Monthly spending',
          ),
          SettingsPlaceholderRow(
            icon: Icons.compare_arrows_outlined,
            title: 'Income vs expenses',
          ),
          SettingsPlaceholderRow(
            icon: Icons.pie_chart_outline,
            title: 'Category breakdown',
          ),
          SettingsPlaceholderRow(
            icon: Icons.waterfall_chart_outlined,
            title: 'Cash flow',
          ),
          SettingsPlaceholderRow(
            icon: Icons.show_chart_outlined,
            title: 'Net worth history',
          ),
          SettingsPlaceholderRow(
            icon: Icons.ssid_chart_outlined,
            title: 'Budget history',
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

class SettingsPlaceholderRow extends StatelessWidget {
  const SettingsPlaceholderRow({
    required this.icon,
    required this.title,
    super.key,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      trailing: const Text('Later', style: TextStyle(color: AppTheme.muted)),
    );
  }
}

class AccountBalancePanel extends StatelessWidget {
  const AccountBalancePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final currency = store.preferences.currency;
    return AppCard(
      title: 'Accounts',
      child: Column(
        children: [
          for (final account in store.accounts.where(
            (account) => !account.isArchived,
          ))
            MetricRow(
              label: account.name,
              value: money(store.balanceForAccount(account.id), currency),
              icon: accountGroupIcon(account.group.name),
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
    return AppCard(
      title: 'Scheduled',
      child: Column(
        children: [
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
  const BudgetPanel({this.showAll = false, super.key});

  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final budgets = showAll ? store.budgets : store.budgets.take(3);
    return AppCard(
      title: 'Budgets',
      child: Column(
        children: [
          for (final budget in budgets) BudgetProgressRow(budget: budget),
        ],
      ),
    );
  }
}

class RecentTransactionsPanel extends StatelessWidget {
  const RecentTransactionsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final transactions = [...store.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final accountsById = {
      for (final account in store.accounts) account.id: account,
    };
    final categoriesById = {
      for (final category in store.categories) category.id: category,
    };
    return AppCard(
      title: 'Recent ledger',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          for (final transaction in transactions.take(3))
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

class MetricRow extends StatelessWidget {
  const MetricRow({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
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

    return Padding(
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
          const SizedBox(height: 8),
          BudgetProgressBar(spentMinor: spent, budgetMinor: budget.amountMinor),
        ],
      ),
    );
  }
}

Future<void> showAdjustBalanceDialog(
  BuildContext context,
  Account account,
) async {
  final store = FinanceStoreScope.watch(context);
  final controller = TextEditingController(text: dollars(account.balanceCents));
  final value = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Adjust ${account.name}'),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(labelText: 'Balance'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, parseCents(controller.text)),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (value != null) store.adjustAccountBalance(account.id, value);
}

Future<void> showAccountOptions(BuildContext context, String accountId) async {
  final store = FinanceStoreScope.watch(context);
  final account = store.accountById(accountId);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Adjust Balance'),
            onTap: () => Navigator.pop(context, 'adjust'),
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
        ],
      ),
    ),
  );

  if (action == 'adjust' && context.mounted) {
    await showAdjustBalanceDialog(context, account);
  } else if (action == 'edit' && context.mounted) {
    await showEditAccountDialog(context, account);
  } else if (action == 'archive' && context.mounted) {
    final archived = store.archiveAccount(account.id);
    await saveLegacyAccountToV2(context, archived);
  }
}

Future<void> showEditAccountDialog(
  BuildContext context,
  Account account,
) async {
  final store = FinanceStoreScope.watch(context);
  final name = TextEditingController(text: account.name);
  var type = account.type;

  final result = await showDialog<({String name, AccountType type})>(
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
              name: name.text.trim().isEmpty ? account.name : name.text.trim(),
              type: type,
            )),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  if (result == null) return;
  final updated = store.editAccount(
    accountId: account.id,
    name: result.name,
    type: result.type,
  );
  if (!context.mounted) return;
  await saveLegacyAccountToV2(context, updated);
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
  final openingBalance = TextEditingController(text: '0.00');
  var type = AccountType.checking;

  final result =
      await showDialog<
        ({String name, AccountType type, int openingBalanceCents})
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: openingBalance,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Opening balance',
                    ),
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
                  openingBalanceCents: parseCents(openingBalance.text),
                )),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      );

  if (result == null) return;
  final account = store.addAccount(
    name: result.name,
    type: result.type,
    balanceCents: result.openingBalanceCents,
  );
  if (!context.mounted) return;
  await saveLegacyAccountToV2(context, account, dataStore: dataStore);
}

Future<void> saveLegacyAccountToV2(
  BuildContext context,
  Account account, {
  FinanceDataStore? dataStore,
}) async {
  final targetStore = dataStore ?? FinanceDataStoreScope.read(context);
  v2_account.AccountRecord record;
  try {
    record = targetStore
        .accountById(account.id)
        .copyWith(
          name: account.name,
          type: v2AccountTypeFor(account.type),
          isArchived: account.isArchived,
        );
  } on StateError {
    record = v2_account.AccountRecord(
      id: account.id,
      name: account.name,
      type: v2AccountTypeFor(account.type),
      openingBalanceMinor: account.balanceCents,
      isArchived: account.isArchived,
      sync: v2_sync.SyncMetadata.fresh(),
    );
  }
  await targetStore.saveAccount(record);
}

Future<void> showTransferDialog(BuildContext context) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final accounts = dataStore.accounts
      .where((account) => !account.isArchived)
      .toList(growable: false);
  if (accounts.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('At least two accounts are required')),
    );
    return;
  }

  final payee = TextEditingController(text: 'Transfer');
  final amount = TextEditingController();
  var fromAccountId = accounts.first.id;
  var toAccountId = accounts
      .firstWhere((account) => account.id != fromAccountId)
      .id;

  final result =
      await showDialog<
        ({
          String fromAccountId,
          String toAccountId,
          String payee,
          int amountMinor,
        })
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add transfer'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: payee,
                    decoration: const InputDecoration(labelText: 'Payee'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: fromAccountId,
                    decoration: const InputDecoration(labelText: 'From'),
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: toAccountId,
                    decoration: const InputDecoration(labelText: 'To'),
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
                  fromAccountId: fromAccountId,
                  toAccountId: toAccountId,
                  payee: payee.text.trim().isEmpty
                      ? 'Transfer'
                      : payee.text.trim(),
                  amountMinor: parseCents(amount.text).abs(),
                )),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      );

  if (result == null) return;
  await dataStore.addTransfer(
    fromAccountId: result.fromAccountId,
    toAccountId: result.toAccountId,
    date: DateTime.now(),
    payee: result.payee,
    amountMinor: result.amountMinor,
  );
}

Future<void> showScheduledTransactionDialog(BuildContext context) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final accounts = dataStore.accounts
      .where((account) => !account.isArchived)
      .toList(growable: false);
  if (accounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add an account before scheduling')),
    );
    return;
  }

  final payee = TextEditingController();
  final amount = TextEditingController();
  final nextDate = TextEditingController(text: dateInput(DateTime.now()));
  var type = TransactionType.expense;
  var accountId = accounts.first.id;
  var transferAccountId = accounts.length > 1 ? accounts[1].id : null;
  var categoryId = defaultCategoryIdForScheduledTransaction(dataStore, type);
  var frequency = v2_scheduled.RecurrenceFrequency.monthly;
  var alertPreference = v2_scheduled.AlertPreference.none;

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
              title: const Text('Add scheduled transaction'),
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
                            icon: Icon(Icons.remove),
                          ),
                          const ButtonSegment(
                            value: TransactionType.income,
                            label: Text('Income'),
                            icon: Icon(Icons.add),
                          ),
                          if (accounts.length > 1)
                            const ButtonSegment(
                              value: TransactionType.transfer,
                              label: Text('Transfer'),
                              icon: Icon(Icons.swap_horiz),
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
                      TextField(
                        controller: payee,
                        decoration: const InputDecoration(labelText: 'Payee'),
                        autofocus: true,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Amount'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nextDate,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Next date',
                          helperText: 'YYYY-MM-DD',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: accountId,
                        decoration: InputDecoration(
                          labelText: type == TransactionType.transfer
                              ? 'From'
                              : 'Account',
                        ),
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
                      const SizedBox(height: 12),
                      if (type == TransactionType.transfer)
                        DropdownButtonFormField<String>(
                          initialValue: transferAccountId,
                          decoration: const InputDecoration(labelText: 'To'),
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
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: categoryId,
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
                          onChanged: (value) =>
                              setDialogState(() => categoryId = value),
                        ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<v2_scheduled.RecurrenceFrequency>(
                        initialValue: frequency,
                        decoration: const InputDecoration(labelText: 'Repeat'),
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
                      const SizedBox(height: 12),
                      DropdownButtonFormField<v2_scheduled.AlertPreference>(
                        initialValue: alertPreference,
                        decoration: const InputDecoration(labelText: 'Alert'),
                        items: [
                          for (final item
                              in v2_scheduled.AlertPreference.values)
                            DropdownMenuItem(
                              value: item,
                              child: Text(alertPreferenceLabel(item)),
                            ),
                        ],
                        onChanged: (value) => setDialogState(
                          () => alertPreference = value ?? alertPreference,
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
                    amountMinor: parseCents(amount.text).abs(),
                    nextDate: parseDateInput(nextDate.text, DateTime.now()),
                    frequency: frequency,
                    alertPreference: alertPreference,
                  )),
                  child: const Text('Add'),
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

  await dataStore.saveScheduledTransaction(
    v2_scheduled.ScheduledTransactionRecord(
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
      sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
    ),
  );
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
      lastAction: action,
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
}) async {
  final store = FinanceStoreScope.watch(context);
  final dataStore = FinanceDataStoreScope.read(context);
  final payee = TextEditingController();
  final amount = TextEditingController();
  var accountId = store.accounts.first.id;
  var isExpense = initialIsExpense ?? isExpenseDefault(dataStore.preferences);
  var categoryId = defaultCategoryIdForTransactionKind(store, isExpense);

  final result =
      await showDialog<
        ({
          String accountId,
          String categoryId,
          String payee,
          int amountCents,
          bool isExpense,
        })
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add transaction'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Expense'),
                        icon: Icon(Icons.remove),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Income'),
                        icon: Icon(Icons.add),
                      ),
                    ],
                    selected: {isExpense},
                    onSelectionChanged: (values) => setDialogState(() {
                      isExpense = values.first;
                      categoryId = defaultCategoryIdForTransactionKind(
                        store,
                        isExpense,
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: payee,
                    decoration: const InputDecoration(labelText: 'Payee'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: accountId,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: [
                      for (final account in store.accounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) => accountId = value ?? accountId,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final category in store.categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: (value) => categoryId = value ?? categoryId,
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
                onPressed: () {
                  final cents =
                      parseCents(amount.text).abs() * (isExpense ? -1 : 1);
                  Navigator.pop(context, (
                    accountId: accountId,
                    categoryId: categoryId,
                    payee: payee.text.trim().isEmpty
                        ? 'Transaction'
                        : payee.text.trim(),
                    amountCents: cents,
                    isExpense: isExpense,
                  ));
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      );

  if (result != null) {
    store.addTransaction(
      accountId: result.accountId,
      categoryId: result.categoryId,
      date: DateTime.now(),
      payee: result.payee,
      amountCents: result.amountCents,
    );
    await dataStore.savePreferences(
      dataStore.preferences.copyWith(
        lastUsedTransactionType: result.isExpense
            ? TransactionType.expense
            : TransactionType.income,
      ),
    );
  }
}

Future<void> showCategoryDialog(
  BuildContext context, {
  LedgerCategory? category,
  String? categoryId,
}) async {
  final store = FinanceStoreScope.watch(context);
  final legacyCategory = categoryId == null
      ? category
      : store.categoryById(categoryId);
  final controller = TextEditingController(text: legacyCategory?.name ?? '');
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(category == null ? 'Add category' : 'Rename category'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Category name'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (value == null || value.isEmpty) return;
  if (legacyCategory == null) {
    store.addCategory(value);
  } else {
    store.renameCategory(legacyCategory.id, value);
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

String categoryKindLabel(String kindName) {
  return switch (kindName) {
    'income' => 'Income',
    'transfer' => 'Transfer',
    'system' => 'System',
    _ => 'Expense',
  };
}

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

List<v2_category.CategoryRecord> scheduledCategoriesForType(
  FinanceDataStore dataStore,
  TransactionType type,
) {
  final kindName = type == TransactionType.income ? 'income' : 'expense';
  return dataStore.categories
      .where(
        (category) => !category.isArchived && category.kind.name == kindName,
      )
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

String dateInput(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime parseDateInput(String value, DateTime fallback) {
  final parsed = DateTime.tryParse(value.trim());
  if (parsed == null) {
    return DateTime(fallback.year, fallback.month, fallback.day);
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
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
