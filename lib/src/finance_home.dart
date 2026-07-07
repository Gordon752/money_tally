part of '../main.dart';

enum FinanceSection {
  dashboard(Icons.dashboard_outlined, 'Dashboard'),
  accounts(Icons.account_balance_wallet_outlined, 'Accounts'),
  ledger(Icons.receipt_long_outlined, 'Ledger'),
  budgets(Icons.pie_chart_outline, 'Budgets'),
  scheduled(Icons.event_repeat_outlined, 'Scheduled'),
  categories(Icons.sell_outlined, 'Categories');

  const FinanceSection(this.icon, this.label);
  final IconData icon;
  final String label;
}

class FinanceHome extends StatefulWidget {
  const FinanceHome({this.syncLabel = 'Sync ready', this.onSignOut, super.key});

  final String syncLabel;
  final VoidCallback? onSignOut;

  @override
  State<FinanceHome> createState() => _FinanceHomeState();
}

class _FinanceHomeState extends State<FinanceHome> {
  var selected = FinanceSection.dashboard;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 880;

    return Scaffold(
      body: SafeArea(child: isWide ? _wideLayout() : _compactLayout()),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: FinanceSection.values.indexOf(selected),
              onDestinationSelected: (index) =>
                  setState(() => selected = FinanceSection.values[index]),
              destinations: [
                for (final section in FinanceSection.values.take(5))
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
              FinanceSection.categories => const CategoriesView(),
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
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    final incomeThisMonth = store.incomeThisMonthMinor();
    final expensesThisMonth = store.expensesThisMonthMinor();
    return Column(
      children: [
        ResponsiveGrid(
          children: [
            SummaryCard(
              label: 'Net worth',
              value: money(store.netWorthMinor),
              icon: Icons.account_balance_wallet_outlined,
              isPrimary: true,
            ),
            SummaryCard(
              label: 'Total assets',
              value: money(store.totalAssetsMinor),
              icon: Icons.trending_up,
            ),
            SummaryCard(
              label: 'Total liabilities',
              value: money(store.totalLiabilitiesMinor.abs()),
              icon: Icons.request_quote_outlined,
            ),
            SummaryCard(
              label: 'Available cash',
              value: money(store.availableCashMinor),
              icon: Icons.payments_outlined,
            ),
            SummaryCard(
              label: 'Month income',
              value: money(incomeThisMonth),
              icon: Icons.add_circle_outline,
            ),
            SummaryCard(
              label: 'Month expenses',
              value: money(expensesThisMonth),
              icon: Icons.remove_circle_outline,
            ),
            SummaryCard(
              label: 'Month remaining',
              value: money(incomeThisMonth - expensesThisMonth),
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
        for (final account in store.accounts)
          AccountCard(
            account: account,
            balanceMinor: store.balanceForAccount(account.id),
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

class ScheduledView extends StatelessWidget {
  const ScheduledView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final scheduled = [...store.scheduledTransactions]
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (final item in scheduled)
              ScheduledTransactionRow(scheduledTransaction: item),
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

class AccountBalancePanel extends StatelessWidget {
  const AccountBalancePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    return AppCard(
      title: 'Accounts',
      child: Column(
        children: [
          for (final account in store.accounts)
            MetricRow(
              label: account.name,
              value: money(store.balanceForAccount(account.id)),
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
    final scheduled = [...store.scheduledTransactions]
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return AppCard(
      title: 'Scheduled',
      child: Column(
        children: [
          for (final item in scheduled.take(3))
            MetricRow(
              label: item.payee,
              value:
                  '${money(item.type.name == 'expense' ? -item.amountMinor.abs() : item.amountMinor)} · ${dateShort(item.nextDate)}',
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
        money(transaction.amountCents),
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
            money(item.amountCents),
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
                    ? 'Over by ${money(remaining.abs())}'
                    : '${money(remaining)} left',
                style: TextStyle(
                  color: isOver ? AppTheme.rose : AppTheme.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Spent ${money(spent)} of ${money(budget.amountMinor)}',
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
        ],
      ),
    ),
  );

  if (action == 'adjust' && context.mounted) {
    await showAdjustBalanceDialog(context, account);
  }
}

Future<void> showTransactionDialog(BuildContext context) async {
  final store = FinanceStoreScope.watch(context);
  final payee = TextEditingController();
  final amount = TextEditingController();
  var accountId = store.accounts.first.id;
  var categoryId = store.categories
      .where((category) => category.kind == CategoryKind.expense)
      .first
      .id;
  var isExpense = true;

  final result =
      await showDialog<
        ({String accountId, String categoryId, String payee, int amountCents})
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
                    onSelectionChanged: (values) =>
                        setDialogState(() => isExpense = values.first),
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

String money(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final dollars = abs ~/ 100;
  final decimal = (abs % 100).toString().padLeft(2, '0');
  return '$sign\$$dollars.$decimal';
}

String dollars(int cents) => (cents / 100).toStringAsFixed(2);

int parseCents(String value) {
  final cleaned = value.replaceAll(RegExp(r'[$,\s]'), '');
  final parsed = double.tryParse(cleaned) ?? 0;
  return (parsed * 100).round();
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
