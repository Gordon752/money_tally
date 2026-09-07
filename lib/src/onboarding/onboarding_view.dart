part of '../../main.dart';

/// Runs before sign-in or local-only entry; no financial setup is required.
/// Eligibility is checked once per launch. Reset Preferences takes effect on
/// the next launch, without tearing down an active account/session or dialog.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    required this.child,
    this.preferences = const OnboardingPreferences(),
    this.initialVersionSeen,
    super.key,
  });

  final Widget child;
  final OnboardingPreferences preferences;
  final int? initialVersionSeen;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late Future<int>? _version = widget.initialVersionSeen == null
      ? widget.preferences.readOnboardingVersionSeen()
      : null;
  var _completed = false;

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _version,
    initialData: widget.initialVersionSeen,
    builder: (context, snapshot) {
      if (_completed || (snapshot.data ?? 0) >= currentOnboardingVersion) {
        return widget.child;
      }
      if (snapshot.hasError) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Trackmark could not read your welcome preferences.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => setState(() {
                        _version = widget.preferences
                            .readOnboardingVersionSeen();
                      }),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return TrackmarkOnboarding(
        onComplete: () async {
          await widget.preferences.complete();
          if (mounted) setState(() => _completed = true);
        },
      );
    },
  );
}

const _onboardingTitles = [
  'Welcome to Trackmark Money',
  'Know what your money is doing',
  'Plan without moving money around',
  'Stay ahead of what’s coming',
  'You’re ready',
];

class TrackmarkOnboarding extends StatefulWidget {
  const TrackmarkOnboarding({
    required this.onComplete,
    this.onClose,
    super.key,
  });
  final Future<void> Function() onComplete;

  /// Present only for voluntary replay, never for the first-run introduction.
  final VoidCallback? onClose;

  @override
  State<TrackmarkOnboarding> createState() => _TrackmarkOnboardingState();
}

class _TrackmarkOnboardingState extends State<TrackmarkOnboarding> {
  var _page = 0;
  var _saving = false;
  String? _error;

