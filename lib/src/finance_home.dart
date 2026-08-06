part of '../main.dart';

enum FinanceSection {
  dashboard('Dashboard'),
  accounts('Accounts'),
  ledger('Ledger'),
  plan('Plan'),
  scheduled('Scheduled'),
  reports('Reports'),
  categories('Categories'),
  settings('Settings');

  const FinanceSection(this.label);
  final String label;

  IconData get icon => switch (this) {
    FinanceSection.dashboard => AppIcon.dashboard,
    FinanceSection.accounts => AppIcon.accounts,
    FinanceSection.ledger => AppIcon.ledger,
    FinanceSection.plan => AppIcon.plan,
    FinanceSection.scheduled => AppIcon.scheduled,
    FinanceSection.reports => AppIcon.reports,
    FinanceSection.categories => AppIcon.category,
    FinanceSection.settings => AppIcon.settings,
  };

  bool get supportsFloatingAdd => this != FinanceSection.reports;
}

class FinanceHome extends StatefulWidget {
  const FinanceHome({
    this.syncLabel = 'Synced',
    this.lastSuccessfulSyncLabel,
    this.onSyncNow,
    this.onSignOut,
    super.key,
  });

  final String syncLabel;
  final String? lastSuccessfulSyncLabel;
  final Future<void> Function()? onSyncNow;
  final VoidCallback? onSignOut;

  @override
  State<FinanceHome> createState() => _FinanceHomeState();
}

class _FinanceHomeState extends State<FinanceHome> {
  static const compactSections = [
    FinanceSection.dashboard,
    FinanceSection.accounts,
    FinanceSection.ledger,
    FinanceSection.plan,
    FinanceSection.scheduled,
  ];

  var selected = FinanceSection.dashboard;
  String? ledgerAccountFilterId;
  DateTime? _selectedFutureScheduledDate;
  var _planSegment = PlanSegment.budgets;
  var _appliedLaunchPreference = false;
  var _isScrolling = false;
  Timer? _scrollSettleTimer;
  FinanceDataStore? _budgetAlertStore;

  void _setPlanSegment(PlanSegment segment) {
    if (_planSegment == segment) return;
    setState(() => _planSegment = segment);
    final store = FinanceDataStoreScope.read(context);
    unawaited(
      store.savePreferences(
        store.preferences.copyWith(preferredPlanSegment: segment),
      ),
    );
  }

  void _openPlan(PlanSegment segment, {bool createGoal = false}) {
    setState(() {
      selected = FinanceSection.plan;
      _planSegment = segment;
    });
    final store = FinanceDataStoreScope.read(context);
    unawaited(
      store.savePreferences(
        store.preferences.copyWith(preferredPlanSegment: segment),
      ),
    );
    if (createGoal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(showCreateGoalSheet(context));
      });
    }
  }

  @override
  void initState() {
    super.initState();
    scheduledNotificationLaunchPayload.addListener(
      _openScheduledFromNotification,
    );
  }

  void _openScheduledFromNotification() {
    if (scheduledNotificationLaunchPayload.value == null) return;
    scheduledNotificationLaunchPayload.value = null;
    if (mounted) setState(() => selected = FinanceSection.scheduled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = FinanceDataStoreScope.read(context);
    if (_budgetAlertStore != store) {
      _budgetAlertStore?.budgetLowAlertNotifier.removeListener(
        _showBudgetLowAlert,
      );
      _budgetAlertStore = store;
      _budgetAlertStore?.budgetLowAlertNotifier.addListener(
        _showBudgetLowAlert,
      );
    }
    if (_appliedLaunchPreference) return;
    final preferences = store.preferences;
    selected = financeSectionForLaunchScreen(preferences.launchScreen);
    _planSegment = switch (preferences.launchScreen) {
      LaunchScreen.planGoals => PlanSegment.goals,
      LaunchScreen.planBudgets || LaunchScreen.budgets => PlanSegment.budgets,
      _ => preferences.preferredPlanSegment,
    };
    if (scheduledNotificationLaunchPayload.value != null) {
      scheduledNotificationLaunchPayload.value = null;
      selected = FinanceSection.scheduled;
    }
    _appliedLaunchPreference = true;
  }

  @override
  void dispose() {
    _scrollSettleTimer?.cancel();
    _budgetAlertStore?.budgetLowAlertNotifier.removeListener(
      _showBudgetLowAlert,
    );
    scheduledNotificationLaunchPayload.removeListener(
      _openScheduledFromNotification,
    );
    super.dispose();
  }

  void _showBudgetLowAlert() {
    final store = _budgetAlertStore;
    final alert = store?.budgetLowAlertNotifier.value;
    if (!mounted || store == null || alert == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || store.budgetLowAlertNotifier.value != alert) return;
      var consumed = false;
      void consume() {
        if (consumed) return;
        consumed = true;
        store.dismissBudgetLowAlert();
      }

      final controller = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${alert.budgetName} budget is almost used up',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '${money(alert.remainingMinor, store.preferences.currency)} remains for this budget period.',
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Adjust Budget',
            onPressed: () {
              consume();
              final budget = store.budgets
                  .where((item) => item.id == alert.budgetId && item.isVisible)
                  .firstOrNull;
              if (budget == null) return;
              _openPlan(PlanSegment.budgets);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  unawaited(showBudgetDialog(context, budget: budget));
                }
              });
            },
          ),
        ),
      );
      unawaited(controller.closed.then((_) => consume()));
    });
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
                        onPressed: () => showFloatingAddMenu(
                          context,
                          section: selected,
                          planSegment: _planSegment,
                          initialAccountId: selected == FinanceSection.ledger
                              ? ledgerAccountFilterId
                              : null,
                          initialScheduledDate:
                              selected == FinanceSection.scheduled
                              ? _selectedFutureScheduledDate
                              : null,
                        ),
                        child: Icon(AppIcon.add),
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
              onDestinationSelected: (index) {
                HapticFeedback.selectionClick();
                setState(() {
                  selected = compactSections[index];
                  if (selected == FinanceSection.ledger) {
                    ledgerAccountFilterId = null;
                  }
                });
              },
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
          onDestinationSelected: (index) {
            HapticFeedback.selectionClick();
            setState(() {
              selected = FinanceSection.values[index];
              if (selected == FinanceSection.ledger) {
                ledgerAccountFilterId = null;
              }
            });
          },
          leading: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Icon(AppIcon.bankSolid, color: AppTheme.accent),
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

  Future<void> _openManagementSection(FinanceSection section) async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => FinanceManagementScreen(section: section),
      ),
    );
  }

  Widget _sectionBody() {
    if (selected == FinanceSection.plan) {
      return PlanView(
        selectedSegment: _planSegment,
        onSegmentChanged: _setPlanSegment,
        onOpenSettings: () =>
            setState(() => selected = FinanceSection.settings),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              section: selected,
              onOpenSettings: () =>
                  setState(() => selected = FinanceSection.settings),
            ),
          ),
          if (widget.syncLabel == 'Sync issue')
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: ListTile(
                    dense: true,
                    leading: Icon(AppIcon.cloudOff),
                    title: Text('Cloud sync needs attention'),
                    trailing: Icon(AppIcon.chevronRight),
                    onTap: () =>
                        setState(() => selected = FinanceSection.settings),
                  ),
                ),
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
                FinanceSection.dashboard => DashboardView(
                  onViewLedger: () => setState(() {
                    ledgerAccountFilterId = null;
                    selected = FinanceSection.ledger;
                  }),
                  onViewBudgets: () => _openPlan(PlanSegment.budgets),
                  onViewGoals: () => _openPlan(PlanSegment.goals),
                  onCreateGoal: () =>
                      _openPlan(PlanSegment.goals, createGoal: true),
                  onViewScheduled: () =>
                      setState(() => selected = FinanceSection.scheduled),
                ),
                FinanceSection.accounts => AccountsView(
                  onOpenLedgerForAccount: (accountId) => setState(() {
                    ledgerAccountFilterId = accountId;
                    selected = FinanceSection.ledger;
                  }),
                ),
                FinanceSection.ledger => LedgerView(
                  key: ValueKey(
                    'ledger-${ledgerAccountFilterId ?? 'all-accounts'}',
                  ),
                  initialAccountFilterId: ledgerAccountFilterId,
                ),
                FinanceSection.plan => const SizedBox.shrink(),
                FinanceSection.scheduled => ScheduledView(
                  onSelectedDateChanged: (date) {
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final selectedDay = DateTime(
                      date.year,
                      date.month,
                      date.day,
                    );
                    setState(() {
                      _selectedFutureScheduledDate = selectedDay.isAfter(today)
                          ? selectedDay
                          : null;
                    });
                  },
                ),
                FinanceSection.reports => const ReportsView(),
                FinanceSection.categories => const CategoriesView(),
                FinanceSection.settings => SettingsView(
                  onSelectSection: _openManagementSection,
                  syncLabel: widget.syncLabel,
                  lastSuccessfulSyncLabel: widget.lastSuccessfulSyncLabel,
                  onSyncNow: widget.onSyncNow,
                  onSignOut: widget.onSignOut,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class FinanceManagementScreen extends StatelessWidget {
  const FinanceManagementScreen({required this.section, super.key});

  final FinanceSection section;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      FinanceSection.accounts => 'Accounts',
      FinanceSection.categories => 'Categories',
      FinanceSection.plan => 'Plan',
      FinanceSection.reports => 'Reports',
      _ => section.label,
    };
    return Scaffold(
      appBar: AppBar(title: Text(title), scrolledUnderElevation: 0),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
          child: switch (section) {
            FinanceSection.accounts => const AccountsView(),
            FinanceSection.categories => const CategoriesView(),
            FinanceSection.plan => const BudgetsView(),
            FinanceSection.reports => const ReportsView(),
            _ => const SizedBox.shrink(),
          },
        ),
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
    required this.onOpenSettings,
    super.key,
  });

  final FinanceSection section;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  trackmarkMoneyName,
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                visualDensity: VisualDensity.compact,
                onPressed: onOpenSettings,
                icon: Icon(AppIcon.settings, size: AppIconSize.row),
              ),
            ],
          ),
          const SizedBox(height: 2),
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
        padding: EdgeInsets.only(left: 12, right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcon.cloud,
              color: AppTheme.accent,
              size: AppIconSize.compact,
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 62,
              child: AnimatedSwitcher(
                duration: MediaQuery.of(context).disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Text(
                  displayLabel,
                  key: ValueKey(displayLabel),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
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
                  constraints: BoxConstraints.tightFor(width: 24, height: 24),
                  padding: EdgeInsets.zero,
                  onPressed: onSignOut,
                  icon: Icon(AppIcon.signOutSolid, size: AppIconSize.compact),
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
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        child,
        if (helperText != null) ...[
          const SizedBox(height: 3),
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
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
  );
}

EdgeInsets transactionDialogInsetPadding(BuildContext context) {
  final topSafeArea = MediaQuery.paddingOf(context).top;
  final topInset = topSafeArea + AppSpacing.md;
  return EdgeInsets.fromLTRB(24, topInset.clamp(72, 112).toDouble(), 24, 24);
}

class TransactionSheetFrame extends StatelessWidget {
  const TransactionSheetFrame({
    required this.title,
    required this.child,
    required this.actions,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final topInset = (media.padding.top + 10).clamp(64.0, 88.0).toDouble();
    final maxHeight = media.size.height - topInset - keyboardInset - 8;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.fromLTRB(18, topInset, 18, 8),
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 430, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 58,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: child,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                6,
                20,
                keyboardInset > 0 ? 10 : 16,
              ),
              child: actions,
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionFormLabel extends StatelessWidget {
  const TransactionFormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class TransactionFormIcon extends StatelessWidget {
  const TransactionFormIcon(this.icon, {this.color, super.key});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? AppTheme.accent;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: resolvedColor.withValues(alpha: 0.9),
        size: AppIconSize.row,
      ),
    );
  }
}

class TransactionFormDivider extends StatelessWidget {
  const TransactionFormDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Divider(
        height: 1,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.52),
      ),
    );
  }
}

class TransactionFormValueRow extends StatelessWidget {
  const TransactionFormValueRow({
    required this.icon,
    required this.value,
    this.secondary,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String value;
  final String? secondary;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TransactionFormIcon(icon),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleMedium),
              if (secondary != null)
                Text(
                  secondary!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        ...switch (trailing) {
          null => const <Widget>[],
          final value => <Widget>[value],
        },
      ],
    );
  }
}

class ManagementCountPill extends StatelessWidget {
  const ManagementCountPill({
    required this.count,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final int count;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayCount = count > 9999 ? '9999+' : '$count';
    return Semantics(
      button: onTap != null,
      label: semanticLabel ?? '$count transactions',
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.78,
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.64),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: SizedBox(
            width: 58,
            height: 28,
            child: Center(
              child: Text(
                displayCount,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ManagementSwipeAction {
  const ManagementSwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.actionKey,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final Key? actionKey;
}

class ManagementSwipeRow extends StatefulWidget {
  const ManagementSwipeRow({
    required this.child,
    required this.actions,
    super.key,
  });

  final Widget child;
  final List<ManagementSwipeAction> actions;

  @override
  State<ManagementSwipeRow> createState() => _ManagementSwipeRowState();
}

class _ManagementSwipeRowState extends State<ManagementSwipeRow> {
  static const _actionWidth = 72.0;
  var _offset = 0.0;
  var _isDragging = false;

  double get _actionsWidth => widget.actions.length * _actionWidth;

  void _close() => setState(() {
    _isDragging = false;
    _offset = 0;
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          if (_offset < 0)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in widget.actions)
                      SizedBox(
                        key: action.actionKey,
                        width: _actionWidth,
                        height: double.infinity,
                        child: Material(
                          color: action.color.withValues(alpha: 0.12),
                          child: InkWell(
                            onTap: () {
                              _close();
                              HapticFeedback.selectionClick();
                              action.onPressed();
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  action.icon,
                                  size: AppIconSize.compact,
                                  color: action.color,
                                ),
                                Text(
                                  action.label,
                                  maxLines: 1,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: action.color,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 9,
                                        height: 1,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          AnimatedContainer(
            duration: _isDragging
                ? Duration.zero
                : const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => setState(() => _isDragging = true),
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _offset = (_offset + details.delta.dx).clamp(
                    -_actionsWidth,
                    0,
                  );
                });
              },
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                setState(() {
                  _isDragging = false;
                  _offset = velocity < -250 || _offset < -_actionsWidth * 0.3
                      ? -_actionsWidth
                      : 0;
                });
              },
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionFormActions extends StatelessWidget {
  const TransactionFormActions({
    required this.onCancel,
    required this.onSave,
    this.canSave = true,
    this.saveLabel = 'Save',
    this.isSaving = false,
    this.saveKey,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final bool canSave;
  final String saveLabel;
  final bool isSaving;
  final Key? saveKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: isSaving ? null : onCancel,
              child: const Text('Cancel'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton(
              key: saveKey,
              onPressed: canSave && !isSaving ? onSave : null,
              child: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Text(saveLabel),
            ),
          ),
        ),
      ],
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({
    required this.onViewLedger,
    required this.onViewBudgets,
    required this.onViewGoals,
    required this.onCreateGoal,
    required this.onViewScheduled,
    super.key,
  });

  final VoidCallback onViewLedger;
  final VoidCallback onViewBudgets;
  final VoidCallback onViewGoals;
  final VoidCallback onCreateGoal;
  final VoidCallback onViewScheduled;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final scheduled = store.actionableScheduledTransactions();
    final incomeThisMonth = store.incomeThisMonthMinor();
    final expensesThisMonth = store.expensesThisMonthMinor();
    final currency = store.preferences.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NetWorthHeroCard(
          netWorthMinor: store.netWorthMinor,
          assetsMinor: store.totalAssetsMinor + store.fundedGoalAssetsMinor,
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
            GoalsPreviewCard(onViewAll: onViewGoals, onCreate: onCreateGoal),
            NextScheduledCard(
              scheduled: scheduled,
              currency: currency,
              onViewAll: onViewScheduled,
            ),
            const AccountBalancePanel(
              title: 'Accounts Preview',
              maxRows: 4,
              compact: true,
            ),
            BudgetPanel(
              title: 'Budgets Preview',
              maxRows: 2,
              compact: true,
              onViewAll: onViewBudgets,
            ),
            RecentTransactionsPanel(
              title: 'Recent Transactions',
              maxRows: 3,
              compact: true,
              onViewAll: onViewLedger,
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
        padding: EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcon.wallet, color: Colors.white),
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
      padding: EdgeInsets.all(AppSpacing.sm),
      child: CompactMetricRow(
        label: 'Available Cash',
        amountMinor: availableCashMinor,
        currency: currency,
        icon: AppIcon.cash,
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
      padding: EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          CompactMetricRow(
            label: 'Income',
            amountMinor: incomeMinor,
            currency: currency,
            icon: AppIcon.income,
            showPositiveSign: true,
          ),
          CompactMetricRow(
            label: 'Expenses',
            amountMinor: -expensesMinor.abs(),
            currency: currency,
            icon: AppIcon.expense,
          ),
          CompactMetricRow(
            label: 'Remaining',
            amountMinor: incomeMinor - expensesMinor,
            currency: currency,
            icon: AppIcon.savings,
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
    required this.onViewAll,
    super.key,
  });

  final List<v2_scheduled.ScheduledTransactionRecord> scheduled;
  final CurrencyFormatSettings currency;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final nextItems = scheduled.take(3).toList(growable: false);
    return AppCard(
      title: 'Next Scheduled',
      padding: EdgeInsets.all(AppSpacing.sm),
      child: nextItems.isEmpty
          ? CompactEmptyRow(
              icon: AppIcon.recurrence,
              label: 'No scheduled transactions',
            )
          : Column(
              children: [
                for (var index = 0; index < nextItems.length; index++) ...[
                  _NextScheduledRow(
                    scheduled: nextItems[index],
                    currency: currency,
                  ),
                  if (index != nextItems.length - 1)
                    Divider(
                      height: 16,
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.24),
                    ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onViewAll,
                    label: Text('View All Scheduled'),
                    iconAlignment: IconAlignment.end,
                    icon: Icon(AppIcon.arrowForward, size: AppIconSize.inline),
                  ),
                ),
              ],
            ),
    );
  }
}

class _NextScheduledRow extends StatelessWidget {
  const _NextScheduledRow({required this.scheduled, required this.currency});

  final v2_scheduled.ScheduledTransactionRecord scheduled;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          scheduled.type == TransactionType.goalFunding
              ? AppIcon.goal
              : AppIcon.recurrence,
          color: scheduled.type == TransactionType.goalFunding
              ? _goalBlue
              : AppTheme.accent,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scheduled.type == TransactionType.goalFunding
                    ? (scheduled.goalFundingAllocations.length == 1
                          ? 'Goal Funding'
                          : 'Goal Funding · ${scheduled.goalFundingAllocations.length} Goals')
                    : scheduled.payee,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                shortDate(scheduled.nextDate),
                style: TextStyle(
                  color: AppTheme.ink.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        MoneyText(
          amountMinor: scheduled.type.name == 'expense'
              ? -scheduled.amountMinor.abs()
              : scheduled.amountMinor,
          currency: currency,
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: scheduled.type.name == 'expense'
              ? AppTheme.rose
              : scheduled.type == TransactionType.goalFunding
              ? _goalBlue
              : AppTheme.ink,
          showPositiveSign: scheduled.type.name == 'income',
        ),
      ],
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
          Icon(icon, color: AppTheme.accent, size: AppIconSize.form),
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
    final showsLiabilitySummary = progress != null;
    final headerTextStyle = theme.textTheme.titleMedium?.copyWith(
      color: AppTheme.accentStrong,
      fontSize: 19,
      fontWeight: FontWeight.w700,
    );

    if (group == v2_account.AccountGroup.creditCards) {
      return _buildCreditCardGroup(
        context,
        isCollapsed: isCollapsed,
        label: label,
        balanceMinor: balanceMinor,
        progress: progress,
        headerTextStyle: headerTextStyle,
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      borderRadius: 12,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Tooltip(
              message: isCollapsed ? 'Expand $label' : 'Collapse $label',
              child: InkWell(
                key: ValueKey('account-group-${group.name}'),
                borderRadius: BorderRadius.circular(AppRadii.card),
                onTap: () {
                  HapticFeedback.selectionClick();
                  toggleAccountGroupCollapsed(
                    context,
                    group,
                    isCollapsed: isCollapsed,
                  );
                },
                onLongPress: () {
                  AppHaptics.longPressAction();
                  showAccountGroupActions(context, group);
                },
                child: _AccountGroupSummaryRow(
                  group: group,
                  label: label,
                  balanceMinor: balanceMinor,
                  currency: store.preferences.currency,
                  isCollapsed: isCollapsed,
                  headerTextStyle: headerTextStyle,
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
                        if (showsLiabilitySummary) ...[
                          Padding(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.xxs,
                              bottom: AppSpacing.sm,
                            ),
                            child: Text(
                              'Total Balance',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.15,
                              ),
                            ),
                          ),
                          progress,
                        ],
                        SizedBox(
                          height: showsLiabilitySummary
                              ? AppSpacing.md
                              : AppSpacing.xs,
                        ),
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.55,
                          ),
                        ),
                        if (showsLiabilitySummary)
                          const SizedBox(height: AppSpacing.xs),
                        for (var index = 0; index < accounts.length; index++)
                          Dismissible(
                            key: ValueKey(
                              'account-swipe-${accounts[index].id}',
                            ),
                            direction: DismissDirection.horizontal,
                            dismissThresholds: const {
                              DismissDirection.startToEnd: 0.22,
                              DismissDirection.endToStart: 0.22,
                            },
                            background: SwipeActionBackground(
                              alignment: Alignment.centerLeft,
                              icon: AppIcon.transfer,
                              label: 'Expense  Income  Transfer',
                            ),
                            secondaryBackground: SwipeActionBackground(
                              alignment: Alignment.centerRight,
                              icon: AppIcon.edit,
                              label: 'Edit  Archive  Delete',
                              destructive: true,
                            ),
                            confirmDismiss: (direction) async {
                              HapticFeedback.selectionClick();
                              await showAccountOptions(
                                context,
                                accounts[index].id,
                                allowedActions:
                                    direction == DismissDirection.startToEnd
                                    ? const {'expense', 'income', 'transfer'}
                                    : const {'edit', 'archive', 'delete'},
                              );
                              return false;
                            },
                            child: AccountCard(
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
                                size: AppIconSize.form,
                              ),
                              onTap: onOpenLedgerForAccount == null
                                  ? null
                                  : () => onOpenLedgerForAccount!(
                                      accounts[index].id,
                                    ),
                              onLongPress: () {
                                AppHaptics.longPressAction();
                                showAccountOptions(context, accounts[index].id);
                              },
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

  Widget _buildCreditCardGroup(
    BuildContext context, {
    required bool isCollapsed,
    required String label,
    required int balanceMinor,
    required Widget? progress,
    required TextStyle? headerTextStyle,
  }) {
    final animationsDisabled = MediaQuery.of(context).disableAnimations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          borderRadius: 14,
          child: Tooltip(
            message: isCollapsed ? 'Expand $label' : 'Collapse $label',
            child: InkWell(
              key: ValueKey('account-group-${group.name}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                HapticFeedback.selectionClick();
                toggleAccountGroupCollapsed(
                  context,
                  group,
                  isCollapsed: isCollapsed,
                );
              },
              onLongPress: () {
                AppHaptics.longPressAction();
                showAccountGroupActions(context, group);
              },
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AccountGroupSummaryRow(
                      group: group,
                      label: label,
                      balanceMinor: balanceMinor,
                      currency: store.preferences.currency,
                      isCollapsed: isCollapsed,
                      headerTextStyle: headerTextStyle,
                    ),
                    AnimatedSize(
                      duration: animationsDisabled
                          ? Duration.zero
                          : const Duration(milliseconds: 175),
                      reverseDuration: animationsDisabled
                          ? Duration.zero
                          : const Duration(milliseconds: 145),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: isCollapsed || progress == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.sm,
                              ),
                              child: progress,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: animationsDisabled
              ? Duration.zero
              : const Duration(milliseconds: 175),
          reverseDuration: animationsDisabled
              ? Duration.zero
              : const Duration(milliseconds: 145),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isCollapsed
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.xs),
                    for (var index = 0; index < accounts.length; index++) ...[
                      _buildCreditCardAccount(context, accounts[index]),
                      if (index != accounts.length - 1)
                        const SizedBox(height: AppSpacing.xs),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCreditCardAccount(
    BuildContext context,
    v2_account.AccountRecord account,
  ) {
    const radius = 14.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Dismissible(
        key: ValueKey('account-swipe-${account.id}'),
        direction: DismissDirection.horizontal,
        dismissThresholds: const {
          DismissDirection.startToEnd: 0.22,
          DismissDirection.endToStart: 0.22,
        },
        background: SwipeActionBackground(
          alignment: Alignment.centerLeft,
          icon: AppIcon.transfer,
          label: 'Expense  Income  Transfer',
        ),
        secondaryBackground: SwipeActionBackground(
          alignment: Alignment.centerRight,
          icon: AppIcon.edit,
          label: 'Edit  Archive  Delete',
          destructive: true,
        ),
        confirmDismiss: (direction) async {
          HapticFeedback.selectionClick();
          await showAccountOptions(
            context,
            account.id,
            allowedActions: direction == DismissDirection.startToEnd
                ? const {'expense', 'income', 'transfer'}
                : const {'edit', 'archive', 'delete'},
          );
          return false;
        },
        child: AccountCard(
          account: account,
          balanceMinor: store.balanceForAccount(account.id),
          currency: store.preferences.currency,
          subtitle: lastAccountActivitySubtitle(store, account.id),
          balanceFontSize: 17,
          framed: true,
          borderRadius: radius,
          showNavigationChevron: true,
          metricLeadingIndent: 58,
          padding: const EdgeInsets.all(AppSpacing.md),
          leading: _CreditCardAccountBadge(accountName: account.name),
          onTap: onOpenLedgerForAccount == null
              ? null
              : () => onOpenLedgerForAccount!(account.id),
          onLongPress: () {
            AppHaptics.longPressAction();
            showAccountOptions(context, account.id);
          },
        ),
      ),
    );
  }
}

class _AccountGroupSummaryRow extends StatelessWidget {
  const _AccountGroupSummaryRow({
    required this.group,
    required this.label,
    required this.balanceMinor,
    required this.currency,
    required this.isCollapsed,
    required this.headerTextStyle,
  });

  final v2_account.AccountGroup group;
  final String label;
  final int balanceMinor;
  final CurrencyFormatSettings currency;
  final bool isCollapsed;
  final TextStyle? headerTextStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final animationsDisabled = MediaQuery.of(context).disableAnimations;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.55,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.62),
            ),
          ),
          child: Icon(
            accountGroupIcon(group.name),
            color: theme.colorScheme.onSurfaceVariant,
            size: AppIconSize.action,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: headerTextStyle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        MoneyText(
          amountMinor: balanceMinor,
          currency: currency,
          color: balanceMinor < 0 ? AppColors.danger : null,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        const SizedBox(width: AppSpacing.xs),
        AnimatedRotation(
          turns: isCollapsed ? -0.25 : 0,
          duration: animationsDisabled
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: Icon(
            AppIcon.dropdown,
            color: theme.colorScheme.onSurfaceVariant,
            size: AppIconSize.action,
          ),
        ),
      ],
    );
  }
}

class _CreditCardAccountBadge extends StatelessWidget {
  const _CreditCardAccountBadge({required this.accountName});

  final String accountName;

  @override
  Widget build(BuildContext context) {
    final words = accountName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final initial = words.isEmpty
        ? 'C'
        : words.length == 1
        ? words.first.characters.first.toUpperCase()
        : words
              .take(2)
              .map((word) => word.characters.first)
              .join()
              .toUpperCase();
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.18)),
      ),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: AppTheme.accentStrong,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String lastAccountActivitySubtitle(FinanceDataStore store, String accountId) {
  final activity =
      store.transactions
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
      final available = store.creditAvailableMinorForGroup(group);
      return AccountGroupProgressStrip(
        label:
            'Credit Available ${money(available, store.preferences.currency)} of ${money(limit, store.preferences.currency)}',
        progress: used / limit,
        isOver: used > limit,
        showPercentage: true,
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
    this.showPercentage = false,
    super.key,
  });

  final String label;
  final double progress;
  final bool isOver;
  final bool showPercentage;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: EdgeInsets.zero,
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
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: value,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.62),
                      color: (isOver ? AppColors.danger : AppColors.accent)
                          .withValues(alpha: 0.82),
                    ),
                  ),
                ),
              ),
              if (showPercentage) ...[
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${(value * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isOver ? AppColors.danger : AppTheme.accentStrong,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [AppTextStyles.tabularFigures],
                    ),
                  ),
                ),
              ],
            ],
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
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(AppIcon.edit),
              title: Text('Rename'),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              enabled: canMoveUp,
              leading: Icon(AppIcon.arrowUp),
              title: Text('Move Up'),
              onTap: canMoveUp
                  ? () => Navigator.pop(sheetContext, 'moveUp')
                  : null,
            ),
            ListTile(
              enabled: canMoveDown,
              leading: Icon(AppIcon.arrowDown),
              title: const Text('Move Down'),
              onTap: canMoveDown
                  ? () => Navigator.pop(sheetContext, 'moveDown')
                  : null,
            ),
          ],
        ),
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
  const LedgerView({
    this.initialAccountFilterId,
    this.initialManagementFilter,
    super.key,
  });

  final String? initialAccountFilterId;
  final ManagementLedgerFilter? initialManagementFilter;

  @override
  State<LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends State<LedgerView> {
  final _searchFocusNode = FocusNode(
    debugLabel: 'ledger-search',
    skipTraversal: true,
  );
  var query = '';
  var typeFilterName = '';
  var accountFilterId = '';
  var categoryFilterId = '';
  var dateFilter = LedgerDateFilter.all;
  DateTimeRange? customDateRange;
  ManagementLedgerFilter? managementFilter;
  final _collapsedMonthKeys = <String>{};
  final _monthAnchors = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    accountFilterId = widget.initialAccountFilterId ?? '';
    managementFilter = widget.initialManagementFilter;
  }

  @override
  void didUpdateWidget(covariant LedgerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAccountFilterId != oldWidget.initialAccountFilterId &&
        widget.initialAccountFilterId != null) {
      accountFilterId = widget.initialAccountFilterId!;
    }
    if (widget.initialManagementFilter != oldWidget.initialManagementFilter) {
      managementFilter = widget.initialManagementFilter;
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
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
    final now = DateTime.now();
    final managementTransactionIds = managementFilter == null
        ? null
        : ManagementLedgerIndex.build(
            transactions: store.transactions,
            categories: store.categories,
            now: now,
          ).transactionIdsFor(managementFilter!);
    final normalizedQuery = query.trim().toLowerCase();
    final requestedCategoryId = categoryFilterId.isNotEmpty
        ? categoryFilterId
        : managementFilter?.kind == ManagementLedgerFilterKind.category
        ? managementFilter!.value
        : '';
    final categoryScope = requestedCategoryId.isEmpty
        ? null
        : LedgerCategoryScope.fromCategory(
            store.categories,
            requestedCategoryId,
          );
    final unprojectedTransactions =
        store.transactions
            .where((transaction) => !transaction.isDeleted)
            .where(
              (transaction) =>
                  managementTransactionIds == null ||
                  managementTransactionIds.contains(transaction.id),
            )
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
                // Category matching is resolved by the shared allocation
                // projection below so parent scopes and split amounts agree.
                categoryFilterId: '',
                dateFilter: dateFilter,
                customDateRange: customDateRange,
                now: now,
              ),
            )
            .toList()
          ..sort(compareTransactionsNewestFirst);
    final transactions = projectLedgerTransactions(
      unprojectedTransactions,
      categoryScope: categoryScope,
    );
    final goalFundingEvents =
        store.goalFundingEvents
            .where((event) => event.isActive)
            .where(
              (event) =>
                  managementFilter == null &&
                  typeFilterName.isEmpty &&
                  categoryFilterId.isEmpty &&
                  (accountFilterId.isEmpty ||
                      event.sourceAccountId == accountFilterId) &&
                  dateMatchesLedgerFilter(
                    event.date,
                    dateFilter: dateFilter,
                    customDateRange: customDateRange,
                    now: now,
                  ),
            )
            .where((event) {
              if (normalizedQuery.isEmpty) return true;
              final goalNames = event.allocations
                  .map(
                    (allocation) => store.goals
                        .where((goal) => goal.id == allocation.goalId)
                        .firstOrNull
                        ?.name,
                  )
                  .whereType<String>()
                  .join(' ');
              final accountName =
                  accountsById[event.sourceAccountId]?.name ?? '';
              return 'funded goals ${event.note} $goalNames $accountName'
                  .toLowerCase()
                  .contains(normalizedQuery);
            })
            .toList(growable: false)
          ..sort((a, b) => b.date.compareTo(a.date));
    final hasFilters =
        typeFilterName.isNotEmpty ||
        accountFilterId.isNotEmpty ||
        categoryFilterId.isNotEmpty ||
        dateFilter != LedgerDateFilter.all ||
        managementFilter != null;
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
        : dateFilter == LedgerDateFilter.custom && customDateRange != null
        ? '${shortMonthDay(customDateRange!.start)}–${shortMonthDay(customDateRange!.end)}'
        : ledgerDateFilterLabel(dateFilter);
    final activeFilterCount = [
      typeFilterName.isNotEmpty,
      accountFilterId.isNotEmpty,
      categoryFilterId.isNotEmpty,
      dateFilter != LedgerDateFilter.all,
    ].where((isActive) => isActive).length;
    final transactionsByMonth = <DateTime, List<LedgerTransactionProjection>>{};
    for (final projection in transactions) {
      final month = DateTime(
        projection.transaction.date.year,
        projection.transaction.date.month,
      );
      transactionsByMonth.putIfAbsent(month, () => []).add(projection);
    }
    final fundingByMonth = <DateTime, List<GoalFundingEventRecord>>{};
    for (final event in goalFundingEvents) {
      final month = DateTime(event.date.year, event.date.month);
      fundingByMonth.putIfAbsent(month, () => []).add(event);
    }
    final visibleMonths = {
      ...transactionsByMonth.keys,
      ...fundingByMonth.keys,
    }.toList(growable: false)..sort((a, b) => b.compareTo(a));
    for (final month in visibleMonths) {
      _monthAnchors.putIfAbsent(ledgerMonthKey(month), () => GlobalKey());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (accountFilterId.isNotEmpty &&
            accountsById[accountFilterId] != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        accountsById[accountFilterId]!.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Current balance',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                MoneyText(
                  amountMinor: store.balanceForAccount(accountFilterId),
                  currency: store.preferences.currency,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ],
            ),
          ),
        ],
        if (managementFilter case final filter?) ...[
          Container(
            key: const ValueKey('ledger-management-filter-context'),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.46),
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  filter.kind == ManagementLedgerFilterKind.category
                      ? AppIcon.category
                      : AppIcon.payee,
                  size: AppIconSize.inline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${filter.kind == ManagementLedgerFilterKind.category ? 'Category' : 'Payee'}: ${filter.label}',
                        key: const ValueKey('ledger-management-filter-label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Period: Last 12 Months',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => managementFilter = null),
                  child: const Text('Clear Filter'),
                ),
              ],
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: TextField(
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(AppIcon.search, size: AppIconSize.inline),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.2,
                      ),
                    ),
                  ),
                  onTapOutside: (_) => _dismissSearchFocus(),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox.square(
              dimension: 44,
              child: IconButton(
                key: const ValueKey('ledger-filter-button'),
                tooltip: activeFilterCount == 0
                    ? 'Filters'
                    : 'Filters ($activeFilterCount)',
                onPressed: () async {
                  _dismissSearchFocus();
                  await showLedgerFilters(
                    context: context,
                    activeAccounts: activeAccounts,
                    activeCategories: activeCategories,
                    selectedTypeLabel: selectedTypeLabel,
                    selectedAccountLabel: selectedAccountLabel,
                    selectedCategoryLabel: selectedCategoryLabel,
                    selectedDateLabel: selectedDateLabel,
                    visibleMonths: visibleMonths,
                  );
                  if (mounted) _dismissSearchFocus();
                },
                icon: Icon(AppIcon.filter, size: AppIconSize.form),
                style: IconButton.styleFrom(
                  backgroundColor: activeFilterCount == 0
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.55)
                      : Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: activeFilterCount == 0
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onPrimaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox.square(
              dimension: 44,
              child: IconButton(
                tooltip: 'Clear filters',
                onPressed: hasFilters ? clearFilters : null,
                icon: Icon(AppIcon.clearFilter, size: AppIconSize.form),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (transactions.isEmpty && goalFundingEvents.isEmpty)
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
          for (final month in visibleMonths) ...[
            LedgerMonthSection(
              key: _monthAnchors[ledgerMonthKey(month)],
              month: month,
              transactions: transactionsByMonth[month] ?? const [],
              goalFundingEvents: fundingByMonth[month] ?? const [],
              store: store,
              accountsById: accountsById,
              categoriesById: categoriesById,
              isCollapsed: _collapsedMonthKeys.contains(ledgerMonthKey(month)),
              onDismissFocus: _dismissSearchFocus,
              onToggle: () {
                _dismissSearchFocus();
                HapticFeedback.selectionClick();
                setState(() {
                  final key = ledgerMonthKey(month);
                  if (!_collapsedMonthKeys.add(key)) {
                    _collapsedMonthKeys.remove(key);
                  }
                });
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }

  void clearFilters() {
    _dismissSearchFocus();
    setState(() {
      typeFilterName = '';
      accountFilterId = '';
      categoryFilterId = '';
      dateFilter = LedgerDateFilter.all;
      customDateRange = null;
      managementFilter = null;
    });
  }

  void _dismissSearchFocus() {
    _searchFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
  }

  Future<void> showLedgerFilters({
    required BuildContext context,
    required List<v2_account.AccountRecord> activeAccounts,
    required List<v2_category.CategoryRecord> activeCategories,
    required String selectedTypeLabel,
    required String selectedAccountLabel,
    required String selectedCategoryLabel,
    required String selectedDateLabel,
    required List<DateTime> visibleMonths,
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
                  LedgerFilterButton(
                    buttonKey: ValueKey('ledger-type-$typeFilterName'),
                    icon: AppIcon.filter,
                    label: selectedTypeLabel,
                    isActive: typeFilterName.isNotEmpty,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        final value = await showLedgerSelectionSheet<String>(
                          context: context,
                          title: 'Filter by Type',
                          selectedValue: typeFilterName,
                          items: [
                            (
                              value: '',
                              label: 'All types',
                              icon: AppIcon.filter,
                              detail: null,
                            ),
                            for (final type in TransactionType.values)
                              (
                                value: type.name,
                                label: transactionTypeLabel(type),
                                icon: transactionTypeIcon(type),
                                detail: null,
                              ),
                          ],
                        );
                        if (value != null && mounted) {
                          setState(() => typeFilterName = value);
                        }
                      });
                    },
                  ),
                  LedgerFilterButton(
                    buttonKey: ValueKey('ledger-account-$accountFilterId'),
                    icon: AppIcon.wallet,
                    label: selectedAccountLabel,
                    isActive: accountFilterId.isNotEmpty,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        final value = await showLedgerSelectionSheet<String>(
                          context: context,
                          title: 'Filter by Account',
                          searchable: activeAccounts.length > 7,
                          selectedValue: accountFilterId,
                          items: [
                            (
                              value: '',
                              label: 'All accounts',
                              icon: AppIcon.wallet,
                              detail: null,
                            ),
                            for (final account in activeAccounts)
                              (
                                value: account.id,
                                label: account.name,
                                icon: v2AccountIcon(account.type),
                                detail: v2AccountTypeLabel(account.type),
                              ),
                          ],
                        );
                        if (value != null && mounted) {
                          setState(() => accountFilterId = value);
                        }
                      });
                    },
                  ),
                  LedgerFilterButton(
                    buttonKey: ValueKey('ledger-category-$categoryFilterId'),
                    icon: AppIcon.category,
                    label: selectedCategoryLabel,
                    isActive: categoryFilterId.isNotEmpty,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        final value = await showLedgerCategorySelectionSheet(
                          context: context,
                          categories: activeCategories,
                          selectedCategoryId: categoryFilterId,
                        );
                        if (value != null && mounted) {
                          setState(() => categoryFilterId = value);
                        }
                      });
                    },
                  ),
                  LedgerFilterButton(
                    buttonKey: ValueKey('ledger-date-${dateFilter.name}'),
                    icon: AppIcon.calendar,
                    label: selectedDateLabel,
                    isActive: dateFilter != LedgerDateFilter.all,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        final value =
                            await showLedgerSelectionSheet<LedgerDateFilter>(
                              context: context,
                              title: 'Filter by Date',
                              selectedValue: dateFilter,
                              items: [
                                for (final filter in LedgerDateFilter.values)
                                  (
                                    value: filter,
                                    label: ledgerDateFilterLabel(filter),
                                    icon: AppIcon.calendar,
                                    detail: null,
                                  ),
                              ],
                            );
                        if (value == LedgerDateFilter.custom && mounted) {
                          final range = await showDateRangePicker(
                            context: this.context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(DateTime.now().year + 10),
                            initialDateRange: null,
                          );
                          if (range == null || !mounted) return;
                          setState(() {
                            dateFilter = LedgerDateFilter.custom;
                            customDateRange = range;
                          });
                        } else if (value != null && mounted) {
                          setState(() {
                            dateFilter = value;
                            customDateRange = null;
                          });
                        }
                      });
                    },
                  ),
                  if (visibleMonths.isNotEmpty)
                    LedgerFilterButton(
                      buttonKey: ValueKey('ledger-jump-month'),
                      icon: AppIcon.event,
                      label: 'Jump to month',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                          final value = await showLedgerSelectionSheet<String>(
                            context: context,
                            title: 'Jump to Month',
                            selectedValue: '',
                            items: [
                              for (final month in visibleMonths)
                                (
                                  value: ledgerMonthKey(month),
                                  label: monthLabel(month),
                                  icon: AppIcon.event,
                                  detail: null,
                                ),
                            ],
                          );
                          if (value == null || !mounted) return;
                          final anchor = _monthAnchors[value]?.currentContext;
                          if (anchor == null || !anchor.mounted) return;
                          Scrollable.ensureVisible(
                            anchor,
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            alignment: 0.08,
                          );
                        });
                      },
                    ),
                ],
              ),
              SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: () {
                  clearFilters();
                  Navigator.pop(sheetContext);
                },
                icon: Icon(AppIcon.clearFilter),
                label: const Text('Clear filters'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FilteredLedgerScreen extends StatelessWidget {
  const FilteredLedgerScreen({required this.filter, super.key});

  final ManagementLedgerFilter filter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ledger'), scrolledUnderElevation: 0),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          child: LedgerView(initialManagementFilter: filter),
        ),
      ),
    );
  }
}

String ledgerMonthKey(DateTime month) => '${month.year}-${month.month}';

int compareTransactionsNewestFirst(TransactionRecord a, TransactionRecord b) {
  final dateOrder = b.date.compareTo(a.date);
  if (dateOrder != 0) return dateOrder;
  final createdOrder = b.sync.createdAt.compareTo(a.sync.createdAt);
  if (createdOrder != 0) return createdOrder;
  return b.id.compareTo(a.id);
}

String ledgerDayContext(DateTime date) {
  return switch (date.weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => '',
  };
}

DateTime ledgerCalendarDay(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String ledgerFriendlyDayLabel(DateTime date, DateTime now) {
  final day = ledgerCalendarDay(date);
  final today = ledgerCalendarDay(now);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
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
  return '${weekdays[day.weekday - 1]}, ${months[day.month - 1]} ${day.day}';
}

String? ledgerTransactionTimeLabel(BuildContext context, DateTime date) {
  final local = date.toLocal();
  // Existing date-only records normalize to midnight. Do not invent a time
  // label for those transactions.
  if (local.hour == 0 &&
      local.minute == 0 &&
      local.second == 0 &&
      local.millisecond == 0 &&
      local.microsecond == 0) {
    return null;
  }
  return MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
}

class LedgerMonthSection extends StatelessWidget {
  const LedgerMonthSection({
    required this.month,
    required this.transactions,
    required this.goalFundingEvents,
    required this.store,
    required this.accountsById,
    required this.categoriesById,
    required this.isCollapsed,
    required this.onDismissFocus,
    required this.onToggle,
    super.key,
  });

  final DateTime month;
  final List<LedgerTransactionProjection> transactions;
  final List<GoalFundingEventRecord> goalFundingEvents;
  final FinanceDataStore store;
  final Map<String, v2_account.AccountRecord> accountsById;
  final Map<String, v2_category.CategoryRecord> categoriesById;
  final bool isCollapsed;
  final VoidCallback onDismissFocus;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final income = transactions
        .where((item) => item.transaction.type == TransactionType.income)
        .fold(0, (total, item) => total + item.displayedAmountMinor.abs());
    final expenses = transactions
        .where((item) => item.transaction.type == TransactionType.expense)
        .fold(0, (total, item) => total + item.displayedAmountMinor.abs());
    final adjustments = transactions
        .where((item) => item.transaction.type == TransactionType.adjustment)
        .fold(0, (total, item) => total + item.displayedAmountMinor);
    final net = income - expenses + adjustments;
    final activities =
        <
            ({
              DateTime date,
              LedgerTransactionProjection? projection,
              GoalFundingEventRecord? fundingEvent,
            })
          >[
            for (final projection in transactions)
              (
                date: projection.transaction.date,
                projection: projection,
                fundingEvent: null,
              ),
            for (final fundingEvent in goalFundingEvents)
              (
                date: fundingEvent.date,
                projection: null,
                fundingEvent: fundingEvent,
              ),
          ]
          ..sort((left, right) => right.date.compareTo(left.date));
    final activitiesByDay =
        <
          DateTime,
          List<
            ({
              DateTime date,
              LedgerTransactionProjection? projection,
              GoalFundingEventRecord? fundingEvent,
            })
          >
        >{};
    for (final activity in activities) {
      activitiesByDay
          .putIfAbsent(ledgerCalendarDay(activity.date), () => [])
          .add(activity);
    }
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              child: Column(
                children: [
                  Row(
                    children: [
                      AnimatedRotation(
                        turns: isCollapsed ? -0.25 : 0,
                        duration: reduceMotion
                            ? Duration.zero
                            : Duration(milliseconds: 170),
                        curve: Curves.easeOutCubic,
                        child: Icon(AppIcon.dropdown, size: AppIconSize.form),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          monthLabel(month),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '${activities.length} ${activities.length == 1 ? 'activity' : 'activities'}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.68),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  if (isCollapsed) ...[
                    const SizedBox(height: AppSpacing.xs),
                    LedgerMonthlyCompactSummary(
                      incomeMinor: income,
                      expensesMinor: expenses,
                      netMinor: net,
                      currency: store.preferences.currency,
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 190),
            reverseDuration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isCollapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
                        LedgerMonthlySummary(
                          incomeMinor: income,
                          expensesMinor: expenses,
                          netMinor: net,
                          currency: store.preferences.currency,
                        ),
                        const SizedBox(height: 14),
                        for (final entry in activitiesByDay.entries) ...[
                          _LedgerDayCard(
                            date: entry.key,
                            activities: entry.value,
                            store: store,
                            accountsById: accountsById,
                            categoriesById: categoriesById,
                            onDismissFocus: onDismissFocus,
                          ),
                          if (entry.key != activitiesByDay.entries.last.key)
                            const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LedgerDayCard extends StatelessWidget {
  const _LedgerDayCard({
    required this.date,
    required this.activities,
    required this.store,
    required this.accountsById,
    required this.categoriesById,
    required this.onDismissFocus,
  });

  final DateTime date;
  final List<
    ({
      DateTime date,
      LedgerTransactionProjection? projection,
      GoalFundingEventRecord? fundingEvent,
    })
  >
  activities;
  final FinanceDataStore store;
  final Map<String, v2_account.AccountRecord> accountsById;
  final Map<String, v2_category.CategoryRecord> categoriesById;
  final VoidCallback onDismissFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(19);
    final dayNet = activities.fold<int>(
      0,
      (total, activity) =>
          total +
          (activity.projection?.displayedAmountMinor ??
              -activity.fundingEvent!.totalAmountMinor.abs()),
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: borderRadius,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.38 : 0.46,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Column(
          children: [
            LedgerDaySectionHeader(
              date: date,
              netAmountMinor: dayNet,
              currency: store.preferences.currency,
            ),
            for (var index = 0; index < activities.length; index++) ...[
              if (activities[index].projection case final projection?)
                LedgerJournalRow(
                  projection: projection,
                  currency: store.preferences.currency,
                  showDateContext: false,
                  account: accountsById[projection.transaction.accountId],
                  category:
                      categoriesById[projection.categoryScope?.categoryId ??
                          projection.transaction.categoryId],
                  categoryName:
                      projection.categoryScope?.label ??
                      (projection.transaction.categoryId == null
                          ? null
                          : categoriesById[projection.transaction.categoryId]
                                ?.name),
                  onTap: () async {
                    onDismissFocus();
                    await showTransactionDetails(
                      context,
                      projection.transaction.id,
                      projection: projection.isCategoryProjected
                          ? projection
                          : null,
                    );
                    if (context.mounted) onDismissFocus();
                  },
                  onLongPress: () async {
                    onDismissFocus();
                    AppHaptics.longPressAction();
                    await showTransactionOptions(
                      context,
                      projection.transaction.id,
                    );
                    if (context.mounted) onDismissFocus();
                  },
                )
              else
                GoalFundingLedgerRow(
                  event: activities[index].fundingEvent!,
                  showDateContext: false,
                  account:
                      accountsById[activities[index]
                          .fundingEvent!
                          .sourceAccountId],
                  currency: store.preferences.currency,
                  onTap: () => showGoalFundingDetails(
                    context,
                    activities[index].fundingEvent!.id,
                  ),
                ),
              if (index != activities.length - 1)
                Divider(
                  height: 1,
                  indent: 58,
                  endIndent: 16,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.135,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class LedgerMonthlySummary extends StatelessWidget {
  const LedgerMonthlySummary({
    required this.incomeMinor,
    required this.expensesMinor,
    required this.netMinor,
    required this.currency,
    super.key,
  });

  final int incomeMinor;
  final int expensesMinor;
  final int netMinor;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.24,
        ),
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _LedgerMonthlySummaryMetric(
              label: 'Income',
              amountMinor: incomeMinor,
              currency: currency,
              color: AppTheme.accent,
            ),
          ),
          _LedgerMonthlySummaryDivider(color: theme.colorScheme.outlineVariant),
          Expanded(
            child: _LedgerMonthlySummaryMetric(
              label: 'Expenses',
              amountMinor: -expensesMinor,
              currency: currency,
              color: AppColors.danger,
            ),
          ),
          _LedgerMonthlySummaryDivider(color: theme.colorScheme.outlineVariant),
          Expanded(
            child: _LedgerMonthlySummaryMetric(
              label: 'Net',
              amountMinor: netMinor,
              currency: currency,
              showPositiveSign: netMinor > 0,
              color: netMinor < 0 ? AppColors.danger : AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class LedgerMonthlyCompactSummary extends StatelessWidget {
  const LedgerMonthlyCompactSummary({
    required this.incomeMinor,
    required this.expensesMinor,
    required this.netMinor,
    required this.currency,
    super.key,
  });

  final int incomeMinor;
  final int expensesMinor;
  final int netMinor;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _LedgerMonthlySummaryMetric(
              label: 'Income',
              amountMinor: incomeMinor,
              currency: currency,
              color: AppTheme.accent,
              compact: true,
            ),
          ),
          _LedgerMonthlySummaryDivider(
            color: theme.colorScheme.outlineVariant,
            compact: true,
          ),
          Expanded(
            child: _LedgerMonthlySummaryMetric(
              label: 'Expenses',
              amountMinor: -expensesMinor,
              currency: currency,
              color: AppColors.danger,
              compact: true,
            ),
          ),
          _LedgerMonthlySummaryDivider(
            color: theme.colorScheme.outlineVariant,
            compact: true,
          ),
          Expanded(
            child: _LedgerMonthlySummaryMetric(
              label: 'Net',
              amountMinor: netMinor,
              currency: currency,
              showPositiveSign: netMinor > 0,
              color: netMinor < 0 ? AppColors.danger : AppTheme.accent,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerMonthlySummaryDivider extends StatelessWidget {
  const _LedgerMonthlySummaryDivider({
    required this.color,
    this.compact = false,
  });

  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: compact ? 27 : 32,
      color: color.withValues(alpha: 0.38),
    );
  }
}

class _LedgerMonthlySummaryMetric extends StatelessWidget {
  const _LedgerMonthlySummaryMetric({
    required this.label,
    required this.amountMinor,
    required this.currency,
    required this.color,
    this.showPositiveSign = false,
    this.compact = false,
  });

  final String label;
  final int amountMinor;
  final CurrencyFormatSettings currency;
  final Color color;
  final bool showPositiveSign;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
          ),
        ),
        SizedBox(height: compact ? 1 : 2),
        MoneyText(
          amountMinor: amountMinor,
          currency: currency,
          fontSize: compact ? 13 : 15,
          fontWeight: FontWeight.w800,
          showPositiveSign: showPositiveSign,
          color: color,
        ),
      ],
    );
  }
}

class LedgerDaySectionHeader extends StatelessWidget {
  const LedgerDaySectionHeader({
    required this.date,
    required this.netAmountMinor,
    required this.currency,
    super.key,
  });

  final DateTime date;
  final int netAmountMinor;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              ledgerFriendlyDayLabel(date, DateTime.now()),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
          ),
          MoneyText(
            amountMinor: netAmountMinor,
            currency: currency,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            showPositiveSign: netAmountMinor > 0,
            color: netAmountMinor < 0 ? AppColors.danger : null,
          ),
        ],
      ),
    );
  }
}

class LedgerJournalRow extends StatelessWidget {
  const LedgerJournalRow({
    required this.projection,
    required this.currency,
    required this.onTap,
    required this.onLongPress,
    this.account,
    this.category,
    this.categoryName,
    this.showDateContext = true,
    super.key,
  });

  final LedgerTransactionProjection projection;
  TransactionRecord get transaction => projection.transaction;
  final CurrencyFormatSettings currency;
  final v2_account.AccountRecord? account;
  final v2_category.CategoryRecord? category;
  final String? categoryName;
  final bool showDateContext;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final signedAmount = projection.displayedAmountMinor;
    final timeLabel = ledgerTransactionTimeLabel(context, transaction.date);
    final metadataDetails = [
      if (account != null) account!.name,
      if (categoryName != null) categoryName,
      if (transaction.type == TransactionType.adjustment)
        'Manual balance adjustment',
      if (transaction.isTransfer) 'Transfer',
      ?timeLabel,
    ].join(' • ');
    final hasSplit = projection.isPartOfSplit || transaction.isSplit;
    final secondaryStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle(fontSize: 12);

    return Dismissible(
      key: ValueKey('ledger-swipe-${transaction.id}'),
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.28,
        DismissDirection.endToStart: 0.28,
      },
      confirmDismiss: (direction) async {
        HapticFeedback.selectionClick();
        await showTransactionOptions(
          context,
          transaction.id,
          allowedActions: direction == DismissDirection.endToStart
              ? const {'edit', 'delete'}
              : const {'duplicate', 'split', 'schedule'},
        );
        return false;
      },
      background: SwipeActionBackground(
        alignment: Alignment.centerLeft,
        icon: AppIcon.copy,
        label: 'More',
      ),
      secondaryBackground: SwipeActionBackground(
        alignment: Alignment.centerRight,
        icon: AppIcon.edit,
        label: 'Actions',
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showDateContext) ...[
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${transaction.date.day}\n${ledgerDayContext(transaction.date)}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (category != null)
                  CategoryIconBadge.category(
                    category!,
                    size: CategoryIconBadgeSize.row,
                  )
                else
                  _LedgerIconBadge(
                    icon: account == null
                        ? AppIcon.receipt
                        : v2AccountIcon(account!.type),
                    semanticLabel: account == null
                        ? 'Transaction'
                        : '${account!.name} account',
                  ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.payee,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.15,
                        ),
                      ),
                      if (metadataDetails.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          metadataDetails,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondaryStyle,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      amountMinor: signedAmount,
                      currency: currency,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      showPositiveSign:
                          transaction.type == TransactionType.income,
                      color: signedAmount < 0 ? AppColors.danger : null,
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 18,
                      child: hasSplit
                          ? const Align(
                              alignment: Alignment.centerRight,
                              child: _LedgerSplitCapsule(),
                            )
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerSplitCapsule extends StatelessWidget {
  const _LedgerSplitCapsule();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.16,
        ),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.44),
        ),
      ),
      child: Text(
        'split',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LedgerIconBadge extends StatelessWidget {
  const _LedgerIconBadge({
    required this.icon,
    required this.semanticLabel,
    this.color,
  });

  final IconData icon;
  final String semanticLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final identityColor = color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: identityColor.withValues(alpha: 0.10),
          shape: BoxShape.circle,
          border: Border.all(color: identityColor.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, size: 17, color: identityColor.withValues(alpha: .9)),
      ),
    );
  }
}

class GoalFundingLedgerRow extends StatelessWidget {
  const GoalFundingLedgerRow({
    required this.event,
    required this.currency,
    required this.onTap,
    this.account,
    this.showDateContext = true,
    super.key,
  });

  final GoalFundingEventRecord event;
  final CurrencyFormatSettings currency;
  final v2_account.AccountRecord? account;
  final bool showDateContext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeAllocations = event.allocations
        .where((allocation) => allocation.amountMinor > 0)
        .toList(growable: false);
    final allocationSummary = switch (activeAllocations.length) {
      0 => 'Goal funding',
      1 => '1 Goal',
      final count => '$count Goals',
    };
    final timeLabel = ledgerTransactionTimeLabel(context, event.date);
    final metadataDetails = [
      if (account != null) account!.name,
      allocationSummary,
      ?timeLabel,
    ].join(' • ');

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showDateContext) ...[
                SizedBox(
                  width: 38,
                  child: Text(
                    '${event.date.day}\n${ledgerDayContext(event.date)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              _LedgerIconBadge(
                icon: AppIcon.goal,
                semanticLabel: 'Goal funding',
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Funded Goals',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metadataDetails,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    amountMinor: -event.totalAmountMinor.abs(),
                    currency: currency,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(height: 3),
                  const SizedBox(height: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SwipeActionBackground extends StatelessWidget {
  const SwipeActionBackground({
    required this.alignment,
    required this.icon,
    required this.label,
    this.destructive = false,
    super.key,
  });

  final Alignment alignment;
  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppTheme.accent;
    return Container(
      color: color.withValues(alpha: 0.12),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

String monthAbbreviation(int month) => const [
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
][month - 1];

class LedgerFilterButton extends StatelessWidget {
  const LedgerFilterButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    super.key,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
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

    return InkWell(
      key: buttonKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
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
            Icon(icon, size: AppIconSize.inline, color: foreground),
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
            SizedBox(width: AppSpacing.xxs),
            Icon(
              AppIcon.chevronDown,
              size: AppIconSize.inline,
              color: foreground,
            ),
          ],
        ),
      ),
    );
  }
}

/// The common mobile selection surface used by every Ledger filter.  Unlike
/// PopupMenuButton it is scroll-safe, keyboard-safe, and does not create an
/// anchored strip that can overflow a compact screen.
Future<T?> showLedgerSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required T selectedValue,
  required List<({T value, String label, IconData? icon, String? detail})>
  items,
  bool searchable = false,
}) async {
  var query = '';
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final visible = items
            .where((item) {
              if (query.trim().isEmpty) return true;
              final needle = query.trim().toLowerCase();
              return '${item.label} ${item.detail ?? ''}'
                  .toLowerCase()
                  .contains(needle);
            })
            .toList(growable: false);
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.76,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (searchable)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search',
                          prefixIcon: Icon(AppIcon.search),
                        ),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        onChanged: (value) =>
                            setSheetState(() => query = value),
                      ),
                    ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 56,
                        color: Theme.of(
                          sheetContext,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.22),
                      ),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final selected = item.value == selectedValue;
                        return ListTile(
                          minTileHeight: 52,
                          leading: item.icon == null ? null : Icon(item.icon),
                          title: Text(item.label),
                          subtitle: item.detail == null
                              ? null
                              : Text(item.detail!),
                          trailing: selected
                              ? Icon(
                                  AppIcon.check,
                                  color: Theme.of(
                                    sheetContext,
                                  ).colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(sheetContext, item.value),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<String?> showLedgerCategorySelectionSheet({
  required BuildContext context,
  required List<v2_category.CategoryRecord> categories,
  required String selectedCategoryId,
}) async {
  final byParent = <String, List<v2_category.CategoryRecord>>{};
  final roots = <v2_category.CategoryRecord>[];
  for (final category in categories) {
    final parentId = category.parentCategoryId;
    if (parentId == null || parentId.isEmpty) {
      roots.add(category);
    } else {
      byParent.putIfAbsent(parentId, () => []).add(category);
    }
  }
  for (final group in byParent.values) {
    group.sort((a, b) => a.name.compareTo(b.name));
  }
  roots.sort((a, b) => a.name.compareTo(b.name));
  final selectedParent = categories
      .where((item) => item.id == selectedCategoryId)
      .firstOrNull
      ?.parentCategoryId;
  final expanded = <String>{
    if (selectedParent != null && selectedParent.isNotEmpty) selectedParent,
  };
  var query = '';
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final needle = query.trim().toLowerCase();
        final isSearching = needle.isNotEmpty;
        final rows =
            <({v2_category.CategoryRecord category, int depth})>[
                  for (final root in roots) ...[
                    (category: root, depth: 0),
                    if (isSearching || expanded.contains(root.id))
                      for (final child
                          in byParent[root.id] ??
                              const <v2_category.CategoryRecord>[])
                        if (!isSearching ||
                            child.name.toLowerCase().contains(needle) ||
                            root.name.toLowerCase().contains(needle))
                          (category: child, depth: 1),
                  ],
                ]
                .where((row) {
                  if (!isSearching) return true;
                  return row.category.name.toLowerCase().contains(needle) ||
                      (row.depth == 0 &&
                          (byParent[row.category.id] ?? const []).any(
                            (child) =>
                                child.name.toLowerCase().contains(needle),
                          ));
                })
                .toList(growable: false);
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * .78,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Filter by Category',
                        style: Theme.of(sheetContext).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search categories',
                        prefixIcon: Icon(AppIcon.search),
                      ),
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      children: [
                        ListTile(
                          leading: Icon(AppIcon.category),
                          title: const Text('All categories'),
                          trailing: selectedCategoryId.isEmpty
                              ? Icon(
                                  AppIcon.check,
                                  color: Theme.of(
                                    sheetContext,
                                  ).colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(sheetContext, ''),
                        ),
                        for (final row in rows)
                          _LedgerCategoryFilterRow(
                            category: row.category,
                            parentName: row.depth == 0
                                ? null
                                : categories
                                      .where(
                                        (item) =>
                                            item.id ==
                                            row.category.parentCategoryId,
                                      )
                                      .firstOrNull
                                      ?.name,
                            depth: row.depth,
                            hasChildren: (byParent[row.category.id] ?? const [])
                                .isNotEmpty,
                            expanded: expanded.contains(row.category.id),
                            selected: selectedCategoryId == row.category.id,
                            onToggle: () => setSheetState(() {
                              if (!expanded.add(row.category.id)) {
                                expanded.remove(row.category.id);
                              }
                            }),
                            onSelect: () =>
                                Navigator.pop(sheetContext, row.category.id),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _LedgerCategoryFilterRow extends StatelessWidget {
  const _LedgerCategoryFilterRow({
    required this.category,
    required this.parentName,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
    required this.selected,
    required this.onToggle,
    required this.onSelect,
  });
  final v2_category.CategoryRecord category;
  final String? parentName;
  final int depth;
  final bool hasChildren;
  final bool expanded;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.only(left: 16 + depth * 24.0, right: 8),
    leading: CategoryIconBadge.category(
      category,
      size: CategoryIconBadgeSize.compact,
    ),
    title: Text(category.name),
    subtitle: parentName == null ? null : Text(parentName!),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected)
          Icon(AppIcon.check, color: Theme.of(context).colorScheme.primary),
        if (hasChildren)
          IconButton(
            tooltip: expanded ? 'Collapse' : 'Expand',
            onPressed: onToggle,
            icon: AnimatedRotation(
              turns: expanded ? .25 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(AppIcon.chevronDown),
            ),
          ),
      ],
    ),
    onTap: onSelect,
  );
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

enum LedgerDateFilter { all, today, thisMonth, last30Days, custom }

bool transactionMatchesLedgerFilters(
  TransactionRecord transaction, {
  required String typeFilterName,
  required String accountFilterId,
  required String categoryFilterId,
  required LedgerDateFilter dateFilter,
  DateTimeRange? customDateRange,
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
      !transaction.effectiveCategoryAllocations.any(
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
    LedgerDateFilter.custom =>
      customDateRange != null &&
          !transactionDay.isBefore(
            DateTime(
              customDateRange.start.year,
              customDateRange.start.month,
              customDateRange.start.day,
            ),
          ) &&
          !transactionDay.isAfter(
            DateTime(
              customDateRange.end.year,
              customDateRange.end.month,
              customDateRange.end.day,
            ),
          ),
  };
}

bool dateMatchesLedgerFilter(
  DateTime date, {
  required LedgerDateFilter dateFilter,
  DateTimeRange? customDateRange,
  required DateTime now,
}) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  return switch (dateFilter) {
    LedgerDateFilter.all => true,
    LedgerDateFilter.today => day == today,
    LedgerDateFilter.thisMonth =>
      date.year == now.year && date.month == now.month,
    LedgerDateFilter.last30Days =>
      !day.isBefore(today.subtract(const Duration(days: 30))) &&
          !day.isAfter(today),
    LedgerDateFilter.custom =>
      customDateRange != null &&
          !day.isBefore(
            DateTime(
              customDateRange.start.year,
              customDateRange.start.month,
              customDateRange.start.day,
            ),
          ) &&
          !day.isAfter(
            DateTime(
              customDateRange.end.year,
              customDateRange.end.month,
              customDateRange.end.day,
            ),
          ),
  };
}

String transactionTypeLabel(TransactionType type) {
  return switch (type) {
    TransactionType.expense => 'Expense',
    TransactionType.income => 'Income',
    TransactionType.transfer => 'Transfer',
    TransactionType.goalFunding => 'Goal Funding',
    TransactionType.adjustment => 'Adjustment',
  };
}

IconData transactionTypeIcon(TransactionType type) {
  return switch (type) {
    TransactionType.expense => AppIcon.trendDown,
    TransactionType.income => AppIcon.trendUp,
    TransactionType.transfer => AppIcon.transfer,
    TransactionType.goalFunding => AppIcon.goal,
    TransactionType.adjustment => AppIcon.tune,
  };
}

Future<void> showDefaultTransactionDialog(
  BuildContext context, {
  String? initialAccountId,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final preferences = store.preferences;
  final shouldOpenTransfer = switch (preferences.defaultTransactionType) {
    DefaultTransactionType.transfer => true,
    DefaultTransactionType.lastUsed =>
      preferences.lastUsedTransactionType == TransactionType.transfer,
    DefaultTransactionType.expense || DefaultTransactionType.income => false,
  };

  if (shouldOpenTransfer) {
    await showTransferDialog(
      context,
      initialFromAccountId:
          initialAccountId ?? resolvedDefaultTransferSourceAccountId(store),
    );
    return;
  }

  await showTransactionDialog(
    context,
    initialIsExpense: isExpenseDefault(preferences),
    initialAccountId:
        initialAccountId ?? resolvedDefaultTransactionAccountId(store),
  );
}

String ledgerDateFilterLabel(LedgerDateFilter filter) {
  return switch (filter) {
    LedgerDateFilter.all => 'All dates',
    LedgerDateFilter.today => 'Today',
    LedgerDateFilter.thisMonth => 'This month',
    LedgerDateFilter.last30Days => 'Last 30 days',
    LedgerDateFilter.custom => 'Custom range',
  };
}

String shortMonthDay(DateTime date) =>
    '${monthAbbreviation(date.month)} ${date.day}';

Future<void> showTransactionOptions(
  BuildContext context,
  String transactionId, {
  Set<String>? allowedActions,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final transaction = dataStore.transactions.firstWhere(
    (item) => item.id == transactionId,
  );
  final scheduledUndoTarget = dataStore.scheduledPaymentUndoTarget(
    transaction.id,
  );
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (allowedActions == null || allowedActions.contains('edit'))
              ListTile(
                enabled:
                    transaction.type == TransactionType.expense ||
                    transaction.type == TransactionType.income ||
                    transaction.type == TransactionType.transfer,
                leading: Icon(AppIcon.edit),
                title: const Text('Edit'),
                onTap:
                    transaction.type == TransactionType.expense ||
                        transaction.type == TransactionType.income ||
                        transaction.type == TransactionType.transfer
                    ? () => Navigator.pop(sheetContext, 'edit')
                    : null,
              ),
            if (allowedActions == null || allowedActions.contains('duplicate'))
              ListTile(
                leading: Icon(AppIcon.copy),
                title: const Text('Duplicate'),
                onTap: () => Navigator.pop(sheetContext, 'duplicate'),
              ),
            if (allowedActions == null || allowedActions.contains('split'))
              ListTile(
                enabled:
                    transaction.type == TransactionType.expense ||
                    transaction.type == TransactionType.income,
                leading: Icon(AppIcon.split),
                title: const Text('Split'),
                onTap:
                    transaction.type == TransactionType.expense ||
                        transaction.type == TransactionType.income
                    ? () => Navigator.pop(sheetContext, 'split')
                    : null,
              ),
            if (allowedActions == null || allowedActions.contains('schedule'))
              ListTile(
                enabled: transaction.type != TransactionType.adjustment,
                leading: Icon(AppIcon.recurrence),
                title: const Text('Make Scheduled'),
                onTap: transaction.type != TransactionType.adjustment
                    ? () => Navigator.pop(sheetContext, 'schedule')
                    : null,
              ),
            if (scheduledUndoTarget != null)
              ListTile(
                key: const ValueKey('undo-scheduled-transaction-option'),
                leading: Icon(AppIcon.undo),
                title: Text(
                  undoScheduledTransactionLabel(
                    scheduledUndoTarget.scheduledTransaction.type,
                  ),
                ),
                subtitle: const Text(
                  'Restore the original scheduled occurrence',
                ),
                textColor: AppTheme.rose,
                iconColor: AppTheme.rose,
                onTap: () => Navigator.pop(sheetContext, 'undoScheduled'),
              ),
            if (allowedActions == null || allowedActions.contains('delete'))
              ListTile(
                leading: Icon(AppIcon.delete),
                title: const Text('Delete'),
                textColor: AppTheme.rose,
                iconColor: AppTheme.rose,
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
          ],
        ),
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
      await showTransactionDialog(
        context,
        transaction: transaction,
        initialSplitMode: true,
      );
    case 'schedule':
      await makeTransactionScheduled(context, transaction);
    case 'delete':
      await deleteTransaction(context, transaction);
    case 'undoScheduled':
      if (scheduledUndoTarget != null) {
        await showUndoScheduledPaymentConfirmation(
          context,
          transactionId: transaction.id,
          target: scheduledUndoTarget,
        );
      }
  }
}

Future<void> showTransactionDetails(
  BuildContext context,
  String transactionId, {
  LedgerTransactionProjection? projection,
}) async {
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
  final undoTarget = dataStore.scheduledPaymentUndoTarget(transaction.id);
  final signedAmount = switch (transaction.type) {
    TransactionType.expense => -transaction.amountMinor.abs(),
    TransactionType.income => transaction.amountMinor.abs(),
    TransactionType.transfer => transaction.amountMinor.abs(),
    TransactionType.goalFunding => transaction.amountMinor.abs(),
    TransactionType.adjustment => transaction.amountMinor,
  };
  final amountColor = signedAmount < 0
      ? AppColors.danger
      : transaction.type == TransactionType.income
      ? AppTheme.accent
      : null;

  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) => TransactionSheetFrame(
      title: 'Transaction Details',
      actions: ScheduledTransactionDetailActions(
        onClose: () => Navigator.pop(dialogContext),
        onEdit: canEdit ? () => Navigator.pop(dialogContext, 'edit') : null,
        onMarkPaid: null,
        onUndoScheduledPayment: undoTarget == null
            ? null
            : () => Navigator.pop(dialogContext, 'undoScheduledPayment'),
        undoScheduledLabel: undoTarget == null
            ? 'Undo Scheduled Transaction'
            : undoScheduledTransactionLabel(
                undoTarget.scheduledTransaction.type,
              ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (projection?.isCategoryProjected ?? false) ...[
            Container(
              key: const ValueKey('transaction-projection-context'),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(
                  dialogContext,
                ).colorScheme.primaryContainer.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Viewing ${projection!.categoryScope!.label} allocation',
                    style: Theme.of(dialogContext).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${money(projection.displayedAmountMinor, dataStore.preferences.currency)} · '
                    'Full transaction ${money(projection.originalDisplayedAmountMinor, dataStore.preferences.currency)}',
                    style: Theme.of(dialogContext).textTheme.bodySmall
                        ?.copyWith(
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const TransactionFormDivider(),
          ],
          ScheduledTransactionDetailRow(
            rowKey: ValueKey('transaction-detail-payee'),
            icon: transaction.type == TransactionType.transfer
                ? AppIcon.description
                : AppIcon.payee,
            label: transaction.type == TransactionType.transfer
                ? 'Description'
                : 'Payee',
            value: transaction.payee.trim().isEmpty
                ? 'Not provided'
                : transaction.payee,
          ),
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: transactionDetailIcon(transaction.type),
            label: 'Type',
            value: transactionTypeLabel(transaction.type),
          ),
          TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: AppIcon.money,
            label: 'Amount',
            value: money(signedAmount, dataStore.preferences.currency),
            valueColor: amountColor,
            tabularFigures: true,
          ),
          TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: AppIcon.calendar,
            label: 'Date',
            value: fullMonthDateLabel(transaction.date),
          ),
          if (undoTarget != null) ...[
            const TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.recurrence,
              label: 'Origin',
              value: 'Scheduled Transaction',
            ),
            const TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.eventNote,
              label: 'Scheduled date',
              value: fullMonthDateLabel(undoTarget.occurrence.scheduledDate),
            ),
          ],
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: v2AccountIcon(
              accountsById[transaction.accountId]?.type ??
                  v2_account.AccountType.otherBanking,
            ),
            label: transaction.type == TransactionType.transfer
                ? 'From Account'
                : 'Account',
            value: accountsById[transaction.accountId]?.name ?? 'Unavailable',
          ),
          if (transaction.transferAccountId != null) ...[
            TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.wallet,
              label: 'To Account',
              value:
                  accountsById[transaction.transferAccountId]?.name ??
                  'Unavailable',
            ),
          ],
          if (transaction.categoryId != null) ...[
            TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.category,
              leading: categoriesById[transaction.categoryId] == null
                  ? null
                  : CategoryIconBadge.category(
                      categoriesById[transaction.categoryId]!,
                      size: CategoryIconBadgeSize.form,
                    ),
              label: 'Category',
              value: categoriesById[transaction.categoryId]?.name ?? 'Unknown',
            ),
          ],
          if (transaction.note.trim().isNotEmpty) ...[
            TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.notes,
              label: 'Notes',
              value: transaction.note,
            ),
          ],
          if (transaction.isCategorySplit)
            for (final split in transaction.effectiveCategoryAllocations) ...[
              TransactionFormDivider(),
              ScheduledTransactionDetailRow(
                icon: AppIcon.split,
                leading: categoriesById[split.categoryId] == null
                    ? null
                    : CategoryIconBadge.category(
                        categoriesById[split.categoryId]!,
                        size: CategoryIconBadgeSize.form,
                      ),
                label:
                    categoriesById[split.categoryId]?.name ?? 'Split category',
                value: money(split.amountMinor, dataStore.preferences.currency),
                tabularFigures: true,
              ),
            ],
        ],
      ),
    ),
  );

  if (!context.mounted) return;
  if (action == 'edit') {
    if (transaction.type == TransactionType.transfer) {
      await showTransferDialog(context, transfer: transaction);
    } else {
      await showTransactionDialog(context, transaction: transaction);
    }
  } else if (action == 'undoScheduledPayment' && undoTarget != null) {
    await showUndoScheduledPaymentConfirmation(
      context,
      transactionId: transaction.id,
      target: undoTarget,
    );
  }
}

Future<void> showUndoScheduledPaymentConfirmation(
  BuildContext context, {
  required String transactionId,
  required ScheduledPaymentUndoTarget target,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  var isProcessing = false;
  String? errorMessage;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        Future<void> undoPayment() async {
          if (isProcessing) return;
          setDialogState(() {
            isProcessing = true;
            errorMessage = null;
          });
          try {
            await dataStore.undoScheduledPayment(transactionId);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } on FinanceDataValidationException catch (error) {
            if (!dialogContext.mounted) return;
            setDialogState(() {
              isProcessing = false;
              errorMessage = error.message;
            });
          } catch (error, stackTrace) {
            debugPrint(
              'Undo scheduled payment failed for transaction $transactionId: '
              '$error\n$stackTrace',
            );
            if (!dialogContext.mounted) return;
            setDialogState(() {
              isProcessing = false;
              errorMessage =
                  'The scheduled payment could not be undone. Please try again.';
            });
          }
        }

        final plannedAmount = target.occurrence.plannedAmountMinor.abs();
        final actualAmount = target.transaction.amountMinor.abs();
        final type = target.scheduledTransaction.type;
        return TransactionSheetFrame(
          title: undoScheduledTransactionConfirmationTitle(type),
          actions: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: isProcessing
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: const ValueKey('confirm-undo-scheduled-payment'),
                    onPressed: isProcessing ? null : undoPayment,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.rose,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      isProcessing
                          ? 'Undoing…'
                          : undoScheduledTransactionLabel(type),
                    ),
                  ),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                undoScheduledTransactionConfirmationMessage(type),
                style: Theme.of(dialogContext).textTheme.bodyLarge,
              ),
              if (plannedAmount != actualAmount) ...[
                SizedBox(height: AppSpacing.lg),
                ScheduledTransactionDetailRow(
                  icon: AppIcon.eventNote,
                  label: 'Planned amount',
                  value: money(plannedAmount, dataStore.preferences.currency),
                  tabularFigures: true,
                ),
                TransactionFormDivider(),
                ScheduledTransactionDetailRow(
                  icon: AppIcon.receipt,
                  label: 'Actual payment',
                  value: money(actualAmount, dataStore.preferences.currency),
                  tabularFigures: true,
                ),
              ],
              if (errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  errorMessage!,
                  key: const ValueKey('undo-scheduled-payment-error'),
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

String undoScheduledTransactionLabel(TransactionType type) {
  return switch (type) {
    TransactionType.expense => 'Undo Payment',
    TransactionType.income => 'Undo Income',
    TransactionType.transfer => 'Undo Transfer',
    TransactionType.goalFunding => 'Undo Goal Funding',
    TransactionType.adjustment => 'Undo Scheduled Transaction',
  };
}

String undoScheduledTransactionConfirmationTitle(TransactionType type) {
  return switch (type) {
    TransactionType.expense => 'Undo this scheduled payment?',
    TransactionType.income => 'Undo this scheduled income?',
    TransactionType.transfer => 'Undo this scheduled transfer?',
    TransactionType.goalFunding => 'Undo this scheduled Goal funding?',
    TransactionType.adjustment => 'Undo scheduled transaction?',
  };
}

String undoScheduledTransactionConfirmationMessage(TransactionType type) {
  return switch (type) {
    TransactionType.expense =>
      'This removes the generated ledger transaction, restores its effect on the related account, and returns the scheduled occurrence to unpaid status.',
    TransactionType.income =>
      'This removes the posted income from its account and returns the scheduled occurrence to unpaid status.',
    TransactionType.transfer =>
      'This returns the money to the source account, removes it from the destination account, and restores the scheduled occurrence for its original date.',
    TransactionType.goalFunding =>
      'This restores the source account, reverses the Goal allocations, and restores the scheduled occurrence for its original date.',
    TransactionType.adjustment =>
      'This reverses the generated ledger transaction and restores the scheduled occurrence.',
  };
}

IconData transactionDetailIcon(TransactionType type) {
  return switch (type) {
    TransactionType.expense => AppIcon.expense,
    TransactionType.income => AppIcon.income,
    TransactionType.transfer => AppIcon.transfer,
    TransactionType.goalFunding => AppIcon.goal,
    TransactionType.adjustment => AppIcon.filter,
  };
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
  final undoTarget = dataStore.scheduledPaymentUndoTarget(transaction.id);
  if (undoTarget != null) {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'This transaction came from a scheduled occurrence.',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Undoing it restores the occurrence for its original scheduled date.',
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  key: const ValueKey('delete-scheduled-undo-action'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.rose,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(sheetContext, 'undo'),
                  icon: Icon(AppIcon.undo),
                  label: Text(
                    undoScheduledTransactionLabel(
                      undoTarget.scheduledTransaction.type,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  key: const ValueKey('delete-ledger-record-only-action'),
                  onPressed: () => Navigator.pop(sheetContext, 'deleteOnly'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.rose,
                    side: BorderSide(
                      color: AppTheme.rose.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text('Delete Ledger Record Only'),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'This reverses the account effects but does not restore the scheduled occurrence.',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'undo') {
      await showUndoScheduledPaymentConfirmation(
        context,
        transactionId: transaction.id,
        target: undoTarget,
      );
      return;
    }
    if (action != 'deleteOnly') return;
  }
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
  final effectiveAllocations = transaction.effectiveCategoryAllocations;
  final drafts = effectiveAllocations.isEmpty
      ? [
          SplitLineDraft(
            categoryId: defaultCategoryId,
            amountMinor: transaction.amountMinor.abs(),
          ),
          SplitLineDraft(categoryId: categories.first.id, amountMinor: 0),
        ]
      : [
          for (final line in effectiveAllocations)
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
                          icon: Icon(AppIcon.expense),
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
                    icon: Icon(AppIcon.add),
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
    this.id,
    required this.categoryId,
    required this.amountMinor,
    String noteText = '',
  }) : note = TextEditingController(text: noteText);

  String? id;
  String categoryId;
  int amountMinor;
  final TextEditingController note;
}

class SingleCategoryAllocationSection extends StatelessWidget {
  const SingleCategoryAllocationSection({
    required this.keyPrefix,
    required this.categoryName,
    this.category,
    required this.onChooseCategory,
    required this.onSplit,
    super.key,
  });

  final String keyPrefix;
  final String? categoryName;
  final v2_category.CategoryRecord? category;
  final VoidCallback onChooseCategory;
  final VoidCallback? onSplit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCategory = categoryName != null;
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.15,
      color: hasCategory
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      key: ValueKey('$keyPrefix-single-category-field'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TransactionFormLabel('Category'),
        InkWell(
          key: ValueKey('$keyPrefix-category'),
          borderRadius: BorderRadius.circular(AppRadii.control),
          onTap: onChooseCategory,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                if (category case final selectedCategory?)
                  CategoryIconBadge.category(
                    selectedCategory,
                    size: CategoryIconBadgeSize.form,
                  )
                else
                  TransactionFormIcon(AppIcon.category),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    categoryName ?? 'Choose category',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Icon(AppIcon.chevronDown, size: AppIconSize.hero),
              ],
            ),
          ),
        ),
        if (hasCategory && onSplit != null)
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 1),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('$keyPrefix-enable-split'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                onPressed: onSplit,
                icon: Icon(AppIcon.split, size: AppIconSize.inline),
                label: const Text('Split transaction'),
              ),
            ),
          ),
      ],
    );
  }
}

class InlineSplitAllocationSection extends StatelessWidget {
  const InlineSplitAllocationSection({
    required this.keyPrefix,
    required this.drafts,
    required this.categories,
    required this.currency,
    required this.totalMinor,
    required this.firstAutoRemainder,
    required this.onChooseCategory,
    required this.onAmountChanged,
    required this.onAdd,
    required this.onRemove,
    this.onUseSingleCategory,
    this.autofocusAmountIndex,
    this.quietWhenZero = false,
    super.key,
  });

  final String keyPrefix;
  final List<SplitLineDraft> drafts;
  final List<v2_category.CategoryRecord> categories;
  final CurrencyFormatSettings currency;
  final int totalMinor;
  final bool firstAutoRemainder;
  final ValueChanged<int> onChooseCategory;
  final void Function(int index, int amountMinor) onAmountChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback? onUseSingleCategory;
  final int? autofocusAmountIndex;
  final bool quietWhenZero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.15,
    );
    final hintStyle = valueStyle?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final splitTotalMinor = drafts.fold<int>(
      0,
      (total, line) => total + line.amountMinor.abs(),
    );
    final remainingMinor = totalMinor.abs() - splitTotalMinor;
    final isQuietZeroState = quietWhenZero && totalMinor == 0;
    final footerLabelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    TextStyle? splitValueStyle({bool danger = false}) =>
        theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: danger ? AppColors.danger : theme.colorScheme.onSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return Column(
      key: ValueKey('$keyPrefix-split-category-field'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: TransactionFormLabel('Split Categories')),
          ],
        ),
        for (var index = 0; index < drafts.length; index++) ...[
          if (index > 0)
            Divider(
              height: AppSpacing.md,
              thickness: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.42),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                AppIcon.drag,
                size: AppIconSize.inline,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.62,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (categories
                      .where(
                        (category) => category.id == drafts[index].categoryId,
                      )
                      .firstOrNull
                  case final selectedCategory?) ...[
                CategoryIconBadge.category(
                  selectedCategory,
                  size: CategoryIconBadgeSize.compact,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: InkWell(
                  key: ValueKey('$keyPrefix-split-category-$index'),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  onTap: () => onChooseCategory(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Text(
                      categories
                              .where(
                                (category) =>
                                    category.id == drafts[index].categoryId,
                              )
                              .firstOrNull
                              ?.name ??
                          'Choose category',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (categories.any(
                            (category) =>
                                category.id == drafts[index].categoryId,
                          )
                          ? valueStyle
                          : hintStyle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 118,
                child: AmountEntryField(
                  fieldKey: ValueKey(
                    '$keyPrefix-split-amount-${drafts[index].id ?? index}-${index == 0 && firstAutoRemainder ? drafts[index].amountMinor : ''}',
                  ),
                  initialMinor: drafts[index].amountMinor.abs(),
                  currency: currency,
                  labelText: null,
                  autofocus: autofocusAmountIndex == index,
                  selectAllOnFocus:
                      autofocusAmountIndex == index &&
                      drafts[index].amountMinor != 0,
                  replaceZeroOnFirstInput:
                      autofocusAmountIndex == index &&
                      drafts[index].amountMinor == 0,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  textStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  onChanged: (value) => onAmountChanged(index, value.abs()),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                key: ValueKey('$keyPrefix-remove-split-$index'),
                visualDensity: VisualDensity.compact,
                tooltip: index == 0
                    ? 'First split keeps the remainder'
                    : 'Remove split',
                onPressed: index == 0 ? null : () => onRemove(index),
                icon: Icon(
                  AppIcon.expense,
                  size: AppIconSize.row,
                  color: index == 0
                      ? theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.32,
                        )
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          children: [
            TextButton.icon(
              key: ValueKey('$keyPrefix-add-split'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
              onPressed: onAdd,
              icon: Icon(AppIcon.add, size: AppIconSize.inline),
              label: const Text('Add split'),
            ),
            if (onUseSingleCategory != null)
              TextButton(
                key: ValueKey('$keyPrefix-use-single-category'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                onPressed: onUseSingleCategory,
                child: const Text('Use single category'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            const Spacer(),
            Text('Total', style: footerLabelStyle),
            const SizedBox(width: AppSpacing.lg),
            Text(
              money(splitTotalMinor, currency),
              style: isQuietZeroState ? footerLabelStyle : splitValueStyle(),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const Spacer(),
            Text('Remaining', style: footerLabelStyle),
            const SizedBox(width: AppSpacing.lg),
            Text(
              isQuietZeroState
                  ? money(0, currency)
                  : remainingMinor == 0
                  ? 'Balanced'
                  : money(remainingMinor, currency),
              key: ValueKey('$keyPrefix-split-remaining'),
              style: isQuietZeroState
                  ? footerLabelStyle
                  : splitValueStyle(danger: remainingMinor != 0)?.copyWith(
                      color: remainingMinor == 0
                          ? AppTheme.accent
                          : AppColors.danger,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<bool> confirmDiscardAdditionalSplits(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Use single category?'),
          content: const Text(
            'The additional split allocations will be removed. '
            'The first category will remain selected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Use Single Category'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> makeTransactionScheduled(
  BuildContext context,
  TransactionRecord transaction,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final linkedSchedule = transaction.scheduledTransactionId == null
      ? null
      : dataStore.scheduledTransactions
            .where(
              (item) =>
                  item.id == transaction.scheduledTransactionId &&
                  !item.isDeleted,
            )
            .firstOrNull;
  await showScheduledTransactionDialog(
    context,
    existing: linkedSchedule,
    sourceTransaction: linkedSchedule == null ? transaction : null,
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

class PlanView extends StatefulWidget {
  const PlanView({
    required this.selectedSegment,
    required this.onSegmentChanged,
    required this.onOpenSettings,
    super.key,
  });

  final PlanSegment selectedSegment;
  final ValueChanged<PlanSegment> onSegmentChanged;
  final VoidCallback onOpenSettings;

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  final _budgetScrollController = ScrollController();
  final _goalScrollController = ScrollController();

  @override
  void dispose() {
    _budgetScrollController.dispose();
    _goalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGoals = widget.selectedSegment == PlanSegment.goals;
    return CustomScrollView(
      key: PageStorageKey('plan-${widget.selectedSegment.name}'),
      controller: isGoals ? _goalScrollController : _budgetScrollController,
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            section: FinanceSection.plan,
            onOpenSettings: widget.onOpenSettings,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: SegmentedButton<PlanSegment>(
                key: const ValueKey('plan-segmented-control'),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppTheme.accent,
                  selectedForegroundColor: Colors.white,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.55),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: PlanSegment.budgets,
                    label: Text('Budgets'),
                  ),
                  ButtonSegment(value: PlanSegment.goals, label: Text('Goals')),
                ],
                selected: {widget.selectedSegment},
                onSelectionChanged: (selection) {
                  HapticFeedback.selectionClick();
                  widget.onSegmentChanged(selection.single);
                },
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
          sliver: SliverToBoxAdapter(
            child: isGoals ? const GoalsPlanContent() : const BudgetsView(),
          ),
        ),
      ],
    );
  }
}

class ScheduledView extends StatefulWidget {
  const ScheduledView({this.onSelectedDateChanged, super.key});

  final ValueChanged<DateTime>? onSelectedDateChanged;

  @override
  State<ScheduledView> createState() => _ScheduledViewState();
}

enum CalendarActivityFilter { all, income, expenses, transfers, goals }

extension CalendarActivityFilterPresentation on CalendarActivityFilter {
  String get label => switch (this) {
    CalendarActivityFilter.all => 'All',
    CalendarActivityFilter.income => 'Income',
    CalendarActivityFilter.expenses => 'Expenses',
    CalendarActivityFilter.transfers => 'Transfers',
    CalendarActivityFilter.goals => 'Goals',
  };

  String get emptyStateLabel => this == CalendarActivityFilter.all
      ? 'recorded'
      : label.substring(0, label.length - (label.endsWith('s') ? 1 : 0));

  IconData get icon => switch (this) {
    CalendarActivityFilter.all => AppIcon.calendarGrid,
    CalendarActivityFilter.income => AppIcon.income,
    CalendarActivityFilter.expenses => AppIcon.expense,
    CalendarActivityFilter.transfers => AppIcon.transfer,
    CalendarActivityFilter.goals => AppIcon.goal,
  };

  bool matches(CalendarActivityType type) => switch (this) {
    CalendarActivityFilter.all => true,
    CalendarActivityFilter.income => type == CalendarActivityType.income,
    CalendarActivityFilter.expenses => type == CalendarActivityType.expense,
    CalendarActivityFilter.transfers => type == CalendarActivityType.transfer,
    CalendarActivityFilter.goals => type == CalendarActivityType.goal,
  };

  bool matchesScheduled(TransactionType type) => switch (this) {
    CalendarActivityFilter.all => type != TransactionType.adjustment,
    CalendarActivityFilter.income => type == TransactionType.income,
    CalendarActivityFilter.expenses => type == TransactionType.expense,
    CalendarActivityFilter.transfers => type == TransactionType.transfer,
    CalendarActivityFilter.goals => type == TransactionType.goalFunding,
  };

  String get scheduledCompletedLabel => switch (this) {
    CalendarActivityFilter.all => 'Completed',
    CalendarActivityFilter.income => 'Received',
    CalendarActivityFilter.expenses => 'Paid',
    CalendarActivityFilter.transfers => 'Completed',
    CalendarActivityFilter.goals => 'Funded',
  };

  Color color(BuildContext context) => switch (this) {
    CalendarActivityFilter.all => AppTheme.accent,
    CalendarActivityFilter.income => AppTheme.accent,
    CalendarActivityFilter.expenses => AppColors.danger,
    CalendarActivityFilter.transfers => Theme.of(
      context,
    ).colorScheme.onSurfaceVariant,
    CalendarActivityFilter.goals => _goalBlue,
  };
}

String calendarActivityTypeLabel(CalendarActivityType type) => switch (type) {
  CalendarActivityType.income => 'Income',
  CalendarActivityType.expense => 'Expense',
  CalendarActivityType.transfer => 'Transfer',
  CalendarActivityType.goal => 'Goal',
};

class CalendarDayActivity {
  const CalendarDayActivity.transaction(this.transaction)
    : goalActivity = null,
      scheduledOccurrence = null;

  const CalendarDayActivity.goal(this.goalActivity)
    : transaction = null,
      scheduledOccurrence = null;

  const CalendarDayActivity.scheduled(this.scheduledOccurrence)
    : transaction = null,
      goalActivity = null;

  final TransactionRecord? transaction;
  final GoalCalendarActivity? goalActivity;
  final ScheduledCalendarOccurrence? scheduledOccurrence;

  DateTime get date =>
      transaction?.date ??
      goalActivity?.date ??
      scheduledOccurrence!.scheduledDate;

  CalendarActivityType get type {
    final item = transaction;
    if (item == null) {
      final scheduled = scheduledOccurrence;
      if (scheduled == null) return CalendarActivityType.goal;
      return switch (scheduled.transaction.type) {
        TransactionType.income => CalendarActivityType.income,
        TransactionType.expense => CalendarActivityType.expense,
        TransactionType.transfer => CalendarActivityType.transfer,
        TransactionType.goalFunding => CalendarActivityType.goal,
        TransactionType.adjustment => throw StateError(
          'Adjustments are not supported scheduled calendar activities.',
        ),
      };
    }
    return switch (item.type) {
      TransactionType.income => CalendarActivityType.income,
      TransactionType.expense => CalendarActivityType.expense,
      TransactionType.transfer => CalendarActivityType.transfer,
      TransactionType.goalFunding => CalendarActivityType.goal,
      TransactionType.adjustment => throw StateError(
        'Adjustments are not supported calendar activities.',
      ),
    };
  }

  int get displayAmountMinor {
    final item = transaction;
    if (item != null) {
      return switch (item.type) {
        TransactionType.income => item.amountMinor.abs(),
        TransactionType.expense => -item.amountMinor.abs(),
        TransactionType.transfer => item.amountMinor.abs(),
        TransactionType.goalFunding => item.amountMinor.abs(),
        TransactionType.adjustment => item.amountMinor,
      };
    }
    final scheduled = scheduledOccurrence;
    if (scheduled != null) {
      return switch (scheduled.transaction.type) {
        TransactionType.income => scheduled.plannedAmountMinor.abs(),
        TransactionType.expense => -scheduled.plannedAmountMinor.abs(),
        TransactionType.transfer => scheduled.plannedAmountMinor.abs(),
        TransactionType.goalFunding => scheduled.plannedAmountMinor.abs(),
        TransactionType.adjustment => scheduled.plannedAmountMinor,
      };
    }
    return (goalActivity!.fundingEvent?.totalAmountMinor ??
            goalActivity!.contribution!.amountMinor)
        .abs();
  }

  String get typeLabel => calendarActivityTypeLabel(type);

  IconData get icon => switch (type) {
    CalendarActivityType.income => AppIcon.income,
    CalendarActivityType.expense => AppIcon.expense,
    CalendarActivityType.transfer => AppIcon.transfer,
    CalendarActivityType.goal => AppIcon.goal,
  };

  Color color(BuildContext context) => switch (type) {
    CalendarActivityType.income => AppTheme.accent,
    CalendarActivityType.expense => AppColors.danger,
    CalendarActivityType.transfer => Theme.of(
      context,
    ).colorScheme.onSurfaceVariant,
    CalendarActivityType.goal => _goalBlue,
  };
}

class CalendarDayActivitySummary {
  CalendarDayActivitySummary(this.activities);

  final List<CalendarDayActivity> activities;

  Set<CalendarActivityType> get types =>
      activities.map((activity) => activity.type).toSet();

  int countFor(CalendarActivityFilter filter) =>
      activities.where((activity) => filter.matches(activity.type)).length;

  int? amountFor(CalendarActivityFilter filter) {
    if (filter == CalendarActivityFilter.all) return null;
    final matching = activities.where(
      (activity) => filter.matches(activity.type),
    );
    if (matching.isEmpty) return null;
    return matching.fold<int>(
      0,
      (total, activity) => total + activity.displayAmountMinor,
    );
  }
}

List<CalendarDayActivity> calendarActualActivitiesForMonth(
  Iterable<TransactionRecord> transactions,
  Iterable<GoalCalendarActivity> goalActivities,
  DateTime month,
) {
  final start = calendarDateKey(DateTime(month.year, month.month));
  final end = calendarDateKey(DateTime(month.year, month.month + 1));
  final result = <CalendarDayActivity>[
    for (final transaction in transactions)
      if (!transaction.isDeleted &&
          transaction.type != TransactionType.adjustment &&
          !calendarDateKey(transaction.date).isBefore(start) &&
          calendarDateKey(transaction.date).isBefore(end))
        CalendarDayActivity.transaction(transaction),
    for (final activity in goalActivities) CalendarDayActivity.goal(activity),
  ]..sort((left, right) => left.date.compareTo(right.date));
  return result;
}

Map<DateTime, CalendarDayActivitySummary> calendarActivitySummaryByDay(
  Iterable<CalendarDayActivity> activities,
) {
  final grouped = <DateTime, List<CalendarDayActivity>>{};
  for (final activity in activities) {
    grouped.putIfAbsent(calendarDateKey(activity.date), () => []).add(activity);
  }
  return {
    for (final entry in grouped.entries)
      entry.key: CalendarDayActivitySummary(entry.value),
  };
}

List<CalendarDayActivity> scheduledCalendarActivities(
  Iterable<ScheduledCalendarOccurrence> occurrences,
) => [
  for (final occurrence in occurrences)
    CalendarDayActivity.scheduled(occurrence),
];

class _ScheduledViewState extends State<ScheduledView> {
  var _calendarCollapsed = false;
  var _activityFilter = CalendarActivityFilter.all;
  final Map<String, GlobalKey> _dateAnchors = {};
  late DateTime _visibleMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  late DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  String _dateKey(DateTime date) => calendarDateId(date);

  void _scrollToDate(DateTime date, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchorContext = _dateAnchors[_dateKey(date)]?.currentContext;
      if (anchorContext == null) {
        if (attempt < 2) _scrollToDate(date, attempt + 1);
        return;
      }
      Scrollable.ensureVisible(
        anchorContext,
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _visibleMonth = DateTime(date.year, date.month);
    });
    widget.onSelectedDateChanged?.call(date);
    _scrollToDate(date);
  }

  void _changeVisibleMonth(int delta) {
    final nextMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    final selectedDay = min(_selectedDate.day, daysInMonth(nextMonth));
    final nextSelectedDate = DateTime(
      nextMonth.year,
      nextMonth.month,
      selectedDay,
    );
    setState(() {
      _dateAnchors.clear();
      _visibleMonth = nextMonth;
      _selectedDate = nextSelectedDate;
    });
    widget.onSelectedDateChanged?.call(nextSelectedDate);
  }

  Widget _buildOccurrenceRow(
    BuildContext context,
    ScheduledCalendarOccurrence occurrence,
    CurrencyFormatSettings currency,
  ) {
    final store = FinanceDataStoreScope.read(context);
    final item = occurrence.transaction;
    final dateKey = calendarDateId(occurrence.scheduledDate);
    final displayItem = item.copyWith(
      nextDate: occurrence.scheduledDate,
      amountMinor: occurrence.plannedAmountMinor,
      sync: item.sync,
    );
    final isPendingOccurrence = occurrence.isPending && !item.isDeleted;
    final needsAttention =
        item.type == TransactionType.goalFunding &&
        item.goalFundingAllocations.any(
          (allocation) => !store.goals.any(
            (goal) => goal.id == allocation.goalId && goal.isActive,
          ),
        );
    final row = ScheduledTransactionRow(
      key: ValueKey('scheduled-row-${item.id}-$dateKey'),
      scheduledTransaction: displayItem,
      currency: currency,
      needsAttention: needsAttention,
      onTap: () => showScheduledTransactionDetails(
        context,
        item,
        scheduledDate: occurrence.scheduledDate,
        plannedAmountMinor: occurrence.plannedAmountMinor,
        occurrenceRecord: occurrence.isPending ? null : occurrence.record,
      ),
      onLongPress: () {
        AppHaptics.longPressAction();
        if (!occurrence.isPending) {
          unawaited(
            showCompletedScheduledOccurrenceActions(
              context,
              item,
              occurrence.record!,
            ),
          );
          return;
        }
        unawaited(
          showScheduledTransactionActions(
            context,
            item,
            scheduledDate: occurrence.scheduledDate,
            plannedAmountMinor: occurrence.plannedAmountMinor,
          ),
        );
      },
    );
    if (!isPendingOccurrence) return row;
    return Dismissible(
      key: ValueKey('scheduled-swipe-${item.id}-$dateKey'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.22,
        DismissDirection.endToStart: 0.22,
      },
      background: SwipeActionBackground(
        alignment: Alignment.centerLeft,
        icon: AppIcon.edit,
        label: 'Edit',
      ),
      secondaryBackground: SwipeActionBackground(
        alignment: Alignment.centerRight,
        icon: AppIcon.skip,
        label: 'Skip Once  Delete',
        destructive: true,
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.selectionClick();
        await showScheduledTransactionActions(
          context,
          item,
          scheduledDate: occurrence.scheduledDate,
          plannedAmountMinor: occurrence.plannedAmountMinor,
          allowedActions: direction == DismissDirection.startToEnd
              ? const {'edit'}
              : const {'skip', 'delete'},
        );
        return false;
      },
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final allScheduled = [...store.scheduledTransactions];
    final monthOccurrences = scheduledOccurrencesForMonth(
      allScheduled,
      _visibleMonth,
    );
    final visibleMonthOccurrences = monthOccurrences
        .where(
          (occurrence) =>
              occurrence.isPending &&
              store.hasActionableScheduledAccounts(occurrence.transaction),
        )
        .toList(growable: false);
    final calendarActivities = scheduledCalendarActivities(
      visibleMonthOccurrences,
    );
    final activitySummaryByDay = calendarActivitySummaryByDay(
      calendarActivities,
    );
    final filteredMonthOccurrences = visibleMonthOccurrences
        .where(
          (occurrence) =>
              _activityFilter.matchesScheduled(occurrence.transaction.type),
        )
        .toList(growable: false);
    final groupedOccurrences = scheduledOccurrencesByDate(
      filteredMonthOccurrences,
    );
    final activityDates = groupedOccurrences.keys.toList()..sort();
    final monthSummary = scheduledMonthSummary(
      monthOccurrences.where(
        (occurrence) =>
            !occurrence.isPending ||
            store.hasActionableScheduledAccounts(occurrence.transaction),
      ),
      store.transactions,
      filter: _activityFilter,
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            ScheduledCalendarPreview(
              month: _visibleMonth,
              activitySummaryByDay: activitySummaryByDay,
              activityFilter: _activityFilter,
              onActivityFilterChanged: (filter) {
                HapticFeedback.selectionClick();
                setState(() {
                  _dateAnchors.clear();
                  _activityFilter = filter;
                });
              },
              summary: monthSummary,
              currency: store.preferences.currency,
              isCollapsed: _calendarCollapsed,
              onToggleCollapsed: () =>
                  setState(() => _calendarCollapsed = !_calendarCollapsed),
              onPreviousMonth: () => _changeVisibleMonth(-1),
              onNextMonth: () => _changeVisibleMonth(1),
              selectedDate: _selectedDate,
              onSelectDate: _selectDate,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Scheduled occurrences',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 170),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(
                  '${_visibleMonth.year}-${_visibleMonth.month}-'
                  '${_activityFilter.name}',
                ),
                children: [
                  if (filteredMonthOccurrences.isEmpty)
                    ListTile(
                      key: ValueKey('calendar-filter-empty-state'),
                      leading: Icon(AppIcon.eventBusy, color: AppTheme.muted),
                      title: Text(
                        'No scheduled transactions in ${monthLabel(_visibleMonth)}',
                      ),
                    )
                  else
                    for (final date in activityDates) ...[
                      Padding(
                        key: _dateAnchors.putIfAbsent(
                          _dateKey(date),
                          () => GlobalKey(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            shortDate(date),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: AppTheme.muted,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ),
                      for (final occurrence
                          in groupedOccurrences[date] ??
                              const <ScheduledCalendarOccurrence>[])
                        _buildOccurrenceRow(
                          context,
                          occurrence,
                          store.preferences.currency,
                        ),
                    ],
                ],
              ),
            ),
            Divider(height: 1),
            ListTile(
              leading: Icon(AppIcon.notification, color: AppTheme.accent),
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
    required this.activitySummaryByDay,
    required this.activityFilter,
    required this.onActivityFilterChanged,
    required this.summary,
    required this.currency,
    required this.isCollapsed,
    required this.onToggleCollapsed,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.selectedDate,
    required this.onSelectDate,
    super.key,
  });

  final DateTime month;
  final Map<DateTime, CalendarDayActivitySummary> activitySummaryByDay;
  final CalendarActivityFilter activityFilter;
  final ValueChanged<CalendarActivityFilter> onActivityFilterChanged;
  final ScheduledMonthSummary summary;
  final CurrencyFormatSettings currency;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPreviousMonth,
                icon: Icon(AppIcon.chevronLeft),
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
                icon: Icon(AppIcon.chevronRight),
              ),
              IconButton(
                tooltip: isCollapsed ? 'Expand calendar' : 'Collapse calendar',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onToggleCollapsed();
                },
                icon: AnimatedRotation(
                  turns: isCollapsed ? 0 : 0.5,
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  child: Icon(AppIcon.chevronDown),
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
              activitySummaryByDay: activitySummaryByDay,
              activityFilter: activityFilter,
              currency: currency,
              selectedDate: selectedDate,
              onSelectDate: onSelectDate,
              onActivityFilterChanged: onActivityFilterChanged,
            ),
            secondChild: const SizedBox.shrink(),
          ),
          ScheduledMonthlySummary(
            summary: summary,
            activityFilter: activityFilter,
            currency: currency,
          ),
        ],
      ),
    );
  }
}

class ScheduledCalendarGrid extends StatelessWidget {
  const ScheduledCalendarGrid({
    required this.month,
    required this.activitySummaryByDay,
    required this.activityFilter,
    required this.currency,
    required this.selectedDate,
    required this.onSelectDate,
    required this.onActivityFilterChanged,
    super.key,
  });

  final DateTime month;
  final Map<DateTime, CalendarDayActivitySummary> activitySummaryByDay;
  final CalendarActivityFilter activityFilter;
  final CurrencyFormatSettings currency;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<CalendarActivityFilter> onActivityFilterChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = daysInMonth(month);
    final firstWeekdayOffset = DateTime(month.year, month.month).weekday % 7;
    final rows = ((firstWeekdayOffset + days) / 7).ceil();
    return Column(
      children: [
        SizedBox(
          height: 38,
          child: SingleChildScrollView(
            key: const ValueKey('calendar-activity-filter'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                for (final filter in CalendarActivityFilter.values) ...[
                  Builder(
                    builder: (context) {
                      final selected = filter == activityFilter;
                      return ChoiceChip(
                        key: ValueKey('calendar-filter-${filter.name}'),
                        label: Text(filter.label),
                        avatar: Icon(
                          filter.icon,
                          size: AppIconSize.compact,
                          color: selected
                              ? Colors.white
                              : filter == CalendarActivityFilter.all
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : filter.color(context),
                        ),
                        selected: selected,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        selectedColor: AppTheme.accent,
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                        ),
                        onSelected: (_) => onActivityFilterChanged(filter),
                      );
                    },
                  ),
                  if (filter != CalendarActivityFilter.values.last)
                    const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
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
                      final summary = day == null
                          ? null
                          : activitySummaryByDay[calendarDateKey(
                              DateTime(month.year, month.month, day),
                            )];
                      return Expanded(
                        child: ScheduledCalendarDayCell(
                          day: day,
                          month: month,
                          activitySummary: summary,
                          activityFilter: activityFilter,
                          currency: currency,
                          isSelected:
                              selectedDate != null &&
                              selectedDate!.year == month.year &&
                              selectedDate!.month == month.month &&
                              selectedDate!.day == day,
                          isToday:
                              DateTime.now().year == month.year &&
                              DateTime.now().month == month.month &&
                              DateTime.now().day == day,
                          onSelectDate: onSelectDate,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class ScheduledCalendarDayCell extends StatelessWidget {
  const ScheduledCalendarDayCell({
    required this.day,
    required this.month,
    required this.activitySummary,
    required this.activityFilter,
    required this.currency,
    required this.isSelected,
    required this.isToday,
    required this.onSelectDate,
    super.key,
  });

  final int? day;
  final DateTime month;
  final CalendarDayActivitySummary? activitySummary;
  final CalendarActivityFilter activityFilter;
  final CurrencyFormatSettings currency;
  final bool isSelected;
  final bool isToday;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (day == null) {
      return const SizedBox(height: 72);
    }
    final matchingCount = activitySummary?.countFor(activityFilter) ?? 0;
    final matchingAmount = activitySummary?.amountFor(activityFilter);
    final presentTypes =
        activitySummary?.types ?? const <CalendarActivityType>{};
    final isAll = activityFilter == CalendarActivityFilter.all;
    final isMarked = matchingCount > 0;
    return Semantics(
      label:
          '$day, $matchingCount ${matchingCount == 1 ? 'activity' : 'activities'}'
          '${isAll && presentTypes.isNotEmpty ? ', ${presentTypes.map(calendarActivityTypeLabel).join(', ')}' : ''}'
          '${!isAll && matchingAmount != null ? ', ${money(matchingAmount, currency)}' : ''}',
      button: true,
      child: SizedBox(
        height: 72,
        child: InkWell(
          key: ValueKey(
            'scheduled-calendar-day-${month.year}-${month.month}-$day',
          ),
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelectDate(DateTime(month.year, month.month, day!)),
          child: Center(
            child: SizedBox(
              width: 52,
              height: 68,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      key: ValueKey(
                        'scheduled-calendar-selection-${month.year}-${month.month}-$day',
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.accent.withValues(alpha: 0.10)
                            : null,
                        borderRadius: BorderRadius.circular(14),
                        border: isSelected
                            ? Border.all(
                                color: AppTheme.accent.withValues(alpha: 0.55),
                              )
                            : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(1, 6, 1, 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 24,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: isToday
                                  ? BoxDecoration(
                                      border: Border.all(
                                        color: AppTheme.accent,
                                        width: 1.2,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.pill,
                                      ),
                                    )
                                  : null,
                              child: Text(
                                '$day',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: isMarked || isSelected
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  color: isSelected ? AppTheme.accent : null,
                                  height: 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            if (isAll)
                              CalendarActivityDots(types: presentTypes)
                            else if (matchingAmount != null)
                              CalendarCellAmount(
                                key: ValueKey(
                                  'calendar-filtered-total-'
                                  '${month.year}-${month.month}-$day',
                                ),
                                amountMinor: matchingAmount,
                                currency: currency,
                                color: activityFilter.color(context),
                              )
                            else
                              const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (matchingCount > 0)
                    Positioned(
                      top: 1,
                      right: 1,
                      child: Container(
                        key: ValueKey(
                          'scheduled-calendar-count-'
                          '${month.year}-${month.month}-$day',
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 17,
                          minHeight: 17,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.accent.withValues(alpha: 0.16)
                              : AppTheme.accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.24),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          matchingCount > 999 ? '999+' : '$matchingCount',
                          style: const TextStyle(
                            color: AppTheme.accent,
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
      ),
    );
  }
}

class CalendarActivityDots extends StatelessWidget {
  const CalendarActivityDots({required this.types, super.key});

  final Set<CalendarActivityType> types;

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) return const SizedBox(height: 14);
    const order = [
      CalendarActivityType.income,
      CalendarActivityType.expense,
      CalendarActivityType.transfer,
      CalendarActivityType.goal,
    ];
    Color colorFor(CalendarActivityType type) => switch (type) {
      CalendarActivityType.income => AppTheme.accent,
      CalendarActivityType.expense => AppColors.danger,
      CalendarActivityType.transfer => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant,
      CalendarActivityType.goal => _goalBlue,
    };

    return SizedBox(
      key: const ValueKey('calendar-activity-dots'),
      height: 14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final type in order)
            if (types.contains(type)) ...[
              Semantics(
                label: calendarActivityTypeLabel(type),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorFor(type),
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: 6, height: 6),
                ),
              ),
              if (type != order.last) const SizedBox(width: 3),
            ],
        ],
      ),
    );
  }
}

class CalendarCellAmount extends StatelessWidget {
  const CalendarCellAmount({
    required this.amountMinor,
    required this.currency,
    required this.color,
    super.key,
  });

  final int amountMinor;
  final CurrencyFormatSettings currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = MoneyFormatter(
      currency,
    ).formatMinor(amountMinor, showPositiveSign: false);
    return SizedBox(
      width: 52,
      height: 14,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          value,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            height: 1,
            fontFeatures: const [AppTextStyles.tabularFigures],
          ),
        ),
      ),
    );
  }
}

class ScheduledMonthlySummary extends StatelessWidget {
  const ScheduledMonthlySummary({
    required this.summary,
    required this.activityFilter,
    required this.currency,
    super.key,
  });

  final ScheduledMonthSummary summary;
  final CalendarActivityFilter activityFilter;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('scheduled-month-summary'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        children: [
          ScheduledMonthlySummaryValue(
            label: 'Planned',
            value: MoneyFormatter(
              currency,
            ).formatMinor(summary.plannedAmountMinor),
            valueKey: const ValueKey('scheduled-month-planned'),
          ),
          ScheduledMonthlySummaryValue(
            label: activityFilter.scheduledCompletedLabel,
            labelKey: const ValueKey('scheduled-month-completed-label'),
            value: MoneyFormatter(
              currency,
            ).formatMinor(summary.paidAmountMinor),
            valueKey: const ValueKey('scheduled-month-paid'),
          ),
          ScheduledMonthlySummaryValue(
            label: 'Remaining',
            value: MoneyFormatter(
              currency,
            ).formatMinor(summary.remainingAmountMinor),
            valueKey: const ValueKey('scheduled-month-remaining'),
          ),
        ],
      ),
    );
  }
}

class ScheduledMonthlySummaryValue extends StatelessWidget {
  const ScheduledMonthlySummaryValue({
    required this.label,
    required this.value,
    required this.valueKey,
    this.labelKey,
    super.key,
  });

  final String label;
  final String value;
  final Key valueKey;
  final Key? labelKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            key: labelKey,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            key: valueKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class CategoriesView extends StatefulWidget {
  const CategoriesView({super.key});

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<CategoriesView> {
  final Set<String> _collapsedCategoryIds = <String>{};
  var _initializedExpansionState = false;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final categories = store.categories
        .where((category) => category.isVisible)
        .toList(growable: false);
    if (!_initializedExpansionState) {
      final parentIds = categories
          .map((category) => category.parentCategoryId)
          .whereType<String>()
          .toSet();
      _collapsedCategoryIds.addAll(parentIds);
      _initializedExpansionState = true;
    }
    final managementIndex = ManagementLedgerIndex.build(
      transactions: store.transactions,
      categories: store.categories,
      now: DateTime.now(),
    );
    final displayCategories = visibleCategoriesInDisplayOrder(
      categories,
      _collapsedCategoryIds,
    );
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
            icon: Icon(AppIcon.add),
            label: const Text('Add category'),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < displayCategories.length;
                  index++
                ) ...[
                  Builder(
                    builder: (context) {
                      final category = displayCategories[index];
                      final depth = categoryDepth(category, categoriesById);
                      final childCount = categories
                          .where(
                            (candidate) =>
                                candidate.parentCategoryId == category.id,
                          )
                          .length;
                      final hasChildren = childCount > 0;
                      final isChild = depth > 0;
                      final isExpanded = !_collapsedCategoryIds.contains(
                        category.id,
                      );
                      final subtitle = categorySubtitle(
                        category,
                        categoriesById,
                      );
                      return Padding(
                        padding: EdgeInsets.only(left: depth * 22.0),
                        child: Stack(
                          children: [
                            if (isChild) ...[
                              Positioned(
                                left: 5,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  key: ValueKey(
                                    'category-branch-${category.id}',
                                  ),
                                  width: 1,
                                  color: AppTheme.line.withValues(alpha: 0.7),
                                ),
                              ),
                              Positioned(
                                left: 5,
                                top: 31,
                                child: Container(
                                  width: 10,
                                  height: 1,
                                  color: AppTheme.line.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                            Padding(
                              padding: EdgeInsets.only(left: isChild ? 10 : 0),
                              child: ManagementSwipeRow(
                                key: ValueKey('category-swipe-${category.id}'),
                                actions: [
                                  ManagementSwipeAction(
                                    label: 'Edit',
                                    icon: AppIcon.edit,
                                    color: AppTheme.accent,
                                    actionKey: ValueKey(
                                      'category-edit-${category.id}',
                                    ),
                                    onPressed: () => showCategoryDialog(
                                      context,
                                      categoryId: category.id,
                                    ),
                                  ),
                                  ManagementSwipeAction(
                                    label: 'Archive',
                                    icon: AppIcon.archive,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    actionKey: ValueKey(
                                      'category-archive-${category.id}',
                                    ),
                                    onPressed: () =>
                                        store.archiveCategory(category.id),
                                  ),
                                  ManagementSwipeAction(
                                    label: 'Delete',
                                    icon: AppIcon.delete,
                                    color: AppColors.danger,
                                    actionKey: ValueKey(
                                      'category-delete-${category.id}',
                                    ),
                                    onPressed: () =>
                                        store.deleteCategory(category.id),
                                  ),
                                ],
                                child: ListTile(
                                  key: ValueKey('category-row-${category.id}'),
                                  dense: true,
                                  visualDensity: const VisualDensity(
                                    vertical: -1,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 2,
                                  ),
                                  onTap: () => showCategoryDetails(
                                    context,
                                    category.id,
                                    index: managementIndex,
                                  ),
                                  onLongPress: () {
                                    AppHaptics.longPressAction();
                                    showCategoryActions(context, category);
                                  },
                                  leading: CategoryIconBadge.category(
                                    category,
                                    size: isChild
                                        ? CategoryIconBadgeSize.compact
                                        : CategoryIconBadgeSize.row,
                                  ),
                                  title: Text(
                                    category.name,
                                    style: isChild
                                        ? Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          )
                                        : const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                  ),
                                  subtitle: Text(
                                    hasChildren && !isExpanded
                                        ? '$subtitle · $childCount ${childCount == 1 ? 'subcategory' : 'subcategories'}'
                                        : subtitle,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: isChild ? 11 : null,
                                        ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ManagementCountPill(
                                        key: ValueKey(
                                          'category-count-${category.id}',
                                        ),
                                        count: managementIndex.categoryCount(
                                          category.id,
                                        ),
                                        semanticLabel:
                                            '${category.name}, ${managementIndex.categoryCount(category.id)} transactions in the last 12 months',
                                        onTap: () => openManagementLedger(
                                          context,
                                          ManagementLedgerFilter.category(
                                            categoryId: category.id,
                                            label: category.name,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (hasChildren)
                                        IconButton(
                                          tooltip: isExpanded
                                              ? 'Collapse ${category.name}'
                                              : 'Expand ${category.name}',
                                          onPressed: () {
                                            HapticFeedback.selectionClick();
                                            setState(() {
                                              if (isExpanded) {
                                                _collapsedCategoryIds.add(
                                                  category.id,
                                                );
                                              } else {
                                                _collapsedCategoryIds.remove(
                                                  category.id,
                                                );
                                              }
                                            });
                                          },
                                          icon: AnimatedRotation(
                                            turns: isExpanded ? 0.25 : 0,
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            child: Icon(AppIcon.chevronRight),
                                          ),
                                        )
                                      else
                                        const SizedBox(width: 48),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (index < displayCategories.length - 1)
                    Divider(
                      height: 1,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.52),
                      indent:
                          58 +
                          categoryDepth(
                                displayCategories[index],
                                categoriesById,
                              ) *
                              18.0,
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsView extends StatefulWidget {
  const SettingsView({
    this.onSelectSection,
    this.syncLabel = 'Synced',
    this.lastSuccessfulSyncLabel,
    this.onSyncNow,
    this.onSignOut,
    this.exportFileService,
    this.now,
    super.key,
  });

  final ValueChanged<FinanceSection>? onSelectSection;
  final String syncLabel;
  final String? lastSuccessfulSyncLabel;
  final Future<void> Function()? onSyncNow;
  final VoidCallback? onSignOut;
  final ExportFileService? exportFileService;
  final DateTime Function()? now;

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
  State<SettingsView> createState() => _SettingsViewState();

  static CurrencyFormatSettings _currencyFor(String code) {
    return _currencyOptions.firstWhere(
      (option) => option.currencyCode == code,
      orElse: () => _currencyOptions.first,
    );
  }
}

class _SettingsViewState extends State<SettingsView> {
  ExportFileService? _defaultExportFileService;
  _ExportKind? _sharingExport;

  ExportFileService get _exportFileService =>
      widget.exportFileService ??
      (_defaultExportFileService ??= ExportFileService());

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final preferences = store.preferences;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionCard(
          title: 'Cloud Sync',
          children: [
            SettingsActionRow(
              icon: widget.syncLabel == 'Sync issue'
                  ? AppIcon.cloudOff
                  : AppIcon.cloudDone,
              title: 'Status',
              subtitle: switch (widget.syncLabel) {
                'Synced' => 'Your data is securely synced',
                'Syncing' => 'Your data is syncing',
                'Sync issue' => 'Cloud sync needs attention',
                'Offline' => 'You are currently offline',
                _ => 'Your data is stored securely',
              },
              trailingText: widget.syncLabel,
              showStatusPill: true,
              onTap: widget.onSyncNow == null
                  ? null
                  : () => widget.onSyncNow!.call(),
            ),
            SettingsActionRow(
              icon: AppIcon.schedule,
              title: 'Last successful sync',
              subtitle:
                  widget.lastSuccessfulSyncLabel ??
                  (widget.syncLabel == 'Synced'
                      ? 'This session'
                      : 'Not available'),
              showDivider: widget.onSyncNow != null || widget.onSignOut != null,
            ),
            if (widget.onSyncNow != null)
              SettingsActionRow(
                icon: AppIcon.sync,
                title: 'Sync now',
                subtitle: 'Refresh your data',
                showDivider: widget.onSignOut != null,
                onTap: () => widget.onSyncNow!.call(),
              ),
            if (widget.onSignOut != null)
              SettingsActionRow(
                icon: AppIcon.signOut,
                title: 'Sign out',
                subtitle: 'Sign out of your account',
                destructive: true,
                showDivider: false,
                onTap: widget.onSignOut,
              ),
          ],
        ),
        SizedBox(height: 16),
        SettingsSectionCard(
          title: 'App Preferences',
          children: [
            SettingsDropdown<LaunchScreen>(
              icon: AppIcon.home,
              label: 'Launch screen',
              value: preferences.launchScreen,
              values: LaunchScreen.values
                  .where((value) => value != LaunchScreen.budgets)
                  .toList(growable: false),
              labelOf: launchScreenLabel,
              onChanged: (value) => store.savePreferences(
                preferences.copyWith(launchScreen: value),
              ),
            ),
            SettingsDropdown<AppearanceMode>(
              icon: AppIcon.contrast,
              label: 'Appearance',
              value: preferences.appearanceMode,
              values: AppearanceMode.values,
              labelOf: appearanceModeLabel,
              onChanged: (value) => store.savePreferences(
                preferences.copyWith(appearanceMode: value),
              ),
            ),
            SettingsDropdown<FloatingAddButtonPosition>(
              icon: AppIcon.income,
              label: 'Floating add button',
              value: preferences.floatingAddButtonPosition,
              values: FloatingAddButtonPosition.values,
              labelOf: floatingAddButtonPositionLabel,
              onChanged: (value) => store.savePreferences(
                preferences.copyWith(floatingAddButtonPosition: value),
              ),
            ),
            SettingsDropdown<DefaultTransactionType>(
              icon: AppIcon.receipt,
              label: 'Default transaction type',
              showDivider: false,
              value: preferences.defaultTransactionType,
              values: DefaultTransactionType.values,
              labelOf: defaultTransactionTypeLabel,
              onChanged: (value) => store.savePreferences(
                preferences.copyWith(defaultTransactionType: value),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        SettingsSectionCard(
          title: 'Money Format',
          children: [
            SettingsDropdown<CurrencyFormatSettings>(
              icon: AppIcon.currency,
              label: 'Currency',
              value: SettingsView._currencyFor(
                preferences.currency.currencyCode,
              ),
              values: SettingsView._currencyOptions,
              labelOf: (value) => currencySettingsLabel(value.currencyCode),
              onChanged: (value) => store.savePreferences(
                preferences.copyWith(
                  currency: value.copyWith(
                    decimalPlaces: preferences.currency.decimalPlaces,
                    thousandsSeparator: preferences.currency.thousandsSeparator,
                  ),
                ),
              ),
            ),
            SettingsActionRow(
              icon: AppIcon.edit,
              title: 'Custom currency',
              subtitle:
                  '${preferences.currency.currencyCode} ${preferences.currency.symbol}',
              onTap: () => showCustomCurrencyDialog(context),
            ),
            SettingsDropdown<int>(
              icon: AppIcon.numbers,
              label: 'Decimal places',
              value: preferences.currency.decimalPlaces,
              values: const [0, 2],
              labelOf: (value) => '$value',
              onChanged: (value) => store.savePreferences(
                preferences.copyWith(
                  currency: preferences.currency.copyWith(decimalPlaces: value),
                ),
              ),
            ),
            SettingsDropdown<String>(
              icon: AppIcon.numberedList,
              label: 'Thousands separator',
              showDivider: false,
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
        SizedBox(height: 16),
        SettingsSectionCard(
          title: 'Notifications',
          children: [
            SettingsSwitch(
              icon: AppIcon.notification,
              label: 'Scheduled transaction alerts',
              subtitle: 'Receive reminders for scheduled transactions',
              value: preferences.notificationsEnabled,
              onChanged: (value) => store.savePreferences(
                preferences.copyWith(notificationsEnabled: value),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        SettingsSectionCard(
          title: 'Manage',
          children: [
            SettingsActionRow(
              icon: AppIcon.wallet,
              title: 'Manage accounts',
              subtitle: 'Defaults, ordering, archived accounts, and warnings',
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ManageAccountsScreen(),
                  ),
                );
              },
            ),
            SettingsActionRow(
              icon: AppIcon.category,
              title: 'Manage categories',
              subtitle: 'Expense and income categories',
              onTap: () =>
                  widget.onSelectSection?.call(FinanceSection.categories),
            ),
            SettingsActionRow(
              icon: AppIcon.payee,
              title: 'Manage payees',
              subtitle: 'Active and archived payees',
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => PayeesManagementScreen(),
                  ),
                );
              },
            ),
            SettingsActionRow(
              icon: AppIcon.pieChart,
              title: 'Manage budgets',
              subtitle: 'Budget amounts and categories',
              showDivider: false,
              onTap: () => widget.onSelectSection?.call(FinanceSection.plan),
            ),
          ],
        ),
        SizedBox(height: 16),
        SettingsSectionCard(
          title: 'More',
          children: [
            SettingsActionRow(
              icon: AppIcon.insights,
              title: 'Reports',
              subtitle: 'Review spending and category trends',
              showDivider: false,
              onTap: () => widget.onSelectSection?.call(FinanceSection.reports),
            ),
          ],
        ),
        SizedBox(height: 16),
        SettingsSectionCard(
          title: 'Data Management',
          children: [
            SettingsActionRow(
              icon: AppIcon.history,
              title: 'Reset Scheduled History',
              subtitle: 'Clear paid and skipped occurrence history',
              destructive: true,
              onTap: () => showResetScheduledHistorySheet(context, store),
            ),
            Builder(
              builder: (rowContext) => SettingsActionRow(
                icon: AppIcon.import,
                title: 'Export CSV',
                subtitle: 'Share or copy your transaction history',
                trailingText: _sharingExport == _ExportKind.csv
                    ? 'Sharing…'
                    : null,
                onTap: () =>
                    _showExportActions(rowContext, kind: _ExportKind.csv),
              ),
            ),
            Builder(
              builder: (rowContext) => SettingsActionRow(
                icon: AppIcon.backup,
                title: 'Export Backup',
                subtitle: 'Share or copy a complete Trackmark Money backup',
                trailingText: _sharingExport == _ExportKind.backup
                    ? 'Sharing…'
                    : null,
                onTap: () =>
                    _showExportActions(rowContext, kind: _ExportKind.backup),
              ),
            ),
            SettingsActionRow(
              icon: AppIcon.restore,
              title: 'Backup and restore',
              subtitle: 'Restore a JSON backup from the clipboard',
              showDivider: false,
              onTap: () => restoreJsonBackupFromClipboard(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showExportActions(
    BuildContext anchorContext, {
    required _ExportKind kind,
  }) async {
    if (_sharingExport != null) return;

    final sharePositionOrigin = exportSharePositionOrigin(anchorContext);
    final action = await _showExportActionSheet(context, kind: kind);
    if (!mounted || action == null) return;

    final store = FinanceDataStoreScope.read(context);
    final payload = switch (kind) {
      _ExportKind.csv => const BackupCodec().encodeTransactionsCsv(
        store.dataSet,
      ),
      _ExportKind.backup => const BackupCodec().encodeJson(store.dataSet),
    };

    if (action == _ExportAction.copy) {
      await copyExportToClipboard(
        context,
        title: kind == _ExportKind.csv
            ? 'CSV copied to clipboard'
            : 'Backup copied to clipboard',
        payload: payload,
      );
      return;
    }

    setState(() => _sharingExport = kind);
    final createdAt = widget.now?.call() ?? DateTime.now();
    try {
      await _exportFileService.shareTextFile(
        content: payload,
        fileName: kind == _ExportKind.csv
            ? csvExportFileName(createdAt)
            : backupExportFileName(createdAt),
        mimeType: kind == _ExportKind.csv ? 'text/csv' : 'application/json',
        shareTitle: kind == _ExportKind.csv
            ? 'Trackmark Money transactions'
            : 'Trackmark Money backup',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kind == _ExportKind.csv
                ? 'Could not share CSV file'
                : 'Could not share backup file',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharingExport = null);
    }
  }
}

enum _ExportKind { csv, backup }

enum _ExportAction { share, copy }

Future<_ExportAction?> _showExportActionSheet(
  BuildContext context, {
  required _ExportKind kind,
}) {
  final isCsv = kind == _ExportKind.csv;
  return showModalBottomSheet<_ExportAction>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isCsv ? 'Export CSV' : 'Export Backup',
            style: Theme.of(
              sheetContext,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: AppSpacing.sm),
          _ExportActionTile(
            key: ValueKey('export-share-file'),
            icon: AppIcon.export,
            title: isCsv ? 'Share CSV File' : 'Share Backup File',
            subtitle: isCsv
                ? 'Create a CSV file and open the phone’s share sheet'
                : 'Create a Trackmark Money backup file and open the phone’s '
                      'share sheet',
            onTap: () => Navigator.of(sheetContext).pop(_ExportAction.share),
          ),
          Divider(
            height: 1,
            indent: 56,
            color: Theme.of(
              sheetContext,
            ).colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          _ExportActionTile(
            key: ValueKey('export-copy-clipboard'),
            icon: AppIcon.contentCopy,
            title: isCsv ? 'Copy CSV to Clipboard' : 'Copy JSON to Clipboard',
            subtitle: isCsv
                ? 'Copy the raw CSV text'
                : 'Copy the raw backup text',
            onTap: () => Navigator.of(sheetContext).pop(_ExportAction.copy),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            key: const ValueKey('export-cancel'),
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

class _ExportActionTile extends StatelessWidget {
  const _ExportActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 72,
      contentPadding: EdgeInsets.zero,
      leading: SettingsRowIcon(icon: icon),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.25,
        ),
      ),
      trailing: Icon(AppIcon.chevronRightRounded),
      onTap: onTap,
    );
  }
}

Rect exportSharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.attached &&
      renderObject.hasSize &&
      renderObject.size.width > 0 &&
      renderObject.size.height > 0) {
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  final screenSize = MediaQuery.maybeSizeOf(context) ?? const Size(1, 1);
  return Rect.fromCenter(
    center: Offset(screenSize.width / 2, screenSize.height / 2),
    width: 1,
    height: 1,
  );
}

Future<void> showResetScheduledHistorySheet(
  BuildContext context,
  FinanceDataStore dataStore,
) async {
  final shouldReset = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Reset Scheduled History?',
              style: Theme.of(
                sheetContext,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This removes paid and skipped scheduled-occurrence history '
              'and resets Scheduled calendar summaries. Active recurring '
              'schedules and ledger transactions will remain.',
              style: Theme.of(sheetContext).textTheme.bodyLarge?.copyWith(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      key: const ValueKey('cancel-scheduled-history-reset'),
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      key: const ValueKey('confirm-scheduled-history-reset'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: const Text('Reset History'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (shouldReset != true || !context.mounted) return;

  try {
    await dataStore.resetScheduledHistory();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Scheduled history reset')));
  } on Exception catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not reset scheduled history: $error')),
    );
  }
}

class PayeesManagementScreen extends StatefulWidget {
  const PayeesManagementScreen({super.key});

  @override
  State<PayeesManagementScreen> createState() => _PayeesManagementScreenState();
}

class _PayeesManagementScreenState extends State<PayeesManagementScreen> {
  var _archivedExpanded = false;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final managementIndex = ManagementLedgerIndex.build(
      transactions: store.transactions,
      categories: store.categories,
      now: DateTime.now(),
    );
    final payees = [...managedPayees(store)]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final archived = archivedPayees(
      store,
    ).where((payee) => !isSystemGeneratedManagedPayee(payee)).toList();
    final groupedPayees = <String, List<String>>{};
    for (final payee in payees) {
      final first = payee.trim().isEmpty ? '#' : payee.trim()[0].toUpperCase();
      final section = RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
      groupedPayees.putIfAbsent(section, () => <String>[]).add(payee);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Payees'),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Add payee',
            onPressed: () => addManagedPayee(context),
            icon: Icon(AppIcon.add),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (payees.isEmpty)
              AppCard(
                child: Column(
                  children: [
                    Icon(
                      AppIcon.addPerson,
                      color: AppTheme.accent,
                      size: AppIconSize.prominent,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No saved payees',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Payees are remembered from transactions, or you can add one now.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => addManagedPayee(context),
                      icon: Icon(AppIcon.add),
                      label: const Text('Add payee'),
                    ),
                  ],
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  children: [
                    for (final group in groupedPayees.entries) ...[
                      Padding(
                        key: ValueKey('payee-section-${group.key}'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            group.key,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                      for (
                        var index = 0;
                        index < group.value.length;
                        index++
                      ) ...[
                        Builder(
                          builder: (context) {
                            final payee = group.value[index];
                            return ManagementSwipeRow(
                              key: ValueKey(
                                'payee-swipe-${payee.toLowerCase()}',
                              ),
                              actions: [
                                ManagementSwipeAction(
                                  label: 'Edit',
                                  icon: AppIcon.edit,
                                  color: AppTheme.accent,
                                  actionKey: ValueKey(
                                    'payee-edit-${payee.toLowerCase()}',
                                  ),
                                  onPressed: () =>
                                      renameManagedPayee(context, payee),
                                ),
                                ManagementSwipeAction(
                                  label: 'Archive',
                                  icon: AppIcon.archive,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  actionKey: ValueKey(
                                    'payee-archive-${payee.toLowerCase()}',
                                  ),
                                  onPressed: () =>
                                      archiveManagedPayee(context, payee),
                                ),
                                ManagementSwipeAction(
                                  label: 'Delete',
                                  icon: AppIcon.delete,
                                  color: AppColors.danger,
                                  actionKey: ValueKey(
                                    'payee-delete-${payee.toLowerCase()}',
                                  ),
                                  onPressed: () =>
                                      deleteManagedPayee(context, payee),
                                ),
                              ],
                              child: ListTile(
                                key: ValueKey(
                                  'payee-row-${payee.toLowerCase()}',
                                ),
                                contentPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  8,
                                  4,
                                ),
                                dense: true,
                                visualDensity: const VisualDensity(
                                  vertical: -3,
                                ),
                                minVerticalPadding: 0,
                                title: Text(
                                  payee,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ManagementCountPill(
                                      key: ValueKey(
                                        'payee-count-${payee.toLowerCase()}',
                                      ),
                                      count: managementIndex
                                          .payeeSummary(payee)
                                          .count,
                                      semanticLabel:
                                          '$payee, ${managementIndex.payeeSummary(payee).count} transactions in the last 12 months',
                                      onTap: () => openManagementLedger(
                                        context,
                                        ManagementLedgerFilter.payee(
                                          payee: payee,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => showPayeeDetails(
                                  context,
                                  payee,
                                  index: managementIndex,
                                ),
                                onLongPress: () {
                                  AppHaptics.longPressAction();
                                  showManagedPayeeActions(context, payee);
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            if (archived.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                padding: EdgeInsets.zero,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      ListTile(
                        key: const ValueKey('archived-payees-header'),
                        title: Text(
                          'Archived (${archived.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: AnimatedRotation(
                          turns: _archivedExpanded ? 0.5 : 0,
                          duration: Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: Icon(AppIcon.chevronDown),
                        ),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(
                            () => _archivedExpanded = !_archivedExpanded,
                          );
                        },
                      ),
                      if (_archivedExpanded)
                        for (
                          var index = 0;
                          index < archived.length;
                          index++
                        ) ...[
                          ListTile(
                            key: ValueKey(
                              'archived-payee-${archived[index].toLowerCase()}',
                            ),
                            title: Text(
                              archived[index],
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            dense: true,
                            visualDensity: const VisualDensity(vertical: -2),
                            minVerticalPadding: 0,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => restoreManagedPayee(
                                    context,
                                    archived[index],
                                  ),
                                  child: const Text('Restore'),
                                ),
                                IconButton(
                                  tooltip:
                                      'Delete ${archived[index]} permanently',
                                  onPressed: () =>
                                      permanentlyDeleteManagedPayee(
                                        context,
                                        archived[index],
                                      ),
                                  icon: Icon(AppIcon.delete),
                                  color: AppColors.danger,
                                ),
                              ],
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<String?> showPayeeNameDialog(
  BuildContext context, {
  String initialName = '',
}) async {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (context) => PayeeEditorScreen(initialName: initialName),
    ),
  );
}

class PayeeEditorScreen extends StatefulWidget {
  const PayeeEditorScreen({required this.initialName, super.key});

  final String initialName;

  @override
  State<PayeeEditorScreen> createState() => _PayeeEditorScreenState();
}

class _PayeeEditorScreenState extends State<PayeeEditorScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialName.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Payee' : 'Add Payee'),
        scrolledUnderElevation: 0,
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            AppCard(
              child: DialogFieldGroup(
                label: 'Name',
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: dialogFieldDecoration(),
                  onSubmitted: (_) => _save(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> addManagedPayee(BuildContext context) async {
  final name = await showPayeeNameDialog(context);
  if (!context.mounted || name == null) return;
  final store = FinanceDataStoreScope.read(context);
  final saved = [...store.preferences.savedPayeeNames];
  saved.removeWhere((item) => item.toLowerCase() == name.toLowerCase());
  saved.insert(0, name);
  final archived = {...store.preferences.archivedPayeeNames}
    ..remove(name.toLowerCase());
  final deleted = {...store.preferences.deletedPayeeNames}
    ..remove(name.toLowerCase());
  await store.savePreferences(
    store.preferences.copyWith(
      savedPayeeNames: saved,
      archivedPayeeNames: archived,
      deletedPayeeNames: deleted,
    ),
  );
  HapticFeedback.mediumImpact();
}

Future<void> showManagedPayeeActions(BuildContext context, String payee) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(AppIcon.edit),
            title: Text('Edit'),
            onTap: () => Navigator.pop(sheetContext, 'edit'),
          ),
          ListTile(
            leading: Icon(AppIcon.archive),
            title: Text('Archive'),
            onTap: () => Navigator.pop(sheetContext, 'archive'),
          ),
          ListTile(
            leading: Icon(AppIcon.delete),
            title: const Text('Delete permanently'),
            textColor: AppColors.danger,
            iconColor: AppColors.danger,
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  // Let the action sheet finish dismissing before pushing another route.
  await Future<void>.delayed(const Duration(milliseconds: 180));
  if (!context.mounted) return;
  switch (action) {
    case 'edit':
      await renameManagedPayee(context, payee);
    case 'archive':
      await archiveManagedPayee(context, payee);
    case 'delete':
      await deleteManagedPayee(context, payee);
  }
}

Future<void> openManagementLedger(
  BuildContext context,
  ManagementLedgerFilter filter,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => FilteredLedgerScreen(filter: filter),
    ),
  );
}

Future<void> showPayeeDetails(
  BuildContext context,
  String payee, {
  required ManagementLedgerIndex index,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final summary = index.payeeSummary(payee);
  final archived = store.preferences.archivedPayeeNames.contains(
    normalizeManagedPayee(payee),
  );
  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) => TransactionSheetFrame(
      title: 'Payee Details',
      actions: ScheduledTransactionDetailActions(
        onClose: () => Navigator.pop(dialogContext),
        onEdit: () => Navigator.pop(dialogContext, 'edit'),
        onMarkPaid: null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScheduledTransactionDetailRow(
            rowKey: const ValueKey('payee-detail-name'),
            icon: AppIcon.payee,
            label: 'Payee',
            value: payee,
          ),
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            rowKey: const ValueKey('payee-detail-count'),
            icon: AppIcon.ledger,
            label: 'Transactions · Last 12 Months',
            value: '${summary.count}',
            tabularFigures: true,
          ),
          if (summary.expenseMinor > 0) ...[
            const TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.expense,
              label: 'Total Spent · Last 12 Months',
              value: money(summary.expenseMinor, store.preferences.currency),
              valueColor: AppColors.danger,
              tabularFigures: true,
            ),
          ],
          if (summary.incomeMinor > 0) ...[
            const TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.income,
              label: 'Total Received · Last 12 Months',
              value: money(summary.incomeMinor, store.preferences.currency),
              valueColor: AppTheme.accent,
              tabularFigures: true,
            ),
          ],
          if (summary.mostRecentDate case final date?) ...[
            const TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.calendar,
              label: 'Most Recent Transaction',
              value: fullMonthDateLabel(date),
            ),
          ],
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: archived ? AppIcon.archive : AppIcon.check,
            label: 'Status',
            value: archived ? 'Archived' : 'Active',
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('payee-detail-view-transactions'),
              onPressed: () => Navigator.pop(dialogContext, 'transactions'),
              icon: Icon(AppIcon.ledger),
              label: const Text('View Transactions'),
            ),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'edit') {
    await renameManagedPayee(context, payee);
  } else if (action == 'transactions') {
    await openManagementLedger(
      context,
      ManagementLedgerFilter.payee(payee: payee),
    );
  }
}

Future<void> renameManagedPayee(BuildContext context, String oldName) async {
  final newName = await showPayeeNameDialog(context, initialName: oldName);
  if (!context.mounted || newName == null || newName == oldName) return;
  final store = FinanceDataStoreScope.read(context);
  final matchingTransactions = store.transactions
      .where(
        (item) =>
            !item.isDeleted &&
            item.payee.toLowerCase() == oldName.toLowerCase(),
      )
      .toList(growable: false);
  for (final transaction in matchingTransactions) {
    await store.saveTransaction(transaction.copyWith(payee: newName));
  }
  final saved = [...store.preferences.savedPayeeNames]
    ..removeWhere((item) => item.toLowerCase() == oldName.toLowerCase());
  saved.insert(0, newName);
  final archived = {...store.preferences.archivedPayeeNames}
    ..remove(oldName.toLowerCase());
  final deleted = {...store.preferences.deletedPayeeNames}
    ..remove(newName.toLowerCase());
  await store.savePreferences(
    store.preferences.copyWith(
      savedPayeeNames: saved,
      archivedPayeeNames: archived,
      deletedPayeeNames: deleted,
    ),
  );
  HapticFeedback.mediumImpact();
}

Future<void> archiveManagedPayee(BuildContext context, String payee) async {
  final store = FinanceDataStoreScope.read(context);
  final archived = {...store.preferences.archivedPayeeNames}
    ..add(payee.toLowerCase());
  final deleted = {...store.preferences.deletedPayeeNames}
    ..remove(payee.toLowerCase());
  await store.savePreferences(
    store.preferences.copyWith(
      archivedPayeeNames: archived,
      deletedPayeeNames: deleted,
    ),
  );
  HapticFeedback.selectionClick();
}

Future<void> restoreManagedPayee(BuildContext context, String payee) async {
  final store = FinanceDataStoreScope.read(context);
  final archived = {...store.preferences.archivedPayeeNames}
    ..remove(payee.toLowerCase());
  final deleted = {...store.preferences.deletedPayeeNames}
    ..remove(payee.toLowerCase());
  await store.savePreferences(
    store.preferences.copyWith(
      archivedPayeeNames: archived,
      deletedPayeeNames: deleted,
    ),
  );
  HapticFeedback.selectionClick();
}

Future<void> deleteManagedPayee(BuildContext context, String payee) async {
  await permanentlyDeleteManagedPayee(context, payee);
}

Future<void> permanentlyDeleteManagedPayee(
  BuildContext context,
  String payee,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete payee permanently?'),
      content: Text(
        '$payee will no longer appear in saved payees or suggestions. Existing transactions will not be changed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Delete permanently'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final store = FinanceDataStoreScope.read(context);
  final saved = [...store.preferences.savedPayeeNames]
    ..removeWhere((item) => item.toLowerCase() == payee.toLowerCase());
  final archived = {...store.preferences.archivedPayeeNames}
    ..remove(payee.toLowerCase());
  final deleted = {...store.preferences.deletedPayeeNames}
    ..add(payee.toLowerCase());
  await store.savePreferences(
    store.preferences.copyWith(
      savedPayeeNames: saved,
      archivedPayeeNames: archived,
      deletedPayeeNames: deleted,
    ),
  );
  HapticFeedback.mediumImpact();
}

Future<void> showCustomCurrencyDialog(BuildContext context) async {
  final store = FinanceDataStoreScope.read(context);
  final preferences = store.preferences;
  final code = TextEditingController(text: preferences.currency.currencyCode);
  final symbol = TextEditingController(text: preferences.currency.symbol);
  final result = await showDialog<({String currencyCode, String symbol})>(
    context: context,
    builder: (dialogContext) => TransactionSheetFrame(
      title: 'Custom Currency',
      actions: TransactionFormActions(
        onCancel: () => Navigator.pop(dialogContext),
        onSave: () => Navigator.pop(dialogContext, (
          currencyCode: code.text.trim().toUpperCase(),
          symbol: symbol.text,
        )),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TransactionFormLabel('Currency code'),
          Row(
            children: [
              TransactionFormIcon(AppIcon.text),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  key: const ValueKey('custom-currency-code'),
                  controller: code,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    hintText: 'Currency code',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          TransactionFormDivider(),
          TransactionFormLabel('Symbol'),
          Row(
            children: [
              TransactionFormIcon(AppIcon.moneyOutlined),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  key: const ValueKey('custom-currency-symbol'),
                  controller: symbol,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.pop(dialogContext, (
                    currencyCode: code.text.trim().toUpperCase(),
                    symbol: symbol.text,
                  )),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    hintText: 'Symbol',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ],
      ),
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

class ReportsView extends StatefulWidget {
  const ReportsView({this.now, super.key});

  final DateTime Function()? now;

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  var _range = ReportDateRange.thisMonth;
  String? _selectedCategoryId;
  List<TransactionRecord>? _cachedTransactions;
  List<v2_category.CategoryRecord>? _cachedCategories;
  ReportDateRange? _cachedRange;
  DateTime? _cachedDay;
  ReportSnapshot? _cachedSnapshot;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  ReportSnapshot _reportFor(FinanceDataStore store) {
    final now = _now;
    final day = DateTime(now.year, now.month, now.day);
    if (identical(_cachedTransactions, store.transactions) &&
        identical(_cachedCategories, store.categories) &&
        _cachedRange == _range &&
        _cachedDay == day &&
        _cachedSnapshot != null) {
      return _cachedSnapshot!;
    }
    final snapshot = const MoneyReportCalculator().calculate(
      transactions: store.transactions,
      categories: store.categories,
      range: _range,
      now: now,
    );
    _cachedTransactions = store.transactions;
    _cachedCategories = store.categories;
    _cachedRange = _range;
    _cachedDay = day;
    _cachedSnapshot = snapshot;
    return snapshot;
  }

  Future<void> _chooseRange() async {
    final selected = await showPolishedChoicePicker<ReportDateRange>(
      context,
      title: 'Date Range',
      selected: _range,
      choices: [
        for (final range in ReportDateRange.values)
          PolishedChoice(
            value: range,
            label: range.label,
            leading: Icon(AppIcon.dateRange),
          ),
      ],
    );
    if (selected == null || selected == _range || !mounted) return;
    setState(() {
      _range = selected;
      _selectedCategoryId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final report = _reportFor(store);
    final currency = store.preferences.currency;
    final colors = reportCategoryColors(context);

    return Column(
      children: [
        Card(
          child: InkWell(
            key: const ValueKey('reports-date-range'),
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: _chooseRange,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  TransactionFormIcon(AppIcon.calendarMonth),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Date range',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          report.period.label,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  Icon(AppIcon.chevronDown),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ReportSummaryCard(report: report, currency: currency),
        const SizedBox(height: AppSpacing.sm),
        ReportSectionCard(
          title: 'Spending by Category',
          child: report.hasExpenses
              ? CategorySpendingReport(
                  totals: report.categoryTotals,
                  totalExpensesMinor: report.expensesMinor,
                  currency: currency,
                  colors: colors,
                  selectedCategoryId: _selectedCategoryId,
                  onSelected: (categoryId) {
                    setState(() {
                      _selectedCategoryId = _selectedCategoryId == categoryId
                          ? null
                          : categoryId;
                    });
                  },
                )
              : ReportEmptyState(
                  icon: AppIcon.donutChart,
                  message: 'No expense data for this period',
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ReportSectionCard(
          title: 'Monthly Trend',
          child: report.hasTrendData
              ? MonthlyTrendReport(
                  totals: report.monthlyTotals,
                  currency: currency,
                )
              : ReportEmptyState(
                  icon: AppIcon.barChart,
                  message: 'No trend data yet',
                ),
        ),
      ],
    );
  }
}

class ReportSummaryCard extends StatelessWidget {
  const ReportSummaryCard({
    required this.report,
    required this.currency,
    super.key,
  });

  final ReportSnapshot report;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final net = report.netCashFlowMinor;
    return ReportSectionCard(
      title: report.period.label,
      child: Row(
        children: [
          Expanded(
            child: ReportSummaryValue(
              key: const ValueKey('report-summary-income'),
              label: 'Income',
              value: money(report.incomeMinor, currency),
              color: AppTheme.accent,
            ),
          ),
          const ReportVerticalDivider(),
          Expanded(
            child: ReportSummaryValue(
              key: const ValueKey('report-summary-expenses'),
              label: 'Expenses',
              value: money(report.expensesMinor, currency),
              color: AppTheme.rose,
            ),
          ),
          const ReportVerticalDivider(),
          Expanded(
            child: ReportSummaryValue(
              key: const ValueKey('report-summary-net'),
              label: 'Net Cash Flow',
              value: money(net, currency),
              color: net < 0 ? AppTheme.rose : AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class ReportSummaryValue extends StatelessWidget {
  const ReportSummaryValue({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTextStyles.money(context, fontSize: 17, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class ReportVerticalDivider extends StatelessWidget {
  const ReportVerticalDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 46,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.55),
    );
  }
}

class ReportSectionCard extends StatelessWidget {
  const ReportSectionCard({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class CategorySpendingReport extends StatelessWidget {
  const CategorySpendingReport({
    required this.totals,
    required this.totalExpensesMinor,
    required this.currency,
    required this.colors,
    required this.selectedCategoryId,
    required this.onSelected,
    super.key,
  });

  final List<CategoryReportTotal> totals;
  final int totalExpensesMinor;
  final CurrencyFormatSettings currency;
  final List<Color> colors;
  final String? selectedCategoryId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final chart = Semantics(
      label:
          'Spending by category donut chart. Total expenses ${money(totalExpensesMinor, currency)}.',
      child: SizedBox(
        key: const ValueKey('spending-category-donut'),
        width: 190,
        height: 190,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                centerSpaceRadius: 57,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response?.touchedSection == null) {
                      return;
                    }
                    final index = response!.touchedSection!.touchedSectionIndex;
                    if (index >= 0 && index < totals.length) {
                      onSelected(totals[index].id);
                    }
                  },
                ),
                sections: [
                  for (var index = 0; index < totals.length; index += 1)
                    PieChartSectionData(
                      value: totals[index].amountMinor.toDouble(),
                      color: colors[index % colors.length],
                      radius: selectedCategoryId == totals[index].id ? 36 : 31,
                      showTitle: false,
                      borderSide: selectedCategoryId == totals[index].id
                          ? BorderSide(
                              color: Theme.of(context).colorScheme.surface,
                              width: 2,
                            )
                          : BorderSide.none,
                    ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Expenses',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  child: Text(
                    money(totalExpensesMinor, currency),
                    style: AppTextStyles.money(context, fontSize: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final ranking = Column(
      children: [
        for (var index = 0; index < totals.length; index += 1)
          CategoryReportRow(
            key: ValueKey('report-category-${totals[index].id}'),
            total: totals[index],
            color: colors[index % colors.length],
            currency: currency,
            selected: selectedCategoryId == totals[index].id,
            onTap: () => onSelected(totals[index].id),
            showDivider: index != totals.length - 1,
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 620) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Center(child: chart)),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: ranking),
            ],
          );
        }
        return Column(
          children: [
            chart,
            const SizedBox(height: AppSpacing.sm),
            ranking,
          ],
        );
      },
    );
  }
}

class CategoryReportRow extends StatelessWidget {
  const CategoryReportRow({
    required this.total,
    required this.color,
    required this.currency,
    required this.selected,
    required this.onTap,
    required this.showDivider,
    super.key,
  });

  final CategoryReportTotal total;
  final Color color;
  final CurrencyFormatSettings currency;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final percent = (total.percentage * 100).round();
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.control),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.08)
              : Colors.transparent,
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.45),
                  ),
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              CategoryIconBadge(
                iconName: total.iconName,
                kind: v2_category.CategoryKind.expense,
                colorValue: total.colorValue,
                semanticLabel: '${total.name} category',
                size: CategoryIconBadgeSize.compact,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  total.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                money(total.amountMinor, currency),
                style: const TextStyle(
                  fontFeatures: [AppTextStyles.tabularFigures],
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 42,
                child: Text(
                  '$percent%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFeatures: const [AppTextStyles.tabularFigures],
                    fontWeight: FontWeight.w700,
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

class MonthlyTrendReport extends StatelessWidget {
  const MonthlyTrendReport({
    required this.totals,
    required this.currency,
    super.key,
  });

  final List<MonthlyReportTotal> totals;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final maxAmount = totals.fold<int>(
      0,
      (maximum, month) =>
          max(maximum, max(month.incomeMinor, month.expensesMinor)),
    );
    final maxY = max(1, maxAmount).toDouble() / 100 * 1.18;
    final chartWidth = max(
      MediaQuery.sizeOf(context).width - 82,
      totals.length * 52.0,
    );

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            ReportLegendDot(color: AppTheme.accent, label: 'Income'),
            SizedBox(width: AppSpacing.lg),
            ReportLegendDot(color: AppTheme.rose, label: 'Expenses'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: monthlyTrendSemantics(totals, currency),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              key: const ValueKey('monthly-trend-chart'),
              width: chartWidth,
              height: 230,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.38),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: maxY / 4,
                        getTitlesWidget: (value, _) => Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Text(
                            compactMoneyAxis(value),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, _) {
                          final index = value.toInt();
                          if (index < 0 || index >= totals.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Text(
                              reportMonthAbbreviation(totals[index].month),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) =>
                          Theme.of(context).colorScheme.inverseSurface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final month = totals[group.x];
                        final label = rodIndex == 0 ? 'Income' : 'Expenses';
                        final amount = rodIndex == 0
                            ? month.incomeMinor
                            : month.expensesMinor;
                        return BarTooltipItem(
                          '$label\n${money(amount, currency)}',
                          TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onInverseSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (var index = 0; index < totals.length; index += 1)
                      BarChartGroupData(
                        x: index,
                        barsSpace: 3,
                        barRods: [
                          BarChartRodData(
                            toY: totals[index].incomeMinor / 100,
                            width: 9,
                            color: AppTheme.accent,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                          BarChartRodData(
                            toY: totals[index].expensesMinor / 100,
                            width: 9,
                            color: AppTheme.rose,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.center,
          children: [
            for (final month in totals)
              Text(
                '${reportMonthAbbreviation(month.month)} net ${money(month.netCashFlowMinor, currency)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: month.netCashFlowMinor < 0
                      ? AppTheme.rose
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class ReportLegendDot extends StatelessWidget {
  const ReportLegendDot({required this.color, required this.label, super.key});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class ReportEmptyState extends StatelessWidget {
  const ReportEmptyState({
    required this.icon,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

List<Color> reportCategoryColors(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return [
    AppTheme.accent,
    AppTheme.blue,
    AppTheme.gold,
    AppTheme.rose,
    const Color(0xFF775AA8),
    isDark ? const Color(0xFF75A184) : const Color(0xFF4F8F5F),
  ];
}

String reportMonthAbbreviation(DateTime month) {
  const labels = [
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
  return labels[month.month - 1];
}

String compactMoneyAxis(double value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K';
  }
  return value.round().toString();
}

String monthlyTrendSemantics(
  List<MonthlyReportTotal> totals,
  CurrencyFormatSettings currency,
) {
  return [
    'Monthly income and expenses.',
    for (final month in totals)
      '${reportMonthAbbreviation(month.month)} ${month.month.year}: income ${money(month.incomeMinor, currency)}, expenses ${money(month.expensesMinor, currency)}, net ${money(month.netCashFlowMinor, currency)}.',
  ].join(' ');
}

class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
    this.showDivider = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return SettingsActionRow(
      key: ValueKey('settings-preference-$label'),
      icon: icon,
      title: label,
      subtitle: labelOf(value),
      showDivider: showDivider,
      onTap: () async {
        final selected = await showPolishedChoicePicker<T>(
          context,
          title: label,
          selected: value,
          choices: [
            for (final item in values)
              PolishedChoice(
                value: item,
                label: labelOf(item),
                leading: Icon(icon),
              ),
          ],
        );
        if (selected != null) onChanged(selected);
      },
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 2,
      ),
      secondary: SettingsRowIcon(icon: icon),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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
    this.subtitle,
    this.trailingText,
    this.showStatusPill = false,
    this.showDivider = true,
    this.destructive = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final bool showStatusPill;
  final bool showDivider;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = destructive ? theme.colorScheme.error : null;
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
        minTileHeight: 66,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        leading: SettingsRowIcon(
          icon: icon,
          color: destructive ? theme.colorScheme.error : AppTheme.accent,
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w800, color: foreground),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.2,
                ),
              ),
        trailing: showStatusPill && trailingText != null
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  trailingText!,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : onTap != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailingText != null) ...[
                    Text(
                      trailingText!,
                      style: TextStyle(
                        color: destructive
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 4),
                  ],
                  Icon(
                    AppIcon.chevronRightRounded,
                    color: destructive
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              )
            : trailingText == null
            ? null
            : Text(
                trailingText!,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
        onTap: onTap,
      ),
    );
  }
}

class SettingsRowIcon extends StatelessWidget {
  const SettingsRowIcon({required this.icon, this.color, super.key});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppTheme.accent;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.09),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: effectiveColor, size: AppIconSize.row),
    );
  }
}

class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
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
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          ...children,
        ],
      ),
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
    await store.restoreBackupDataSet(restored);
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
            CompactEmptyRow(icon: AppIcon.wallet, label: 'No accounts yet'),
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
    final scheduled = store.actionableScheduledTransactions();
    final dueCount = store.scheduledDueOrOverdueCount();
    return AppCard(
      title: 'Scheduled',
      child: Column(
        children: [
          if (dueCount > 0)
            MetricRow(
              label: 'Due today',
              value: '$dueCount',
              icon: AppIcon.notificationImportant,
            ),
          for (final item in scheduled.take(3))
            MetricRow(
              label: item.payee,
              value:
                  '${money(item.type.name == 'expense' ? -item.amountMinor.abs() : item.amountMinor, currency)} · ${dateShort(item.nextDate)}',
              icon: AppIcon.recurrence,
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
    this.onViewAll,
    super.key,
  });

  final bool showAll;
  final String title;
  final int? maxRows;
  final bool compact;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final budgets = store.budgets
        .where((budget) => budget.isVisible)
        .toList(growable: false);
    final archivedBudgets = store.budgets
        .where((budget) => budget.isArchived && !budget.isDeleted)
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
                icon: Icon(AppIcon.add),
                label: Text('Add budget'),
              ),
            ),
            SizedBox(height: 12),
          ],
          if (visibleBudgets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                children: [
                  CompactEmptyRow(
                    icon: AppIcon.pieChart,
                    label: 'No budgets yet',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Create a budget to set a spending limit and track what remains.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted),
                  ),
                  if (showAll) ...[
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () => showBudgetDialog(context),
                      child: const Text('Create Budget'),
                    ),
                  ],
                ],
              ),
            ),
          for (final budget in visibleBudgets)
            BudgetProgressRow(budget: budget),
          if (showAll && archivedBudgets.isNotEmpty) ...[
            const Divider(height: AppSpacing.lg),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Archived (${archivedBudgets.length})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              children: [
                for (final budget in archivedBudgets)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(budget.name),
                    subtitle: Text(budget.period.label),
                    trailing: TextButton(
                      onPressed: () => store.restoreBudget(budget.id),
                      child: const Text('Restore'),
                    ),
                    onTap: () => showBudgetDetails(context, budget),
                  ),
              ],
            ),
          ],
          if (onViewAll != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onViewAll,
                child: const Text('View All Budgets →'),
              ),
            ),
          ],
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
    this.onViewAll,
    super.key,
  });

  final String title;
  final int maxRows;
  final bool compact;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final store = FinanceDataStoreScope.watch(context);
    final transactions = [...store.transactions]
      ..removeWhere((transaction) => transaction.isDeleted)
      ..sort(compareTransactionsNewestFirst);
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
            CompactEmptyRow(
              icon: AppIcon.receipt,
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
          if (onViewAll != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onViewAll,
                child: const Text('View Full Ledger →'),
              ),
            ),
          ],
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
    this.borderRadius,
    super.key,
  });

  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final inheritedShape = Theme.of(context).cardTheme.shape;
    final shape = borderRadius == null
        ? null
        : inheritedShape is RoundedRectangleBorder
        ? inheritedShape.copyWith(
            borderRadius: BorderRadius.circular(borderRadius!),
          )
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius!),
          );
    return Card(
      shape: shape,
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
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _spacedChildren(children),
          );
        }

        // A Wrap aligns every card in a row to that row's tallest card. On
        // iPad and macOS, dashboard cards intentionally vary in height, so
        // that leaves large blank areas below shorter cards. Flow each column
        // independently while retaining the existing visual order.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _spacedChildren([
                    for (
                      var index = column;
                      index < children.length;
                      index += columns
                    )
                      children[index],
                  ]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _spacedChildren(List<Widget> items) => [
    for (var index = 0; index < items.length; index++) ...[
      if (index > 0) const SizedBox(height: AppSpacing.sm),
      items[index],
    ],
  ];
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
      leading: Icon(AppIcon.recurrence, color: AppTheme.accent),
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
    final period = store.budgetPeriodResult(budget);
    final spent = period.spentMinor;
    final remaining = period.remainingMinor;
    final isOver = period.isOverBudget;
    final categorySummary = budgetCategorySummary(store, budget);
    final today = budgetDateKey(DateTime.now());
    final daysLeft = period.window.endExclusive.difference(today).inDays;
    final dateRange = budgetPeriodDateRange(period.window);

    return Dismissible(
      key: ValueKey('budget-swipe-${budget.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.22,
        DismissDirection.endToStart: 0.22,
      },
      background: SwipeActionBackground(
        alignment: Alignment.centerLeft,
        icon: AppIcon.tune,
        label: 'Adjust Budget',
      ),
      secondaryBackground: SwipeActionBackground(
        alignment: Alignment.centerRight,
        icon: AppIcon.edit,
        label: 'Edit  Delete',
        destructive: true,
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.selectionClick();
        await showBudgetActions(
          context,
          budget,
          allowedActions: direction == DismissDirection.startToEnd
              ? const {'adjust'}
              : const {'edit', 'delete'},
        );
        return false;
      },
      child: InkWell(
        onTap: () => showBudgetDetails(context, budget),
        onLongPress: () {
          AppHaptics.longPressAction();
          showBudgetActions(context, budget);
        },
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
                '${period.configuration.period.label} · $dateRange',
                style: const TextStyle(color: AppTheme.muted),
              ),
              const SizedBox(height: 4),
              Text(
                '${money(spent, currency)} spent of ${money(period.availableMinor, currency)} available',
                style: const TextStyle(color: AppTheme.muted),
              ),
              const SizedBox(height: 4),
              Text(
                spent == 0
                    ? 'No spending yet this period'
                    : isOver
                    ? '${money(remaining.abs(), currency)} over budget'
                    : '${money(remaining, currency)} remaining',
                style: TextStyle(
                  color: isOver ? AppTheme.rose : AppTheme.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  categorySummary,
                  if (daysLeft > 0)
                    '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left'
                  else if (daysLeft == 0)
                    'Ends today',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: const TextStyle(color: AppTheme.muted),
              ),
              const SizedBox(height: 8),
              BudgetProgressBar(
                spentMinor: spent,
                budgetMinor: period.availableMinor,
              ),
              if (period.configuration.rolloverEnabled &&
                  period.rolloverInMinor != 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Includes ${money(period.rolloverInMinor, currency)} rollover',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String budgetCategorySummary(FinanceDataStore store, BudgetRecord budget) {
  final categoryIds = const BudgetCalculator()
      .configurationAt(budget, DateTime.now())
      .categoryIds;
  if (categoryIds.isEmpty) return 'No categories selected';
  final categoriesById = {
    for (final category in store.categories) category.id: category,
  };
  final names = [
    for (final categoryId in categoryIds)
      categoriesById[categoryId]?.name ?? 'Unknown category',
  ];
  final visibleNames = names.take(3).join(', ');
  final hiddenCount = names.length - 3;
  if (hiddenCount <= 0) return 'Categories: $visibleNames';
  return 'Categories: $visibleNames, +$hiddenCount more';
}

String budgetPeriodDateRange(BudgetPeriodWindow window) {
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
  final end = window.endExclusive.subtract(const Duration(days: 1));
  if (window.start.year == end.year && window.start.month == end.month) {
    return '${months[window.start.month - 1]} ${window.start.day}–${end.day}';
  }
  if (window.start.year == end.year) {
    return '${months[window.start.month - 1]} ${window.start.day}–'
        '${months[end.month - 1]} ${end.day}';
  }
  return '${months[window.start.month - 1]} ${window.start.day}, '
      '${window.start.year}–${months[end.month - 1]} ${end.day}, ${end.year}';
}

String budgetPeriodAnchorDescription(BudgetPeriod period, DateTime startDate) {
  return switch (period) {
    BudgetPeriod.weekly =>
      'Each week begins on ${budgetWeekdayLabel(startDate.weekday)}.',
    BudgetPeriod.biweekly => 'Each period lasts 14 days from this start date.',
    BudgetPeriod.monthly =>
      'Each month begins on day ${startDate.day}; shorter months use their final day.',
    BudgetPeriod.quarterly =>
      'Each 3-month period begins on this date; shorter months use their final day.',
    BudgetPeriod.yearly =>
      'Each year begins on this month and day; shorter dates use their final day.',
  };
}

String budgetWeekdayLabel(int weekday) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];

class _BudgetFormResult {
  const _BudgetFormResult({
    required this.name,
    required this.amountMinor,
    required this.categoryIds,
    required this.period,
    required this.startDate,
    required this.rolloverEnabled,
    required this.includeSubcategories,
    required this.lowBudgetAlertEnabled,
    required this.note,
  });

  final String name;
  final int amountMinor;
  final List<String> categoryIds;
  final BudgetPeriod period;
  final DateTime startDate;
  final bool rolloverEnabled;
  final bool includeSubcategories;
  final bool lowBudgetAlertEnabled;
  final String note;
}

enum _BudgetEditScope { thisPeriod, thisAndFuture, nextPeriod }

Future<void> showBudgetDetails(
  BuildContext context,
  BudgetRecord budget,
) async {
  final store = FinanceDataStoreScope.read(context);
  final currency = store.preferences.currency;
  final history = store.budgetHistoryThrough(budget);
  var periodIndex = history.length - 1;

  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final period = history[periodIndex];
        final remaining = period.remainingMinor;
        final current = periodIndex == history.length - 1;
        final categoriesById = {
          for (final category in store.categories) category.id: category,
        };
        final categoryNames = period.configuration.categoryIds
            .map((id) => categoriesById[id]?.name ?? 'Unknown category')
            .join(', ');
        final today = budgetDateKey(DateTime.now());
        final daysLeft = current
            ? period.window.endExclusive.difference(today).inDays
            : 0;

        return TransactionSheetFrame(
          title: 'Budget Details',
          actions: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: budget.isArchived
                      ? null
                      : () => Navigator.pop(dialogContext, 'archive'),
                  icon: Icon(AppIcon.archive),
                  label: const Text('Archive'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: budget.isArchived
                      ? null
                      : () => Navigator.pop(dialogContext, 'edit'),
                  icon: Icon(AppIcon.edit),
                  label: const Text('Edit'),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                budget.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous period',
                    onPressed: periodIndex > 0
                        ? () => setDialogState(() => periodIndex--)
                        : null,
                    icon: Icon(AppIcon.chevronLeft),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          period.configuration.period.label,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          budgetPeriodDateRange(period.window),
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next period',
                    onPressed: periodIndex < history.length - 1
                        ? () => setDialogState(() => periodIndex++)
                        : null,
                    icon: Icon(AppIcon.chevronRight),
                  ),
                ],
              ),
              const TransactionFormDivider(),
              ScheduledTransactionDetailRow(
                icon: AppIcon.category,
                label: period.configuration.categoryIds.length == 1
                    ? 'Category'
                    : 'Categories',
                value: categoryNames,
              ),
              const TransactionFormDivider(),
              ScheduledTransactionDetailRow(
                icon: AppIcon.money,
                label: 'Base budget',
                value: money(period.baseAmountMinor, currency),
                tabularFigures: true,
              ),
              const TransactionFormDivider(),
              ScheduledTransactionDetailRow(
                icon: AppIcon.recurrence,
                label: 'Rollover brought forward',
                value: period.configuration.rolloverEnabled
                    ? money(period.rolloverInMinor, currency)
                    : 'Off',
                tabularFigures: true,
              ),
              const TransactionFormDivider(),
              ScheduledTransactionDetailRow(
                icon: AppIcon.wallet,
                label: 'Available this period',
                value: money(period.availableMinor, currency),
                tabularFigures: true,
              ),
              const TransactionFormDivider(),
              ScheduledTransactionDetailRow(
                icon: AppIcon.expense,
                label: 'Spent',
                value: money(period.spentMinor, currency),
                valueColor: period.spentMinor == 0 ? AppTheme.muted : null,
                tabularFigures: true,
              ),
              const TransactionFormDivider(),
              ScheduledTransactionDetailRow(
                icon: remaining < 0 ? AppIcon.error : AppIcon.check,
                label: remaining < 0 ? 'Over budget' : 'Remaining',
                value: money(remaining.abs(), currency),
                valueColor: remaining < 0 ? AppTheme.rose : AppTheme.accent,
                tabularFigures: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              BudgetProgressBar(
                spentMinor: period.spentMinor,
                budgetMinor: period.availableMinor,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                current && daysLeft > 0
                    ? '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left'
                    : current
                    ? 'Current period'
                    : 'Completed period · Rollover out ${money(period.rolloverOutMinor, currency)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted),
              ),
              const TransactionFormDivider(),
              Text(
                'Transactions this period',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (period.includedTransactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'No spending yet this period',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                )
              else
                for (final included in period.includedTransactions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      included.transaction.payee.trim().isEmpty
                          ? 'Expense'
                          : included.transaction.payee,
                    ),
                    subtitle: Text(dateShort(included.transaction.date)),
                    trailing: Text(
                      money(included.amountMinor, currency),
                      style: const TextStyle(
                        color: AppTheme.rose,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      unawaited(
                        showTransactionDetails(
                          context,
                          included.transaction.id,
                        ),
                      );
                    },
                  ),
              if (budget.note.trim().isNotEmpty) ...[
                const TransactionFormDivider(),
                ScheduledTransactionDetailRow(
                  icon: AppIcon.notes,
                  label: 'Note',
                  value: budget.note,
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  if (!context.mounted || action == null) return;
  if (action == 'edit') {
    await showBudgetDialog(context, budget: budget);
  } else if (action == 'archive') {
    await FinanceDataStoreScope.read(context).archiveBudget(budget.id);
  }
}

Future<void> showBudgetDialog(
  BuildContext context, {
  BudgetRecord? budget,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final calculator = const BudgetCalculator();
  final now = budgetDateKey(DateTime.now());
  final currentConfiguration = budget == null
      ? null
      : calculator.configurationAt(budget, now);
  final name = TextEditingController(text: budget?.name ?? '');
  final note = TextEditingController(text: budget?.note ?? '');
  var amountMinor = currentConfiguration?.amountMinor ?? 0;
  final selectedCategoryIds = {...?currentConfiguration?.categoryIds};
  var period = currentConfiguration?.period ?? BudgetPeriod.monthly;
  var startDate = currentConfiguration == null
      ? now
      : calculator.inferredStartDate(currentConfiguration, date: now);
  var rolloverEnabled = currentConfiguration?.rolloverEnabled ?? false;
  var includeSubcategories = currentConfiguration?.includeSubcategories ?? true;
  var lowBudgetAlertEnabled = budget?.lowBudgetAlertEnabled ?? true;
  final categories = dataStore.categories
      .where(
        (category) =>
            category.isVisible &&
            category.kind == v2_category.CategoryKind.expense,
      )
      .toList(growable: false);

  final result = await showDialog<_BudgetFormResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final theme = Theme.of(context);
        final fieldValueStyle = theme.textTheme.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.15,
        );
        final fieldHintStyle = fieldValueStyle?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        const borderlessDecoration = InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        );

        void saveBudgetResult() {
          Navigator.pop(
            context,
            _BudgetFormResult(
              name: name.text.trim(),
              amountMinor: amountMinor.abs(),
              categoryIds: selectedCategoryIds.toList(),
              period: period,
              startDate: budgetDateKey(startDate),
              rolloverEnabled: rolloverEnabled,
              includeSubcategories: includeSubcategories,
              lowBudgetAlertEnabled: lowBudgetAlertEnabled,
              note: note.text.trim(),
            ),
          );
        }

        final canSave =
            name.text.trim().isNotEmpty &&
            amountMinor > 0 &&
            selectedCategoryIds.isNotEmpty;

        return TransactionSheetFrame(
          title: budget == null ? 'Create Budget' : 'Edit Budget',
          actions: TransactionFormActions(
            onCancel: () => Navigator.pop(context),
            onSave: canSave ? saveBudgetResult : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TransactionFormLabel('Name'),
              Row(
                children: [
                  TransactionFormIcon(AppIcon.pieChart),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: name,
                      decoration: borderlessDecoration.copyWith(
                        hintText: 'Budget name',
                        hintStyle: fieldHintStyle,
                      ),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      style: fieldValueStyle,
                      autofocus: true,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ),
                ],
              ),
              TransactionFormDivider(),
              TransactionFormLabel('Budget amount'),
              Row(
                children: [
                  TransactionFormIcon(AppIcon.money),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AmountEntryField(
                      fieldKey: const ValueKey('budget-amount'),
                      initialMinor: amountMinor,
                      currency: dataStore.preferences.currency,
                      labelText: null,
                      keyboardType: TextInputType.number,
                      decoration: borderlessDecoration,
                      textStyle: fieldValueStyle,
                      onChanged: (value) =>
                          setDialogState(() => amountMinor = value),
                    ),
                  ),
                ],
              ),
              const TransactionFormDivider(),
              Padding(
                padding: const EdgeInsets.only(top: 1, bottom: 2),
                child: Text(
                  'Categories',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                'Choose the expense categories included in this budget.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (var index = 0; index < categories.length; index++) ...[
                CheckboxListTile(
                  key: ValueKey('budget-category-${categories[index].id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -1),
                  secondary: CategoryIconBadge.category(
                    categories[index],
                    size: CategoryIconBadgeSize.form,
                  ),
                  title: Text(categories[index].name, style: fieldValueStyle),
                  value: selectedCategoryIds.contains(categories[index].id),
                  activeColor: AppTheme.accent,
                  onChanged: (value) => setDialogState(() {
                    if (value ?? false) {
                      selectedCategoryIds.add(categories[index].id);
                    } else {
                      selectedCategoryIds.remove(categories[index].id);
                    }
                  }),
                ),
                if (index != categories.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.38,
                    ),
                  ),
              ],
              if (categories.any(
                (category) =>
                    selectedCategoryIds.contains(category.id) &&
                    categories.any(
                      (candidate) =>
                          candidate.parentCategoryId == category.id &&
                          candidate.isVisible,
                    ),
              )) ...[
                const TransactionFormDivider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Include subcategories',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Count spending in child categories too.',
                  ),
                  value: includeSubcategories,
                  onChanged: (value) =>
                      setDialogState(() => includeSubcategories = value),
                ),
              ],
              const TransactionFormDivider(),
              TransactionFormLabel('Start Date'),
              InkWell(
                key: const ValueKey('budget-start-date'),
                onTap: () async {
                  final selected = await pickDateForField(context, startDate);
                  if (selected != null) {
                    setDialogState(() => startDate = selected);
                  }
                },
                child: TransactionFormValueRow(
                  icon: AppIcon.calendar,
                  value: fullMonthDateLabel(startDate),
                  trailing: Icon(AppIcon.chevronDown),
                ),
              ),
              const TransactionFormDivider(),
              TransactionFormLabel('Period'),
              InkWell(
                key: const ValueKey('budget-period'),
                onTap: () async {
                  final selected = await showPolishedChoicePicker(
                    context,
                    title: 'Budget period',
                    selected: period,
                    choices: [
                      for (final value in BudgetPeriod.values)
                        PolishedChoice(
                          value: value,
                          label: value.label,
                          leading: Icon(AppIcon.calendar),
                        ),
                    ],
                  );
                  if (selected != null) {
                    setDialogState(() => period = selected);
                  }
                },
                child: TransactionFormValueRow(
                  icon: AppIcon.calendar,
                  value: period.label,
                  trailing: Icon(AppIcon.chevronDown),
                ),
              ),
              const TransactionFormDivider(),
              Text(
                budgetPeriodAnchorDescription(period, startDate),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const TransactionFormDivider(),
              SwitchListTile.adaptive(
                key: const ValueKey('budget-rollover'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Rollover unused amount',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Unused or overspent amounts carry into the next budget period.',
                ),
                value: rolloverEnabled,
                onChanged: (value) =>
                    setDialogState(() => rolloverEnabled = value),
              ),
              const TransactionFormDivider(),
              SwitchListTile.adaptive(
                key: const ValueKey('budget-low-alert'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Low Budget Alert',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Notify me when 5% remains.'),
                value: lowBudgetAlertEnabled,
                onChanged: (value) =>
                    setDialogState(() => lowBudgetAlertEnabled = value),
              ),
              const TransactionFormDivider(),
              TransactionFormLabel('Note'),
              Row(
                children: [
                  TransactionFormIcon(AppIcon.notes),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: note,
                      decoration: borderlessDecoration.copyWith(
                        hintText: 'Add a note (optional)',
                        hintStyle: fieldHintStyle,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      style: fieldValueStyle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  if (!context.mounted ||
      result == null ||
      result.name.isEmpty ||
      result.amountMinor <= 0 ||
      result.categoryIds.isEmpty) {
    return;
  }
  HapticFeedback.mediumImpact();
  if (budget == null) {
    final id = 'budget_${DateTime.now().microsecondsSinceEpoch}';
    final provisional = BudgetConfigurationRevision(
      id: '${id}_configuration_${DateTime.now().microsecondsSinceEpoch}',
      effectiveDate: now,
      period: result.period,
      amountMinor: result.amountMinor,
      categoryIds: result.categoryIds,
      startDate: result.startDate,
      anchorDate: result.startDate,
      rolloverEnabled: result.rolloverEnabled,
      includeSubcategories: result.includeSubcategories,
    );
    final effectiveDate = calculator
        .periodWindowContaining(provisional, now)
        .start;
    final configuration = provisional.copyWith(effectiveDate: effectiveDate);
    await dataStore.saveBudget(
      BudgetRecord(
        id: id,
        name: result.name,
        period: result.period,
        amountMinor: result.amountMinor,
        categoryIds: result.categoryIds,
        startDate: configuration.startDate,
        anchorDate: configuration.anchorDate,
        rolloverEnabled: result.rolloverEnabled,
        includeSubcategories: result.includeSubcategories,
        lowBudgetAlertEnabled: result.lowBudgetAlertEnabled,
        note: result.note,
        configurationRevisions: [configuration],
        sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
      ),
    );
    return;
  }

  final structuralChange =
      result.period != currentConfiguration!.period ||
      !isSameCalendarDay(
        result.startDate,
        calculator.inferredStartDate(currentConfiguration, date: now),
      );
  final financialChange =
      result.amountMinor != currentConfiguration.amountMinor ||
      !_sameStringSet(result.categoryIds, currentConfiguration.categoryIds) ||
      result.rolloverEnabled != currentConfiguration.rolloverEnabled ||
      result.includeSubcategories != currentConfiguration.includeSubcategories;
  var scope = _BudgetEditScope.thisAndFuture;
  if (structuralChange) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change future budget periods?'),
        content: const Text(
          'The new period structure will begin after the current period. '
          'Completed budget history will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Begin Next Period'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    scope = _BudgetEditScope.nextPeriod;
  } else if (financialChange) {
    if (!context.mounted) return;
    final selected = await showPolishedChoicePicker<_BudgetEditScope>(
      context,
      title: 'Apply changes to',
      selected: _BudgetEditScope.thisAndFuture,
      choices: const [
        PolishedChoice(
          value: _BudgetEditScope.thisPeriod,
          label: 'This period only',
        ),
        PolishedChoice(
          value: _BudgetEditScope.thisAndFuture,
          label: 'This and future periods',
        ),
      ],
    );
    if (selected == null) return;
    scope = selected;
  }

  final currentWindow = calculator.periodWindowContaining(
    currentConfiguration,
    now,
  );
  final changedDraft = currentConfiguration.copyWith(
    id: '${budget.id}_configuration_${DateTime.now().microsecondsSinceEpoch}',
    period: result.period,
    amountMinor: result.amountMinor,
    categoryIds: result.categoryIds,
    startDate: result.startDate,
    anchorDate: result.startDate,
    rolloverEnabled: result.rolloverEnabled,
    includeSubcategories: result.includeSubcategories,
  );
  final changeEffectiveDate = scope == _BudgetEditScope.nextPeriod
      ? calculator.firstPeriodStartOnOrAfter(
          changedDraft,
          currentWindow.endExclusive,
        )
      : currentWindow.start;
  final changed = changedDraft.copyWith(effectiveDate: changeEffectiveDate);
  final revisions = calculator.normalizedRevisions(budget).where((revision) {
    final effective = budgetDateKey(revision.effectiveDate);
    if (scope == _BudgetEditScope.nextPeriod) {
      return effective.isBefore(changeEffectiveDate);
    }
    if (scope == _BudgetEditScope.thisPeriod) {
      return effective.isBefore(currentWindow.start) ||
          !effective.isBefore(currentWindow.endExclusive);
    }
    return effective.isBefore(currentWindow.start);
  }).toList();
  revisions.add(changed);
  final hasNextBoundary = revisions.any(
    (revision) =>
        isSameCalendarDay(revision.effectiveDate, currentWindow.endExclusive),
  );
  if (scope == _BudgetEditScope.thisPeriod && !hasNextBoundary) {
    revisions.add(
      currentConfiguration.copyWith(
        id: '${budget.id}_configuration_revert_${DateTime.now().microsecondsSinceEpoch}',
        effectiveDate: currentWindow.endExclusive,
      ),
    );
  }
  revisions.sort(
    (left, right) => left.effectiveDate.compareTo(right.effectiveDate),
  );
  final latest = revisions.last;
  await dataStore.saveBudget(
    budget.copyWith(
      name: result.name,
      period: latest.period,
      amountMinor: latest.amountMinor,
      categoryIds: latest.categoryIds,
      startDate: latest.startDate,
      anchorDate: latest.anchorDate,
      weekStartDay: latest.weekStartDay,
      rolloverEnabled: latest.rolloverEnabled,
      includeSubcategories: latest.includeSubcategories,
      lowBudgetAlertEnabled: result.lowBudgetAlertEnabled,
      note: result.note,
      configurationRevisions: revisions,
    ),
  );
}

bool _sameStringSet(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

Future<void> showBudgetActions(
  BuildContext context,
  BudgetRecord budget, {
  Set<String>? allowedActions,
}) async {
  bool allows(String action) =>
      allowedActions == null || allowedActions.contains(action);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allows('adjust'))
            ListTile(
              leading: Icon(AppIcon.tune),
              title: Text('Adjust Budget'),
              onTap: () => Navigator.pop(sheetContext, 'adjust'),
            ),
          if (allows('edit'))
            ListTile(
              leading: Icon(AppIcon.edit),
              title: Text('Edit'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
          if (allows('archive'))
            ListTile(
              leading: Icon(AppIcon.archive),
              title: Text('Archive'),
              onTap: () => Navigator.pop(sheetContext, 'archive'),
            ),
          if (allows('delete'))
            ListTile(
              leading: Icon(AppIcon.delete),
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
    case 'adjust':
      await showBudgetDialog(context, budget: budget);
    case 'edit':
      await showBudgetDialog(context, budget: budget);
    case 'archive':
      await FinanceDataStoreScope.read(context).archiveBudget(budget.id);
    case 'delete':
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete budget?'),
          content: const Text(
            'This removes the budget and its derived history. '
            'Your ledger transactions will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.rose),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete Budget'),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        await FinanceDataStoreScope.read(context).deleteBudget(budget.id);
      }
  }
}

Future<void> showAdjustBalanceDialog(
  BuildContext context,
  v2_account.AccountRecord account,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final isCreditCard = account.group == v2_account.AccountGroup.creditCards;
  final currentBalanceMinor = dataStore.balanceForAccount(account.id);
  var enteredBalanceMinor = isCreditCard
      ? currentBalanceMinor.abs()
      : currentBalanceMinor;
  var isDebtBalance = currentBalanceMinor <= 0;

  final value = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final targetBalanceMinor = isCreditCard
            ? (isDebtBalance
                  ? -enteredBalanceMinor.abs()
                  : enteredBalanceMinor.abs())
            : enteredBalanceMinor;
        final adjustmentMinor = targetBalanceMinor - currentBalanceMinor;
        final amountStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          color: targetBalanceMinor < 0 ? AppTheme.rose : null,
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w900,
        );

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              MediaQuery.viewInsetsOf(sheetContext).bottom + AppSpacing.lg,
            ),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Adjust Balance',
                    style: Theme.of(sheetContext).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    account.name,
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Current balance: ${money(currentBalanceMinor, dataStore.preferences.currency)}',
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (isCreditCard) ...[
                    DialogFieldGroup(
                      label: 'Balance type',
                      child: SegmentedButton<bool>(
                        segments: [
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Debt'),
                            icon: Icon(AppIcon.expense),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Credit'),
                            icon: Icon(AppIcon.income),
                          ),
                        ],
                        selected: {isDebtBalance},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) {
                          HapticFeedback.selectionClick();
                          setSheetState(() => isDebtBalance = selection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  DialogFieldGroup(
                    label: 'New balance',
                    child: AmountEntryField(
                      fieldKey: const ValueKey('account-adjust-balance'),
                      initialMinor: targetBalanceMinor,
                      currency: dataStore.preferences.currency,
                      labelText: null,
                      autofocus: true,
                      selectAllOnFocus: false,
                      allowNegative: !isCreditCard,
                      forceNegative: isCreditCard && isDebtBalance,
                      keyboardType: isCreditCard
                          ? TextInputType.number
                          : const TextInputType.numberWithOptions(signed: true),
                      textStyle: amountStyle,
                      onChanged: (value) {
                        setSheetState(() {
                          enteredBalanceMinor = isCreditCard
                              ? value.abs()
                              : value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Adjustment',
                            style: Theme.of(sheetContext).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        MoneyText(
                          amountMinor: adjustmentMinor,
                          currency: dataStore.preferences.currency,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          showPositiveSign: adjustmentMinor > 0,
                          color: adjustmentMinor < 0 ? AppColors.danger : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          onPressed: targetBalanceMinor == currentBalanceMinor
                              ? null
                              : () => Navigator.pop(
                                  sheetContext,
                                  targetBalanceMinor,
                                ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  if (value == null) return;
  await dataStore.adjustAccountBalance(
    accountId: account.id,
    targetBalanceMinor: value,
    date: DateTime.now(),
  );
}

Future<void> showAccountOptions(
  BuildContext context,
  String accountId, {
  Set<String>? allowedActions,
}) async {
  bool allows(String action) =>
      allowedActions == null || allowedActions.contains(action);
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
            if (allows('expense'))
              ListTile(
                leading: Icon(AppIcon.expense),
                title: Text('Add Expense'),
                onTap: () => Navigator.pop(context, 'expense'),
              ),
            if (allows('income'))
              ListTile(
                leading: Icon(AppIcon.income),
                title: const Text('Add Income'),
                onTap: () => Navigator.pop(context, 'income'),
              ),
            if (allows('transfer'))
              ListTile(
                enabled: dataStore.activeAccountsInDisplayOrder.length > 1,
                leading: Icon(AppIcon.transfer),
                title: const Text('Transfer'),
                onTap: dataStore.activeAccountsInDisplayOrder.length > 1
                    ? () => Navigator.pop(context, 'transfer')
                    : null,
              ),
            if (allows('adjust'))
              ListTile(
                leading: Icon(AppIcon.tune),
                title: Text('Adjust Balance'),
                onTap: () => Navigator.pop(context, 'adjust'),
              ),
            if (allows('moveUp'))
              ListTile(
                enabled: canMoveUp,
                leading: Icon(AppIcon.arrowUp),
                title: const Text('Move Up'),
                onTap: canMoveUp
                    ? () => Navigator.pop(context, 'moveUp')
                    : null,
              ),
            if (allows('moveDown'))
              ListTile(
                enabled: canMoveDown,
                leading: Icon(AppIcon.arrowDown),
                title: const Text('Move Down'),
                onTap: canMoveDown
                    ? () => Navigator.pop(context, 'moveDown')
                    : null,
              ),
            if (allows('changeType'))
              ListTile(
                leading: Icon(AppIcon.categoryGroup),
                title: Text('Change Type'),
                onTap: () => Navigator.pop(context, 'changeType'),
              ),
            if (allows('edit'))
              ListTile(
                leading: Icon(AppIcon.edit),
                title: Text('Edit'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (allows('archive'))
              ListTile(
                leading: Icon(AppIcon.archive),
                title: Text('Archive'),
                onTap: () => Navigator.pop(context, 'archive'),
              ),
            if (allows('delete'))
              ListTile(
                leading: Icon(AppIcon.delete),
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
    final funded = dataStore.goalFundingEvents
        .where((event) => event.isActive && event.sourceAccountId == account.id)
        .fold<int>(0, (total, event) => total + event.totalAmountMinor.abs());
    final isDefaultGoalAccount = dataStore.goals.any(
      (goal) => !goal.isDeleted && goal.defaultFundingAccountId == account.id,
    );
    if ((funded > 0 || isDefaultGoalAccount) &&
        !await confirmDeleteGoalFundingAccount(
          context,
          account: account,
          fundedMinor: funded,
        )) {
      return;
    }
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
                  ? Icon(AppIcon.check, color: AppTheme.accent)
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
      clearCreditInsights: selectedType != v2_account.AccountType.creditCard,
      clearOriginalLoanAmount: selectedType != v2_account.AccountType.loan,
    ),
  );
}

Future<void> showCreditInsightsInfoDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('About Credit Insights'),
      content: const Text(
        'Credit Insights estimates your upcoming interest using your APR, '
        'statement closing date, and recorded transactions.\n\n'
        'If your transactions are entered accurately, the estimate will '
        'generally be close. Actual interest may differ because card issuers '
        'may use different calculation methods.\n\n'
        'Credit Insights is designed to help you understand your credit card '
        'costs and projected statement balance. It is an estimate and should '
        'not replace your card issuer’s official statement.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class CreditInsightsFormSection extends StatefulWidget {
  const CreditInsightsFormSection({
    required this.enabled,
    required this.onEnabledChanged,
    required this.aprController,
    required this.statementClosingDayController,
    required this.paymentDueDayController,
    required this.fieldValueStyle,
    required this.fieldHintStyle,
    required this.decoration,
    super.key,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final TextEditingController aprController;
  final TextEditingController statementClosingDayController;
  final TextEditingController paymentDueDayController;
  final TextStyle? fieldValueStyle;
  final TextStyle? fieldHintStyle;
  final InputDecoration decoration;

  @override
  State<CreditInsightsFormSection> createState() =>
      _CreditInsightsFormSectionState();
}

class _CreditInsightsFormSectionState extends State<CreditInsightsFormSection> {
  final _aprFocusNode = FocusNode(debugLabel: 'credit-insights-apr');
  final _statementDayFocusNode = FocusNode(
    debugLabel: 'credit-insights-statement-day',
  );
  final _paymentDueDayFocusNode = FocusNode(
    debugLabel: 'credit-insights-payment-due-day',
  );

  @override
  void didUpdateWidget(CreditInsightsFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled) _aprFocusNode.requestFocus();
      });
    } else if (oldWidget.enabled && !widget.enabled) {
      _aprFocusNode.unfocus();
      _statementDayFocusNode.unfocus();
      _paymentDueDayFocusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _aprFocusNode.dispose();
    _statementDayFocusNode.dispose();
    _paymentDueDayFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('credit-insights-fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: TransactionFormLabel('Credit Insights')),
            IconButton(
              tooltip: 'About Credit Insights',
              icon: Icon(AppIcon.info, size: AppIconSize.inline),
              onPressed: () => showCreditInsightsInfoDialog(context),
            ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: TransactionFormIcon(AppIcon.insights),
          title: Text('Enable Credit Insights', style: widget.fieldValueStyle),
          value: widget.enabled,
          onChanged: widget.onEnabledChanged,
        ),
        AnimatedSize(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 165),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: widget.enabled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TransactionFormDivider(),
                    _CreditInsightsTextField(
                      fieldKey: const ValueKey('credit-insights-apr'),
                      label: 'APR',
                      controller: widget.aprController,
                      focusNode: _aprFocusNode,
                      hintText: 'Enter APR (%)',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _statementDayFocusNode.requestFocus(),
                      fieldValueStyle: widget.fieldValueStyle,
                      fieldHintStyle: widget.fieldHintStyle,
                      decoration: widget.decoration,
                    ),
                    const TransactionFormDivider(),
                    _CreditInsightsTextField(
                      fieldKey: const ValueKey(
                        'credit-insights-statement-closing-day',
                      ),
                      label: 'Statement Closing Day',
                      controller: widget.statementClosingDayController,
                      focusNode: _statementDayFocusNode,
                      hintText: 'Enter day (1–31)',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) =>
                          _paymentDueDayFocusNode.requestFocus(),
                      fieldValueStyle: widget.fieldValueStyle,
                      fieldHintStyle: widget.fieldHintStyle,
                      decoration: widget.decoration,
                    ),
                    const TransactionFormDivider(),
                    _CreditInsightsTextField(
                      fieldKey: const ValueKey(
                        'credit-insights-payment-due-day',
                      ),
                      label: 'Payment Due Day',
                      controller: widget.paymentDueDayController,
                      focusNode: _paymentDueDayFocusNode,
                      hintText: 'Enter day (1–31)',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _paymentDueDayFocusNode.unfocus(),
                      fieldValueStyle: widget.fieldValueStyle,
                      fieldHintStyle: widget.fieldHintStyle,
                      decoration: widget.decoration,
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CreditInsightsTextField extends StatelessWidget {
  const _CreditInsightsTextField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.keyboardType,
    required this.textInputAction,
    required this.onSubmitted,
    required this.fieldValueStyle,
    required this.fieldHintStyle,
    required this.decoration,
    this.inputFormatters,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String> onSubmitted;
  final TextStyle? fieldValueStyle;
  final TextStyle? fieldHintStyle;
  final InputDecoration decoration;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TransactionFormIcon(AppIcon.numbers),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: fieldValueStyle),
              TextField(
                key: fieldKey,
                controller: controller,
                focusNode: focusNode,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                onSubmitted: onSubmitted,
                inputFormatters: inputFormatters,
                decoration: decoration.copyWith(
                  hintText: hintText,
                  hintStyle: fieldHintStyle,
                ),
                style: fieldValueStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

({double apr, int statementClosingDay, int paymentDueDay})?
validCreditInsightsValues({
  required bool enabled,
  required TextEditingController aprController,
  required TextEditingController statementClosingDayController,
  required TextEditingController paymentDueDayController,
}) {
  if (!enabled) return (apr: 0, statementClosingDay: 0, paymentDueDay: 0);
  final apr = double.tryParse(aprController.text.trim());
  final statementDay = int.tryParse(statementClosingDayController.text.trim());
  final dueDay = int.tryParse(paymentDueDayController.text.trim());
  if (apr == null ||
      apr < 0 ||
      statementDay == null ||
      statementDay < 1 ||
      statementDay > 31 ||
      dueDay == null ||
      dueDay < 1 ||
      dueDay > 31) {
    return null;
  }
  return (apr: apr, statementClosingDay: statementDay, paymentDueDay: dueDay);
}

Future<void> showCreditInsightsValidationDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Complete Credit Insights'),
      content: const Text(
        'Enter an APR and valid statement closing and payment due days from 1 to 31.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Owns form controllers for the lifetime of a dialog route.  The route can
/// remain mounted for its exit animation after [showDialog] has returned, so
/// disposing from the route subtree avoids a text field observing a disposed
/// controller during that final transition.
class _AccountFormControllerScope extends StatefulWidget {
  const _AccountFormControllerScope({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_AccountFormControllerScope> createState() =>
      _AccountFormControllerScopeState();
}

class _AccountFormControllerScopeState
    extends State<_AccountFormControllerScope> {
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

Future<void> showEditAccountDialog(
  BuildContext context,
  v2_account.AccountRecord account,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final name = TextEditingController(text: account.name);
  final annualPercentageRate = TextEditingController(
    text: account.annualPercentageRate?.toStringAsFixed(2) ?? '',
  );
  final statementClosingDay = TextEditingController(
    text: account.statementClosingDay?.toString() ?? '',
  );
  final paymentDueDay = TextEditingController(
    text: account.paymentDueDay?.toString() ?? '',
  );
  var creditLimitMinor = account.creditLimitMinor ?? 0;
  var interestEstimationEnabled = account.interestEstimationEnabled;
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
          bool interestEstimationEnabled,
          double? annualPercentageRate,
          int? statementClosingDay,
          int? paymentDueDay,
          int? originalLoanAmountMinor,
          bool includeInGroupBalance,
          bool includeInNetWorth,
        })
      >(
        context: context,
        builder: (context) => _AccountFormControllerScope(
          controllers: [
            name,
            annualPercentageRate,
            statementClosingDay,
            paymentDueDay,
          ],
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final theme = Theme.of(context);
              final fieldValueStyle = theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
                height: 1.15,
              );
              final fieldHintStyle = fieldValueStyle?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              );
              const borderlessDecoration = InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              );

              void saveAccountResult() {
                final insights = validCreditInsightsValues(
                  enabled:
                      type == v2_account.AccountType.creditCard &&
                      interestEstimationEnabled,
                  aprController: annualPercentageRate,
                  statementClosingDayController: statementClosingDay,
                  paymentDueDayController: paymentDueDay,
                );
                if (insights == null) {
                  unawaited(showCreditInsightsValidationDialog(context));
                  return;
                }
                Navigator.pop(context, (
                  name: name.text.trim().isEmpty
                      ? account.name
                      : name.text.trim(),
                  type: type,
                  creditLimitMinor: type == v2_account.AccountType.creditCard
                      ? optionalPositiveMinor(creditLimitMinor)
                      : null,
                  interestEstimationEnabled:
                      type == v2_account.AccountType.creditCard &&
                      interestEstimationEnabled,
                  annualPercentageRate:
                      type == v2_account.AccountType.creditCard &&
                          interestEstimationEnabled
                      ? insights.apr
                      : null,
                  statementClosingDay:
                      type == v2_account.AccountType.creditCard &&
                          interestEstimationEnabled
                      ? insights.statementClosingDay
                      : null,
                  paymentDueDay:
                      type == v2_account.AccountType.creditCard &&
                          interestEstimationEnabled
                      ? insights.paymentDueDay
                      : null,
                  originalLoanAmountMinor: type == v2_account.AccountType.loan
                      ? optionalPositiveMinor(originalLoanAmountMinor)
                      : null,
                  includeInGroupBalance: includeInGroupBalance,
                  includeInNetWorth: includeInNetWorth,
                ));
              }

              return TransactionSheetFrame(
                title: 'Edit Account',
                actions: TransactionFormActions(
                  onCancel: () => Navigator.pop(context),
                  onSave: saveAccountResult,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TransactionFormLabel('Name'),
                    Row(
                      children: [
                        TransactionFormIcon(AppIcon.wallet),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextField(
                            controller: name,
                            decoration: borderlessDecoration.copyWith(
                              hintText: 'Account name',
                              hintStyle: fieldHintStyle,
                            ),
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            style: fieldValueStyle,
                            autofocus: true,
                          ),
                        ),
                      ],
                    ),
                    const TransactionFormDivider(),
                    const TransactionFormLabel('Type'),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      onTap: () async {
                        FocusManager.instance.primaryFocus?.unfocus();
                        final selectedType = await showV2AccountTypePicker(
                          context,
                          selected: type,
                        );
                        if (selectedType != null) {
                          setDialogState(() => type = selectedType);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            TransactionFormIcon(v2AccountIcon(type)),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                v2AccountTypeLabel(type),
                                style: fieldValueStyle,
                              ),
                            ),
                            Icon(AppIcon.chevronDown, size: AppIconSize.hero),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: MediaQuery.of(context).disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 165),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          alignment: Alignment.topCenter,
                          child: child,
                        ),
                      ),
                      child: type == v2_account.AccountType.creditCard
                          ? Column(
                              key: const ValueKey('credit-limit-field'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TransactionFormDivider(),
                                TransactionFormLabel('Credit limit'),
                                Row(
                                  children: [
                                    TransactionFormIcon(AppIcon.creditCard),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: AmountEntryField(
                                        fieldKey: const ValueKey(
                                          'account-credit-limit',
                                        ),
                                        initialMinor: creditLimitMinor,
                                        currency:
                                            dataStore.preferences.currency,
                                        labelText: null,
                                        keyboardType: TextInputType.number,
                                        decoration: borderlessDecoration,
                                        textStyle: fieldValueStyle,
                                        onChanged: (value) =>
                                            creditLimitMinor = value.abs(),
                                      ),
                                    ),
                                  ],
                                ),
                                const TransactionFormDivider(),
                                CreditInsightsFormSection(
                                  enabled: interestEstimationEnabled,
                                  onEnabledChanged: (value) => setDialogState(
                                    () => interestEstimationEnabled = value,
                                  ),
                                  aprController: annualPercentageRate,
                                  statementClosingDayController:
                                      statementClosingDay,
                                  paymentDueDayController: paymentDueDay,
                                  fieldValueStyle: fieldValueStyle,
                                  fieldHintStyle: fieldHintStyle,
                                  decoration: borderlessDecoration,
                                ),
                              ],
                            )
                          : type == v2_account.AccountType.loan
                          ? Column(
                              key: const ValueKey('loan-amount-field'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const TransactionFormDivider(),
                                TransactionFormLabel('Original loan amount'),
                                Row(
                                  children: [
                                    TransactionFormIcon(AppIcon.loan),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: AmountEntryField(
                                        fieldKey: const ValueKey(
                                          'account-original-loan-amount',
                                        ),
                                        initialMinor: originalLoanAmountMinor,
                                        currency:
                                            dataStore.preferences.currency,
                                        labelText: null,
                                        keyboardType: TextInputType.number,
                                        decoration: borderlessDecoration,
                                        textStyle: fieldValueStyle,
                                        onChanged: (value) =>
                                            originalLoanAmountMinor = value
                                                .abs(),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('no-account-extra-field'),
                            ),
                    ),
                    TransactionFormDivider(),
                    TransactionFormLabel('Balance options'),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: TransactionFormIcon(AppIcon.bank),
                      title: Text(
                        'Include in group balance',
                        style: fieldValueStyle,
                      ),
                      value: includeInGroupBalance,
                      onChanged: (value) =>
                          setDialogState(() => includeInGroupBalance = value),
                    ),
                    Divider(
                      height: 1,
                      indent: 56,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.38,
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: TransactionFormIcon(AppIcon.pieChart),
                      title: Text(
                        'Include in net worth',
                        style: fieldValueStyle,
                      ),
                      value: includeInNetWorth,
                      onChanged: (value) =>
                          setDialogState(() => includeInNetWorth = value),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  if (result == null) return;
  await dataStore.saveAccount(
    account.copyWith(
      name: result.name,
      type: result.type,
      creditLimitMinor: result.creditLimitMinor,
      interestEstimationEnabled: result.interestEstimationEnabled,
      annualPercentageRate: result.annualPercentageRate,
      statementClosingDay: result.statementClosingDay,
      paymentDueDay: result.paymentDueDay,
      originalLoanAmountMinor: result.originalLoanAmountMinor,
      clearCreditLimit: result.creditLimitMinor == null,
      clearCreditInsights: result.type != v2_account.AccountType.creditCard,
      clearOriginalLoanAmount: result.originalLoanAmountMinor == null,
      includeInGroupBalance: result.includeInGroupBalance,
      includeInNetWorth: result.includeInNetWorth,
    ),
  );
}

Future<void> showFloatingAddMenu(
  BuildContext context, {
  FinanceSection? section,
  PlanSegment? planSegment,
  String? initialAccountId,
  DateTime? initialScheduledDate,
}) async {
  final isScheduled = section == FinanceSection.scheduled;
  final orderedActions = isScheduled
      ? const ['expense', 'income', 'transfer', 'goalFunding']
      : switch (section) {
          FinanceSection.plan when planSegment == PlanSegment.goals => const [
            'goal',
            'goalFunding',
          ],
          FinanceSection.plan => const ['budget'],
          FinanceSection.accounts => const [
            'account',
            'expense',
            'income',
            'transfer',
            'category',
            'scheduled',
          ],
          _ => const [
            'expense',
            'income',
            'transfer',
            'goalFunding',
            'account',
            'category',
            'scheduled',
          ],
        };

  FloatingActionMenuItem itemFor(String action) {
    return switch (action) {
      'expense' => FloatingActionMenuItem(
        label: 'Expense',
        leading: Icon(AppIcon.expense),
        onSelected: () => Navigator.pop(context, 'expense'),
      ),
      'income' => FloatingActionMenuItem(
        label: 'Income',
        leading: Icon(AppIcon.income),
        onSelected: () => Navigator.pop(context, 'income'),
      ),
      'transfer' => FloatingActionMenuItem(
        label: 'Transfer',
        leading: Icon(AppIcon.transfer),
        onSelected: () => Navigator.pop(context, 'transfer'),
      ),
      'account' => FloatingActionMenuItem(
        label: 'Account',
        leading: Icon(AppIcon.wallet),
        onSelected: () => Navigator.pop(context, 'account'),
      ),
      'budget' => FloatingActionMenuItem(
        label: 'Budget',
        leading: Icon(AppIcon.pieChart),
        onSelected: () => Navigator.pop(context, 'budget'),
      ),
      'goal' => FloatingActionMenuItem(
        label: 'Create Goal',
        leading: Icon(AppIcon.goal),
        onSelected: () => Navigator.pop(context, 'goal'),
      ),
      'goalFunding' => FloatingActionMenuItem(
        label: 'Fund Goals',
        leading: Icon(AppIcon.savings),
        onSelected: () => Navigator.pop(context, 'goalFunding'),
      ),
      'category' => FloatingActionMenuItem(
        label: 'Category',
        leading: Icon(AppIcon.category),
        onSelected: () => Navigator.pop(context, 'category'),
      ),
      _ => FloatingActionMenuItem(
        label: 'Scheduled Transaction',
        leading: Icon(AppIcon.recurrence),
        onSelected: () => Navigator.pop(context, 'scheduled'),
      ),
    };
  }

  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: MoneyTallyFloatingActionMenu(
        items: [for (final action in orderedActions) itemFor(action)],
      ),
    ),
  );

  if (!context.mounted || selected == null) return;
  HapticFeedback.selectionClick();
  final store = FinanceDataStoreScope.read(context);
  switch (selected) {
    case 'expense':
      if (isScheduled) {
        await showScheduledTransactionDialog(
          context,
          initialType: TransactionType.expense,
          initialDate: initialScheduledDate,
        );
      } else {
        await showTransactionDialog(
          context,
          initialIsExpense: true,
          initialAccountId:
              initialAccountId ?? resolvedDefaultTransactionAccountId(store),
        );
      }
    case 'income':
      if (isScheduled) {
        await showScheduledTransactionDialog(
          context,
          initialType: TransactionType.income,
          initialDate: initialScheduledDate,
        );
      } else {
        await showTransactionDialog(
          context,
          initialIsExpense: false,
          initialAccountId:
              initialAccountId ?? resolvedDefaultTransactionAccountId(store),
        );
      }
    case 'category':
      await showCategoryDialog(context);
    case 'account':
      await showAccountDialog(context);
    case 'transfer':
      if (isScheduled) {
        await showScheduledTransactionDialog(
          context,
          initialType: TransactionType.transfer,
          initialDate: initialScheduledDate,
        );
      } else {
        await showTransferDialog(
          context,
          initialFromAccountId:
              initialAccountId ?? resolvedDefaultTransferSourceAccountId(store),
        );
      }
    case 'budget':
      await showBudgetDialog(context);
    case 'goal':
      await showCreateGoalSheet(context);
    case 'goalFunding':
      if (isScheduled) {
        await showScheduledGoalFundingDialog(
          context,
          initialDate: initialScheduledDate,
        );
      } else {
        await showFundGoalsSheet(context);
      }
    case 'scheduled':
      await showScheduledTransactionDialog(
        context,
        initialDate: initialScheduledDate,
      );
  }
}

Future<void> showAccountDialog(BuildContext context) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final name = TextEditingController();
  final annualPercentageRate = TextEditingController();
  final statementClosingDay = TextEditingController();
  final paymentDueDay = TextEditingController();
  var creditLimitMinor = 0;
  var interestEstimationEnabled = false;
  var originalLoanAmountMinor = 0;
  var type = AccountType.checking;
  var openingBalanceCents = 0;
  var includeInGroupBalance =
      dataStore.preferences.newAccountIncludeInGroupBalance;
  var includeInNetWorth = dataStore.preferences.newAccountIncludeInNetWorth;

  final result =
      await showDialog<
        ({
          String name,
          AccountType type,
          int openingBalanceCents,
          int? creditLimitMinor,
          bool interestEstimationEnabled,
          double? annualPercentageRate,
          int? statementClosingDay,
          int? paymentDueDay,
          int? originalLoanAmountMinor,
          bool includeInGroupBalance,
          bool includeInNetWorth,
        })
      >(
        context: context,
        builder: (context) => _AccountFormControllerScope(
          controllers: [
            name,
            annualPercentageRate,
            statementClosingDay,
            paymentDueDay,
          ],
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final theme = Theme.of(context);
              final fieldValueStyle = theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
                height: 1.15,
              );
              final fieldHintStyle = fieldValueStyle?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              );
              const borderlessDecoration = InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              );

              void saveAccountResult() {
                final insights = validCreditInsightsValues(
                  enabled:
                      type == AccountType.creditCard &&
                      interestEstimationEnabled,
                  aprController: annualPercentageRate,
                  statementClosingDayController: statementClosingDay,
                  paymentDueDayController: paymentDueDay,
                );
                if (insights == null) {
                  unawaited(showCreditInsightsValidationDialog(context));
                  return;
                }
                Navigator.pop(context, (
                  name: name.text.trim().isEmpty
                      ? accountTypeLabel(type)
                      : name.text.trim(),
                  type: type,
                  openingBalanceCents: openingBalanceCents,
                  creditLimitMinor: type == AccountType.creditCard
                      ? optionalPositiveMinor(creditLimitMinor)
                      : null,
                  interestEstimationEnabled:
                      type == AccountType.creditCard &&
                      interestEstimationEnabled,
                  annualPercentageRate:
                      type == AccountType.creditCard &&
                          interestEstimationEnabled
                      ? insights.apr
                      : null,
                  statementClosingDay:
                      type == AccountType.creditCard &&
                          interestEstimationEnabled
                      ? insights.statementClosingDay
                      : null,
                  paymentDueDay:
                      type == AccountType.creditCard &&
                          interestEstimationEnabled
                      ? insights.paymentDueDay
                      : null,
                  originalLoanAmountMinor: type == AccountType.loan
                      ? optionalPositiveMinor(originalLoanAmountMinor)
                      : null,
                  includeInGroupBalance: includeInGroupBalance,
                  includeInNetWorth: includeInNetWorth,
                ));
              }

              return TransactionSheetFrame(
                title: 'Add Account',
                actions: TransactionFormActions(
                  onCancel: () => Navigator.pop(context),
                  onSave: saveAccountResult,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TransactionFormLabel('Name'),
                    Row(
                      children: [
                        TransactionFormIcon(AppIcon.wallet),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextField(
                            controller: name,
                            decoration: borderlessDecoration.copyWith(
                              hintText: 'Account name',
                              hintStyle: fieldHintStyle,
                            ),
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            style: fieldValueStyle,
                            autofocus: true,
                          ),
                        ),
                      ],
                    ),
                    const TransactionFormDivider(),
                    const TransactionFormLabel('Type'),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      onTap: () async {
                        FocusManager.instance.primaryFocus?.unfocus();
                        final selectedType = await showAccountTypePicker(
                          context,
                          selected: type,
                        );
                        if (selectedType != null) {
                          setDialogState(() => type = selectedType);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            TransactionFormIcon(accountIcon(type)),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                accountTypeLabel(type),
                                style: fieldValueStyle,
                              ),
                            ),
                            Icon(AppIcon.chevronDown, size: AppIconSize.hero),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: MediaQuery.of(context).disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 165),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          alignment: Alignment.topCenter,
                          child: child,
                        ),
                      ),
                      child: type == AccountType.creditCard
                          ? Column(
                              key: const ValueKey('credit-limit-field'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TransactionFormDivider(),
                                TransactionFormLabel('Credit limit'),
                                Row(
                                  children: [
                                    TransactionFormIcon(AppIcon.creditCard),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: AmountEntryField(
                                        fieldKey: const ValueKey(
                                          'account-credit-limit',
                                        ),
                                        initialMinor: creditLimitMinor,
                                        currency:
                                            dataStore.preferences.currency,
                                        labelText: null,
                                        keyboardType: TextInputType.number,
                                        decoration: borderlessDecoration,
                                        textStyle: fieldValueStyle,
                                        onChanged: (value) =>
                                            creditLimitMinor = value.abs(),
                                      ),
                                    ),
                                  ],
                                ),
                                const TransactionFormDivider(),
                                CreditInsightsFormSection(
                                  enabled: interestEstimationEnabled,
                                  onEnabledChanged: (value) => setDialogState(
                                    () => interestEstimationEnabled = value,
                                  ),
                                  aprController: annualPercentageRate,
                                  statementClosingDayController:
                                      statementClosingDay,
                                  paymentDueDayController: paymentDueDay,
                                  fieldValueStyle: fieldValueStyle,
                                  fieldHintStyle: fieldHintStyle,
                                  decoration: borderlessDecoration,
                                ),
                              ],
                            )
                          : type == AccountType.loan
                          ? Column(
                              key: const ValueKey('loan-amount-field'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const TransactionFormDivider(),
                                TransactionFormLabel('Original loan amount'),
                                Row(
                                  children: [
                                    TransactionFormIcon(AppIcon.loan),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: AmountEntryField(
                                        fieldKey: const ValueKey(
                                          'account-original-loan-amount',
                                        ),
                                        initialMinor: originalLoanAmountMinor,
                                        currency:
                                            dataStore.preferences.currency,
                                        labelText: null,
                                        keyboardType: TextInputType.number,
                                        decoration: borderlessDecoration,
                                        textStyle: fieldValueStyle,
                                        onChanged: (value) =>
                                            originalLoanAmountMinor = value
                                                .abs(),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('no-account-extra-field'),
                            ),
                    ),
                    TransactionFormDivider(),
                    TransactionFormLabel('Opening balance'),
                    Row(
                      children: [
                        TransactionFormIcon(AppIcon.money),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: AmountEntryField(
                            initialMinor: openingBalanceCents,
                            currency: dataStore.preferences.currency,
                            labelText: null,
                            allowNegative: true,
                            keyboardType: TextInputType.number,
                            decoration: borderlessDecoration,
                            textStyle: fieldValueStyle,
                            onChanged: (value) => openingBalanceCents = value,
                          ),
                        ),
                      ],
                    ),
                    TransactionFormDivider(),
                    TransactionFormLabel('Balance options'),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: TransactionFormIcon(AppIcon.bank),
                      title: Text(
                        'Include in group balance',
                        style: fieldValueStyle,
                      ),
                      value: includeInGroupBalance,
                      onChanged: (value) =>
                          setDialogState(() => includeInGroupBalance = value),
                    ),
                    Divider(
                      height: 1,
                      indent: 56,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.38,
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: TransactionFormIcon(AppIcon.pieChart),
                      title: Text(
                        'Include in net worth',
                        style: fieldValueStyle,
                      ),
                      value: includeInNetWorth,
                      onChanged: (value) =>
                          setDialogState(() => includeInNetWorth = value),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  if (result == null) return;
  HapticFeedback.mediumImpact();
  final normalizedOpeningBalanceCents = switch (result.type) {
    AccountType.creditCard ||
    AccountType.loan => -result.openingBalanceCents.abs(),
    _ => result.openingBalanceCents,
  };
  final v2Type = v2AccountTypeFor(result.type);
  final nextSortOrder = dataStore.activeAccountsInDisplayOrder
      .where((item) => item.group == v2Type.group)
      .fold(0, (highest, item) => max(highest, item.sortOrder + 100));
  await dataStore.saveAccount(
    v2_account.AccountRecord(
      id: 'account_${DateTime.now().microsecondsSinceEpoch}',
      name: result.name,
      type: v2Type,
      openingBalanceMinor: normalizedOpeningBalanceCents,
      creditLimitMinor: v2Type == v2_account.AccountType.creditCard
          ? result.creditLimitMinor
          : null,
      interestEstimationEnabled:
          v2Type == v2_account.AccountType.creditCard &&
          result.interestEstimationEnabled,
      annualPercentageRate:
          v2Type == v2_account.AccountType.creditCard &&
              result.interestEstimationEnabled
          ? result.annualPercentageRate
          : null,
      statementClosingDay:
          v2Type == v2_account.AccountType.creditCard &&
              result.interestEstimationEnabled
          ? result.statementClosingDay
          : null,
      paymentDueDay:
          v2Type == v2_account.AccountType.creditCard &&
              result.interestEstimationEnabled
          ? result.paymentDueDay
          : null,
      originalLoanAmountMinor: v2Type == v2_account.AccountType.loan
          ? result.originalLoanAmountMinor ??
                normalizedOpeningBalanceCents.abs()
          : null,
      includeInGroupBalance: result.includeInGroupBalance,
      includeInNetWorth: result.includeInNetWorth,
      sortOrder: nextSortOrder,
      sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
    ),
  );
}

Future<void> showTransferDialog(
  BuildContext context, {
  String? initialFromAccountId,
  TransactionRecord? transfer,
  bool includeGoalAccounts = false,
  bool initialScheduleFutureOccurrences = false,
  FutureScheduleDraft? initialFutureSchedule,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final accounts = dataStore.accounts
      .where(
        (account) =>
            account.isVisible &&
            (includeGoalAccounts ||
                !account.isInternalGoalAccount ||
                account.id == initialFromAccountId ||
                account.id == transfer?.accountId),
      )
      .toList(growable: false);
  if (accounts.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('At least two accounts are required')),
    );
    return;
  }

  final description = TextEditingController(text: transfer?.payee ?? '');
  final date = TextEditingController(
    text: dateInput(transfer?.date ?? DateTime.now()),
  );
  final note = TextEditingController(text: transfer?.note ?? '');
  final futureSchedule =
      initialFutureSchedule ??
      FutureScheduleDraft(
        firstDate: firstMonthlyDateAfter(
          transfer?.date ?? DateTime.now(),
          DateTime.now(),
        ),
      );
  var amountMinor = transfer?.amountMinor.abs() ?? 0;
  var fromAccountId =
      accounts.any(
        (account) =>
            account.id == (transfer?.accountId ?? initialFromAccountId),
      )
      ? (transfer?.accountId ?? initialFromAccountId)!
      : '';
  var toAccountId =
      accounts.any((account) => account.id == transfer?.transferAccountId) &&
          transfer?.transferAccountId != fromAccountId
      ? transfer!.transferAccountId!
      : '';
  final linkedSchedule = transfer?.scheduledTransactionId == null
      ? null
      : dataStore.scheduledTransactions
            .where(
              (item) =>
                  item.id == transfer!.scheduledTransactionId &&
                  !item.isDeleted,
            )
            .firstOrNull;
  TransactionType? switchToType;
  var editLinkedSchedule = false;
  var scheduleFutureOccurrences =
      linkedSchedule == null && initialScheduleFutureOccurrences;

  final result =
      await showDialog<
        ({
          String fromAccountId,
          String toAccountId,
          String payee,
          DateTime date,
          String note,
          int amountMinor,
          bool scheduleFutureOccurrences,
          DateTime firstScheduledDate,
          int scheduledTimeMinutes,
          v2_scheduled.RecurrenceFrequency scheduledFrequency,
          v2_scheduled.AlertPreference scheduledAlertPreference,
        })
      >(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final selectedFromAccount = accounts
                .where((account) => account.id == fromAccountId)
                .firstOrNull;
            final selectedToAccount = accounts
                .where((account) => account.id == toAccountId)
                .firstOrNull;
            final sourceCurrentBalanceMinor = selectedFromAccount == null
                ? 0
                : dataStore.balanceForAccount(selectedFromAccount.id);
            final sourceBalanceWithoutExistingTransfer =
                selectedFromAccount == null
                ? 0
                : sourceCurrentBalanceMinor -
                      (transfer?.deltaForAccount(selectedFromAccount.id) ?? 0);
            final projectedSourceBalanceMinor = selectedFromAccount == null
                ? 0
                : sourceBalanceWithoutExistingTransfer - amountMinor.abs();
            final wouldOverdrawSource =
                selectedFromAccount != null &&
                accountIsAsset(selectedFromAccount) &&
                projectedSourceBalanceMinor < 0;
            final mutedStyle = theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              height: 1.18,
              fontWeight: FontWeight.w400,
            );
            final accountRowStyle = theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              height: 1.08,
            );
            final fieldValueStyle = theme.textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              height: 1.15,
            );
            final fieldHintStyle = fieldValueStyle?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            );
            final canSaveTransfer =
                fromAccountId.isNotEmpty &&
                toAccountId.isNotEmpty &&
                fromAccountId != toAccountId &&
                amountMinor.abs() > 0 &&
                (!scheduleFutureOccurrences ||
                    isValidFutureScheduleDate(
                      futureSchedule.parsedFirstDate(DateTime.now()),
                      parseDateInput(date.text, DateTime.now()),
                    ));

            Widget accountSubtitle(
              v2_account.AccountRecord account, {
              required bool isSource,
            }) {
              if (!isSource || !wouldOverdrawSource) {
                return Text(
                  'Balance ${money(dataStore.balanceForAccount(account.id), dataStore.preferences.currency)}',
                  style: mutedStyle,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Balance ${money(projectedSourceBalanceMinor, dataStore.preferences.currency)}',
                    style: mutedStyle?.copyWith(color: AppColors.danger),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Insufficient funds',
                    key: const ValueKey('transfer-insufficient-funds'),
                    style: mutedStyle?.copyWith(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'This transaction would leave ${account.name} at ${money(projectedSourceBalanceMinor, dataStore.preferences.currency)}.',
                    style: mutedStyle?.copyWith(color: AppColors.danger),
                  ),
                ],
              );
            }

            Widget accountRow({
              required Key rowKey,
              required v2_account.AccountRecord? account,
              required String placeholder,
              required VoidCallback? onTap,
              bool isSource = false,
            }) {
              final enabled = onTap != null;
              return InkWell(
                key: rowKey,
                borderRadius: BorderRadius.circular(AppRadii.control),
                onTap: onTap,
                child: Opacity(
                  opacity: enabled ? 1 : 0.46,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        TransactionFormIcon(
                          account == null
                              ? AppIcon.wallet
                              : v2AccountIcon(account.type),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                account?.name ?? placeholder,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: account == null
                                    ? accountRowStyle?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      )
                                    : accountRowStyle,
                              ),
                              if (account != null) ...[
                                const SizedBox(height: 5),
                                accountSubtitle(account, isSource: isSource),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Icon(AppIcon.chevronDown, size: AppIconSize.hero),
                      ],
                    ),
                  ),
                ),
              );
            }

            Future<void> saveTransferResult() async {
              if (wouldOverdrawSource &&
                  dataStore.preferences.warnBeforeNegativeAssetBalance &&
                  !await confirmAssetAccountOverdraw(
                    context,
                    account: selectedFromAccount,
                    projectedBalanceMinor: projectedSourceBalanceMinor,
                  )) {
                return;
              }
              if (!context.mounted) return;
              Navigator.pop(context, (
                fromAccountId: fromAccountId,
                toAccountId: toAccountId,
                payee: description.text.trim().isEmpty
                    ? 'Transfer'
                    : description.text.trim(),
                date: parseTransactionDateInput(
                  date.text,
                  transfer?.date ?? DateTime.now(),
                ),
                note: note.text.trim(),
                amountMinor: amountMinor.abs(),
                scheduleFutureOccurrences: scheduleFutureOccurrences,
                firstScheduledDate: futureSchedule.parsedFirstDate(
                  DateTime.now(),
                ),
                scheduledTimeMinutes: futureSchedule.timeMinutes,
                scheduledFrequency: futureSchedule.frequency,
                scheduledAlertPreference: futureSchedule.alertPreference,
              ));
            }

            return TransactionSheetFrame(
              title: transfer == null ? 'Add Transaction' : 'Edit Transaction',
              actions: TransactionFormActions(
                onCancel: () => Navigator.pop(context),
                canSave: canSaveTransfer,
                onSave: saveTransferResult,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 292),
                      child: SegmentedButton<TransactionType>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: AppTheme.accent,
                          selectedForegroundColor: Colors.white,
                          foregroundColor: theme.colorScheme.onSurface,
                          textStyle: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                        ),
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
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const TransactionFormLabel('From Account'),
                  accountRow(
                    rowKey: const ValueKey('transfer-from-account'),
                    account: selectedFromAccount,
                    placeholder: 'Choose account',
                    isSource: true,
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final selectedAccountId =
                          await showTransactionAccountPicker(
                            context,
                            accounts: accounts,
                            selectedAccountId: fromAccountId,
                          );
                      if (selectedAccountId == null) return;
                      setDialogState(() {
                        fromAccountId = selectedAccountId;
                        if (toAccountId == fromAccountId) toAccountId = '';
                      });
                    },
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Amount'),
                  Row(
                    children: [
                      TransactionFormIcon(AppIcon.money),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AmountEntryField(
                          fieldKey: const ValueKey('transfer-amount'),
                          initialMinor: amountMinor,
                          currency: dataStore.preferences.currency,
                          labelText: null,
                          autofocus:
                              transfer == null && fromAccountId.isNotEmpty,
                          textAlign: TextAlign.left,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                          onChanged: (value) =>
                              setDialogState(() => amountMinor = value.abs()),
                        ),
                      ),
                    ],
                  ),
                  const TransactionFormDivider(),
                  const TransactionFormLabel('To Account'),
                  accountRow(
                    rowKey: ValueKey('transfer-to-$fromAccountId'),
                    account: selectedToAccount,
                    placeholder: fromAccountId.isEmpty
                        ? 'Choose a source account first'
                        : 'Choose destination',
                    onTap: fromAccountId.isEmpty
                        ? null
                        : () async {
                            FocusManager.instance.primaryFocus?.unfocus();
                            final selectedAccountId =
                                await showTransactionAccountPicker(
                                  context,
                                  accounts: accounts
                                      .where(
                                        (account) =>
                                            account.id != fromAccountId,
                                      )
                                      .toList(growable: false),
                                  selectedAccountId: toAccountId,
                                );
                            if (selectedAccountId != null) {
                              setDialogState(
                                () => toAccountId = selectedAccountId,
                              );
                            }
                          },
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Description'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TransactionFormIcon(AppIcon.description),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('transfer-payee'),
                          controller: description,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: 'Add a description (optional)',
                            hintStyle: fieldHintStyle,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                          style: fieldValueStyle,
                        ),
                      ),
                    ],
                  ),
                  // Future purpose-based Goal Allocations can be inserted here
                  // without changing transfer accounting or the surrounding rows.
                  const TransactionFormDivider(),
                  const TransactionFormLabel('Date'),
                  InkWell(
                    key: const ValueKey('transfer-date'),
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final picked = await pickDateForField(
                        context,
                        parseDateInput(date.text, DateTime.now()),
                      );
                      if (picked != null) {
                        setDialogState(() => date.text = dateInput(picked));
                      }
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          TransactionFormIcon(AppIcon.calendar),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              fullMonthDateLabel(
                                parseDateInput(date.text, DateTime.now()),
                              ),
                              style: fieldValueStyle,
                            ),
                          ),
                          Text(
                            isSameCalendarDay(
                                  parseDateInput(date.text, DateTime.now()),
                                  DateTime.now(),
                                )
                                ? 'Today'
                                : '',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Icon(
                            AppIcon.event,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Notes'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TransactionFormIcon(AppIcon.notes),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('transfer-note'),
                          controller: note,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Add a note (optional)',
                            hintStyle: fieldHintStyle,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                          style: fieldValueStyle,
                          minLines: 1,
                          maxLines: 3,
                        ),
                      ),
                    ],
                  ),
                  if (linkedSchedule == null) ...[
                    const TransactionFormDivider(),
                    InkWell(
                      key: const ValueKey('transfer-schedule-toggle'),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      onTap: () => setDialogState(
                        () => scheduleFutureOccurrences =
                            !scheduleFutureOccurrences,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            TransactionFormIcon(AppIcon.recurrence),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                'Schedule future occurrences',
                                style: fieldValueStyle,
                              ),
                            ),
                            Switch.adaptive(
                              value: scheduleFutureOccurrences,
                              onChanged: (value) => setDialogState(
                                () => scheduleFutureOccurrences = value,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (scheduleFutureOccurrences) ...[
                      const TransactionFormDivider(),
                      InlineFutureScheduleSection(
                        draft: futureSchedule,
                        keyPrefix: 'transfer-schedule',
                        onChanged: () => setDialogState(() {}),
                      ),
                    ],
                  ] else ...[
                    const TransactionFormDivider(),
                    InkWell(
                      key: const ValueKey('transfer-edit-future-schedule'),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      onTap: () {
                        editLinkedSchedule = true;
                        Navigator.pop(context);
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            TransactionFormIcon(AppIcon.recurrence),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Edit future schedule',
                                    style: fieldValueStyle,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Date, time, frequency, and reminder',
                                    style: mutedStyle,
                                  ),
                                ],
                              ),
                            ),
                            Icon(AppIcon.chevronRight),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );

  if (editLinkedSchedule && linkedSchedule != null && context.mounted) {
    await showScheduledTransactionDialog(context, existing: linkedSchedule);
    return;
  }
  if (switchToType != null && context.mounted) {
    await showTransactionDialog(
      context,
      initialIsExpense: switchToType == TransactionType.expense,
      initialAccountId: fromAccountId,
      transaction: transfer,
      initialScheduleFutureOccurrences: scheduleFutureOccurrences,
      initialFutureSchedule: futureSchedule,
    );
    return;
  }
  if (result == null) return;
  HapticFeedback.mediumImpact();
  if (transfer == null) {
    if (result.scheduleFutureOccurrences) {
      final scheduleId = 'sched_${DateTime.now().microsecondsSinceEpoch}';
      final transactionRecord = TransactionRecord(
        id: 'txn_${DateTime.now().microsecondsSinceEpoch}',
        type: TransactionType.transfer,
        accountId: result.fromAccountId,
        transferAccountId: result.toAccountId,
        date: result.date,
        payee: result.payee,
        amountMinor: result.amountMinor,
        note: result.note,
        scheduledTransactionId: scheduleId,
        sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
      );
      final schedule = v2_scheduled.ScheduledTransactionRecord(
        id: scheduleId,
        type: TransactionType.transfer,
        accountId: result.fromAccountId,
        transferAccountId: result.toAccountId,
        payee: result.payee,
        note: result.note,
        amountMinor: result.amountMinor,
        nextDate: result.firstScheduledDate,
        frequency: result.scheduledFrequency,
        alertPreference: result.scheduledAlertPreference,
        customAlertTimeMinutes: result.scheduledTimeMinutes,
        sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
      );
      try {
        if (schedule.hasAlert && !dataStore.preferences.notificationsEnabled) {
          await dataStore.savePreferences(
            dataStore.preferences.copyWith(notificationsEnabled: true),
          );
        }
        await dataStore.saveTransactionAndSchedule(
          transaction: transactionRecord,
          scheduledTransaction: schedule,
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The transfer and schedule could not be saved. Please try again.',
              ),
            ),
          );
        }
        return;
      }
    } else {
      await dataStore.addTransfer(
        fromAccountId: result.fromAccountId,
        toAccountId: result.toAccountId,
        date: result.date,
        payee: result.payee,
        amountMinor: result.amountMinor,
        note: result.note,
      );
    }
  } else if (result.scheduleFutureOccurrences) {
    final scheduleId = 'sched_${DateTime.now().microsecondsSinceEpoch}';
    final transactionRecord = transfer.copyWith(
      type: TransactionType.transfer,
      accountId: result.fromAccountId,
      transferAccountId: result.toAccountId,
      date: result.date,
      payee: result.payee,
      amountMinor: result.amountMinor,
      note: result.note,
      scheduledTransactionId: scheduleId,
      clearCategory: true,
    );
    final schedule = v2_scheduled.ScheduledTransactionRecord(
      id: scheduleId,
      type: TransactionType.transfer,
      accountId: result.fromAccountId,
      transferAccountId: result.toAccountId,
      payee: result.payee,
      note: result.note,
      amountMinor: result.amountMinor,
      nextDate: result.firstScheduledDate,
      frequency: result.scheduledFrequency,
      alertPreference: result.scheduledAlertPreference,
      customAlertTimeMinutes: result.scheduledTimeMinutes,
      sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
    );
    try {
      if (schedule.hasAlert && !dataStore.preferences.notificationsEnabled) {
        await dataStore.savePreferences(
          dataStore.preferences.copyWith(notificationsEnabled: true),
        );
      }
      await dataStore.saveTransactionAndSchedule(
        transaction: transactionRecord,
        scheduledTransaction: schedule,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The transfer and schedule could not be saved. Please try again.',
            ),
          ),
        );
      }
      return;
    }
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
      lastUsedTransferSourceAccountId: result.fromAccountId,
    ),
  );
}

Future<bool> showScheduledTransactionDialog(
  BuildContext context, {
  v2_scheduled.ScheduledTransactionRecord? existing,
  TransactionType? initialType,
  TransactionRecord? sourceTransaction,
  DateTime? initialDate,
}) async {
  if (existing?.type == TransactionType.goalFunding ||
      initialType == TransactionType.goalFunding) {
    return showScheduledGoalFundingDialog(
      context,
      existing: existing,
      initialDate: initialDate,
    );
  }
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
    return false;
  }

  final payeeOptions = savedPayees(dataStore);
  final payee = TextEditingController(
    text: existing?.payee ?? sourceTransaction?.payee ?? '',
  );
  final note = TextEditingController(
    text: existing?.note ?? sourceTransaction?.note ?? '',
  );
  var amountMinor =
      existing?.amountMinor ?? sourceTransaction?.amountMinor.abs() ?? 0;
  final nextDate = TextEditingController(
    text: dateInput(
      existing?.nextDate ??
          (sourceTransaction == null
              ? initialDate ?? DateTime.now()
              : firstMonthlyDateAfter(sourceTransaction.date, DateTime.now())),
    ),
  );
  final customAlertTime = TextEditingController(
    text: alertTimeInput(existing?.customAlertTimeMinutes ?? 9 * 60),
  );
  var type =
      existing?.type ??
      sourceTransaction?.type ??
      initialType ??
      TransactionType.expense;
  final initialAccountId = existing?.accountId ?? sourceTransaction?.accountId;
  var accountId = accounts.any((account) => account.id == initialAccountId)
      ? initialAccountId!
      : '';
  final initialTransferAccountId =
      existing?.transferAccountId ?? sourceTransaction?.transferAccountId;
  var transferAccountId =
      accounts.any((account) => account.id == initialTransferAccountId)
      ? initialTransferAccountId
      : null;
  var categoryId = existing?.categoryId ?? sourceTransaction?.categoryId;
  final initialSplitLines =
      existing?.effectiveCategoryAllocations ??
      sourceTransaction?.effectiveCategoryAllocations ??
      const [];
  final splitDrafts = initialSplitLines
      .map(
        (line) => SplitLineDraft(
          id: line.id,
          categoryId: line.categoryId,
          amountMinor: line.amountMinor,
          noteText: line.note,
        ),
      )
      .toList();
  if (splitDrafts.isEmpty && type != TransactionType.transfer) {
    splitDrafts.add(
      SplitLineDraft(
        id: 'split_${DateTime.now().microsecondsSinceEpoch}_0',
        categoryId: categoryId ?? '',
        amountMinor: amountMinor.abs(),
      ),
    );
  }
  var splitMode =
      existing?.isCategorySplit ?? sourceTransaction?.isCategorySplit ?? false;
  var autofocusSecondSplitAmount = false;
  final splitSectionKey = GlobalKey();
  var firstSplitAutoRemainder = !splitMode;
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
          String note,
          int amountMinor,
          List<TransactionSplitLine> splitLines,
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
            final theme = Theme.of(context);
            final categories = scheduledCategoriesForType(dataStore, type);
            if (categoryId != null &&
                !categories.any((category) => category.id == categoryId)) {
              categoryId = null;
            }
            for (final draft in splitDrafts) {
              if (!categories.any(
                (category) => category.id == draft.categoryId,
              )) {
                draft.categoryId = '';
              }
            }
            if (type != TransactionType.transfer && splitDrafts.isEmpty) {
              splitDrafts.add(
                SplitLineDraft(
                  id: 'split_${DateTime.now().microsecondsSinceEpoch}_${splitDrafts.length}',
                  categoryId: categoryId ?? '',
                  amountMinor: amountMinor.abs(),
                ),
              );
            }
            if (type != TransactionType.transfer &&
                firstSplitAutoRemainder &&
                splitDrafts.isNotEmpty) {
              final otherTotal = splitDrafts
                  .skip(1)
                  .fold<int>(
                    0,
                    (total, line) => total + line.amountMinor.abs(),
                  );
              final remainder = amountMinor.abs() - otherTotal;
              splitDrafts.first.amountMinor = remainder > 0 ? remainder : 0;
            }
            if (type != TransactionType.transfer && splitDrafts.isNotEmpty) {
              categoryId = splitDrafts.first.categoryId.isEmpty
                  ? null
                  : splitDrafts.first.categoryId;
            }
            if (transferAccountId == accountId) {
              transferAccountId = null;
            }
            final selectedAccount = accounts
                .where((account) => account.id == accountId)
                .firstOrNull;
            final selectedDestination = accounts
                .where((account) => account.id == transferAccountId)
                .firstOrNull;
            final selectedCategory = categories
                .where((category) => category.id == categoryId)
                .firstOrNull;
            final splitTotalMinor = splitDrafts.fold<int>(
              0,
              (total, line) => total + line.amountMinor.abs(),
            );
            final splitCategoryIds = splitDrafts
                .map((line) => line.categoryId)
                .where((id) => id.isNotEmpty)
                .toSet();
            final splitRowsComplete =
                splitDrafts.isNotEmpty &&
                splitDrafts.every(
                  (line) => line.categoryId.isNotEmpty && line.amountMinor > 0,
                ) &&
                splitCategoryIds.length == splitDrafts.length;
            final splitIsBalanced =
                splitRowsComplete && splitTotalMinor == amountMinor.abs();
            final mutedStyle = theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              height: 1.18,
              fontWeight: FontWeight.w400,
            );
            final rowValueStyle = theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              height: 1.08,
            );
            final fieldValueStyle = theme.textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              height: 1.15,
            );
            final fieldHintStyle = fieldValueStyle?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            );
            final canSave =
                selectedAccount != null &&
                amountMinor.abs() > 0 &&
                nextDate.text.trim().isNotEmpty &&
                (type == TransactionType.transfer ||
                    (selectedCategory != null && splitIsBalanced)) &&
                (type != TransactionType.transfer ||
                    (selectedDestination != null &&
                        selectedDestination.id != selectedAccount.id));

            Widget accountRow({
              required Key rowKey,
              required v2_account.AccountRecord? account,
              required String placeholder,
              required VoidCallback? onTap,
            }) {
              return InkWell(
                key: rowKey,
                borderRadius: BorderRadius.circular(AppRadii.control),
                onTap: onTap,
                child: Opacity(
                  opacity: onTap == null ? 0.46 : 1,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        TransactionFormIcon(
                          account == null
                              ? AppIcon.wallet
                              : v2AccountIcon(account.type),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                account?.name ?? placeholder,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: account == null
                                    ? rowValueStyle?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      )
                                    : rowValueStyle,
                              ),
                              if (account != null) ...[
                                const SizedBox(height: 5),
                                Text(
                                  'Balance ${money(dataStore.balanceForAccount(account.id), dataStore.preferences.currency)}',
                                  style: mutedStyle,
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Icon(AppIcon.chevronDown, size: AppIconSize.hero),
                      ],
                    ),
                  ),
                ),
              );
            }

            Widget choiceRow({
              required Key rowKey,
              required IconData icon,
              required String value,
              required VoidCallback onTap,
              String? secondary,
            }) {
              return InkWell(
                key: rowKey,
                borderRadius: BorderRadius.circular(AppRadii.control),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      TransactionFormIcon(icon),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(value, style: rowValueStyle),
                            if (secondary != null) ...[
                              SizedBox(height: 4),
                              Text(secondary, style: mutedStyle),
                            ],
                          ],
                        ),
                      ),
                      Icon(AppIcon.chevronDown, size: AppIconSize.hero),
                    ],
                  ),
                ),
              );
            }

            Future<void> chooseAccount({required bool destination}) async {
              FocusManager.instance.primaryFocus?.unfocus();
              final options = destination
                  ? accounts
                        .where((account) => account.id != accountId)
                        .toList(growable: false)
                  : accounts;
              final selectedId = await showTransactionAccountPicker(
                context,
                accounts: options,
                selectedAccountId: destination
                    ? transferAccountId ?? ''
                    : accountId,
              );
              if (selectedId == null) return;
              setDialogState(() {
                if (destination) {
                  transferAccountId = selectedId;
                } else {
                  accountId = selectedId;
                  if (transferAccountId == accountId) {
                    transferAccountId = null;
                  }
                }
              });
            }

            void recalculateScheduledRemainder() {
              if (!firstSplitAutoRemainder || splitDrafts.isEmpty) return;
              final otherTotal = splitDrafts
                  .skip(1)
                  .fold<int>(
                    0,
                    (total, line) => total + line.amountMinor.abs(),
                  );
              final remainder = amountMinor.abs() - otherTotal;
              splitDrafts.first.amountMinor = remainder > 0 ? remainder : 0;
            }

            Future<void> chooseScheduledSplitCategory(int index) async {
              FocusManager.instance.primaryFocus?.unfocus();
              final selectedId = await showTransactionCategoryFlow(
                context,
                dataStore: dataStore,
                isExpense: type == TransactionType.expense,
                selectedCategoryId: splitDrafts[index].categoryId,
              );
              if (selectedId == null || !context.mounted) return;
              setDialogState(() {
                splitDrafts[index].categoryId = selectedId;
                if (index == 0) categoryId = selectedId;
              });
            }

            void enterScheduledSplitMode() {
              if (splitDrafts.isEmpty || categoryId == null) return;
              setDialogState(() {
                splitMode = true;
                firstSplitAutoRemainder = true;
                splitDrafts.first
                  ..categoryId = categoryId!
                  ..amountMinor = amountMinor.abs();
                if (splitDrafts.length == 1) {
                  splitDrafts.add(
                    SplitLineDraft(
                      id: 'split_${DateTime.now().microsecondsSinceEpoch}_1',
                      categoryId: '',
                      amountMinor: 0,
                    ),
                  );
                }
                autofocusSecondSplitAmount = true;
                recalculateScheduledRemainder();
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final splitContext = splitSectionKey.currentContext;
                if (splitContext == null) return;
                Scrollable.ensureVisible(
                  splitContext,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: 0.35,
                );
              });
            }

            Future<void> useSingleScheduledCategory() async {
              final hasMeaningfulAdditionalSplits = splitDrafts
                  .skip(1)
                  .any(
                    (draft) =>
                        draft.categoryId.isNotEmpty ||
                        draft.amountMinor != 0 ||
                        draft.note.text.trim().isNotEmpty,
                  );
              if (hasMeaningfulAdditionalSplits &&
                  !await confirmDiscardAdditionalSplits(context)) {
                return;
              }
              if (!context.mounted) return;
              setDialogState(() {
                for (final draft in splitDrafts.skip(1)) {
                  draft.note.dispose();
                }
                if (splitDrafts.length > 1) {
                  splitDrafts.removeRange(1, splitDrafts.length);
                }
                splitDrafts.first.amountMinor = amountMinor.abs();
                categoryId = splitDrafts.first.categoryId.isEmpty
                    ? null
                    : splitDrafts.first.categoryId;
                firstSplitAutoRemainder = true;
                splitMode = false;
                autofocusSecondSplitAmount = false;
              });
            }

            List<TransactionSplitLine> buildScheduledSplitLines() {
              if (type == TransactionType.transfer || !splitMode) {
                return const [];
              }
              return [
                for (var index = 0; index < splitDrafts.length; index++)
                  TransactionSplitLine(
                    id:
                        splitDrafts[index].id ??
                        'split_${DateTime.now().microsecondsSinceEpoch}_$index',
                    categoryId: splitDrafts[index].categoryId,
                    amountMinor: splitDrafts[index].amountMinor.abs(),
                    note: splitDrafts[index].note.text.trim(),
                  ),
              ];
            }

            void saveResult() {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context, (
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
                note: note.text.trim(),
                amountMinor: amountMinor.abs(),
                splitLines: buildScheduledSplitLines(),
                nextDate: parseDateInput(nextDate.text, DateTime.now()),
                frequency: frequency,
                alertPreference: alertPreference,
                customAlertTimeMinutes: parseAlertTimeMinutes(
                  customAlertTime.text,
                  9 * 60,
                ),
                repeatAlertUntilResolved:
                    alertPreference != v2_scheduled.AlertPreference.none &&
                    repeatAlertUntilResolved,
              ));
            }

            return TransactionSheetFrame(
              title: isEditing
                  ? 'Edit Scheduled Transaction'
                  : 'Create Scheduled Transaction',
              actions: TransactionFormActions(
                onCancel: () => Navigator.pop(context),
                canSave: canSave,
                onSave: saveResult,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 292),
                      child: SegmentedButton<TransactionType>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: AppTheme.accent,
                          selectedForegroundColor: Colors.white,
                          foregroundColor: theme.colorScheme.onSurface,
                          textStyle: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                        ),
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
                          final nextType = values.first;
                          if (nextType == type) return;
                          final previousType = type;
                          type = nextType;
                          if (type != TransactionType.transfer &&
                              previousType != TransactionType.transfer &&
                              previousType != type) {
                            categoryId = null;
                            for (final draft in splitDrafts.skip(1)) {
                              draft.note.dispose();
                            }
                            if (splitDrafts.length > 1) {
                              splitDrafts.removeRange(1, splitDrafts.length);
                            }
                            splitDrafts.first
                              ..categoryId = ''
                              ..amountMinor = amountMinor.abs();
                            firstSplitAutoRemainder = true;
                            splitMode = false;
                            autofocusSecondSplitAmount = false;
                          }
                          if (type == TransactionType.transfer &&
                              transferAccountId == accountId) {
                            transferAccountId = null;
                          }
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TransactionFormLabel(
                    type == TransactionType.transfer
                        ? 'From Account'
                        : 'Account',
                  ),
                  accountRow(
                    rowKey: const ValueKey('scheduled-account'),
                    account: selectedAccount,
                    placeholder: 'Choose account',
                    onTap: () => chooseAccount(destination: false),
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Amount'),
                  Row(
                    children: [
                      TransactionFormIcon(AppIcon.money),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AmountEntryField(
                          fieldKey: const ValueKey('scheduled-amount'),
                          initialMinor: amountMinor,
                          currency: dataStore.preferences.currency,
                          labelText: null,
                          autofocus: existing == null && accountId.isNotEmpty,
                          textAlign: TextAlign.left,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                          onChanged: (value) => setDialogState(() {
                            amountMinor = value.abs();
                            recalculateScheduledRemainder();
                          }),
                        ),
                      ),
                    ],
                  ),
                  const TransactionFormDivider(),
                  if (type == TransactionType.transfer) ...[
                    const TransactionFormLabel('To Account'),
                    accountRow(
                      rowKey: ValueKey('scheduled-to-$accountId'),
                      account: selectedDestination,
                      placeholder: accountId.isEmpty
                          ? 'Choose a source account first'
                          : 'Choose destination',
                      onTap: accountId.isEmpty
                          ? null
                          : () => chooseAccount(destination: true),
                    ),
                    TransactionFormDivider(),
                    TransactionFormLabel('Description'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TransactionFormIcon(AppIcon.description),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('scheduled-payee'),
                            controller: payee,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.next,
                            onTapOutside: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: InputDecoration(
                              hintText: 'Add a description (optional)',
                              hintStyle: fieldHintStyle,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                            ),
                            style: fieldValueStyle,
                          ),
                        ),
                      ],
                    ),
                    // Future purpose-based Goal Allocations can be inserted
                    // here without changing scheduled transfer accounting.
                  ] else ...[
                    TransactionFormLabel('Payee'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TransactionFormIcon(AppIcon.payee),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: PayeeAutocompleteField(
                            dataStore: dataStore,
                            fieldKey: const ValueKey('scheduled-payee'),
                            controller: payee,
                            options: payeeOptions,
                            inlineSuggestions: true,
                            inlineSuggestionsAbove: true,
                            decoration: InputDecoration(
                              hintText: 'Search or enter payee',
                              hintStyle: fieldHintStyle,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                            ),
                            textStyle: fieldValueStyle,
                            textInputAction: TextInputAction.next,
                            showSuggestionToggle: false,
                          ),
                        ),
                      ],
                    ),
                    const TransactionFormDivider(),
                    if (splitMode)
                      InlineSplitAllocationSection(
                        key: splitSectionKey,
                        keyPrefix: 'scheduled',
                        drafts: splitDrafts,
                        categories: categories,
                        currency: dataStore.preferences.currency,
                        totalMinor: amountMinor.abs(),
                        firstAutoRemainder: firstSplitAutoRemainder,
                        autofocusAmountIndex: autofocusSecondSplitAmount
                            ? 1
                            : null,
                        onChooseCategory: chooseScheduledSplitCategory,
                        onAmountChanged: (index, value) => setDialogState(() {
                          autofocusSecondSplitAmount = false;
                          splitDrafts[index].amountMinor = value.abs();
                          if (index == 0) {
                            firstSplitAutoRemainder = false;
                          } else {
                            recalculateScheduledRemainder();
                          }
                        }),
                        onAdd: () => setDialogState(() {
                          autofocusSecondSplitAmount = false;
                          final currentTotal = splitDrafts.fold<int>(
                            0,
                            (total, line) => total + line.amountMinor.abs(),
                          );
                          final remainder = amountMinor.abs() - currentTotal;
                          splitDrafts.add(
                            SplitLineDraft(
                              id: 'split_${DateTime.now().microsecondsSinceEpoch}_${splitDrafts.length}',
                              categoryId: '',
                              amountMinor: remainder > 0 ? remainder : 0,
                            ),
                          );
                        }),
                        onRemove: (index) => setDialogState(() {
                          autofocusSecondSplitAmount = false;
                          splitDrafts[index].note.dispose();
                          splitDrafts.removeAt(index);
                          recalculateScheduledRemainder();
                          categoryId = splitDrafts.first.categoryId.isEmpty
                              ? null
                              : splitDrafts.first.categoryId;
                          if (splitDrafts.length == 1) {
                            splitDrafts.first.amountMinor = amountMinor.abs();
                            firstSplitAutoRemainder = true;
                            splitMode = false;
                          }
                        }),
                        onUseSingleCategory: useSingleScheduledCategory,
                      )
                    else
                      SingleCategoryAllocationSection(
                        keyPrefix: 'scheduled',
                        categoryName: selectedCategory?.name,
                        category: selectedCategory,
                        onChooseCategory: () => chooseScheduledSplitCategory(0),
                        onSplit: selectedCategory == null
                            ? null
                            : enterScheduledSplitMode,
                      ),
                  ],
                  const TransactionFormDivider(),
                  Padding(
                    padding: const EdgeInsets.only(top: 1, bottom: 8),
                    child: Text(
                      'Schedule',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  TransactionFormLabel('Frequency'),
                  choiceRow(
                    rowKey: ValueKey('scheduled-frequency'),
                    icon: AppIcon.repeat,
                    value: recurrenceFrequencyLabel(frequency),
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final selected = await showScheduledChoicePicker(
                        context,
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
                  TransactionFormDivider(),
                  TransactionFormLabel('Start date'),
                  choiceRow(
                    rowKey: ValueKey('scheduled-next-date'),
                    icon: AppIcon.calendar,
                    value: fullMonthDateLabel(
                      parseDateInput(nextDate.text, DateTime.now()),
                    ),
                    secondary:
                        isSameCalendarDay(
                          parseDateInput(nextDate.text, DateTime.now()),
                          DateTime.now(),
                        )
                        ? 'Today'
                        : null,
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final picked = await pickDateForField(
                        context,
                        parseDateInput(nextDate.text, DateTime.now()),
                      );
                      if (picked != null) {
                        setDialogState(() => nextDate.text = dateInput(picked));
                      }
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Time'),
                  choiceRow(
                    rowKey: ValueKey('scheduled-alert-time'),
                    icon: AppIcon.schedule,
                    value: customAlertTime.text,
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final minutes = parseAlertTimeMinutes(
                        customAlertTime.text,
                        9 * 60,
                      );
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: minutes ~/ 60,
                          minute: minutes % 60,
                        ),
                        initialEntryMode: TimePickerEntryMode.dial,
                        builder: (context, child) => polishedPickerBuilder(
                          context,
                          child,
                          forceTwelveHourTime: true,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(
                          () => customAlertTime.text = alertTimeInput(
                            picked.hour * 60 + picked.minute,
                          ),
                        );
                      }
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                  ),
                  const TransactionFormDivider(),
                  TransactionFormLabel('Reminder'),
                  choiceRow(
                    rowKey: ValueKey('scheduled-alert'),
                    icon: alertPreference == v2_scheduled.AlertPreference.none
                        ? AppIcon.notificationNone
                        : AppIcon.notificationActive,
                    value: alertPreferenceLabel(alertPreference),
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final selected = await showScheduledChoicePicker(
                        context,
                        title: 'Reminder',
                        values: v2_scheduled.AlertPreference.values,
                        selected: alertPreference,
                        label: alertPreferenceLabel,
                      );
                      if (selected != null) {
                        setDialogState(() {
                          alertPreference = selected;
                          if (selected == v2_scheduled.AlertPreference.none) {
                            repeatAlertUntilResolved = false;
                          }
                        });
                      }
                    },
                  ),
                  AnimatedSize(
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 165),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (alertPreference !=
                            v2_scheduled.AlertPreference.none) ...[
                          const TransactionFormDivider(),
                          InkWell(
                            key: const ValueKey('scheduled-repeat-alert'),
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                            onTap: () => setDialogState(
                              () => repeatAlertUntilResolved =
                                  !repeatAlertUntilResolved,
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  TransactionFormIcon(
                                    AppIcon.notificationImportant,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Text(
                                      'Repeat until marked paid or skipped',
                                      style: fieldValueStyle,
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: repeatAlertUntilResolved,
                                    onChanged: (value) => setDialogState(
                                      () => repeatAlertUntilResolved = value,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Notes'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TransactionFormIcon(AppIcon.notes),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('scheduled-note'),
                          controller: note,
                          textCapitalization: TextCapitalization.sentences,
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          decoration: InputDecoration(
                            hintText: 'Add a note (optional)',
                            hintStyle: fieldHintStyle,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                          style: fieldValueStyle,
                          minLines: 1,
                          maxLines: 3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );

  for (final draft in splitDrafts) {
    draft.note.dispose();
  }
  if (result == null) return false;
  HapticFeedback.mediumImpact();
  if (result.type == TransactionType.transfer &&
      result.transferAccountId == null) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Choose a destination account')),
    );
    return false;
  }

  if (result.alertPreference != v2_scheduled.AlertPreference.none &&
      !dataStore.preferences.notificationsEnabled) {
    await dataStore.savePreferences(
      dataStore.preferences.copyWith(notificationsEnabled: true),
    );
  }

  final scheduledTransaction = existing == null
      ? v2_scheduled.ScheduledTransactionRecord(
          id: 'sched_${DateTime.now().microsecondsSinceEpoch}',
          type: result.type,
          accountId: result.accountId,
          transferAccountId: result.transferAccountId,
          categoryId: result.categoryId,
          splitLines: result.splitLines,
          payee: result.payee,
          note: result.note,
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
          splitLines: result.splitLines,
          payee: result.payee,
          note: result.note,
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
  if (sourceTransaction == null) {
    await dataStore.saveScheduledTransaction(scheduledTransaction);
  } else {
    await dataStore.saveTransactionAndSchedule(
      transaction: sourceTransaction.copyWith(
        scheduledTransactionId: scheduledTransaction.id,
      ),
      scheduledTransaction: scheduledTransaction,
    );
  }
  return true;
}

Future<T?> showScheduledChoicePicker<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T selected,
  required String Function(T value) label,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.62,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text(
                title,
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final value in values)
                    ListTile(
                      key: ValueKey('scheduled-choice-${label(value)}'),
                      title: Text(label(value)),
                      trailing: value == selected
                          ? Icon(AppIcon.check, color: AppTheme.accent)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    ),
  );
}

Future<void> showScheduledTransactionDetails(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item, {
  DateTime? scheduledDate,
  int? plannedAmountMinor,
  v2_scheduled.ScheduledOccurrenceRecord? occurrenceRecord,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final occurrenceDate = scheduledDate ?? item.nextDate;
  final occurrenceAmount = plannedAmountMinor ?? item.amountMinor;
  String accountName(String? id) {
    for (final account in dataStore.accounts) {
      if (account.id == id) return account.name;
    }
    return 'Unavailable';
  }

  String categoryName(String? id) {
    for (final category in dataStore.categories) {
      if (category.id == id) return category.name;
    }
    return 'Uncategorized';
  }

  String goalName(String id) {
    for (final goal in dataStore.goals) {
      if (goal.id == id) return goal.name;
    }
    return 'Unavailable Goal';
  }

  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) => TransactionSheetFrame(
      title: item.type == TransactionType.goalFunding
          ? 'Scheduled Goal Funding'
          : 'Scheduled Transaction',
      actions: ScheduledTransactionDetailActions(
        onClose: () => Navigator.pop(dialogContext),
        onEdit: occurrenceRecord != null || item.isDeleted
            ? null
            : () => Navigator.pop(dialogContext, 'edit'),
        onMarkPaid: occurrenceRecord == null && !item.isDeleted
            ? () => Navigator.pop(dialogContext, 'paid')
            : occurrenceRecord != null
            ? () => Navigator.pop(dialogContext, 'occurrenceActions')
            : null,
        primaryLabel: occurrenceRecord == null
            ? (item.type == TransactionType.goalFunding
                  ? 'Fund Now'
                  : 'Mark as Paid')
            : 'Actions',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.type != TransactionType.goalFunding)
            ScheduledTransactionDetailRow(
              rowKey: ValueKey('scheduled-detail-payee'),
              icon: item.type == TransactionType.transfer
                  ? AppIcon.description
                  : AppIcon.payee,
              label: item.type == TransactionType.transfer
                  ? 'Description'
                  : 'Payee',
              value: item.payee,
            ),
          if (item.type != TransactionType.goalFunding)
            const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: transactionTypeIcon(item.type),
            label: 'Type',
            value: transactionTypeLabel(item.type),
          ),
          TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: AppIcon.money,
            label: 'Scheduled amount',
            value: money(occurrenceAmount, dataStore.preferences.currency),
            tabularFigures: true,
          ),
          TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: AppIcon.calendar,
            label: 'Next date',
            value: fullMonthDateLabel(occurrenceDate),
          ),
          if (occurrenceRecord != null) ...[
            TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon:
                  occurrenceRecord.status ==
                      v2_scheduled.ScheduledOccurrenceStatus.paid
                  ? AppIcon.success
                  : AppIcon.skip,
              label: 'Status',
              value:
                  occurrenceRecord.status ==
                      v2_scheduled.ScheduledOccurrenceStatus.paid
                  ? (item.type == TransactionType.goalFunding
                        ? 'Funded'
                        : 'Paid')
                  : 'Skipped',
            ),
          ],
          TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: AppIcon.repeat,
            label: 'Frequency',
            value: recurrenceFrequencyLabel(item.frequency),
          ),
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: v2AccountIcon(
              dataStore.accounts
                      .where((account) => account.id == item.accountId)
                      .firstOrNull
                      ?.type ??
                  v2_account.AccountType.otherBanking,
            ),
            label:
                item.type == TransactionType.transfer ||
                    item.type == TransactionType.goalFunding
                ? 'From Account'
                : 'Account',
            value: accountName(item.accountId),
          ),
          if (item.type == TransactionType.goalFunding) ...[
            TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.goal,
              label: 'Goal allocations',
              value:
                  '${item.goalFundingAllocations.length} ${item.goalFundingAllocations.length == 1 ? 'Goal' : 'Goals'}',
              valueColor: _goalBlue,
            ),
            for (final allocation in item.goalFundingAllocations) ...[
              TransactionFormDivider(),
              ScheduledTransactionDetailRow(
                icon: AppIcon.goal,
                label: goalName(allocation.goalId),
                value: money(
                  allocation.amountMinor,
                  dataStore.preferences.currency,
                ),
                valueColor: _goalBlue,
                tabularFigures: true,
              ),
            ],
          ] else if (item.type == TransactionType.transfer) ...[
            TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.wallet,
              label: 'To Account',
              value: accountName(item.transferAccountId),
            ),
          ] else ...[
            TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.category,
              label: 'Category',
              value: categoryName(item.categoryId),
            ),
          ],
          TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: item.alertPreference == v2_scheduled.AlertPreference.none
                ? AppIcon.notificationNone
                : AppIcon.notificationActive,
            label: 'Alert',
            value: alertPreferenceLabel(item.alertPreference),
          ),
          if (item.note.trim().isNotEmpty) ...[
            TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.notes,
              label: 'Notes',
              value: item.note,
            ),
          ],
        ],
      ),
    ),
  );
  if (action == 'edit' && context.mounted) {
    final editDate = occurrenceRecord == null ? occurrenceDate : item.nextDate;
    final editAmount = occurrenceRecord == null
        ? occurrenceAmount
        : item.amountMinor;
    await editScheduledTransactionFromOccurrence(
      context,
      item,
      scheduledDate: editDate,
      plannedAmountMinor: editAmount,
    );
  } else if (action == 'paid' && context.mounted) {
    if (item.type == TransactionType.goalFunding) {
      await fundScheduledGoalFunding(
        context,
        item,
        scheduledDate: occurrenceDate,
      );
    } else {
      await markScheduledTransactionPaid(
        context,
        item,
        scheduledDate: occurrenceDate,
        plannedAmountMinor: occurrenceAmount,
      );
    }
  } else if (action == 'occurrenceActions' &&
      occurrenceRecord != null &&
      context.mounted) {
    await showCompletedScheduledOccurrenceActions(
      context,
      item,
      occurrenceRecord,
    );
  }
}

class ScheduledTransactionDetailRow extends StatelessWidget {
  const ScheduledTransactionDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.leading,
    this.rowKey,
    this.tabularFigures = false,
    this.valueColor,
    super.key,
  });

  final Key? rowKey;
  final IconData icon;
  final String label;
  final String value;
  final Widget? leading;
  final bool tabularFigures;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: rowKey,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leading ?? TransactionFormIcon(icon),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: valueColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  fontFeatures: tabularFigures
                      ? const [FontFeature.tabularFigures()]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ScheduledTransactionDetailActions extends StatelessWidget {
  const ScheduledTransactionDetailActions({
    required this.onClose,
    required this.onEdit,
    required this.onMarkPaid,
    this.onUndoScheduledPayment,
    this.undoScheduledLabel = 'Undo Scheduled Transaction',
    this.primaryLabel = 'Mark as Paid',
    super.key,
  });

  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onUndoScheduledPayment;
  final String undoScheduledLabel;
  final String primaryLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: onClose,
                  child: const Text('Close'),
                ),
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: const Text('Edit'),
                  ),
                ),
              ),
            ],
            if (onMarkPaid != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: const ValueKey('scheduled-detail-mark-paid'),
                    onPressed: onMarkPaid,
                    child: Text(primaryLabel),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (onUndoScheduledPayment != null) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              key: const ValueKey('undo-scheduled-payment'),
              onPressed: onUndoScheduledPayment,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.rose,
                side: BorderSide(color: AppTheme.rose.withValues(alpha: 0.5)),
              ),
              icon: Icon(AppIcon.undo),
              label: Text(undoScheduledLabel),
            ),
          ),
        ],
      ],
    );
  }
}

TransactionRecord? transactionForScheduledOccurrence(
  FinanceDataStore dataStore,
  v2_scheduled.ScheduledTransactionRecord item,
  v2_scheduled.ScheduledOccurrenceRecord occurrence,
) {
  if (occurrence.transactionId != null) {
    final byId = dataStore.transactions
        .where(
          (transaction) =>
              transaction.id == occurrence.transactionId &&
              !transaction.isDeleted,
        )
        .firstOrNull;
    if (byId != null) return byId;
  }
  return dataStore.transactions
      .where(
        (transaction) =>
            !transaction.isDeleted &&
            transaction.scheduledTransactionId == item.id &&
            transaction.scheduledOccurrenceDate != null &&
            isSameCalendarDay(
              transaction.scheduledOccurrenceDate!,
              occurrence.scheduledDate,
            ),
      )
      .firstOrNull;
}

Future<void> showCompletedScheduledOccurrenceActions(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item,
  v2_scheduled.ScheduledOccurrenceRecord occurrence,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  if (item.type == TransactionType.goalFunding) {
    final event = dataStore.goalFundingEvents
        .where(
          (event) =>
              event.id == occurrence.goalFundingEventId && event.isActive,
        )
        .firstOrNull;
    if (event != null) await showGoalFundingDetails(context, event.id);
    return;
  }
  final transaction = transactionForScheduledOccurrence(
    dataStore,
    item,
    occurrence,
  );
  final undoTarget = transaction == null
      ? null
      : dataStore.scheduledPaymentUndoTarget(transaction.id);
  final canRestore =
      item.isDeleted &&
      nextScheduledDate(item.copyWith(nextDate: occurrence.scheduledDate)) !=
          null;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (transaction != null)
            ListTile(
              leading: Icon(AppIcon.edit),
              title: Text('Edit payment'),
              onTap: () => Navigator.pop(sheetContext, 'editPayment'),
            ),
          if (!item.isDeleted)
            ListTile(
              leading: Icon(AppIcon.recurrence),
              title: Text('Edit future schedule'),
              onTap: () => Navigator.pop(sheetContext, 'editFuture'),
            ),
          if (canRestore)
            ListTile(
              leading: Icon(AppIcon.restore),
              title: Text('Restore future schedule'),
              onTap: () => Navigator.pop(sheetContext, 'restoreFuture'),
            ),
          if (undoTarget != null)
            ListTile(
              key: const ValueKey('scheduled-occurrence-undo-action'),
              leading: Icon(AppIcon.undo),
              title: Text(undoScheduledTransactionLabel(item.type)),
              subtitle: const Text(
                'Restore this occurrence to its original date',
              ),
              textColor: AppTheme.rose,
              iconColor: AppTheme.rose,
              onTap: () => Navigator.pop(sheetContext, 'undoScheduled'),
            ),
          ListTile(
            leading: Icon(AppIcon.delete),
            title: const Text('Delete occurrence'),
            subtitle: Text(
              transaction == null
                  ? 'Remove this scheduled history entry'
                  : 'Also removes its ledger transaction',
            ),
            textColor: AppTheme.rose,
            iconColor: AppTheme.rose,
            onTap: () => Navigator.pop(sheetContext, 'deleteOccurrence'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case 'editPayment':
      if (transaction == null) return;
      if (transaction.type == TransactionType.transfer) {
        await showTransferDialog(context, transfer: transaction);
      } else {
        await showTransactionDialog(context, transaction: transaction);
      }
    case 'editFuture':
      await editScheduledTransactionFromOccurrence(
        context,
        item,
        scheduledDate: item.nextDate,
        plannedAmountMinor: item.amountMinor,
      );
    case 'restoreFuture':
      await restoreScheduledTransactionAfterOccurrence(
        context,
        item,
        occurrence,
      );
    case 'undoScheduled':
      if (transaction == null || undoTarget == null) return;
      await showUndoScheduledPaymentConfirmation(
        context,
        transactionId: transaction.id,
        target: undoTarget,
      );
    case 'deleteOccurrence':
      await deleteCompletedScheduledOccurrence(
        context,
        item,
        occurrence,
        transaction,
      );
  }
}

Future<void> restoreScheduledTransactionAfterOccurrence(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item,
  v2_scheduled.ScheduledOccurrenceRecord occurrence,
) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final nextDate = nextDateForScheduledFrequency(
    occurrence.scheduledDate,
    item.frequency,
  );
  if (nextDate == null) return;
  await showScheduledTransactionDialog(
    context,
    existing: v2_scheduled.ScheduledTransactionRecord(
      id: 'sched_${DateTime.now().microsecondsSinceEpoch}',
      type: item.type,
      accountId: item.accountId,
      transferAccountId: item.transferAccountId,
      categoryId: item.categoryId,
      splitLines: item.splitLines,
      goalFundingAllocations: item.goalFundingAllocations,
      payee: item.payee,
      note: item.note,
      amountMinor: item.amountMinor,
      nextDate: nextDate,
      frequency: item.frequency,
      endDate: item.endDate != null && !item.endDate!.isBefore(nextDate)
          ? item.endDate
          : null,
      alertPreference: item.alertPreference,
      customAlertTimeMinutes: item.customAlertTimeMinutes,
      repeatAlertUntilResolved: item.repeatAlertUntilResolved,
      sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
    ),
  );
}

Future<void> deleteCompletedScheduledOccurrence(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item,
  v2_scheduled.ScheduledOccurrenceRecord occurrence,
  TransactionRecord? transaction,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete occurrence?'),
      content: Text(
        transaction == null
            ? 'This removes the selected scheduled history entry.'
            : 'This removes the selected scheduled history entry and its ledger transaction.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.rose),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final dataStore = FinanceDataStoreScope.read(context);
  if (transaction != null) await deleteTransaction(context, transaction);
  await dataStore.saveScheduledTransaction(
    item.copyWith(
      occurrences: item.occurrences
          .where(
            (existing) =>
                !isSameCalendarDay(
                  existing.scheduledDate,
                  occurrence.scheduledDate,
                ) ||
                existing.status != occurrence.status,
          )
          .toList(growable: false),
      sync: item.sync.touched(deviceId: dataStore.deviceId),
    ),
  );
}

Future<void> showScheduledTransactionActions(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item, {
  DateTime? scheduledDate,
  int? plannedAmountMinor,
  Set<String>? allowedActions,
}) async {
  final occurrenceDate = scheduledDate ?? item.nextDate;
  final occurrenceAmount = plannedAmountMinor ?? item.amountMinor;
  bool allows(String action) =>
      allowedActions == null || allowedActions.contains(action);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allows('paid'))
            ListTile(
              leading: Icon(AppIcon.success),
              title: Text(
                item.type == TransactionType.goalFunding
                    ? 'Fund Now'
                    : 'Mark as Paid',
              ),
              onTap: () => Navigator.pop(sheetContext, 'paid'),
            ),
          if (allows('skip'))
            ListTile(
              leading: Icon(AppIcon.skip),
              title: Text('Skip Once'),
              onTap: () => Navigator.pop(sheetContext, 'skip'),
            ),
          if (allows('edit'))
            ListTile(
              leading: Icon(AppIcon.edit),
              title: Text('Edit'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
          if (allows('duplicate'))
            ListTile(
              leading: Icon(AppIcon.copy),
              title: Text('Duplicate'),
              onTap: () => Navigator.pop(sheetContext, 'duplicate'),
            ),
          if (allows('delete'))
            ListTile(
              leading: Icon(AppIcon.delete),
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
      if (item.type == TransactionType.goalFunding) {
        await fundScheduledGoalFunding(
          context,
          item,
          scheduledDate: occurrenceDate,
        );
      } else {
        await markScheduledTransactionPaid(
          context,
          item,
          scheduledDate: occurrenceDate,
          plannedAmountMinor: occurrenceAmount,
        );
      }
    case 'skip':
      await skipScheduledTransactionOnce(
        context,
        item,
        scheduledDate: occurrenceDate,
        plannedAmountMinor: occurrenceAmount,
      );
    case 'edit':
      await editScheduledTransactionFromOccurrence(
        context,
        item,
        scheduledDate: occurrenceDate,
        plannedAmountMinor: occurrenceAmount,
      );
    case 'duplicate':
      await duplicateScheduledTransaction(
        context,
        item.copyWith(
          nextDate: occurrenceDate,
          amountMinor: occurrenceAmount,
          sync: item.sync,
        ),
      );
    case 'delete':
      await deleteScheduledTransaction(context, item, fromDate: occurrenceDate);
  }
}

Future<void> editScheduledTransactionFromOccurrence(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item, {
  required DateTime scheduledDate,
  required int plannedAmountMinor,
}) async {
  if (isSameCalendarDay(scheduledDate, item.nextDate)) {
    await showScheduledTransactionDialog(
      context,
      existing: item.copyWith(amountMinor: plannedAmountMinor, sync: item.sync),
    );
    return;
  }

  final dataStore = FinanceDataStoreScope.read(context);
  final futureItem = v2_scheduled.ScheduledTransactionRecord(
    id: '${item.id}_from_${calendarDateId(scheduledDate)}_${DateTime.now().microsecondsSinceEpoch}',
    type: item.type,
    accountId: item.accountId,
    transferAccountId: item.transferAccountId,
    categoryId: item.categoryId,
    splitLines: item.splitLines,
    goalFundingAllocations: item.goalFundingAllocations,
    payee: item.payee,
    note: item.note,
    amountMinor: plannedAmountMinor,
    nextDate: scheduledDate,
    frequency: item.frequency,
    endDate: item.endDate,
    alertPreference: item.alertPreference,
    customAlertTimeMinutes: item.customAlertTimeMinutes,
    repeatAlertUntilResolved: item.repeatAlertUntilResolved,
    sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
  );
  final saved = await showScheduledTransactionDialog(
    context,
    existing: futureItem,
  );
  if (!saved) return;

  final cutoff = DateTime(
    scheduledDate.year,
    scheduledDate.month,
    scheduledDate.day,
  ).subtract(const Duration(days: 1));
  await dataStore.saveScheduledTransaction(
    item.copyWith(
      endDate: cutoff,
      scheduledNotificationIds: const [],
      sync: item.sync.touched(deviceId: dataStore.deviceId),
      clearLastReminderScheduledAt: true,
    ),
  );
}

Future<void> markScheduledTransactionPaid(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item, {
  DateTime? scheduledDate,
  int? plannedAmountMinor,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final occurrenceDate = scheduledDate ?? item.nextDate;
  final occurrenceAmount = plannedAmountMinor ?? item.amountMinor;
  final actualAmount = occurrenceAmount.abs();
  var actualAmountMinor = actualAmount;
  final paymentDate = TextEditingController(text: dateInput(DateTime.now()));
  final payee = TextEditingController(text: item.payee);
  final note = TextEditingController(text: item.note);
  var selectedCategoryId = item.categoryId;
  final paymentSplitDrafts = item.type == TransactionType.transfer
      ? <SplitLineDraft>[]
      : (item.effectiveCategoryAllocations.isNotEmpty
            ? item.effectiveCategoryAllocations
                  .map(
                    (line) => SplitLineDraft(
                      id: line.id,
                      categoryId: line.categoryId,
                      amountMinor: line.amountMinor,
                      noteText: line.note,
                    ),
                  )
                  .toList()
            : <SplitLineDraft>[
                SplitLineDraft(
                  id: 'split_${DateTime.now().microsecondsSinceEpoch}_0',
                  categoryId: item.categoryId ?? '',
                  amountMinor: occurrenceAmount.abs(),
                ),
              ]);
  var isSubmitting = false;
  String? errorMessage;

  v2_account.AccountRecord? accountById(String? id) {
    return dataStore.accounts.where((account) => account.id == id).firstOrNull;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final theme = Theme.of(dialogContext);
        final sourceAccount = accountById(item.accountId);
        final destinationAccount = accountById(item.transferAccountId);
        final isTransfer = item.type == TransactionType.transfer;
        final categories = scheduledCategoriesForType(dataStore, item.type);
        for (final draft in paymentSplitDrafts) {
          if (!categories.any((category) => category.id == draft.categoryId)) {
            draft.categoryId = '';
          }
        }
        if (!isTransfer && paymentSplitDrafts.isNotEmpty) {
          selectedCategoryId = paymentSplitDrafts.first.categoryId.isEmpty
              ? null
              : paymentSplitDrafts.first.categoryId;
        }
        final splitTotalMinor = paymentSplitDrafts.fold<int>(
          0,
          (total, line) => total + line.amountMinor.abs(),
        );
        final splitCategoryIds = paymentSplitDrafts
            .map((line) => line.categoryId)
            .where((id) => id.isNotEmpty)
            .toSet();
        final splitIsBalanced =
            isTransfer ||
            (paymentSplitDrafts.isNotEmpty &&
                paymentSplitDrafts.every(
                  (line) => line.categoryId.isNotEmpty && line.amountMinor > 0,
                ) &&
                splitCategoryIds.length == paymentSplitDrafts.length &&
                splitTotalMinor == actualAmountMinor.abs());
        final canConfirm =
            actualAmountMinor.abs() > 0 &&
            sourceAccount != null &&
            (!isTransfer ||
                (destinationAccount != null &&
                    destinationAccount.id != sourceAccount.id)) &&
            splitIsBalanced;
        final fieldValueStyle = theme.textTheme.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.15,
        );
        final fieldHintStyle = fieldValueStyle?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );

        Widget readOnlyRow({
          required Key rowKey,
          required IconData icon,
          required String value,
          String? secondary,
          bool tabular = false,
          VoidCallback? onTap,
        }) {
          final content = Row(
            children: [
              TransactionFormIcon(icon),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                        fontFeatures: tabular
                            ? const [FontFeature.tabularFigures()]
                            : null,
                      ),
                    ),
                    if (secondary != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        secondary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.72,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
          if (onTap == null) return KeyedSubtree(key: rowKey, child: content);
          return InkWell(
            key: rowKey,
            borderRadius: BorderRadius.circular(AppRadii.control),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: content),
                  Icon(AppIcon.chevronDown, size: AppIconSize.hero),
                ],
              ),
            ),
          );
        }

        Future<void> choosePaymentSplitCategory(int index) async {
          FocusManager.instance.primaryFocus?.unfocus();
          final selectedId = await showTransactionCategoryFlow(
            dialogContext,
            dataStore: dataStore,
            isExpense: item.type == TransactionType.expense,
            selectedCategoryId: paymentSplitDrafts[index].categoryId,
          );
          if (selectedId == null || !dialogContext.mounted) return;
          setDialogState(() {
            paymentSplitDrafts[index].categoryId = selectedId;
            if (index == 0) selectedCategoryId = selectedId;
          });
        }

        List<TransactionSplitLine> buildPaymentSplitLines() {
          if (isTransfer || !item.isCategorySplit) return const [];
          return [
            for (var index = 0; index < paymentSplitDrafts.length; index++)
              TransactionSplitLine(
                id:
                    paymentSplitDrafts[index].id ??
                    'split_${DateTime.now().microsecondsSinceEpoch}_$index',
                categoryId: paymentSplitDrafts[index].categoryId,
                amountMinor: paymentSplitDrafts[index].amountMinor.abs(),
                note: paymentSplitDrafts[index].note.text.trim(),
              ),
          ];
        }

        Future<void> confirmPayment() async {
          if (!canConfirm || isSubmitting) return;
          FocusManager.instance.primaryFocus?.unfocus();
          setDialogState(() {
            isSubmitting = true;
            errorMessage = null;
          });
          try {
            final paymentItem = isTransfer
                ? item
                : item.copyWith(
                    categoryId: selectedCategoryId,
                    sync: item.sync,
                  );
            await completeScheduledTransactionPayment(
              dataStore,
              paymentItem,
              scheduledDate: occurrenceDate,
              plannedAmountMinor: occurrenceAmount,
              actualAmountMinor: actualAmountMinor.abs(),
              paymentDate: parseDateInput(paymentDate.text, DateTime.now()),
              payee: payee.text.trim().isEmpty
                  ? scheduledPayeeFallback(item.type)
                  : payee.text.trim(),
              note: note.text.trim(),
              splitLines: buildPaymentSplitLines(),
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (_) {
            if (!dialogContext.mounted) return;
            setDialogState(() {
              isSubmitting = false;
              errorMessage =
                  'The payment could not be saved. Please try again.';
            });
          }
        }

        return TransactionSheetFrame(
          title: 'Mark as Paid',
          actions: TransactionFormActions(
            onCancel: () => Navigator.pop(dialogContext),
            onSave: confirmPayment,
            canSave: canConfirm,
            saveLabel: 'Confirm',
            isSaving: isSubmitting,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TransactionFormLabel('Scheduled amount'),
              readOnlyRow(
                rowKey: ValueKey('mark-paid-scheduled-amount'),
                icon: AppIcon.eventNote,
                value: money(
                  occurrenceAmount.abs(),
                  dataStore.preferences.currency,
                ),
                secondary: 'Planned for this occurrence',
                tabular: true,
              ),
              TransactionFormDivider(),
              TransactionFormLabel('Actual amount'),
              Row(
                children: [
                  TransactionFormIcon(AppIcon.money),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AmountEntryField(
                      fieldKey: const ValueKey('mark-paid-actual-amount'),
                      initialMinor: actualAmount,
                      currency: dataStore.preferences.currency,
                      labelText: null,
                      selectAllOnFocus: true,
                      textAlign: TextAlign.left,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      onChanged: (value) =>
                          setDialogState(() => actualAmountMinor = value.abs()),
                    ),
                  ),
                ],
              ),
              const TransactionFormDivider(),
              const TransactionFormLabel('Payment date'),
              InkWell(
                key: const ValueKey('mark-paid-date'),
                borderRadius: BorderRadius.circular(AppRadii.control),
                onTap: () async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  final picked = await pickDateForField(
                    dialogContext,
                    parseDateInput(paymentDate.text, DateTime.now()),
                  );
                  if (picked != null) {
                    setDialogState(() => paymentDate.text = dateInput(picked));
                  }
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      TransactionFormIcon(AppIcon.calendar),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          fullMonthDateLabel(
                            parseDateInput(paymentDate.text, DateTime.now()),
                          ),
                          style: fieldValueStyle?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        isSameCalendarDay(
                              parseDateInput(paymentDate.text, DateTime.now()),
                              DateTime.now(),
                            )
                            ? 'Today'
                            : '',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Icon(
                        AppIcon.event,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              TransactionFormDivider(),
              TransactionFormLabel(isTransfer ? 'From Account' : 'Account'),
              readOnlyRow(
                rowKey: ValueKey('mark-paid-account'),
                icon: sourceAccount == null
                    ? AppIcon.wallet
                    : v2AccountIcon(sourceAccount.type),
                value: sourceAccount?.name ?? 'Unavailable account',
                secondary: sourceAccount == null
                    ? null
                    : 'Balance ${money(dataStore.balanceForAccount(sourceAccount.id), dataStore.preferences.currency)}',
              ),
              if (isTransfer) ...[
                TransactionFormDivider(),
                TransactionFormLabel('To Account'),
                readOnlyRow(
                  rowKey: ValueKey('mark-paid-to-account'),
                  icon: destinationAccount == null
                      ? AppIcon.wallet
                      : v2AccountIcon(destinationAccount.type),
                  value: destinationAccount?.name ?? 'Unavailable destination',
                  secondary: destinationAccount == null
                      ? null
                      : 'Balance ${money(dataStore.balanceForAccount(destinationAccount.id), dataStore.preferences.currency)}',
                ),
              ],
              const TransactionFormDivider(),
              TransactionFormLabel(isTransfer ? 'Description' : 'Payee'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TransactionFormIcon(
                    isTransfer ? AppIcon.description : AppIcon.payee,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('mark-paid-payee'),
                      controller: payee,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: InputDecoration(
                        hintText: isTransfer
                            ? 'Add a description (optional)'
                            : 'Add a payee (optional)',
                        hintStyle: fieldHintStyle,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: fieldValueStyle,
                    ),
                  ),
                ],
              ),
              if (!isTransfer) ...[
                const TransactionFormDivider(),
                InlineSplitAllocationSection(
                  keyPrefix: 'mark-paid',
                  drafts: paymentSplitDrafts,
                  categories: categories,
                  currency: dataStore.preferences.currency,
                  totalMinor: actualAmountMinor.abs(),
                  firstAutoRemainder: false,
                  onChooseCategory: choosePaymentSplitCategory,
                  onAmountChanged: (index, value) => setDialogState(
                    () => paymentSplitDrafts[index].amountMinor = value.abs(),
                  ),
                  onAdd: () => setDialogState(() {
                    final currentTotal = paymentSplitDrafts.fold<int>(
                      0,
                      (total, line) => total + line.amountMinor.abs(),
                    );
                    final remainder = actualAmountMinor.abs() - currentTotal;
                    paymentSplitDrafts.add(
                      SplitLineDraft(
                        id: 'split_${DateTime.now().microsecondsSinceEpoch}_${paymentSplitDrafts.length}',
                        categoryId: '',
                        amountMinor: remainder > 0 ? remainder : 0,
                      ),
                    );
                  }),
                  onRemove: (index) => setDialogState(() {
                    paymentSplitDrafts[index].note.dispose();
                    paymentSplitDrafts.removeAt(index);
                    selectedCategoryId =
                        paymentSplitDrafts.first.categoryId.isEmpty
                        ? null
                        : paymentSplitDrafts.first.categoryId;
                  }),
                ),
              ],
              TransactionFormDivider(),
              TransactionFormLabel('Notes'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TransactionFormIcon(AppIcon.notes),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('mark-paid-note'),
                      controller: note,
                      textCapitalization: TextCapitalization.sentences,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: InputDecoration(
                        hintText: 'Add a note (optional)',
                        hintStyle: fieldHintStyle,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: fieldValueStyle,
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  errorMessage!,
                  key: const ValueKey('mark-paid-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
  for (final draft in paymentSplitDrafts) {
    draft.note.dispose();
  }
}

Future<void> fundScheduledGoalFunding(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item, {
  DateTime? scheduledDate,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final occurrenceDate = scheduledDate ?? item.nextDate;
  final account = dataStore.accounts
      .where((account) => account.id == item.accountId)
      .firstOrNull;
  final goalsById = {for (final goal in dataStore.goals) goal.id: goal};
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => TransactionSheetFrame(
      title: 'Fund Goals Now?',
      actions: TransactionFormActions(
        onCancel: () => Navigator.pop(dialogContext, false),
        canSave: account != null && item.hasValidGoalFundingAllocations,
        saveLabel: 'Fund Now',
        onSave: () => Navigator.pop(dialogContext, true),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This moves ${money(item.amountMinor, dataStore.preferences.currency)} from ${account?.name ?? 'the selected account'} into your Goals.',
            style: Theme.of(dialogContext).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final allocation in item.goalFundingAllocations)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    AppIcon.goal,
                    color: _goalBlue,
                    size: AppIconSize.compact,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      goalsById[allocation.goalId]?.name ?? 'Unavailable Goal',
                    ),
                  ),
                  Text(
                    money(
                      allocation.amountMinor,
                      dataStore.preferences.currency,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await dataStore.completeScheduledGoalFunding(
      scheduledTransactionId: item.id,
      occurrenceDate: occurrenceDate,
    );
  } on FinanceDataValidationException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }
}

Future<TransactionRecord> completeScheduledTransactionPayment(
  FinanceDataStore dataStore,
  v2_scheduled.ScheduledTransactionRecord item, {
  DateTime? scheduledDate,
  int? plannedAmountMinor,
  required int actualAmountMinor,
  required DateTime paymentDate,
  required String payee,
  required String note,
  List<TransactionSplitLine> splitLines = const [],
}) async {
  final occurrenceDate = scheduledDate ?? item.nextDate;
  final occurrenceAmount = plannedAmountMinor ?? item.amountMinor;
  final existingTransaction = dataStore.transactions
      .where(
        (transaction) =>
            !transaction.isDeleted &&
            transaction.scheduledTransactionId == item.id &&
            transaction.scheduledOccurrenceDate != null &&
            isSameCalendarDay(
              transaction.scheduledOccurrenceDate!,
              occurrenceDate,
            ),
      )
      .firstOrNull;
  final transaction =
      existingTransaction ??
      await _createScheduledOccurrenceTransaction(
        dataStore,
        item,
        scheduledDate: occurrenceDate,
        plannedAmountMinor: occurrenceAmount,
        actualAmountMinor: actualAmountMinor,
        paymentDate: paymentDate,
        payee: payee,
        note: note,
        splitLines: splitLines,
      );
  final occurrence = v2_scheduled.ScheduledOccurrenceRecord(
    scheduledDate: occurrenceDate,
    plannedAmountMinor: occurrenceAmount.abs(),
    status: v2_scheduled.ScheduledOccurrenceStatus.paid,
    actualAmountMinor: transaction.amountMinor.abs(),
    actualPaymentDate: transaction.date,
    transactionId: transaction.id,
  );
  await recordScheduledOccurrence(
    dataStore,
    item,
    v2_scheduled.ScheduledAction.paid,
    occurrence: occurrence,
  );
  return transaction;
}

Future<TransactionRecord> _createScheduledOccurrenceTransaction(
  FinanceDataStore dataStore,
  v2_scheduled.ScheduledTransactionRecord item, {
  required DateTime scheduledDate,
  required int plannedAmountMinor,
  required int actualAmountMinor,
  required DateTime paymentDate,
  required String payee,
  required String note,
  required List<TransactionSplitLine> splitLines,
}) async {
  switch (item.type) {
    case TransactionType.expense:
      if (item.categoryId == null) {
        throw StateError('A category is required');
      }
      return dataStore.addExpense(
        accountId: item.accountId,
        categoryId: item.categoryId!,
        date: paymentDate,
        payee: payee,
        amountMinor: actualAmountMinor,
        note: note,
        splitLines: splitLines,
        scheduledTransactionId: item.id,
        scheduledOccurrenceDate: scheduledDate,
        scheduledPlannedAmountMinor: plannedAmountMinor.abs(),
      );
    case TransactionType.income:
      if (item.categoryId == null) {
        throw StateError('A category is required');
      }
      return dataStore.addIncome(
        accountId: item.accountId,
        categoryId: item.categoryId!,
        date: paymentDate,
        payee: payee,
        amountMinor: actualAmountMinor,
        note: note,
        splitLines: splitLines,
        scheduledTransactionId: item.id,
        scheduledOccurrenceDate: scheduledDate,
        scheduledPlannedAmountMinor: plannedAmountMinor.abs(),
      );
    case TransactionType.transfer:
      if (item.transferAccountId == null ||
          item.transferAccountId == item.accountId) {
        throw StateError('A distinct destination is required');
      }
      return dataStore.addTransfer(
        fromAccountId: item.accountId,
        toAccountId: item.transferAccountId!,
        date: paymentDate,
        payee: payee,
        amountMinor: actualAmountMinor,
        note: note,
        scheduledTransactionId: item.id,
        scheduledOccurrenceDate: scheduledDate,
        scheduledPlannedAmountMinor: plannedAmountMinor.abs(),
      );
    case TransactionType.goalFunding:
      throw StateError('Goal Funding does not create a transaction record.');
    case TransactionType.adjustment:
      throw StateError('Adjustments cannot be scheduled');
  }
}

Future<void> skipScheduledTransactionOnce(
  BuildContext context,
  v2_scheduled.ScheduledTransactionRecord item, {
  DateTime? scheduledDate,
  int? plannedAmountMinor,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final occurrenceDate = scheduledDate ?? item.nextDate;
  final occurrenceAmount = plannedAmountMinor ?? item.amountMinor;
  await recordScheduledOccurrence(
    dataStore,
    item,
    v2_scheduled.ScheduledAction.skipped,
    occurrence: v2_scheduled.ScheduledOccurrenceRecord(
      scheduledDate: occurrenceDate,
      plannedAmountMinor: occurrenceAmount.abs(),
      status: v2_scheduled.ScheduledOccurrenceStatus.skipped,
    ),
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
      splitLines: item.splitLines,
      goalFundingAllocations: item.goalFundingAllocations,
      payee: '${item.payee} copy',
      note: item.note,
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
  v2_scheduled.ScheduledTransactionRecord item, {
  DateTime? fromDate,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete Scheduled Transaction?'),
      content: const Text(
        'This will permanently delete this recurring transaction and all future scheduled occurrences.\n\n'
        'Past transactions that have already been completed will not be affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-delete-scheduled-transaction'),
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.rose),
          child: const Text('Delete Schedule'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final dataStore = FinanceDataStoreScope.read(context);
  if (fromDate != null && fromDate.isAfter(item.nextDate)) {
    final cutoff = DateTime(
      fromDate.year,
      fromDate.month,
      fromDate.day,
    ).subtract(const Duration(days: 1));
    final existingEndDate = item.endDate;
    await dataStore.saveScheduledTransaction(
      item.copyWith(
        endDate: existingEndDate != null && existingEndDate.isBefore(cutoff)
            ? existingEndDate
            : cutoff,
        scheduledNotificationIds: const [],
        sync: item.sync.touched(deviceId: dataStore.deviceId),
        clearLastReminderScheduledAt: true,
      ),
    );
    return;
  }
  await dataStore.saveScheduledTransaction(
    item.copyWith(sync: item.sync.deleted(deviceId: dataStore.deviceId)),
  );
}

Future<void> recordScheduledOccurrence(
  FinanceDataStore dataStore,
  v2_scheduled.ScheduledTransactionRecord item,
  v2_scheduled.ScheduledAction action, {
  required v2_scheduled.ScheduledOccurrenceRecord occurrence,
}) async {
  if (isSameCalendarDay(occurrence.scheduledDate, item.nextDate)) {
    await advanceOrCloseScheduledTransaction(
      dataStore,
      item,
      action,
      occurrence: occurrence,
    );
    return;
  }

  final occurrences = [
    for (final existing in item.occurrences)
      if (!isSameCalendarDay(existing.scheduledDate, occurrence.scheduledDate))
        existing,
    occurrence,
  ];
  await dataStore.saveScheduledTransaction(
    item.copyWith(
      occurrences: occurrences,
      scheduledNotificationIds: const [],
      sync: item.sync.touched(deviceId: dataStore.deviceId),
      clearLastReminderScheduledAt: true,
    ),
  );
}

Future<void> advanceOrCloseScheduledTransaction(
  FinanceDataStore dataStore,
  v2_scheduled.ScheduledTransactionRecord item,
  v2_scheduled.ScheduledAction action, {
  v2_scheduled.ScheduledOccurrenceRecord? occurrence,
}) async {
  final occurrences = occurrence == null
      ? [...item.occurrences]
      : [
          for (final existing in item.occurrences)
            if (!isSameCalendarDay(
              existing.scheduledDate,
              occurrence.scheduledDate,
            ))
              existing,
          occurrence,
        ];
  final nextDate = nextScheduledDate(item);
  if (nextDate == null || nextDate.isAfter(item.endDate ?? DateTime(9999))) {
    await dataStore.saveScheduledTransaction(
      item.copyWith(
        lastAction: action,
        occurrences: occurrences,
        sync: item.sync.deleted(deviceId: dataStore.deviceId),
      ),
    );
    return;
  }
  await dataStore.saveScheduledTransaction(
    item.copyWith(
      nextDate: nextDate,
      lastAction: v2_scheduled.ScheduledAction.none,
      occurrences: occurrences,
      sync: item.sync.touched(deviceId: dataStore.deviceId),
    ),
  );
}

DateTime? nextScheduledDate(v2_scheduled.ScheduledTransactionRecord item) {
  return nextDateForScheduledFrequency(item.nextDate, item.frequency);
}

DateTime? nextDateForScheduledFrequency(
  DateTime date,
  v2_scheduled.RecurrenceFrequency frequency,
) {
  return switch (frequency) {
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
  bool initialSplitMode = false,
  bool initialScheduleFutureOccurrences = false,
  FutureScheduleDraft? initialFutureSchedule,
}) async {
  final dataStore = FinanceDataStoreScope.read(context);
  final activeAccounts = [...dataStore.activeAccountsInDisplayOrder];
  // Goal spending is intentionally launched from Goal Details. The internal
  // Goal account stays hidden from ordinary global account pickers, but must
  // remain available to that contextual expense form.
  final contextualAccountId = transaction?.accountId ?? initialAccountId;
  if (contextualAccountId != null &&
      !activeAccounts.any((account) => account.id == contextualAccountId)) {
    final contextual = dataStore.accounts
        .where(
          (account) => account.id == contextualAccountId && account.isVisible,
        )
        .firstOrNull;
    if (contextual != null) activeAccounts.add(contextual);
  }
  if (activeAccounts.isEmpty) return;
  final payeeOptions = savedPayees(dataStore);
  final payee = TextEditingController(text: transaction?.payee ?? '');
  final note = TextEditingController(text: transaction?.note ?? '');
  final date = TextEditingController(
    text: dateInput(transaction?.date ?? DateTime.now()),
  );
  final newCategoryName = TextEditingController();
  final newCategoryFocusNode = FocusNode();
  final futureSchedule =
      initialFutureSchedule ??
      FutureScheduleDraft(
        firstDate: firstMonthlyDateAfter(
          transaction?.date ?? DateTime.now(),
          DateTime.now(),
        ),
      );
  var amountMinor = transaction?.amountMinor.abs() ?? 0;
  var accountId =
      activeAccounts.any(
        (account) => account.id == (transaction?.accountId ?? initialAccountId),
      )
      ? (transaction?.accountId ?? initialAccountId)!
      : '';
  var isExpense =
      transaction?.type == TransactionType.expense ||
      (transaction?.type == TransactionType.transfer &&
          (initialIsExpense ?? true)) ||
      (transaction == null &&
          (initialIsExpense ?? isExpenseDefault(dataStore.preferences)));
  var categoryId = transaction?.categoryId ?? '';
  final hasExistingSplit = transaction?.isCategorySplit ?? false;
  var firstSplitAutoRemainder = !hasExistingSplit;
  final splitDrafts =
      transaction?.effectiveCategoryAllocations
          .map(
            (line) => SplitLineDraft(
              id: line.id,
              categoryId: line.categoryId,
              amountMinor: line.amountMinor,
              noteText: line.note,
            ),
          )
          .toList() ??
      <SplitLineDraft>[];
  if (categoryId.isEmpty && splitDrafts.isNotEmpty) {
    categoryId = splitDrafts.first.categoryId;
  }
  if (splitDrafts.isEmpty) {
    splitDrafts.add(
      SplitLineDraft(
        id: 'split_${DateTime.now().microsecondsSinceEpoch}_0',
        categoryId: categoryId,
        amountMinor: amountMinor.abs(),
      ),
    );
  }
  var splitMode = hasExistingSplit || initialSplitMode;
  if (splitMode && splitDrafts.length == 1 && categoryId.isNotEmpty) {
    splitDrafts.add(
      SplitLineDraft(
        id: 'split_${DateTime.now().microsecondsSinceEpoch}_1',
        categoryId: '',
        amountMinor: 0,
      ),
    );
  }
  var autofocusSecondSplitAmount = initialSplitMode && !hasExistingSplit;
  final splitSectionKey = GlobalKey();
  var switchToTransfer = false;
  var isCreatingCategory = false;
  var isSavingCategory = false;
  String? newCategoryError;
  int? newCategorySplitIndex;
  final linkedSchedule = transaction?.scheduledTransactionId == null
      ? null
      : dataStore.scheduledTransactions
            .where(
              (item) =>
                  item.id == transaction!.scheduledTransactionId &&
                  !item.isDeleted,
            )
            .firstOrNull;
  var editLinkedSchedule = false;
  var scheduleFutureOccurrences =
      linkedSchedule == null && initialScheduleFutureOccurrences;

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
          List<TransactionSplitLine> splitLines,
          bool scheduleFutureOccurrences,
          DateTime firstScheduledDate,
          int scheduledTimeMinutes,
          v2_scheduled.RecurrenceFrequency scheduledFrequency,
          v2_scheduled.AlertPreference scheduledAlertPreference,
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
              categoryId = '';
            }
            for (final draft in splitDrafts) {
              if (!categoryOptions.any(
                (category) => category.id == draft.categoryId,
              )) {
                draft.categoryId = '';
              }
            }

            final theme = Theme.of(context);
            final selectedCategory = categoryOptions
                .where((category) => category.id == categoryId)
                .firstOrNull;
            final selectedAccount = accountId.isEmpty
                ? null
                : activeAccounts.firstWhere(
                    (account) => account.id == accountId,
                  );
            final currentBalanceMinor = selectedAccount == null
                ? 0
                : dataStore.balanceForAccount(selectedAccount.id);
            final balanceWithoutExistingTransaction = selectedAccount == null
                ? 0
                : currentBalanceMinor -
                      (transaction?.deltaForAccount(selectedAccount.id) ?? 0);
            final previewBalanceMinor = selectedAccount == null
                ? 0
                : isExpense
                ? balanceWithoutExistingTransaction - amountMinor.abs()
                : balanceWithoutExistingTransaction + amountMinor.abs();
            final wouldOverdrawAsset =
                selectedAccount != null &&
                accountIsAsset(selectedAccount) &&
                isExpense &&
                previewBalanceMinor < 0;
            final mutedStyle = theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              height: 1.18,
              fontWeight: FontWeight.w400,
            );
            final accountRowStyle = theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              height: 1.08,
            );
            final fieldValueStyle = theme.textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              height: 1.15,
            );
            final fieldHintStyle = fieldValueStyle?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            );
            final absoluteAmountMinor = amountMinor.abs();

            String newSplitId() =>
                'split_${DateTime.now().microsecondsSinceEpoch}_${splitDrafts.length}';

            void syncPrimaryCategoryFromSplit() {
              if (splitDrafts.isNotEmpty) {
                categoryId = splitDrafts.first.categoryId;
              }
            }

            void ensureSplitDrafts() {
              if (splitDrafts.isNotEmpty) return;
              splitDrafts.add(
                SplitLineDraft(
                  id: newSplitId(),
                  categoryId: categoryId,
                  amountMinor: absoluteAmountMinor,
                ),
              );
              firstSplitAutoRemainder = true;
            }

            void recalculateAutoRemainder() {
              if (!firstSplitAutoRemainder || splitDrafts.isEmpty) {
                return;
              }
              final otherTotal = splitDrafts
                  .skip(1)
                  .fold<int>(
                    0,
                    (total, line) => total + line.amountMinor.abs(),
                  );
              final remainder = absoluteAmountMinor - otherTotal;
              splitDrafts.first.amountMinor = remainder > 0 ? remainder : 0;
            }

            ensureSplitDrafts();
            recalculateAutoRemainder();
            syncPrimaryCategoryFromSplit();

            final splitTotalMinor = splitDrafts.fold<int>(
              0,
              (total, line) => total + line.amountMinor.abs(),
            );
            final remainingMinor = absoluteAmountMinor - splitTotalMinor;
            final splitRowsComplete =
                splitDrafts.isNotEmpty &&
                splitDrafts.every(
                  (line) => line.categoryId.isNotEmpty && line.amountMinor > 0,
                ) &&
                splitDrafts
                        .map((line) => line.categoryId)
                        .where((id) => id.isNotEmpty)
                        .toSet()
                        .length ==
                    splitDrafts.length;
            final splitIsBalanced = splitRowsComplete && remainingMinor == 0;
            final canSaveTransaction =
                !isCreatingCategory &&
                accountId.isNotEmpty &&
                absoluteAmountMinor > 0 &&
                splitIsBalanced &&
                (!scheduleFutureOccurrences ||
                    isValidFutureScheduleDate(
                      futureSchedule.parsedFirstDate(DateTime.now()),
                      parseDateInput(date.text, DateTime.now()),
                    ));

            List<TransactionSplitLine> buildSplitLines() {
              return [
                for (var index = 0; index < splitDrafts.length; index++)
                  TransactionSplitLine(
                    id:
                        splitDrafts[index].id ??
                        'split_${DateTime.now().microsecondsSinceEpoch}_$index',
                    categoryId: splitDrafts[index].categoryId,
                    amountMinor: splitDrafts[index].amountMinor.abs(),
                    note: splitDrafts[index].note.text.trim(),
                  ),
              ];
            }

            void cancelInlineCategoryCreation() {
              FocusManager.instance.primaryFocus?.unfocus();
              setDialogState(() {
                isCreatingCategory = false;
                isSavingCategory = false;
                newCategoryError = null;
                newCategorySplitIndex = null;
                newCategoryName.clear();
              });
            }

            Future<void> createInlineCategory() async {
              if (isSavingCategory) return;
              final name = newCategoryName.text.trim();
              if (name.isEmpty) {
                setDialogState(
                  () => newCategoryError = 'Enter a category name.',
                );
                return;
              }
              final kind = isExpense
                  ? v2_category.CategoryKind.expense
                  : v2_category.CategoryKind.income;
              final duplicateExists = dataStore.categories.any(
                (category) =>
                    category.isVisible &&
                    category.kind == kind &&
                    category.name.trim().toLowerCase() == name.toLowerCase(),
              );
              if (duplicateExists) {
                setDialogState(
                  () => newCategoryError =
                      'A category with this name already exists.',
                );
                return;
              }

              FocusManager.instance.primaryFocus?.unfocus();
              setDialogState(() {
                isSavingCategory = true;
                newCategoryError = null;
              });
              final createdId = 'cat_${DateTime.now().microsecondsSinceEpoch}';
              try {
                await dataStore.saveCategoryLocalFirst(
                  v2_category.CategoryRecord(
                    id: createdId,
                    name: name,
                    kind: kind,
                    sync: v2_sync.SyncMetadata.fresh(
                      deviceId: dataStore.deviceId,
                    ),
                  ),
                );
                if (!context.mounted) return;
                HapticFeedback.mediumImpact();
                setDialogState(() {
                  final splitIndex = newCategorySplitIndex;
                  if (splitIndex != null && splitIndex < splitDrafts.length) {
                    splitDrafts[splitIndex].categoryId = createdId;
                    if (splitIndex == 0) categoryId = createdId;
                  } else {
                    categoryId = createdId;
                  }
                  isCreatingCategory = false;
                  isSavingCategory = false;
                  newCategoryError = null;
                  newCategorySplitIndex = null;
                  newCategoryName.clear();
                });
              } catch (_) {
                if (!context.mounted) return;
                setDialogState(() {
                  isSavingCategory = false;
                  newCategoryError =
                      'The category could not be saved. Please try again.';
                });
              }
            }

            Widget inlineCategoryCreationRow() {
              return Column(
                key: const ValueKey('transaction-new-category'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TransactionFormLabel('New Category'),
                  Row(
                    children: [
                      TransactionFormIcon(AppIcon.category),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('transaction-new-category-name'),
                          controller: newCategoryName,
                          focusNode: newCategoryFocusNode,
                          autofocus: true,
                          enabled: !isSavingCategory,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) {
                            if (newCategoryError != null) {
                              setDialogState(() => newCategoryError = null);
                            }
                          },
                          onSubmitted: (_) => createInlineCategory(),
                          decoration: InputDecoration(
                            hintText: 'Category name',
                            hintStyle: fieldHintStyle,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                          ),
                          style: fieldValueStyle,
                        ),
                      ),
                      TextButton(
                        onPressed: isSavingCategory
                            ? null
                            : cancelInlineCategoryCreation,
                        child: const Text('Cancel'),
                      ),
                      IconButton(
                        key: const ValueKey('transaction-save-new-category'),
                        tooltip: 'Add category',
                        onPressed: isSavingCategory
                            ? null
                            : createInlineCategory,
                        icon: isSavingCategory
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(AppIcon.check),
                      ),
                    ],
                  ),
                  if (newCategoryError != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 56, top: 2),
                      child: Text(
                        newCategoryError!,
                        key: const ValueKey('transaction-new-category-error'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              );
            }

            Future<void> chooseSplitCategory(int index) async {
              FocusManager.instance.primaryFocus?.unfocus();
              final selectedCategoryId = await showTransactionCategoryFlow(
                context,
                dataStore: dataStore,
                isExpense: isExpense,
                selectedCategoryId: splitDrafts[index].categoryId,
              );
              if (selectedCategoryId == null) return;
              setDialogState(() {
                splitDrafts[index].categoryId = selectedCategoryId;
                if (index == 0) categoryId = selectedCategoryId;
              });
            }

            void enterSplitMode() {
              if (splitDrafts.isEmpty || categoryId.isEmpty) return;
              setDialogState(() {
                splitMode = true;
                firstSplitAutoRemainder = true;
                splitDrafts.first
                  ..categoryId = categoryId
                  ..amountMinor = absoluteAmountMinor;
                if (splitDrafts.length == 1) {
                  splitDrafts.add(
                    SplitLineDraft(
                      id: newSplitId(),
                      categoryId: '',
                      amountMinor: 0,
                    ),
                  );
                }
                autofocusSecondSplitAmount = true;
                recalculateAutoRemainder();
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final splitContext = splitSectionKey.currentContext;
                if (splitContext == null) return;
                Scrollable.ensureVisible(
                  splitContext,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: 0.35,
                );
              });
            }

            Future<void> useSingleCategory() async {
              final hasMeaningfulAdditionalSplits = splitDrafts
                  .skip(1)
                  .any(
                    (draft) =>
                        draft.categoryId.isNotEmpty ||
                        draft.amountMinor != 0 ||
                        draft.note.text.trim().isNotEmpty,
                  );
              if (hasMeaningfulAdditionalSplits &&
                  !await confirmDiscardAdditionalSplits(context)) {
                return;
              }
              if (!context.mounted) return;
              setDialogState(() {
                for (final draft in splitDrafts.skip(1)) {
                  draft.note.dispose();
                }
                if (splitDrafts.length > 1) {
                  splitDrafts.removeRange(1, splitDrafts.length);
                }
                splitDrafts.first.amountMinor = absoluteAmountMinor;
                categoryId = splitDrafts.first.categoryId;
                firstSplitAutoRemainder = true;
                splitMode = false;
                autofocusSecondSplitAmount = false;
              });
            }

            Future<void> saveTransactionResult() async {
              recalculateAutoRemainder();
              syncPrimaryCategoryFromSplit();
              final currentCategoryIds = splitDrafts
                  .map((line) => line.categoryId)
                  .where((id) => id.isNotEmpty)
                  .toSet();
              final currentSplitTotal = splitDrafts.fold<int>(
                0,
                (total, line) => total + line.amountMinor.abs(),
              );
              final splitsAreValid =
                  splitDrafts.isNotEmpty &&
                  splitDrafts.every(
                    (line) =>
                        line.categoryId.isNotEmpty && line.amountMinor > 0,
                  ) &&
                  currentCategoryIds.length == splitDrafts.length &&
                  currentSplitTotal == amountMinor.abs();
              if (!splitsAreValid) return;
              if (wouldOverdrawAsset &&
                  dataStore.preferences.warnBeforeNegativeAssetBalance &&
                  !await confirmAssetAccountOverdraw(
                    context,
                    account: selectedAccount,
                    projectedBalanceMinor: previewBalanceMinor,
                  )) {
                return;
              }
              if (!context.mounted) return;
              Navigator.pop(context, (
                accountId: accountId,
                categoryId: categoryId,
                payee: payee.text.trim().isEmpty
                    ? 'Transaction'
                    : payee.text.trim(),
                note: note.text.trim(),
                date: parseTransactionDateInput(
                  date.text,
                  transaction?.date ?? DateTime.now(),
                ),
                amountMinor: amountMinor.abs(),
                isExpense: isExpense,
                splitLines: splitMode
                    ? buildSplitLines()
                    : const <TransactionSplitLine>[],
                scheduleFutureOccurrences: scheduleFutureOccurrences,
                firstScheduledDate: futureSchedule.parsedFirstDate(
                  DateTime.now(),
                ),
                scheduledTimeMinutes: futureSchedule.timeMinutes,
                scheduledFrequency: futureSchedule.frequency,
                scheduledAlertPreference: futureSchedule.alertPreference,
              ));
            }

            Widget accountSubtitle() {
              if (selectedAccount == null) return const SizedBox.shrink();
              switch (selectedAccount.type) {
                case v2_account.AccountType.creditCard:
                  final available = selectedAccount.creditLimitMinor == null
                      ? null
                      : selectedAccount.creditLimitMinor! -
                            previewBalanceMinor.abs();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Balance ${money(previewBalanceMinor, dataStore.preferences.currency)}',
                        style: mutedStyle?.copyWith(color: AppColors.danger),
                      ),
                      if (available != null)
                        Text(
                          'Available ${money(available, dataStore.preferences.currency)}',
                          style: mutedStyle,
                        ),
                    ],
                  );
                case v2_account.AccountType.loan:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Balance Due ${money(previewBalanceMinor, dataStore.preferences.currency)}',
                        style: mutedStyle?.copyWith(color: AppColors.danger),
                      ),
                      Text(
                        'Remaining ${money(previewBalanceMinor.abs(), dataStore.preferences.currency)}',
                        style: mutedStyle,
                      ),
                    ],
                  );
                case v2_account.AccountType.checking:
                case v2_account.AccountType.savings:
                case v2_account.AccountType.cash:
                case v2_account.AccountType.otherBanking:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Balance ${money(previewBalanceMinor, dataStore.preferences.currency)}',
                        style: mutedStyle?.copyWith(
                          color: wouldOverdrawAsset ? AppColors.danger : null,
                        ),
                      ),
                      if (wouldOverdrawAsset) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Insufficient funds',
                          key: const ValueKey('transaction-insufficient-funds'),
                          style: mutedStyle?.copyWith(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'This transaction would leave ${selectedAccount.name} at ${money(previewBalanceMinor, dataStore.preferences.currency)}.',
                          style: mutedStyle?.copyWith(color: AppColors.danger),
                        ),
                      ],
                    ],
                  );
              }
            }

            Widget selectableRow({
              required IconData icon,
              required Widget title,
              required VoidCallback onTap,
              Widget? subtitle,
              String? placeholder,
              TextStyle? valueStyle,
            }) {
              final resolvedValueStyle = valueStyle ?? accountRowStyle;
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadii.control),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      TransactionFormIcon(icon),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DefaultTextStyle.merge(
                              style:
                                  (placeholder == null
                                      ? resolvedValueStyle
                                      : resolvedValueStyle?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        )) ??
                                  const TextStyle(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              child: title,
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 5),
                              subtitle,
                            ],
                          ],
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Icon(AppIcon.chevronDown, size: AppIconSize.hero),
                    ],
                  ),
                ),
              );
            }

            Widget splitAllocationSection() {
              return InlineSplitAllocationSection(
                key: splitSectionKey,
                keyPrefix: 'transaction',
                drafts: splitDrafts,
                categories: categoryOptions,
                currency: dataStore.preferences.currency,
                totalMinor: absoluteAmountMinor,
                firstAutoRemainder: firstSplitAutoRemainder,
                autofocusAmountIndex: autofocusSecondSplitAmount ? 1 : null,
                quietWhenZero: true,
                onChooseCategory: chooseSplitCategory,
                onAmountChanged: (index, value) => setDialogState(() {
                  autofocusSecondSplitAmount = false;
                  splitDrafts[index].amountMinor = value.abs();
                  if (index == 0) {
                    firstSplitAutoRemainder = false;
                  } else {
                    recalculateAutoRemainder();
                  }
                }),
                onAdd: () => setDialogState(() {
                  autofocusSecondSplitAmount = false;
                  ensureSplitDrafts();
                  final currentTotal = splitDrafts.fold<int>(
                    0,
                    (total, line) => total + line.amountMinor.abs(),
                  );
                  final remainder = absoluteAmountMinor - currentTotal;
                  splitDrafts.add(
                    SplitLineDraft(
                      id: newSplitId(),
                      categoryId: '',
                      amountMinor: remainder > 0 ? remainder : 0,
                    ),
                  );
                }),
                onRemove: (index) => setDialogState(() {
                  autofocusSecondSplitAmount = false;
                  splitDrafts[index].note.dispose();
                  splitDrafts.removeAt(index);
                  recalculateAutoRemainder();
                  syncPrimaryCategoryFromSplit();
                  if (splitDrafts.length == 1) {
                    splitDrafts.first.amountMinor = absoluteAmountMinor;
                    firstSplitAutoRemainder = true;
                    splitMode = false;
                  }
                }),
                onUseSingleCategory: useSingleCategory,
              );
            }

            return TransactionSheetFrame(
              title: transaction == null
                  ? 'Add Transaction'
                  : 'Edit Transaction',
              actions: TransactionFormActions(
                onCancel: () => Navigator.pop(context),
                canSave: canSaveTransaction,
                onSave: saveTransactionResult,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 292),
                      child: SegmentedButton<TransactionType>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: AppTheme.accent,
                          selectedForegroundColor: Colors.white,
                          foregroundColor: theme.colorScheme.onSurface,
                          textStyle: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                        ),
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
                            categoryId = '';
                            for (final draft in splitDrafts) {
                              draft.note.dispose();
                            }
                            splitDrafts.clear();
                            splitDrafts.add(
                              SplitLineDraft(
                                id: 'split_${DateTime.now().microsecondsSinceEpoch}_0',
                                categoryId: '',
                                amountMinor: amountMinor.abs(),
                              ),
                            );
                            firstSplitAutoRemainder = true;
                            splitMode = false;
                            autofocusSecondSplitAmount = false;
                            isCreatingCategory = false;
                            isSavingCategory = false;
                            newCategoryError = null;
                            newCategorySplitIndex = null;
                            newCategoryName.clear();
                          });
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: AppSpacing.md),
                  TransactionFormLabel('Account'),
                  selectableRow(
                    icon: selectedAccount == null
                        ? AppIcon.wallet
                        : v2AccountIcon(selectedAccount.type),
                    placeholder: selectedAccount == null
                        ? 'Choose account'
                        : null,
                    title: Text(selectedAccount?.name ?? 'Choose account'),
                    subtitle: accountSubtitle(),
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final selectedAccountId =
                          await showTransactionAccountPicker(
                            context,
                            accounts: activeAccounts,
                            selectedAccountId: accountId,
                          );
                      if (selectedAccountId != null) {
                        setDialogState(() => accountId = selectedAccountId);
                      }
                    },
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Amount'),
                  Row(
                    children: [
                      TransactionFormIcon(AppIcon.money),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AmountEntryField(
                          fieldKey: const ValueKey('transaction-amount'),
                          initialMinor: amountMinor,
                          currency: dataStore.preferences.currency,
                          labelText: null,
                          autofocus:
                              transaction == null && accountId.isNotEmpty,
                          textAlign: TextAlign.left,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              amountMinor = value.abs();
                              recalculateAutoRemainder();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Payee'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TransactionFormIcon(AppIcon.payee),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: PayeeAutocompleteField(
                          dataStore: dataStore,
                          fieldKey: const ValueKey('transaction-payee'),
                          controller: payee,
                          options: payeeOptions,
                          inlineSuggestions: true,
                          inlineSuggestionsAbove: true,
                          decoration: InputDecoration(
                            hintText: 'Search or enter payee',
                            hintStyle: fieldHintStyle,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                          textStyle: fieldValueStyle,
                          textInputAction: TextInputAction.next,
                          showSuggestionToggle: false,
                        ),
                      ),
                    ],
                  ),
                  const TransactionFormDivider(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (splitMode)
                        splitAllocationSection()
                      else
                        SingleCategoryAllocationSection(
                          keyPrefix: 'transaction',
                          categoryName: selectedCategory?.name,
                          category: selectedCategory,
                          onChooseCategory: () => chooseSplitCategory(0),
                          onSplit: selectedCategory == null
                              ? null
                              : enterSplitMode,
                        ),
                      if (isCreatingCategory) ...[
                        const SizedBox(height: AppSpacing.sm),
                        inlineCategoryCreationRow(),
                      ],
                    ],
                  ),
                  const TransactionFormDivider(),
                  const TransactionFormLabel('Date'),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final picked = await pickDateForField(
                        context,
                        parseDateInput(date.text, DateTime.now()),
                      );
                      if (picked != null) {
                        setDialogState(() => date.text = dateInput(picked));
                      }
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          TransactionFormIcon(AppIcon.calendar),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              fullMonthDateLabel(
                                parseDateInput(date.text, DateTime.now()),
                              ),
                              style: fieldValueStyle,
                            ),
                          ),
                          Text(
                            isSameCalendarDay(
                                  parseDateInput(date.text, DateTime.now()),
                                  DateTime.now(),
                                )
                                ? 'Today'
                                : '',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Icon(
                            AppIcon.event,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Notes'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TransactionFormIcon(AppIcon.notes),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('transaction-note'),
                          controller: note,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Add a note (optional)',
                            hintStyle: fieldHintStyle,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                          style: fieldValueStyle,
                          minLines: 1,
                          maxLines: 3,
                        ),
                      ),
                    ],
                  ),
                  if (linkedSchedule == null) ...[
                    const TransactionFormDivider(),
                    InkWell(
                      key: const ValueKey('transaction-schedule-toggle'),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      onTap: () => setDialogState(
                        () => scheduleFutureOccurrences =
                            !scheduleFutureOccurrences,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            TransactionFormIcon(AppIcon.recurrence),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                'Schedule future occurrences',
                                style: fieldValueStyle,
                              ),
                            ),
                            Switch.adaptive(
                              value: scheduleFutureOccurrences,
                              onChanged: (value) => setDialogState(
                                () => scheduleFutureOccurrences = value,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (scheduleFutureOccurrences) ...[
                      const TransactionFormDivider(),
                      InlineFutureScheduleSection(
                        draft: futureSchedule,
                        keyPrefix: 'transaction-schedule',
                        onChanged: () => setDialogState(() {}),
                      ),
                    ],
                  ] else ...[
                    const TransactionFormDivider(),
                    InkWell(
                      key: const ValueKey('transaction-edit-future-schedule'),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      onTap: () {
                        editLinkedSchedule = true;
                        Navigator.pop(context);
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            TransactionFormIcon(AppIcon.recurrence),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Edit future schedule',
                                    style: fieldValueStyle,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Date, time, frequency, and reminder',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(AppIcon.chevronRight),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );

  for (final draft in splitDrafts) {
    draft.note.dispose();
  }
  if (editLinkedSchedule && linkedSchedule != null && context.mounted) {
    await showScheduledTransactionDialog(context, existing: linkedSchedule);
    return;
  }
  if (switchToTransfer && context.mounted) {
    await showTransferDialog(
      context,
      initialFromAccountId: accountId,
      transfer: transaction,
      initialScheduleFutureOccurrences: scheduleFutureOccurrences,
      initialFutureSchedule: futureSchedule,
    );
    return;
  }
  if (result == null) return;
  HapticFeedback.mediumImpact();
  if (transaction == null) {
    if (result.scheduleFutureOccurrences) {
      final scheduleId = 'sched_${DateTime.now().microsecondsSinceEpoch}';
      final transactionRecord = TransactionRecord(
        id: 'txn_${DateTime.now().microsecondsSinceEpoch}',
        type: result.isExpense
            ? TransactionType.expense
            : TransactionType.income,
        accountId: result.accountId,
        categoryId: result.categoryId,
        date: result.date,
        payee: result.payee,
        amountMinor: result.amountMinor,
        note: result.note,
        splitLines: result.splitLines,
        scheduledTransactionId: scheduleId,
        sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
      );
      final schedule = v2_scheduled.ScheduledTransactionRecord(
        id: scheduleId,
        type: transactionRecord.type,
        accountId: result.accountId,
        categoryId: result.categoryId,
        splitLines: result.splitLines,
        payee: result.payee,
        note: result.note,
        amountMinor: result.amountMinor,
        nextDate: result.firstScheduledDate,
        frequency: result.scheduledFrequency,
        alertPreference: result.scheduledAlertPreference,
        customAlertTimeMinutes: result.scheduledTimeMinutes,
        sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
      );
      try {
        if (schedule.hasAlert && !dataStore.preferences.notificationsEnabled) {
          await dataStore.savePreferences(
            dataStore.preferences.copyWith(notificationsEnabled: true),
          );
        }
        await dataStore.saveTransactionAndSchedule(
          transaction: transactionRecord,
          scheduledTransaction: schedule,
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The transaction and schedule could not be saved. Please try again.',
              ),
            ),
          );
        }
        return;
      }
    } else if (result.isExpense) {
      await dataStore.addExpense(
        accountId: result.accountId,
        categoryId: result.categoryId,
        date: result.date,
        payee: result.payee,
        amountMinor: result.amountMinor,
        note: result.note,
        splitLines: result.splitLines,
      );
    } else {
      await dataStore.addIncome(
        accountId: result.accountId,
        categoryId: result.categoryId,
        date: result.date,
        payee: result.payee,
        amountMinor: result.amountMinor,
        note: result.note,
        splitLines: result.splitLines,
      );
    }
  } else if (result.scheduleFutureOccurrences) {
    final scheduleId = 'sched_${DateTime.now().microsecondsSinceEpoch}';
    final transactionRecord = transaction.copyWith(
      type: result.isExpense ? TransactionType.expense : TransactionType.income,
      accountId: result.accountId,
      categoryId: result.categoryId,
      date: result.date,
      payee: result.payee,
      note: result.note,
      amountMinor: result.amountMinor,
      splitLines: result.splitLines,
      scheduledTransactionId: scheduleId,
      clearTransferAccount: true,
    );
    final schedule = v2_scheduled.ScheduledTransactionRecord(
      id: scheduleId,
      type: transactionRecord.type,
      accountId: result.accountId,
      categoryId: result.categoryId,
      splitLines: result.splitLines,
      payee: result.payee,
      note: result.note,
      amountMinor: result.amountMinor,
      nextDate: result.firstScheduledDate,
      frequency: result.scheduledFrequency,
      alertPreference: result.scheduledAlertPreference,
      customAlertTimeMinutes: result.scheduledTimeMinutes,
      sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
    );
    try {
      if (schedule.hasAlert && !dataStore.preferences.notificationsEnabled) {
        await dataStore.savePreferences(
          dataStore.preferences.copyWith(notificationsEnabled: true),
        );
      }
      await dataStore.saveTransactionAndSchedule(
        transaction: transactionRecord,
        scheduledTransaction: schedule,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The transaction and schedule could not be saved. Please try again.',
            ),
          ),
        );
      }
      return;
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
        splitLines: result.splitLines,
        clearTransferAccount: true,
      ),
    );
  }
  await dataStore.savePreferences(
    dataStore.preferences.copyWith(
      lastUsedTransactionType: result.isExpense
          ? TransactionType.expense
          : TransactionType.income,
      lastUsedTransactionAccountId: result.accountId,
    ),
  );
}

Future<String?> showCategoryDialog(
  BuildContext context, {
  LedgerCategory? category,
  String? categoryId,
  v2_category.CategoryKind? initialKind,
}) async {
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
            final theme = Theme.of(context);
            final fieldValueStyle = theme.textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              height: 1.15,
            );
            final fieldHintStyle = fieldValueStyle?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            );
            const borderlessDecoration = InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            );
            final selectedParent = parentOptions
                .where((item) => item.id == parentDropdownValue)
                .firstOrNull;
            final selectedIcon = CategoryIconCatalog.find(iconName);
            final selectedColor = categoryColorOptions
                .where((item) => item.value == colorValue)
                .firstOrNull;

            Widget choiceRow({
              required IconData icon,
              required String value,
              required VoidCallback onTap,
              Color? iconColor,
              Widget? leading,
            }) {
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadii.control),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      leading ?? TransactionFormIcon(icon, color: iconColor),
                      SizedBox(width: AppSpacing.md),
                      Expanded(child: Text(value, style: fieldValueStyle)),
                      Icon(AppIcon.chevronDown, size: AppIconSize.hero),
                    ],
                  ),
                ),
              );
            }

            void saveCategoryResult() {
              Navigator.pop(context, (
                name: name.text.trim(),
                kind: kind,
                parentCategoryId: parentCategoryId,
                iconName: iconName,
                colorValue: colorValue,
              ));
            }

            return TransactionSheetFrame(
              title: existingCategory == null
                  ? 'Add Category'
                  : 'Edit Category',
              actions: TransactionFormActions(
                onCancel: () => Navigator.pop(context),
                onSave: saveCategoryResult,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TransactionFormLabel('Category name'),
                  Row(
                    children: [
                      TransactionFormIcon(AppIcon.category),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          controller: name,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          decoration: borderlessDecoration.copyWith(
                            hintText: 'Category name',
                            hintStyle: fieldHintStyle,
                          ),
                          style: fieldValueStyle,
                          autofocus: true,
                        ),
                      ),
                    ],
                  ),
                  const TransactionFormDivider(),
                  const TransactionFormLabel('Type'),
                  choiceRow(
                    icon: categoryKindIcon(kind.name),
                    value: categoryKindLabel(kind.name),
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final selected = await showPolishedChoicePicker(
                        context,
                        title: 'Category type',
                        selected: kind,
                        choices: [
                          for (final item in v2_category.CategoryKind.values)
                            if (item != v2_category.CategoryKind.system)
                              PolishedChoice(
                                value: item,
                                label: categoryKindLabel(item.name),
                                leading: Icon(categoryKindIcon(item.name)),
                              ),
                        ],
                      );
                      if (selected != null) {
                        setDialogState(() {
                          kind = selected;
                          parentCategoryId = null;
                        });
                      }
                    },
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Parent category'),
                  choiceRow(
                    icon: AppIcon.categoryTree,
                    value: selectedParent?.name ?? 'None',
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final selected = await showPolishedChoicePicker(
                        context,
                        title: 'Parent category',
                        selected: parentDropdownValue ?? noCategoryChoice,
                        choices: [
                          PolishedChoice(
                            value: noCategoryChoice,
                            label: 'None',
                            leading: Icon(AppIcon.expense),
                          ),
                          for (final item in parentOptions)
                            PolishedChoice(
                              value: item.id,
                              label: item.name,
                              leading: Icon(categoryIcon(item)),
                            ),
                        ],
                      );
                      if (selected != null) {
                        setDialogState(
                          () => parentCategoryId = selected == noCategoryChoice
                              ? null
                              : selected,
                        );
                      }
                    },
                  ),
                  const TransactionFormDivider(),
                  const TransactionFormLabel('Icon'),
                  choiceRow(
                    icon: categoryIconForName(iconName, kind),
                    leading: CategoryIconBadge(
                      iconName: iconName,
                      kind: kind,
                      colorValue: colorValue,
                      semanticLabel: selectedIcon?.label ?? 'No icon selected',
                      size: CategoryIconBadgeSize.form,
                    ),
                    value: selectedIcon?.label ?? 'No icon',
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final selected = await showCategoryIconPicker(
                        context,
                        selectedKey: iconName ?? categoryIconNoneKey,
                        categoryKind: kind,
                        categoryColorValue: colorValue,
                      );
                      if (selected != null) {
                        setDialogState(
                          () => iconName = selected == categoryIconNoneKey
                              ? null
                              : selected,
                        );
                      }
                    },
                  ),
                  TransactionFormDivider(),
                  TransactionFormLabel('Color'),
                  choiceRow(
                    icon: AppIcon.palette,
                    iconColor: colorValue == null
                        ? AppTheme.accent
                        : Color(colorValue!),
                    value: selectedColor?.label ?? 'Default',
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final selected = await showPolishedChoicePicker(
                        context,
                        title: 'Category color',
                        selected: colorValue ?? noCategoryColorChoice,
                        choices: [
                          PolishedChoice(
                            value: noCategoryColorChoice,
                            label: 'Default',
                            leading: Icon(AppIcon.clearColor),
                          ),
                          for (final item in categoryColorOptions)
                            PolishedChoice(
                              value: item.value,
                              label: item.label,
                              leading: Icon(
                                AppIcon.circle,
                                color: Color(item.value),
                              ),
                            ),
                        ],
                      );
                      if (selected != null) {
                        setDialogState(
                          () => colorValue = selected == noCategoryColorChoice
                              ? null
                              : selected,
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      );

  if (result == null || result.name.isEmpty) return null;
  HapticFeedback.mediumImpact();
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
    final categoryId = 'cat_${DateTime.now().microsecondsSinceEpoch}';
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

const noCategoryChoice = '__none__';
const noCategoryColorChoice = -1;

class PolishedChoice<T> {
  const PolishedChoice({
    required this.value,
    required this.label,
    this.leading,
  });

  final T value;
  final String label;
  final Widget? leading;
}

Future<T?> showPolishedChoicePicker<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<PolishedChoice<T>> choices,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text(
                title,
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final choice in choices)
                    ListTile(
                      leading: choice.leading == null
                          ? null
                          : IconTheme.merge(
                              data: const IconThemeData(color: AppTheme.accent),
                              child: choice.leading!,
                            ),
                      title: Text(choice.label),
                      trailing: choice.value == selected
                          ? Icon(AppIcon.check, color: AppTheme.accent)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, choice.value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
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
            leading: Icon(AppIcon.edit),
            title: Text('Edit'),
            onTap: () => Navigator.pop(sheetContext, 'edit'),
          ),
          ListTile(
            leading: Icon(AppIcon.archive),
            title: Text('Archive'),
            onTap: () => Navigator.pop(sheetContext, 'archive'),
          ),
          ListTile(
            leading: Icon(AppIcon.delete),
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

Future<void> showCategoryDetails(
  BuildContext context,
  String categoryId, {
  required ManagementLedgerIndex index,
}) async {
  final store = FinanceDataStoreScope.read(context);
  final category = store.categories
      .where((item) => item.id == categoryId)
      .firstOrNull;
  if (category == null) return;
  final categoriesById = {for (final item in store.categories) item.id: item};
  final directChildren = store.categories
      .where((item) => item.parentCategoryId == category.id && !item.isDeleted)
      .toList(growable: false);
  final iconLabel =
      CategoryIconCatalog.find(category.iconName)?.label ?? 'Default';
  final colorLabel = category.colorValue == null
      ? 'Default'
      : '#${category.colorValue!.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) => TransactionSheetFrame(
      title: 'Category Details',
      actions: ScheduledTransactionDetailActions(
        onClose: () => Navigator.pop(dialogContext),
        onEdit: () => Navigator.pop(dialogContext, 'edit'),
        onMarkPaid: null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScheduledTransactionDetailRow(
            rowKey: const ValueKey('category-detail-name'),
            icon: categoryIcon(category),
            leading: CategoryIconBadge.category(
              category,
              size: CategoryIconBadgeSize.form,
            ),
            label: 'Category',
            value: category.name,
          ),
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: categoryKindIcon(category.kind.name),
            label: 'Type',
            value: categoryKindLabel(category.kind.name),
          ),
          if (category.parentCategoryId case final parentId?) ...[
            const TransactionFormDivider(),
            ScheduledTransactionDetailRow(
              icon: AppIcon.categoryTree,
              label: 'Parent Category',
              value: categoriesById[parentId]?.name ?? 'Unavailable',
            ),
          ],
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: AppIcon.categoryTree,
            label: 'Direct Subcategories',
            value: '${directChildren.length}',
            tabularFigures: true,
          ),
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            rowKey: const ValueKey('category-detail-count'),
            icon: AppIcon.ledger,
            label: 'Transactions · Last 12 Months',
            value: '${index.categoryCount(category.id)}',
            tabularFigures: true,
          ),
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: categoryIcon(category),
            leading: CategoryIconBadge.category(
              category,
              size: CategoryIconBadgeSize.form,
            ),
            label: 'Icon',
            value: iconLabel,
          ),
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: AppIcon.palette,
            label: 'Color',
            value: colorLabel,
            valueColor: category.colorValue == null
                ? null
                : Color(category.colorValue!),
          ),
          const TransactionFormDivider(),
          ScheduledTransactionDetailRow(
            icon: category.isArchived ? AppIcon.archive : AppIcon.check,
            label: 'Status',
            value: category.isArchived ? 'Archived' : 'Active',
          ),
          if (directChildren.isNotEmpty) ...[
            const TransactionFormDivider(),
            Text(
              'Subcategories',
              style: Theme.of(dialogContext).textTheme.labelMedium?.copyWith(
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final child in directChildren)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  child.name,
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('category-detail-view-transactions'),
              onPressed: () => Navigator.pop(dialogContext, 'transactions'),
              icon: Icon(AppIcon.ledger),
              label: const Text('View Transactions'),
            ),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'edit') {
    await showCategoryDialog(context, categoryId: category.id);
  } else if (action == 'transactions') {
    await openManagementLedger(
      context,
      ManagementLedgerFilter.category(
        categoryId: category.id,
        label: category.name,
      ),
    );
  }
}

bool isSystemGeneratedManagedPayee(String payee) =>
    normalizeManagedPayee(payee) == 'balance adjustment';

IconData accountIcon(AccountType type) {
  return switch (type) {
    AccountType.cash => AppIcon.cash,
    AccountType.checking => AppIcon.bank,
    AccountType.savings => AppIcon.savings,
    AccountType.creditCard => AppIcon.creditCard,
    AccountType.loan => AppIcon.loan,
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
    v2_account.AccountType.cash => AppIcon.cash,
    v2_account.AccountType.checking => AppIcon.bank,
    v2_account.AccountType.savings => AppIcon.savings,
    v2_account.AccountType.creditCard => AppIcon.creditCard,
    v2_account.AccountType.loan => AppIcon.loan,
    v2_account.AccountType.otherBanking => AppIcon.wallet,
  };
}

IconData accountGroupIcon(String groupName) {
  return switch (groupName) {
    'cash' => AppIcon.cash,
    'creditCards' => AppIcon.creditCard,
    'loans' => AppIcon.loan,
    _ => AppIcon.bank,
  };
}

IconData categoryKindIcon(String kindName) {
  return switch (kindName) {
    'income' => AppIcon.trendUp,
    'transfer' => AppIcon.transfer,
    'system' => AppIcon.settings,
    _ => AppIcon.category,
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

int categoryDepth(
  v2_category.CategoryRecord category,
  Map<String, v2_category.CategoryRecord> categoriesById,
) {
  var depth = 0;
  var parentId = category.parentCategoryId;
  final visited = <String>{category.id};
  while (parentId != null && visited.add(parentId)) {
    final parent = categoriesById[parentId];
    if (parent == null) break;
    depth += 1;
    parentId = parent.parentCategoryId;
  }
  return depth;
}

List<v2_category.CategoryRecord> visibleCategoriesInDisplayOrder(
  List<v2_category.CategoryRecord> categories,
  Set<String> collapsedCategoryIds,
) {
  final categoriesById = {
    for (final category in categories) category.id: category,
  };

  bool hasCollapsedAncestor(v2_category.CategoryRecord category) {
    var parentId = category.parentCategoryId;
    final visited = <String>{category.id};
    while (parentId != null && visited.add(parentId)) {
      if (collapsedCategoryIds.contains(parentId)) return true;
      final parent = categoriesById[parentId];
      if (parent == null) break;
      parentId = parent.parentCategoryId;
    }
    return false;
  }

  return categoriesInDisplayOrder(categories)
      .where((category) => !hasCollapsedAncestor(category))
      .toList(growable: false);
}

IconData categoryIcon(v2_category.CategoryRecord category) {
  return categoryIconForName(category.iconName, category.kind);
}

IconData categoryIconForName(String? iconName, v2_category.CategoryKind kind) {
  return CategoryIconCatalog.find(iconName)?.icon ??
      categoryKindIcon(kind.name);
}

String categorySubtitle(
  v2_category.CategoryRecord category,
  Map<String, v2_category.CategoryRecord> categoriesById,
) {
  final kind = categoryKindLabel(category.kind.name);
  final parent = categoriesById[category.parentCategoryId];
  return parent == null ? kind : '$kind · ${parent.name}';
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
    LaunchScreen.budgets || LaunchScreen.planBudgets => 'Plan — Budgets',
    LaunchScreen.planGoals => 'Plan — Goals',
    LaunchScreen.scheduled => 'Scheduled',
    LaunchScreen.reports => 'Reports',
  };
}

FinanceSection financeSectionForLaunchScreen(LaunchScreen screen) {
  return switch (screen) {
    LaunchScreen.dashboard => FinanceSection.dashboard,
    LaunchScreen.ledger => FinanceSection.ledger,
    LaunchScreen.accounts => FinanceSection.accounts,
    LaunchScreen.budgets ||
    LaunchScreen.planBudgets ||
    LaunchScreen.planGoals => FinanceSection.plan,
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

const newPayeeSuggestionValue = '__create_new_payee__';

class PayeeAutocompleteField extends StatefulWidget {
  const PayeeAutocompleteField({
    required this.dataStore,
    required this.controller,
    required this.options,
    required this.fieldKey,
    this.decoration,
    this.textStyle,
    this.textInputAction,
    this.onSubmitted,
    this.showSuggestionToggle = true,
    this.optionsViewOpenDirection = OptionsViewOpenDirection.down,
    this.inlineSuggestions = false,
    this.inlineSuggestionsAbove = false,
    super.key,
  });

  final FinanceDataStore dataStore;
  final TextEditingController controller;
  final List<String> options;
  final Key fieldKey;
  final InputDecoration? decoration;
  final TextStyle? textStyle;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool showSuggestionToggle;
  final OptionsViewOpenDirection optionsViewOpenDirection;
  final bool inlineSuggestions;
  final bool inlineSuggestionsAbove;

  @override
  State<PayeeAutocompleteField> createState() => _PayeeAutocompleteFieldState();
}

class _PayeeAutocompleteFieldState extends State<PayeeAutocompleteField> {
  final _focusNode = FocusNode();
  final Set<String> _createdInlinePayees = <String>{};
  var _lastQuery = '';
  var _inlineSuggestionsHidden = false;
  var _selectingInlinePayee = false;
  var _suggestionsDismissed = false;
  String? _dismissedForValue;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inlineSuggestions) return _buildInlineAutocomplete(context);

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsViewOpenDirection: widget.optionsViewOpenDirection,
      displayStringForOption: (option) =>
          option == newPayeeSuggestionValue ? _lastQuery.trim() : option,
      optionsBuilder: (value) {
        final query = value.text;
        _lastQuery = query;
        if (_suggestionsDismissed || _dismissedForValue == query) {
          return const Iterable<String>.empty();
        }
        final suggestions = rankedPayeeSuggestions(
          widget.options,
          query,
        ).toList(growable: false);
        if (query.trim().isNotEmpty && suggestions.isEmpty) {
          return const [newPayeeSuggestionValue];
        }
        return suggestions.take(3);
      },
      onSelected: (option) {
        if (option == newPayeeSuggestionValue) {
          final name = _lastQuery.trim();
          widget.controller.value = TextEditingValue(
            text: name,
            selection: TextSelection.collapsed(offset: name.length),
          );
        } else {
          widget.controller.value = TextEditingValue(
            text: option,
            selection: TextSelection.collapsed(offset: option.length),
          );
        }
        _rememberPayee(widget.controller.text.trim());
        HapticFeedback.selectionClick();
        _dismissSuggestions();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          key: widget.fieldKey,
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          textInputAction: widget.textInputAction ?? TextInputAction.done,
          style: widget.textStyle,
          onTap: () {
            if (_suggestionsDismissed) {
              setState(() {
                _dismissedForValue = null;
                _suggestionsDismissed = false;
              });
            }
          },
          onTapOutside: (_) => _clearPayeeFocus(),
          onChanged: (value) {
            _lastQuery = value;
            if (_dismissedForValue != value) _dismissedForValue = null;
            if (value.trim().isEmpty) {
              setState(() => _suggestionsDismissed = true);
              return;
            }
            if (_suggestionsDismissed) {
              setState(() => _suggestionsDismissed = false);
            }
          },
          onSubmitted: (value) {
            _rememberPayee(value.trim());
            _dismissSuggestions();
            widget.onSubmitted?.call(value);
          },
          decoration:
              (widget.decoration ??
                      dialogFieldDecoration(
                        hintText: 'Type or choose a recent payee',
                      ))
                  .copyWith(
                    suffixIcon:
                        widget.showSuggestionToggle &&
                            focusNode.hasFocus &&
                            !_suggestionsDismissed
                        ? IconButton(
                            tooltip: 'Hide suggestions',
                            onPressed: _dismissSuggestions,
                            icon: Icon(AppIcon.chevronUp),
                          )
                        : null,
                  ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final visible = options.toList(growable: false);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 128),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 3),
                shrinkWrap: true,
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final option = visible[index];
                  final isCreate = option == newPayeeSuggestionValue;
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: SizedBox(
                      height: 40,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Icon(
                              isCreate ? AppIcon.addPayee : AppIcon.payee,
                              size: AppIconSize.inline,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isCreate ? 'Create New Payee' : option,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlineAutocomplete(BuildContext context) {
    final suggestions = _inlineSuggestions();
    final theme = Theme.of(context);
    final suggestionList = suggestions.isEmpty
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < suggestions.length; index++) ...[
                InkWell(
                  key: ValueKey('payee-suggestion-${suggestions[index]}'),
                  onTap: () => _selectPayee(suggestions[index]),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  child: SizedBox(
                    height: 30,
                    child: Row(
                      children: [
                        SizedBox(width: 4),
                        Icon(
                          suggestions[index] == newPayeeSuggestionValue
                              ? AppIcon.addPayee
                              : AppIcon.payee,
                          size: AppIconSize.compact,
                          color: AppTheme.accent.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            suggestions[index] == newPayeeSuggestionValue
                                ? 'Create New Payee'
                                : suggestions[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w400,
                              height: 1.05,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
                if (index != suggestions.length - 1) const SizedBox(height: 3),
              ],
            ],
          );

    return TextFieldTapRegion(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.inlineSuggestionsAbove && suggestionList != null) ...[
            suggestionList,
            const SizedBox(height: 4),
          ],
          TextField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: _focusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: widget.textInputAction ?? TextInputAction.done,
            style: widget.textStyle,
            onTap: () {
              if (widget.controller.text.trim().isEmpty &&
                  (_suggestionsDismissed || _inlineSuggestionsHidden)) {
                setState(() {
                  _dismissedForValue = null;
                  _inlineSuggestionsHidden = false;
                  _suggestionsDismissed = false;
                });
              }
            },
            onTapOutside: (_) => _clearPayeeFocus(),
            onChanged: (value) {
              _lastQuery = value;
              if (_selectingInlinePayee) {
                setState(() {
                  _dismissedForValue = value;
                  _inlineSuggestionsHidden = true;
                  _suggestionsDismissed = true;
                });
                return;
              }
              final normalizedValue = _normalizedPayee(value);
              final dismissedValue = _dismissedForValue;
              final stillDismissedValue =
                  normalizedValue.isNotEmpty &&
                  dismissedValue != null &&
                  _normalizedPayee(dismissedValue) == normalizedValue;
              setState(() {
                if (!stillDismissedValue) {
                  _dismissedForValue = null;
                  _inlineSuggestionsHidden = false;
                }
                if (value.trim().isEmpty) {
                  _inlineSuggestionsHidden = true;
                  _suggestionsDismissed = true;
                } else {
                  _suggestionsDismissed = false;
                }
              });
            },
            onSubmitted: (value) {
              _rememberPayee(value.trim());
              _dismissSuggestions();
              widget.onSubmitted?.call(value);
            },
            decoration:
                widget.decoration ??
                dialogFieldDecoration(
                  hintText: 'Type or choose a recent payee',
                ),
          ),
          if (!widget.inlineSuggestionsAbove && suggestionList != null) ...[
            const SizedBox(height: 4),
            suggestionList,
          ],
        ],
      ),
    );
  }

  List<String> _inlineSuggestions() {
    final query = widget.controller.text;
    _lastQuery = query;
    final normalizedQuery = _normalizedPayee(query);
    final dismissedValue = _dismissedForValue;
    final isDismissedValue =
        normalizedQuery.isNotEmpty &&
        dismissedValue != null &&
        _normalizedPayee(dismissedValue) == normalizedQuery;
    final isKnownPayee =
        normalizedQuery.isNotEmpty &&
        widget.options.any(
          (option) => _normalizedPayee(option) == normalizedQuery,
        );
    final isCreatedPayee =
        normalizedQuery.isNotEmpty &&
        _createdInlinePayees.contains(normalizedQuery);
    if (_inlineSuggestionsHidden ||
        !_focusNode.hasFocus ||
        _suggestionsDismissed ||
        isDismissedValue ||
        isKnownPayee ||
        isCreatedPayee) {
      return const [];
    }
    final suggestions = rankedPayeeSuggestions(
      widget.options,
      query,
    ).toList(growable: false);
    if (query.trim().isNotEmpty && suggestions.isEmpty) {
      return const [newPayeeSuggestionValue];
    }
    return suggestions.take(3).toList(growable: false);
  }

  void _selectPayee(String option) {
    _selectingInlinePayee = true;
    final isCreate = option == newPayeeSuggestionValue;
    final value = option == newPayeeSuggestionValue
        ? _lastQuery.trim()
        : option;
    final normalizedValue = _normalizedPayee(value);
    if (isCreate && normalizedValue.isNotEmpty) {
      _createdInlinePayees.add(normalizedValue);
    }
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    HapticFeedback.selectionClick();
    if (mounted) {
      setState(() {
        _lastQuery = value;
        _dismissedForValue = value;
        _inlineSuggestionsHidden = true;
        _suggestionsDismissed = true;
      });
    }
    _clearPayeeFocus();
    _rememberPayee(value);
    widget.onSubmitted?.call(value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _selectingInlinePayee = false;
      _clearPayeeFocus();
      setState(() {
        _lastQuery = value;
        _dismissedForValue = value;
        _inlineSuggestionsHidden = true;
        _suggestionsDismissed = true;
      });
    });
  }

  void _handleControllerChanged() {
    if (!mounted || !widget.inlineSuggestions) return;
    final value = widget.controller.text;
    final normalizedValue = _normalizedPayee(value);
    if (normalizedValue.isEmpty) return;
    final matchesKnownPayee = widget.options.any(
      (option) => _normalizedPayee(option) == normalizedValue,
    );
    final matchesCreatedPayee = _createdInlinePayees.contains(normalizedValue);
    final matchesDismissedValue =
        _dismissedForValue != null &&
        _normalizedPayee(_dismissedForValue!) == normalizedValue;
    if ((matchesKnownPayee || matchesCreatedPayee || matchesDismissedValue) &&
        (!_inlineSuggestionsHidden || !_suggestionsDismissed)) {
      setState(() {
        _lastQuery = value;
        _dismissedForValue = value;
        _inlineSuggestionsHidden = true;
        _suggestionsDismissed = true;
      });
    }
  }

  void _handleFocusChanged() {
    if (!mounted) return;
    if (!_focusNode.hasFocus && widget.inlineSuggestions) {
      _inlineSuggestionsHidden = true;
      _suggestionsDismissed = true;
      _dismissedForValue = widget.controller.text;
    }
    setState(() {});
  }

  void _dismissSuggestions() {
    if (mounted) {
      setState(() {
        _dismissedForValue = widget.controller.text;
        _inlineSuggestionsHidden = true;
        _suggestionsDismissed = true;
      });
    }
    _clearPayeeFocus();
  }

  String _normalizedPayee(String value) => value.trim().toLowerCase();

  void _clearPayeeFocus() {
    _focusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _rememberPayee(String name) {
    if (name.isEmpty) return;
    final store = widget.dataStore;
    final saved = [...store.preferences.savedPayeeNames]
      ..removeWhere((item) => item.toLowerCase() == name.toLowerCase())
      ..insert(0, name);
    unawaited(
      store.savePreferences(store.preferences.copyWith(savedPayeeNames: saved)),
    );
  }
}

Iterable<String> rankedPayeeSuggestions(
  List<String> recentPayees,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  final matching = recentPayees
      .where(
        (payee) =>
            normalized.isEmpty || payee.toLowerCase().contains(normalized),
      )
      .toList(growable: false);
  matching.sort((a, b) {
    final lowerA = a.toLowerCase();
    final lowerB = b.toLowerCase();
    final rankA = lowerA == normalized
        ? 0
        : lowerA.startsWith(normalized)
        ? 1
        : 2;
    final rankB = lowerB == normalized
        ? 0
        : lowerB.startsWith(normalized)
        ? 1
        : 2;
    if (rankA != rankB) return rankA.compareTo(rankB);
    if (normalized.isEmpty) {
      return recentPayees.indexOf(a).compareTo(recentPayees.indexOf(b));
    }
    return lowerA.compareTo(lowerB);
  });
  return matching;
}

List<String> savedPayees(FinanceDataStore store) {
  final seen = <String>{};
  final payees = <String>[];
  final archived = store.preferences.archivedPayeeNames;
  final deleted = store.preferences.deletedPayeeNames;
  for (final savedPayee in store.preferences.savedPayeeNames) {
    final payee = savedPayee.trim();
    final normalized = payee.toLowerCase();
    if (payee.isEmpty ||
        archived.contains(normalized) ||
        deleted.contains(normalized) ||
        !seen.add(normalized)) {
      continue;
    }
    payees.add(payee);
  }
  final transactions =
      store.transactions
          .where((item) => !item.isDeleted)
          .toList(growable: false)
        ..sort((a, b) => b.date.compareTo(a.date));
  for (final transaction in transactions) {
    final payee = transaction.payee.trim();
    final normalized = payee.toLowerCase();
    if (payee.isEmpty ||
        archived.contains(normalized) ||
        deleted.contains(normalized) ||
        !seen.add(normalized)) {
      continue;
    }
    payees.add(payee);
  }
  return payees;
}

List<String> managedPayees(FinanceDataStore store) {
  final seen = <String>{};
  final result = <String>[];
  final archived = store.preferences.archivedPayeeNames;
  final deleted = store.preferences.deletedPayeeNames;

  void add(String value) {
    final payee = value.trim();
    final normalized = normalizeManagedPayee(payee);
    if (payee.isEmpty ||
        isSystemGeneratedManagedPayee(payee) ||
        archived.contains(normalized) ||
        deleted.contains(normalized) ||
        !seen.add(normalized)) {
      return;
    }
    result.add(payee);
  }

  for (final payee in store.preferences.savedPayeeNames) {
    add(payee);
  }
  final actualTransactions =
      store.transactions
          .where(
            (transaction) =>
                !transaction.isDeleted &&
                (transaction.type == TransactionType.expense ||
                    transaction.type == TransactionType.income),
          )
          .toList(growable: false)
        ..sort((a, b) => b.date.compareTo(a.date));
  for (final transaction in actualTransactions) {
    add(transaction.payee);
  }
  return result;
}

List<String> archivedPayees(FinanceDataStore store) {
  final namesByNormalized = <String, String>{};
  for (final payee in [
    ...store.preferences.savedPayeeNames,
    ...store.transactions
        .where((item) => !item.isDeleted)
        .map((item) => item.payee),
  ]) {
    final trimmed = payee.trim();
    if (trimmed.isEmpty) continue;
    namesByNormalized.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
  }
  return [
    for (final normalized in store.preferences.archivedPayeeNames)
      if (!store.preferences.deletedPayeeNames.contains(normalized))
        namesByNormalized[normalized] ?? normalized,
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

String? sanitizedCategoryIconName(String? iconName) {
  if (iconName == null) return null;
  final trimmed = iconName.trim();
  if (trimmed.isEmpty) return null;
  return CategoryIconCatalog.contains(trimmed) ? trimmed : null;
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

class FutureScheduleDraft {
  FutureScheduleDraft({
    required DateTime firstDate,
    this.frequency = v2_scheduled.RecurrenceFrequency.monthly,
    this.alertPreference = v2_scheduled.AlertPreference.none,
    int timeMinutes = 9 * 60,
  }) : firstDate = TextEditingController(text: dateInput(firstDate)),
       time = TextEditingController(text: alertTimeInput(timeMinutes));

  final TextEditingController firstDate;
  final TextEditingController time;
  v2_scheduled.RecurrenceFrequency frequency;
  v2_scheduled.AlertPreference alertPreference;

  DateTime parsedFirstDate(DateTime fallback) =>
      parseDateInput(firstDate.text, fallback);

  int get timeMinutes => parseAlertTimeMinutes(time.text, 9 * 60);
}

bool isValidFutureScheduleDate(DateTime date, DateTime transactionDate) {
  final today = DateTime.now();
  final earliest =
      DateTime(
        transactionDate.year,
        transactionDate.month,
        transactionDate.day,
      ).isAfter(DateTime(today.year, today.month, today.day))
      ? DateTime(
          transactionDate.year,
          transactionDate.month,
          transactionDate.day,
        )
      : DateTime(today.year, today.month, today.day);
  final candidate = DateTime(date.year, date.month, date.day);
  return candidate.isAfter(earliest);
}

class InlineFutureScheduleSection extends StatelessWidget {
  const InlineFutureScheduleSection({
    required this.draft,
    required this.onChanged,
    required this.keyPrefix,
    super.key,
  });

  final FutureScheduleDraft draft;
  final VoidCallback onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowValueStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.15,
    );

    Widget row({
      required String keyName,
      required IconData icon,
      required String value,
      required VoidCallback onTap,
    }) {
      return InkWell(
        key: ValueKey('$keyPrefix-$keyName'),
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              TransactionFormIcon(icon),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text(value, style: rowValueStyle)),
              Icon(AppIcon.chevronDown, size: AppIconSize.hero),
            ],
          ),
        ),
      );
    }

    return Column(
      key: ValueKey('$keyPrefix-controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1, bottom: 8),
          child: Text(
            'Schedule',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppTheme.accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        TransactionFormLabel('First scheduled date'),
        row(
          keyName: 'first-date',
          icon: AppIcon.calendar,
          value: fullMonthDateLabel(draft.parsedFirstDate(DateTime.now())),
          onTap: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            final picked = await pickDateForField(
              context,
              draft.parsedFirstDate(DateTime.now()),
            );
            if (picked != null) {
              draft.firstDate.text = dateInput(picked);
              onChanged();
            }
            FocusManager.instance.primaryFocus?.unfocus();
          },
        ),
        TransactionFormDivider(),
        TransactionFormLabel('Time'),
        row(
          keyName: 'time',
          icon: AppIcon.schedule,
          value: draft.time.text,
          onTap: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            final minutes = draft.timeMinutes;
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
              initialEntryMode: TimePickerEntryMode.dial,
              builder: (context, child) => polishedPickerBuilder(
                context,
                child,
                forceTwelveHourTime: true,
              ),
            );
            if (picked != null) {
              draft.time.text = alertTimeInput(
                picked.hour * 60 + picked.minute,
              );
              onChanged();
            }
            FocusManager.instance.primaryFocus?.unfocus();
          },
        ),
        TransactionFormDivider(),
        TransactionFormLabel('Frequency'),
        row(
          keyName: 'frequency',
          icon: AppIcon.repeat,
          value: recurrenceFrequencyLabel(draft.frequency),
          onTap: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            final selected = await showScheduledChoicePicker(
              context,
              title: 'Frequency',
              values: v2_scheduled.RecurrenceFrequency.values,
              selected: draft.frequency,
              label: recurrenceFrequencyLabel,
            );
            if (selected != null) {
              draft.frequency = selected;
              onChanged();
            }
          },
        ),
        TransactionFormDivider(),
        TransactionFormLabel('Reminder'),
        row(
          keyName: 'alert',
          icon: draft.alertPreference == v2_scheduled.AlertPreference.none
              ? AppIcon.notificationNone
              : AppIcon.notificationActive,
          value: alertPreferenceLabel(draft.alertPreference),
          onTap: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            final selected = await showScheduledChoicePicker(
              context,
              title: 'Reminder',
              values: v2_scheduled.AlertPreference.values,
              selected: draft.alertPreference,
              label: alertPreferenceLabel,
            );
            if (selected != null) {
              draft.alertPreference = selected;
              onChanged();
            }
          },
        ),
      ],
    );
  }
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

String currencySettingsLabel(String code) {
  return switch (code) {
    'USD' => 'USD — US Dollar',
    'PHP' => 'PHP — Philippine Peso',
    'EUR' => 'EUR — Euro',
    'GBP' => 'GBP — British Pound',
    'CAD' => 'CAD — Canadian Dollar',
    'AUD' => 'AUD — Australian Dollar',
    'JPY' => 'JPY — Japanese Yen',
    _ => code,
  };
}

Future<AccountType?> showAccountTypePicker(
  BuildContext context, {
  required AccountType selected,
}) {
  return showModalBottomSheet<AccountType>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Account type',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          for (final type in AccountType.values)
            ListTile(
              leading: Icon(accountIcon(type), color: AppTheme.accent),
              title: Text(accountTypeLabel(type)),
              trailing: type == selected
                  ? Icon(AppIcon.check, color: AppTheme.accent)
                  : null,
              onTap: () => Navigator.pop(sheetContext, type),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    ),
  );
}

Future<v2_account.AccountType?> showV2AccountTypePicker(
  BuildContext context, {
  required v2_account.AccountType selected,
}) {
  return showModalBottomSheet<v2_account.AccountType>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Account type',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          for (final type in v2_account.AccountType.values)
            ListTile(
              leading: Icon(v2AccountIcon(type), color: AppTheme.accent),
              title: Text(v2AccountTypeLabel(type)),
              trailing: type == selected
                  ? Icon(AppIcon.check, color: AppTheme.accent)
                  : null,
              onTap: () => Navigator.pop(sheetContext, type),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    ),
  );
}

Future<String?> showTransactionAccountPicker(
  BuildContext context, {
  required List<v2_account.AccountRecord> accounts,
  required String selectedAccountId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.62,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose account',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: accounts.length,
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  return ListTile(
                    leading: Icon(
                      v2AccountIcon(account.type),
                      color: AppTheme.accent,
                    ),
                    title: Text(account.name),
                    trailing: account.id == selectedAccountId
                        ? Icon(AppIcon.check, color: AppTheme.accent)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, account.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> showTransactionCategoryFlow(
  BuildContext context, {
  required FinanceDataStore dataStore,
  required bool isExpense,
  required String selectedCategoryId,
}) async {
  final kind = isExpense
      ? v2_category.CategoryKind.expense
      : v2_category.CategoryKind.income;
  var currentSelection = selectedCategoryId;

  while (context.mounted) {
    final selection = await _showTransactionCategoryPickerSheet(
      context,
      categories: categoriesForTransactionKind(dataStore, isExpense),
      selectedCategoryId: currentSelection,
    );
    if (!context.mounted || selection == null) return null;
    if (selection.categoryId != null) return selection.categoryId;

    final createdId = await showTransactionCategoryCreationDialog(
      context,
      dataStore: dataStore,
      kind: kind,
    );
    if (!context.mounted) return null;
    if (createdId == null) {
      // Add Category was cancelled. Reopen the picker from the live store so
      // the transaction form stays intact and the user can choose again.
      continue;
    }

    final createdCategory = dataStore.categories
        .where(
          (category) =>
              category.id == createdId &&
              category.kind == kind &&
              category.isVisible,
        )
        .firstOrNull;
    if (createdCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The category was saved but is not available for this transaction.',
          ),
        ),
      );
      continue;
    }
    currentSelection = createdCategory.id;
    return currentSelection;
  }
  return null;
}

Future<String?> showTransactionCategoryCreationDialog(
  BuildContext context, {
  required FinanceDataStore dataStore,
  required v2_category.CategoryKind kind,
}) async {
  var categoryName = '';
  String? parentCategoryId;
  String? iconName;
  int? colorValue;
  var isSaving = false;
  String? validationError;

  final createdId = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final parentOptions = dataStore.categories
            .where((category) => category.isVisible && category.kind == kind)
            .toList(growable: false);
        final selectedParentId =
            parentOptions.any((category) => category.id == parentCategoryId)
            ? parentCategoryId
            : null;
        parentCategoryId = selectedParentId;

        Future<void> saveCategory() async {
          if (isSaving) return;
          final trimmedName = categoryName.trim();
          if (trimmedName.isEmpty) {
            setDialogState(() => validationError = 'Enter a category name.');
            return;
          }
          final duplicateExists = dataStore.categories.any(
            (category) =>
                category.isVisible &&
                category.kind == kind &&
                category.name.trim().toLowerCase() == trimmedName.toLowerCase(),
          );
          if (duplicateExists) {
            setDialogState(
              () =>
                  validationError = 'A category with this name already exists.',
            );
            return;
          }

          FocusManager.instance.primaryFocus?.unfocus();
          setDialogState(() {
            isSaving = true;
            validationError = null;
          });
          final categoryId = 'cat_${DateTime.now().microsecondsSinceEpoch}';
          try {
            await dataStore.saveCategoryLocalFirst(
              v2_category.CategoryRecord(
                id: categoryId,
                name: trimmedName,
                kind: kind,
                parentCategoryId: parentCategoryId,
                iconName: iconName,
                colorValue: colorValue,
                sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
              ),
            );
            if (!dialogContext.mounted) return;
            HapticFeedback.mediumImpact();
            Navigator.pop(dialogContext, categoryId);
          } catch (error) {
            if (!dialogContext.mounted) return;
            setDialogState(() {
              isSaving = false;
              validationError =
                  'The category could not be saved. Please try again.';
            });
          }
        }

        final theme = Theme.of(dialogContext);
        final fieldValueStyle = theme.textTheme.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.15,
        );
        final fieldHintStyle = fieldValueStyle?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        const borderlessDecoration = InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        );
        final selectedParent = parentOptions
            .where((item) => item.id == selectedParentId)
            .firstOrNull;
        final selectedIcon = CategoryIconCatalog.find(iconName);
        final selectedColor = categoryColorOptions
            .where((item) => item.value == colorValue)
            .firstOrNull;

        Widget valueRow({
          required IconData icon,
          required String value,
          VoidCallback? onTap,
          Color? iconColor,
          Widget? leading,
          Key? key,
        }) {
          final child = Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                leading ?? TransactionFormIcon(icon, color: iconColor),
                SizedBox(width: AppSpacing.md),
                Expanded(child: Text(value, style: fieldValueStyle)),
                if (onTap != null)
                  Icon(AppIcon.chevronDownRounded, size: AppIconSize.hero),
              ],
            ),
          );
          if (onTap == null) return KeyedSubtree(key: key, child: child);
          return InkWell(
            key: key,
            borderRadius: BorderRadius.circular(AppRadii.control),
            onTap: isSaving ? null : onTap,
            child: child,
          );
        }

        return TransactionSheetFrame(
          title: 'Add Category',
          actions: TransactionFormActions(
            onCancel: () => Navigator.pop(dialogContext),
            onSave: saveCategory,
            isSaving: isSaving,
            saveKey: const ValueKey('transaction-save-new-category'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TransactionFormLabel('Category name'),
              Row(
                children: [
                  TransactionFormIcon(AppIcon.category),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('transaction-new-category-name'),
                      autofocus: true,
                      enabled: !isSaving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        categoryName = value;
                        if (validationError != null) {
                          setDialogState(() => validationError = null);
                        }
                      },
                      onSubmitted: (_) => saveCategory(),
                      decoration: borderlessDecoration.copyWith(
                        hintText: 'Category name',
                        hintStyle: fieldHintStyle,
                      ),
                      style: fieldValueStyle,
                    ),
                  ),
                ],
              ),
              const TransactionFormDivider(),
              const TransactionFormLabel('Type'),
              valueRow(
                icon: categoryKindIcon(kind.name),
                value: categoryKindLabel(kind.name),
              ),
              TransactionFormDivider(),
              TransactionFormLabel('Parent category'),
              valueRow(
                key: ValueKey('transaction-new-category-parent'),
                icon: AppIcon.categoryTree,
                value: selectedParent?.name ?? 'None',
                onTap: () async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  final selected = await showPolishedChoicePicker<String>(
                    dialogContext,
                    title: 'Parent category',
                    selected: selectedParentId ?? noCategoryChoice,
                    choices: [
                      PolishedChoice(
                        value: noCategoryChoice,
                        label: 'None',
                        leading: Icon(AppIcon.expense),
                      ),
                      for (final item in parentOptions)
                        PolishedChoice(
                          value: item.id,
                          label: item.name,
                          leading: Icon(categoryIcon(item)),
                        ),
                    ],
                  );
                  if (selected != null && dialogContext.mounted) {
                    setDialogState(
                      () => parentCategoryId = selected == noCategoryChoice
                          ? null
                          : selected,
                    );
                  }
                },
              ),
              const TransactionFormDivider(),
              const TransactionFormLabel('Icon'),
              valueRow(
                icon: categoryIconForName(iconName, kind),
                leading: CategoryIconBadge(
                  iconName: iconName,
                  kind: kind,
                  colorValue: colorValue,
                  semanticLabel: selectedIcon?.label ?? 'No icon selected',
                  size: CategoryIconBadgeSize.form,
                ),
                value: selectedIcon?.label ?? 'No icon',
                onTap: () async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  final selected = await showCategoryIconPicker(
                    dialogContext,
                    selectedKey: iconName ?? categoryIconNoneKey,
                    categoryKind: kind,
                    categoryColorValue: colorValue,
                  );
                  if (selected != null && dialogContext.mounted) {
                    setDialogState(
                      () => iconName = selected == categoryIconNoneKey
                          ? null
                          : selected,
                    );
                  }
                },
              ),
              TransactionFormDivider(),
              TransactionFormLabel('Color'),
              valueRow(
                icon: AppIcon.palette,
                iconColor: colorValue == null
                    ? AppTheme.accent
                    : Color(colorValue!),
                value: selectedColor?.label ?? 'Default',
                onTap: () async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  final selected = await showPolishedChoicePicker<int>(
                    dialogContext,
                    title: 'Category color',
                    selected: colorValue ?? noCategoryColorChoice,
                    choices: [
                      PolishedChoice(
                        value: noCategoryColorChoice,
                        label: 'Default',
                        leading: Icon(AppIcon.clearColor),
                      ),
                      for (final item in categoryColorOptions)
                        PolishedChoice(
                          value: item.value,
                          label: item.label,
                          leading: Icon(
                            AppIcon.circle,
                            color: Color(item.value),
                          ),
                        ),
                    ],
                  );
                  if (selected != null && dialogContext.mounted) {
                    setDialogState(
                      () => colorValue = selected == noCategoryColorChoice
                          ? null
                          : selected,
                    );
                  }
                },
              ),
              if (validationError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  validationError!,
                  key: const ValueKey('transaction-new-category-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
  return createdId;
}

class _TransactionCategoryPickerResult {
  const _TransactionCategoryPickerResult.category(this.categoryId);

  const _TransactionCategoryPickerResult.addNew() : categoryId = null;

  final String? categoryId;
}

Future<_TransactionCategoryPickerResult?> _showTransactionCategoryPickerSheet(
  BuildContext context, {
  required List<v2_category.CategoryRecord> categories,
  required String selectedCategoryId,
}) async {
  final categoriesById = {
    for (final category in categories) category.id: category,
  };
  final collapsedCategoryIds = categories
      .where(
        (candidate) => categories.any(
          (category) => category.parentCategoryId == candidate.id,
        ),
      )
      .map((category) => category.id)
      .toSet();
  final selectedParentId = categoriesById[selectedCategoryId]?.parentCategoryId;
  if (selectedParentId != null) {
    collapsedCategoryIds.remove(selectedParentId);
  }
  final result = await showModalBottomSheet<_TransactionCategoryPickerResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final theme = Theme.of(sheetContext);
        final colorScheme = theme.colorScheme;
        final visibleCategories = visibleCategoriesInDisplayOrder(
          categories,
          collapsedCategoryIds,
        );
        final childCounts = <String, int>{};
        for (final category in categories) {
          final parentId = category.parentCategoryId;
          if (parentId != null) {
            childCounts[parentId] = (childCounts[parentId] ?? 0) + 1;
          }
        }
        final dividerColor = colorScheme.outlineVariant.withValues(alpha: 0.42);

        Widget categoryRow(v2_category.CategoryRecord category, int index) {
          final depth = categoryDepth(category, categoriesById);
          final childCount = childCounts[category.id] ?? 0;
          final hasChildren = childCount > 0;
          final isExpanded = !collapsedCategoryIds.contains(category.id);
          final isSelected = category.id == selectedCategoryId;
          final parent = categoriesById[category.parentCategoryId];
          final isChild = depth > 0;

          return Semantics(
            selected: isSelected,
            button: true,
            label: isChild
                ? '${category.name}, subcategory of ${parent?.name ?? 'category'}'
                : category.name,
            child: InkWell(
              key: ValueKey('category-picker-row-${category.id}'),
              onTap: () => Navigator.pop(
                sheetContext,
                _TransactionCategoryPickerResult.category(category.id),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                decoration: BoxDecoration(
                  border: index == visibleCategories.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: dividerColor)),
                ),
                padding: EdgeInsets.only(
                  left: AppSpacing.lg + (isChild ? 30 : 0),
                  right: AppSpacing.sm,
                  top: 7,
                  bottom: 7,
                ),
                child: Row(
                  children: [
                    if (isChild)
                      Container(
                        key: ValueKey(
                          'category-picker-hierarchy-${category.id}',
                        ),
                        width: 12,
                        height: 34,
                        margin: const EdgeInsets.only(right: AppSpacing.xs),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: dividerColor, width: 1.5),
                            bottom: BorderSide(color: dividerColor, width: 1.5),
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(7),
                          ),
                        ),
                      ),
                    CategoryIconBadge.category(
                      category,
                      size: isChild
                          ? CategoryIconBadgeSize.row
                          : CategoryIconBadgeSize.form,
                      selected: isSelected,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: isChild
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                            ),
                          ),
                          if (isChild || hasChildren)
                            Text(
                              isChild
                                  ? parent?.name ??
                                        categoryKindLabel(category.kind.name)
                                  : '$childCount ${childCount == 1 ? 'subcategory' : 'subcategories'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          AppIcon.checkRounded,
                          color: AppTheme.accent,
                          size: AppIconSize.form,
                        ),
                      ),
                    if (hasChildren)
                      IconButton(
                        key: ValueKey('category-picker-toggle-${category.id}'),
                        tooltip: isExpanded
                            ? 'Collapse ${category.name}'
                            : 'Expand ${category.name}',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setSheetState(() {
                            if (isExpanded) {
                              collapsedCategoryIds.add(category.id);
                            } else {
                              collapsedCategoryIds.remove(category.id);
                            }
                          });
                        },
                        icon: AnimatedRotation(
                          turns: isExpanded ? 0.25 : 0,
                          duration: Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: Icon(AppIcon.chevronRightRounded),
                        ),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          );
        }

        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xs,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      'Choose Category',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: visibleCategories.isEmpty
                        ? Center(
                            child: Text(
                              'No categories yet',
                              key: const ValueKey('category-picker-empty'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView.builder(
                            key: const ValueKey('category-picker-list'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                            itemCount: visibleCategories.length,
                            itemBuilder: (context, index) =>
                                categoryRow(visibleCategories[index], index),
                          ),
                  ),
                  Divider(height: 1, thickness: 1, color: dividerColor),
                  InkWell(
                    key: const ValueKey('category-picker-add-new'),
                    onTap: () => Navigator.pop(
                      sheetContext,
                      const _TransactionCategoryPickerResult.addNew(),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Icon(AppIcon.addRounded, color: AppTheme.accent),
                          SizedBox(width: AppSpacing.sm),
                          Text(
                            'Add New Category',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  return result;
}

Future<String> createBasicCategory(
  FinanceDataStore dataStore, {
  required String name,
  required v2_category.CategoryKind kind,
}) async {
  final categoryId = 'cat_${DateTime.now().microsecondsSinceEpoch}';
  final category = v2_category.CategoryRecord(
    id: categoryId,
    name: name,
    kind: kind,
    sync: v2_sync.SyncMetadata.fresh(deviceId: dataStore.deviceId),
  );
  await dataStore.saveCategoryLocalFirst(category);
  HapticFeedback.mediumImpact();
  return categoryId;
}

int? optionalPositiveMinor(int value) => value > 0 ? value : null;

String dateInput(DateTime date) {
  return compactDate(date);
}

String fullMonthDateLabel(DateTime date) {
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
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
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

/// Parses the user-selected transaction day without discarding its time.
///
/// The transaction forms intentionally present a date-only field. Existing
/// transactions retain their recorded time when edited, while newly created
/// transactions retain the time at which the form is saved. Date-only domain
/// values continue to use [parseDateInput] and remain normalized to midnight.
DateTime parseTransactionDateInput(String value, DateTime timeSource) {
  final day = parseDateInput(value, timeSource);
  return DateTime(
    day.year,
    day.month,
    day.day,
    timeSource.hour,
    timeSource.minute,
    timeSource.second,
    timeSource.millisecond,
    timeSource.microsecond,
  );
}

bool isSameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

Future<DateTime?> pickDateForField(BuildContext context, DateTime initialDate) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(1970),
    lastDate: DateTime(2100),
    builder: (context, child) => polishedPickerBuilder(context, child),
  );
}

Widget polishedPickerBuilder(
  BuildContext context,
  Widget? child, {
  bool forceTwelveHourTime = false,
}) {
  final baseTheme = Theme.of(context);
  final isDark = baseTheme.brightness == Brightness.dark;
  final panel = isDark ? AppColors.panelDark : Colors.white;
  final subtleSurface = isDark ? AppColors.pageDark : AppTheme.page;
  final line = isDark ? AppColors.lineDark : AppTheme.line;
  final onSurface = baseTheme.colorScheme.onSurface;
  final muted = baseTheme.colorScheme.onSurfaceVariant;
  final actionStyle = TextButton.styleFrom(
    foregroundColor: AppTheme.accent,
    textStyle: const TextStyle(fontWeight: FontWeight.w800),
  );
  final selectedBackground = WidgetStateColor.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? AppTheme.accent
        : Colors.transparent,
  );
  final selectedForeground = WidgetStateColor.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) {
      return onSurface.withValues(alpha: 0.34);
    }
    return states.contains(WidgetState.selected) ? Colors.white : onSurface;
  });
  final selectedSoftBackground = WidgetStateColor.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? AppTheme.accent.withValues(alpha: isDark ? 0.28 : 0.14)
        : subtleSurface,
  );
  final selectedSoftForeground = WidgetStateColor.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? (isDark ? Colors.white : AppTheme.accentStrong)
        : muted,
  );
  final pickerTheme = baseTheme.copyWith(
    colorScheme: baseTheme.colorScheme.copyWith(
      primary: AppTheme.accent,
      onPrimary: Colors.white,
      surface: panel,
      surfaceContainerHigh: panel,
      surfaceContainerHighest: subtleSurface,
      outline: line,
      outlineVariant: line,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      headerBackgroundColor: panel,
      headerForegroundColor: onSurface,
      headerHeadlineStyle: baseTheme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headerHelpStyle: baseTheme.textTheme.titleSmall?.copyWith(
        color: muted,
        fontWeight: FontWeight.w700,
      ),
      weekdayStyle: baseTheme.textTheme.labelMedium?.copyWith(
        color: muted,
        fontWeight: FontWeight.w800,
      ),
      dayStyle: baseTheme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      dayBackgroundColor: selectedBackground,
      dayForegroundColor: selectedForeground,
      dayOverlayColor: WidgetStatePropertyAll(
        AppTheme.accent.withValues(alpha: 0.1),
      ),
      todayForegroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppTheme.accent,
      ),
      todayBorder: const BorderSide(color: AppTheme.accent, width: 1.2),
      yearBackgroundColor: selectedBackground,
      yearForegroundColor: selectedForeground,
      dividerColor: line.withValues(alpha: 0.72),
      subHeaderForegroundColor: muted,
      cancelButtonStyle: actionStyle,
      confirmButtonStyle: actionStyle,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: panel,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      helpTextStyle: baseTheme.textTheme.titleSmall?.copyWith(
        color: muted,
        fontWeight: FontWeight.w700,
      ),
      hourMinuteColor: selectedSoftBackground,
      hourMinuteTextColor: selectedSoftForeground,
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      hourMinuteTextStyle: baseTheme.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      dayPeriodColor: selectedSoftBackground,
      dayPeriodTextColor: selectedSoftForeground,
      dayPeriodBorderSide: BorderSide(color: line),
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      dialBackgroundColor: subtleSurface,
      dialHandColor: AppTheme.accent,
      dialTextColor: selectedForeground,
      entryModeIconColor: AppTheme.accent,
      cancelButtonStyle: actionStyle,
      confirmButtonStyle: actionStyle,
    ),
  );

  Widget themedChild = Theme(data: pickerTheme, child: child!);
  if (forceTwelveHourTime) {
    themedChild = MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
      child: themedChild,
    );
  }
  return themedChild;
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

Map<DateTime, List<ScheduledCalendarOccurrence>> scheduledOccurrencesByDate(
  Iterable<ScheduledCalendarOccurrence> occurrences,
) {
  final grouped = <DateTime, List<ScheduledCalendarOccurrence>>{};
  for (final occurrence in occurrences) {
    final date = calendarDateKey(occurrence.scheduledDate);
    grouped.putIfAbsent(date, () => []).add(occurrence);
  }
  return grouped;
}

class ScheduledCalendarOccurrence {
  const ScheduledCalendarOccurrence({
    required this.transaction,
    required this.scheduledDate,
    required this.plannedAmountMinor,
    this.record,
  });

  final v2_scheduled.ScheduledTransactionRecord transaction;
  final DateTime scheduledDate;
  final int plannedAmountMinor;
  final v2_scheduled.ScheduledOccurrenceRecord? record;

  bool get isPaid =>
      record?.status == v2_scheduled.ScheduledOccurrenceStatus.paid;
  bool get isSkipped =>
      record?.status == v2_scheduled.ScheduledOccurrenceStatus.skipped;
  bool get isPending =>
      record == null ||
      record?.status == v2_scheduled.ScheduledOccurrenceStatus.pending;
}

class ScheduledMonthSummary {
  const ScheduledMonthSummary({
    required this.plannedAmountMinor,
    required this.paidAmountMinor,
    required this.remainingAmountMinor,
  });

  final int plannedAmountMinor;
  final int paidAmountMinor;
  final int remainingAmountMinor;
}

List<ScheduledCalendarOccurrence> scheduledOccurrencesForMonth(
  Iterable<v2_scheduled.ScheduledTransactionRecord> scheduled,
  DateTime month,
) {
  final monthStart = calendarDateKey(DateTime(month.year, month.month));
  final monthEnd = calendarDateKey(DateTime(month.year, month.month + 1));
  final result = <ScheduledCalendarOccurrence>[];

  for (final item in scheduled) {
    final recordedDates = <DateTime>{};
    for (final occurrence in item.occurrences) {
      final occurrenceKey = calendarDateKey(occurrence.scheduledDate);
      if (occurrenceKey.isBefore(monthStart) ||
          !occurrenceKey.isBefore(monthEnd)) {
        continue;
      }
      recordedDates.add(occurrenceKey);
      result.add(
        ScheduledCalendarOccurrence(
          transaction: item,
          scheduledDate: occurrence.scheduledDate,
          plannedAmountMinor: occurrence.plannedAmountMinor,
          record: occurrence,
        ),
      );
    }

    if (item.isDeleted) continue;
    var date = item.nextDate;
    while (calendarDateKey(date).isBefore(monthStart)) {
      final next = nextDateForScheduledFrequency(date, item.frequency);
      if (next == null || !next.isAfter(date)) break;
      date = next;
    }
    while (calendarDateKey(date).isBefore(monthEnd) &&
        !date.isAfter(item.endDate ?? DateTime(9999))) {
      final dateKey = calendarDateKey(date);
      if (!dateKey.isBefore(monthStart) && !recordedDates.contains(dateKey)) {
        result.add(
          ScheduledCalendarOccurrence(
            transaction: item,
            scheduledDate: date,
            plannedAmountMinor: item.amountMinor,
          ),
        );
      }
      final next = nextDateForScheduledFrequency(date, item.frequency);
      if (next == null || !next.isAfter(date)) break;
      date = next;
    }
  }

  result.sort((left, right) {
    final byDate = left.scheduledDate.compareTo(right.scheduledDate);
    if (byDate != 0) return byDate;
    return left.transaction.id.compareTo(right.transaction.id);
  });
  return result;
}

ScheduledMonthSummary scheduledMonthSummary(
  Iterable<ScheduledCalendarOccurrence> occurrences,
  Iterable<TransactionRecord> transactions, {
  CalendarActivityFilter filter = CalendarActivityFilter.all,
}) {
  final activeTransactions = transactions
      .where((transaction) => !transaction.isDeleted)
      .toList(growable: false);
  var planned = 0;
  var paid = 0;
  var remaining = 0;
  for (final occurrence in occurrences) {
    if (!filter.matchesScheduled(occurrence.transaction.type)) continue;
    final plannedAmount = occurrence.plannedAmountMinor.abs();
    planned += plannedAmount;
    if (occurrence.isPaid) {
      final completedAmount = actualAmountForScheduledOccurrence(
        occurrence,
        activeTransactions,
      ).abs();
      paid += completedAmount;
      remaining += max(plannedAmount - completedAmount, 0);
    } else if (occurrence.isPending) {
      remaining += plannedAmount;
    }
  }
  return ScheduledMonthSummary(
    plannedAmountMinor: planned,
    paidAmountMinor: paid,
    remainingAmountMinor: remaining,
  );
}

int actualAmountForScheduledOccurrence(
  ScheduledCalendarOccurrence occurrence,
  Iterable<TransactionRecord> transactions,
) {
  final occurrenceRecord = occurrence.record;
  for (final transaction in transactions) {
    if (occurrenceRecord?.transactionId != null &&
        transaction.id == occurrenceRecord!.transactionId) {
      return transaction.amountMinor;
    }
  }
  for (final transaction in transactions) {
    if (transaction.scheduledTransactionId == occurrence.transaction.id &&
        transaction.scheduledOccurrenceDate != null &&
        isSameCalendarDay(
          transaction.scheduledOccurrenceDate!,
          occurrence.scheduledDate,
        )) {
      return transaction.amountMinor;
    }
  }
  return occurrenceRecord?.actualAmountMinor ?? 0;
}

DateTime calendarDateKey(DateTime date) {
  final localDate = date.isUtc ? date.toLocal() : date;
  return DateTime(localDate.year, localDate.month, localDate.day);
}

String calendarDateId(DateTime date) {
  final key = calendarDateKey(date);
  return '${key.year}-${key.month}-${key.day}';
}

String compactScheduledMoney(int amountMinor, CurrencyFormatSettings currency) {
  final formatter = MoneyFormatter(currency);
  final formatted = formatter.formatMinor(
    amountMinor,
    showPositiveSign: amountMinor > 0,
  );
  if (formatted.length <= 11) return formatted;

  var scale = 1;
  for (var index = 0; index < currency.decimalPlaces; index += 1) {
    scale *= 10;
  }
  final major = amountMinor.abs() / scale;
  final sign = amountMinor < 0
      ? '-'
      : amountMinor > 0
      ? '+'
      : '';
  if (major >= 1000000) {
    return '$sign${currency.symbol}${compactScheduledNumber(major / 1000000)}M';
  }
  if (major >= 1000) {
    return '$sign${currency.symbol}${compactScheduledNumber(major / 1000)}K';
  }
  return formatted;
}

String compactScheduledNumber(double value) {
  return value >= 100 || value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
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
