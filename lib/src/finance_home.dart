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
    final dataStore = FinanceDataStoreScope.watch(context);
    final preferences = dataStore.preferences;
    final dueScheduledCount = scheduledDueCount(
      dataStore.scheduledTransactions,
      DateTime.now(),
    );

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
    final dueScheduledCount = scheduledDueCount(
      FinanceDataStoreScope.watch(context).scheduledTransactions,
      DateTime.now(),
    );
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
    final dueCount = scheduledDueCount(scheduled, DateTime.now());
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
              value: dueCount == 0
                  ? scheduled.isEmpty
                        ? 'None'
                        : dateShort(scheduled.first.nextDate)
                  : '$dueCount due',
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
          if (accounts.any((account) => account.group == group)) ...[
            Builder(
              builder: (context) {
                final isCollapsed = store.preferences.collapsedAccountGroupNames
                    .contains(group.name);
                return SectionHeader(
                  title: accountGroupLabel(group),
                  subtitle: money(
                    accounts
                        .where(
                          (account) =>
                              account.group == group &&
                              account.includeInGroupBalance,
                        )
                        .fold(
                          0,
                          (total, account) =>
                              total + store.balanceForAccount(account.id),
                        ),
                    store.preferences.currency,
                  ),
                  trailing: IconButton(
                    tooltip: isCollapsed
                        ? 'Expand ${accountGroupLabel(group)}'
                        : 'Collapse ${accountGroupLabel(group)}',
                    onPressed: () => toggleAccountGroupCollapsed(
                      context,
                      group,
                      isCollapsed: isCollapsed,
                    ),
                    icon: Icon(
                      isCollapsed
                          ? Icons.keyboard_arrow_right
                          : Icons.keyboard_arrow_down,
                    ),
                  ),
                );
              },
            ),
            if (!store.preferences.collapsedAccountGroupNames.contains(
              group.name,
            ))
              ResponsiveGrid(
                minTileWidth: 300,
                children: [
                  for (final account in accounts.where(
                    (account) => account.group == group,
                  ))
                    AccountCard(
                      account: account,
                      balanceMinor: store.balanceForAccount(account.id),
                      currency: store.preferences.currency,
                      leading: Icon(
                        accountGroupIcon(account.group.name),
                        color: AppTheme.accent,
                      ),
                      onLongPress: () =>
                          showAccountOptions(context, account.id),
                    ),
                ],
              ),
          ],
      ],
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