  Future<void> _finish() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onComplete();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Your progress could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReplay = widget.onClose != null;
    final mediaSize = MediaQuery.sizeOf(context);
    final separateMoneyExampleFromNavigation =
        _page == 1 &&
        (mediaSize.shortestSide >= 600 ||
            (theme.platform == TargetPlatform.macOS && mediaSize.width >= 600));
    final reducedMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return PopScope(
      canPop: isReplay && _page == 0 && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving && _page > 0) setState(() => _page--);
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        Text(
                          trackmarkMoneyName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            '${_page + 1} of 5',
                            key: const ValueKey('onboarding-progress'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (isReplay)
                          IconButton(
                            key: const ValueKey('onboarding-close'),
                            tooltip: 'Close onboarding',
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              visualDensity: VisualDensity.standard,
                            ),
                            onPressed: _saving ? null : widget.onClose,
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: AnimatedSwitcher(
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                              fit: StackFit.expand,
                              alignment: Alignment.topCenter,
                              children: [...previousChildren, ?currentChild],
                            ),
                        duration: reducedMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        child: SingleChildScrollView(
                          key: ValueKey('onboarding-page-$_page'),
                          primary: false,
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  _onboardingTitles[_page],
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        height: 1.15,
                                        letterSpacing: 0,
                                      ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _OnboardingContent(
                                page: _page,
                                explainBalanceEffects: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // A viewport-to-footer gap stays visible even before the
                    // reader scrolls all the way through the trailing padding.
                    if (separateMoneyExampleFromNavigation)
                      const SizedBox(
                        key: ValueKey('onboarding-money-navigation-gap'),
                        height: AppSpacing.md,
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_page > 0) ...[
                          OutlinedButton(
                            key: const ValueKey('onboarding-back'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.standard,
                              minimumSize: const Size(64, 52),
                            ),
                            onPressed: _saving
                                ? null
                                : () => setState(() => _page--),
                            child: const Text('Back'),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Expanded(
                          child: FilledButton(
                            key: const ValueKey('onboarding-continue'),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.standard,
                              minimumSize: const Size.fromHeight(52),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                            ),
                            onPressed: _saving
                                ? null
                                : _page == 4
                                ? _finish
                                : () => setState(() => _page++),
                            child: Text(
                              _saving
                                  ? (isReplay ? 'Closing…' : 'Saving…')
                                  : _page == 4
                                  ? (isReplay
                                        ? 'Done'
                                        : 'Start Using Trackmark')
                                  : 'Continue',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_page == 4)
                      TextButton(
                        key: const ValueKey('onboarding-guides'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.standard,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _saving
                            ? null
                            : () => showTrackmarkGuides(context),
                        child: const Text('View Guides'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingContent extends StatelessWidget {
  const _OnboardingContent({
    required this.page,
    this.explainBalanceEffects = false,
  });
  final int page;
  // Expanded definitions are onboarding-only; the shared guide keeps its copy.
  final bool explainBalanceEffects;

  @override
  Widget build(BuildContext context) => switch (page) {
    0 => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WelcomeParagraph(
          'A simple, intentional way to understand and plan your money.',
        ),
        SizedBox(height: AppSpacing.lg),
        _WelcomeParagraph(
          'Trackmark uses manual entry, so you stay in control of what gets recorded. No bank connection is required.',
          secondary: true,
        ),
      ],
    ),
    1 => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _WelcomeDefinition(
          'Balance',
          'Cleared money currently in the account.',
        ),
        _WelcomeDefinition(
          'Pending',
          explainBalanceEffects
              ? 'Transactions that are known but not cleared yet. Pending affects Available to Spend, but does not change Balance until the transaction is cleared. It does not affect Reserved.'
              : 'Money you know about that has not cleared yet.',
        ),
        _WelcomeDefinition(
          'Reserved',
          explainBalanceEffects
              ? 'Money assigned to Funds or Goals. Reserved reduces Available to Spend, but does not change Balance until that money is actually spent.'
              : 'Money assigned to Funds or Goals.',
        ),
        const _WelcomeDefinition(
          'Available to Spend',
          'Money still free after pending commitments and reservations.',
        ),
        const SizedBox(height: AppSpacing.xs),
        const _ReservationExample(),
        const SizedBox(height: AppSpacing.md),
        const _WelcomeParagraph(
          'The money doesn’t move. Its job changes.',
          emphasis: true,
        ),
      ],
    ),
    2 => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlanIntroduction(
          icon: AppIcon.pieChart,
          title: 'Budgets',
          body:
              'Spending boundaries for categories. Budgets do not reserve cash.',
        ),
        const SizedBox(height: AppSpacing.sm),
        _PlanIntroduction(
          icon: AppIcon.savings,
          title: 'Funds',
          body:
              'Money reserved for recurring or expected expenses that will be spent and replenished.',
        ),
        const SizedBox(height: AppSpacing.sm),
        _PlanIntroduction(
          icon: AppIcon.goal,
          title: 'Goals',
          body:
              'Money reserved toward an objective or balance you want to reach or maintain.',
        ),
        const SizedBox(height: AppSpacing.lg),
        const _WelcomeParagraph(
          'Funds and Goals change what money is for, not which account it is in.',
          emphasis: true,
        ),
      ],
    ),
    3 => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WelcomeParagraph(
          'Scheduled transactions help you track upcoming income, bills, transfers, and other obligations before they happen.',
        ),
        SizedBox(height: AppSpacing.lg),
        _WelcomeParagraph(
          'Add reminders when timing matters, then mark items Paid or Skipped as life happens.',
          secondary: true,
        ),
      ],
    ),
    _ => const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WelcomeParagraph(
          'Start with your accounts, then add transactions as they happen. Trackmark will build the picture from there.',
        ),
        SizedBox(height: AppSpacing.lg),
        _WelcomeParagraph(
          'You can revisit help and guides anytime from Settings.',
          secondary: true,
        ),
      ],
    ),
  };
}

class _WelcomeParagraph extends StatelessWidget {
  const _WelcomeParagraph(
    this.text, {
    this.secondary = false,
    this.emphasis = false,
  });
  final String text;
  final bool secondary;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
      height: 1.45,
      color: secondary ? Theme.of(context).colorScheme.onSurfaceVariant : null,
      fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
    ),
  );
}

class _WelcomeDefinition extends StatelessWidget {
  const _WelcomeDefinition(this.title, this.body);
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.35,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _PlanIntroduction extends StatelessWidget {
  const _PlanIntroduction({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TransactionFormIcon(icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Educational figures, not live financial records or a second calculator.
class _ReservationExample extends StatelessWidget {
  const _ReservationExample();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            r'Starting balance: $2,000',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.md),
          const _ExampleStep(1, r'Reserve $500 for Bills', [
            r'$2,000',
            r'$500',
            r'$1,500',
          ]),
          const Divider(height: 24),
          const _ExampleStep(2, r'Spend $100 from the Bills Fund', [
            r'$1,900',
            r'$400',
            r'$1,500',
          ]),
          const Divider(height: 24),
          const _ExampleStep(3, r'Return $200 from the Fund', [
            r'$1,900',
            r'$200',
            r'$1,700',
          ]),
        ],
      ),
    ),
  );
}

class _ExampleStep extends StatelessWidget {
  const _ExampleStep(this.step, this.title, this.values);
  final int step;
  final String title;
  final List<String> values;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const labels = ['Balance', 'Reserved', 'Available'];
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$step. $title',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth <
                  220 * MediaQuery.textScalerOf(context).scale(14) / 14;
              return Wrap(
                spacing: 8,
                runSpacing: 10,
                children: [
                  for (var index = 0; index < labels.length; index++)
                    SizedBox(
                      width: stacked
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 16) / 3,
                      child: Semantics(
                        label: '${labels[index]} ${values[index]}',
                        excludeSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              labels[index],
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              values[index],
                              style: AppTextStyles.money(context, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

void showTrackmarkGuides(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const TrackmarkGuidesPage()));
}

/// Reuse the introduction as a read-only route over Settings. Unlike the
/// first-run gate, neither completing nor closing this route touches storage,
/// financial state, or the signed-in session underneath it.
void replayTrackmarkOnboarding(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (replayContext) => TrackmarkOnboarding(
        onComplete: () async => Navigator.of(replayContext).pop(),
        onClose: () => Navigator.of(replayContext).pop(),
      ),
    ),
  );
}

/// Reset UI preferences without deleting the payee catalog that historically
/// shares UserPreferences storage, or changing the legacy-import boundary.
Future<void> resetTrackmarkPreferences(
  FinanceDataStore store, {
  OnboardingPreferences onboarding = const OnboardingPreferences(),
}) async {
  final previous = store.preferences;
  await store.savePreferences(
    const UserPreferences().copyWith(
      savedPayeeNames: previous.savedPayeeNames,
      archivedPayeeNames: previous.archivedPayeeNames,
      deletedPayeeNames: previous.deletedPayeeNames,
      payeeCatalogStates: previous.payeeCatalogStates,
      legacyV1MigrationCompleted: previous.legacyV1MigrationCompleted,
    ),
  );
  await onboarding.reset();
}

/// A small offline guide, shared by Ready and Settings until web guides exist.
/// Reuses the introduction's explanations and never changes completion state.
class TrackmarkGuidesPage extends StatelessWidget {
  const TrackmarkGuidesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help & Guides')),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Card(
                clipBehavior: Clip.antiAlias,
                child: TrackmarkSupportLinkRow(
                  key: ValueKey('guides-website-link'),
                  link: TrackmarkSupportLink.help,
                  showDivider: false,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _WelcomeParagraph(
                'Trackmark uses manual entry, so you stay in control of what gets recorded. No bank connection is required.',
              ),
              for (final page in [1, 2, 3]) ...[
                const SizedBox(height: AppSpacing.xl),
                Text(
                  _onboardingTitles[page],
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.md),
                _OnboardingContent(page: page),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