class LedgerView extends StatefulWidget {
  const LedgerView({super.key});

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
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final activeAccounts = store.activeAccountsInDisplayOrder;
    final activeCategories = store.categories
        .where((category) => !category.isArchived)
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
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search transactions',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                key: ValueKey('ledger-type-$typeFilterName'),
                initialValue: typeFilterName,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All types')),
                  for (final type in TransactionType.values)
                    DropdownMenuItem(
                      value: type.name,
                      child: Text(transactionTypeLabel(type)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => typeFilterName = value ?? ''),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                key: ValueKey('ledger-account-$accountFilterId'),
                initialValue: accountFilterId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All accounts'),
                  ),
                  for (final account in activeAccounts)
                    DropdownMenuItem(
                      value: account.id,
                      child: Text(account.name),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => accountFilterId = value ?? ''),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                key: ValueKey('ledger-category-$categoryFilterId'),
                initialValue: categoryFilterId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All categories'),
                  ),
                  for (final category in activeCategories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => categoryFilterId = value ?? ''),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<LedgerDateFilter>(
                key: ValueKey('ledger-date-${dateFilter.name}'),
                initialValue: dateFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Date'),
                items: [
                  for (final filter in LedgerDateFilter.values)
                    DropdownMenuItem(
                      value: filter,
                      child: Text(ledgerDateFilterLabel(filter)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => dateFilter = value ?? LedgerDateFilter.all),
              ),
            ),
            TextButton.icon(
              onPressed: hasFilters
                  ? () => setState(() {
                      typeFilterName = '';
                      accountFilterId = '';
                      categoryFilterId = '';
                      dateFilter = LedgerDateFilter.all;
                    })
                  : null,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                if (transactions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'No transactions match',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final transaction in transactions)
                  TransactionRow(
                    transaction: transaction,
                    currency: store.preferences.currency,
                    accountName: accountsById[transaction.accountId]?.name,
                    categoryName: transaction.categoryId == null
                        ? null
                        : categoriesById[transaction.categoryId]?.name,
                    onLongPress: () =>
                        showTransactionOptions(context, transaction.id),
                  ),
              ],
            ),
          ),
        ),
      ],
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
                transaction.type == TransactionType.income,
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap:
                transaction.type == TransactionType.expense ||
                    transaction.type == TransactionType.income
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
      await showTransactionDialog(context, transaction: transaction);
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
            amountText: dollars(transaction.amountMinor.abs()),
          ),
          SplitLineDraft(categoryId: categories.first.id, amountText: '0.00'),
        ]
      : [
          for (final line in transaction.splitLines)
            SplitLineDraft(
              categoryId: line.categoryId,
              amountText: dollars(line.amountMinor),
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
                          child: TextField(
                            key: ValueKey('split-amount-$index'),
                            controller: drafts[index].amount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                            ),
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
                          amountText: '0.00',
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
                  if (parseCents(drafts[index].amount.text).abs() > 0)
                    TransactionSplitLine(
                      id: 'split_${DateTime.now().microsecondsSinceEpoch}_$index',
                      categoryId: drafts[index].categoryId,
                      amountMinor: parseCents(drafts[index].amount.text).abs(),
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
    required String amountText,
    String noteText = '',
  }) : amount = TextEditingController(text: amountText),
       note = TextEditingController(text: noteText);

  String categoryId;
  final TextEditingController amount;
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
    final categories = store.categories
        .where((category) => !category.isArchived)
        .toList(growable: false);
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
              for (final category in categories)
                ListTile(
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
    final store = FinanceDataStoreScope.watch(context);
    final currency = store.preferences.currency;
    final now = DateTime.now();
    final income = store.incomeThisMonthMinor(now: now);
    final expenses = store.expensesThisMonthMinor(now: now);
    final categoryTotals = spendingByCategoryThisMonth(store, now: now);
    final categoriesById = {
      for (final category in store.categories) category.id: category,
    };
    final budgets = store.budgets.where((budget) => !budget.isArchived);

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
              child: ReportMetricRow(
                icon: Icons.show_chart_outlined,
                label: 'Current',
                value: money(store.netWorthMinor, currency),
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
    final dueCount = scheduledDueCount(scheduled, DateTime.now());
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
  const BudgetPanel({this.showAll = false, super.key});

  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final budgets = store.budgets
        .where((budget) => !budget.isArchived)
        .toList(growable: false);
    final visibleBudgets = showAll ? budgets : budgets.take(3);
    return AppCard(
      title: 'Budgets',
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
          for (final budget in visibleBudgets)
            BudgetProgressRow(budget: budget),
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
      ..removeWhere((transaction) => transaction.isDeleted)
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

Future<void> showBudgetDialog(
  BuildContext context, {
  BudgetRecord? budget,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final name = TextEditingController(text: budget?.name ?? '');
  final amount = TextEditingController(
    text: budget == null ? '' : dollars(budget.amountMinor),
  );
  final selectedCategoryIds = {...?budget?.categoryIds};
  final categories = dataStore.categories
      .where(
        (category) =>
            !category.isArchived &&
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
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Budget amount',
                      ),
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
                  amountMinor: parseCents(amount.text).abs(),
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
    case 'delete':
      await FinanceDataStoreScope.read(
        context,
      ).saveBudget(budget.copyWith(isArchived: true));
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
  final dataStore = FinanceDataStoreScope.read(context);
  final account = store.accountById(accountId);
  final v2Account = dataStore.accountById(accountId);
  final groupAccounts = dataStore.activeAccountsInDisplayOrder
      .where((item) => item.group == v2Account.group)
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
  final dataStore = FinanceDataStoreScope.read(context);
  final v2Account = dataStore.accountById(account.id);
  final name = TextEditingController(text: account.name);
  var type = account.type;
  var includeInGroupBalance = v2Account.includeInGroupBalance;
  var includeInNetWorth = v2Account.includeInNetWorth;

  final result =
      await showDialog<
        ({
          String name,
          AccountType type,
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
  final updated = store.editAccount(
    accountId: account.id,
    name: result.name,
    type: result.type,
  );
  if (!context.mounted) return;
  await saveLegacyAccountToV2(
    context,
    updated,
    dataStore: dataStore,
    includeInGroupBalance: result.includeInGroupBalance,
    includeInNetWorth: result.includeInNetWorth,
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
}) async {
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
  var fromAccountId =
      accounts.any((account) => account.id == initialFromAccountId)
      ? initialFromAccountId!
      : accounts.first.id;
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

Future<void> showScheduledTransactionDialog(
  BuildContext context, {
  v2_scheduled.ScheduledTransactionRecord? existing,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final isEditing = existing != null;
  final accounts = dataStore.accounts
      .where(
        (account) =>
            !account.isArchived ||
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
  final amount = TextEditingController(
    text: existing == null ? '' : dollars(existing.amountMinor),
  );
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
                      if (alertPreference ==
                          v2_scheduled.AlertPreference.custom) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: customAlertTime,
                          keyboardType: TextInputType.datetime,
                          decoration: const InputDecoration(
                            labelText: 'Custom alert time',
                            helperText: 'HH:MM',
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
                    amountMinor: parseCents(amount.text).abs(),
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
  String? initialAccountId,
  TransactionRecord? transaction,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final activeAccounts = dataStore.activeAccountsInDisplayOrder;
  if (activeAccounts.isEmpty) return;
  final payee = TextEditingController(text: transaction?.payee ?? '');
  final amount = TextEditingController(
    text: transaction == null ? '' : dollars(transaction.amountMinor.abs()),
  );
  var accountId =
      activeAccounts.any(
        (account) => account.id == (transaction?.accountId ?? initialAccountId),
      )
      ? (transaction?.accountId ?? initialAccountId)!
      : activeAccounts.first.id;
  var isExpense =
      transaction?.type == TransactionType.expense ||
      (transaction == null &&
          (initialIsExpense ?? isExpenseDefault(dataStore.preferences)));
  var categoryId =
      transaction?.categoryId ??
      defaultV2CategoryIdForTransactionKind(dataStore, isExpense);

  final result =
      await showDialog<
        ({
          String accountId,
          String categoryId,
          String payee,
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
                        categoryId = defaultV2CategoryIdForTransactionKind(
                          dataStore,
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
                        for (final account in activeAccounts)
                          DropdownMenuItem(
                            value: account.id,
                            child: Text(account.name),
                          ),
                      ],
                      onChanged: (value) => accountId = value ?? accountId,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: categoryId.isEmpty ? null : categoryId,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        for (final category in categoryOptions)
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
                  onPressed: categoryId.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context, (
                            accountId: accountId,
                            categoryId: categoryId,
                            payee: payee.text.trim().isEmpty
                                ? 'Transaction'
                                : payee.text.trim(),
                            amountMinor: parseCents(amount.text).abs(),
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

  if (result == null) return;
  if (transaction == null) {
    if (result.isExpense) {
      await dataStore.addExpense(
        accountId: result.accountId,
        categoryId: result.categoryId,
        date: DateTime.now(),
        payee: result.payee,
        amountMinor: result.amountMinor,
      );
    } else {
      await dataStore.addIncome(
        accountId: result.accountId,
        categoryId: result.categoryId,
        date: DateTime.now(),
        payee: result.payee,
        amountMinor: result.amountMinor,
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
        payee: result.payee,
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

Future<void> showCategoryDialog(
  BuildContext context, {
  LedgerCategory? category,
  String? categoryId,
}) async {
  final legacyStore = FinanceStoreScope.watch(context);
  final dataStore = FinanceDataStoreScope.read(context);
  final existingCategory = categoryId == null
      ? null
      : dataStore.categoryById(categoryId);
  final name = TextEditingController(
    text: existingCategory?.name ?? category?.name ?? '',
  );
  var kind = existingCategory?.kind ?? v2_category.CategoryKind.expense;
  var parentCategoryId = existingCategory?.parentCategoryId;
  var iconName = existingCategory?.iconName;
  var colorValue = existingCategory?.colorValue;

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
                      !item.isArchived &&
                      item.kind == kind &&
                      item.id != existingCategory?.id,
                )
                .toList(growable: false);
            if (parentCategoryId != null &&
                !parentOptions.any((item) => item.id == parentCategoryId)) {
              parentCategoryId = null;
            }

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
                        initialValue: parentCategoryId,
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

  if (result == null || result.name.isEmpty) return;
  if (existingCategory == null) {
    final legacyCategory = legacyStore.addCategory(
      result.name,
      kind: legacyCategoryKindFor(result.kind),
    );
    await dataStore.saveCategory(
      v2_category.CategoryRecord(
        id:
            legacyCategory?.id ??
            'cat_${DateTime.now().microsecondsSinceEpoch}',
        name: result.name,
        kind: result.kind,
        parentCategoryId: result.parentCategoryId,
        iconName: result.iconName,
        colorValue: result.colorValue,
        sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
      ),
    );
    return;
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
      parentCategoryId: result.parentCategoryId,
      iconName: result.iconName,
      colorValue: result.colorValue,
      clearParentCategory: result.parentCategoryId == null,
      clearIcon: result.iconName == null,
      clearColor: result.colorValue == null,
    ),
  );
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
    case 'delete':
      await FinanceDataStoreScope.read(
        context,
      ).saveCategory(category.copyWith(isArchived: true));
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

String accountGroupLabel(v2_account.AccountGroup group) {
  return switch (group) {
    v2_account.AccountGroup.banking => 'Banking',
    v2_account.AccountGroup.cash => 'Cash',
    v2_account.AccountGroup.creditCards => 'Credit Cards',
    v2_account.AccountGroup.loans => 'Loans',
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

String alertTimeInput(int minutesAfterMidnight) {
  final normalized = minutesAfterMidnight.clamp(0, 23 * 60 + 59);
  final hours = normalized ~/ 60;
  final minutes = normalized % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}

int parseAlertTimeMinutes(String value, int fallback) {
  final parts = value.trim().split(':');
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
      .where((category) => !category.isArchived && category.kind == kind)
      .toList(growable: false);
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

int scheduledDueCount(
  Iterable<v2_scheduled.ScheduledTransactionRecord> scheduledTransactions,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  return scheduledTransactions.where((item) {
    if (item.isDeleted) return false;
    final dueDate = DateTime(
      item.nextDate.year,
      item.nextDate.month,
      item.nextDate.day,
    );
    return !dueDate.isAfter(today);
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
