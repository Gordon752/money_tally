import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'firebase_options.dart';
import 'src/design/app_icons.dart';
import 'src/design/app_haptics.dart';
import 'src/design/accent_color_catalog.dart';
import 'src/design/category_icon_catalog.dart';
import 'src/design/credit_card_appearance.dart';
import 'src/design/design_tokens.dart';
import 'src/design/money_format.dart';
import 'src/design/widgets/amount_entry_field.dart';
import 'src/design/widgets/budget_progress_bar.dart';
import 'src/design/widgets/category_icon_badge.dart';
import 'src/design/widgets/category_icon_picker.dart';
import 'src/design/widgets/account_card.dart';
import 'src/design/widgets/floating_action_button.dart';
import 'src/design/widgets/floating_action_menu.dart';
import 'src/design/widgets/money_text.dart';
import 'src/design/widgets/percentage_entry_field.dart';
import 'src/design/widgets/scheduled_transaction_row.dart';
import 'src/design/widgets/transaction_row.dart';
import 'src/budgets/budget_calculator.dart';
import 'src/credit/credit_insights_calculator.dart';
import 'src/credit/credit_insights_completeness_ui.dart';
import 'src/domain/budget.dart';
import 'src/domain/account.dart' as v2_account;
import 'src/domain/category.dart' as v2_category;
import 'src/domain/goal.dart';
import 'src/domain/goal_funding.dart';
import 'src/domain/money.dart';
import 'src/domain/scheduled_transaction.dart' as v2_scheduled;
import 'src/domain/sync_metadata.dart' as v2_sync;
import 'src/domain/transaction.dart';
import 'src/domain/user_preferences.dart';
import 'src/export/export_file_service.dart';
import 'src/goals/goal_calculator.dart';
import 'src/migration/v1_snapshot_migrator.dart';
import 'src/migration/finance_data_bootstrapper.dart';
import 'src/management/management_ledger_index.dart';
import 'src/ledger/ledger_projection.dart';
import 'src/notifications/local_notification_scheduler.dart';
import 'src/notifications/notification_scheduler.dart';
import 'src/persistence/backup_codec.dart';
import 'src/persistence/backup_restore_service.dart';
import 'src/persistence/finance_record_repository.dart';
import 'src/persistence/firestore_record_repository.dart';
import 'src/reporting/report_calculator.dart';
import 'src/store/finance_data_store.dart';
import 'src/store/finance_data_store_scope.dart';
import 'src/sync/automatic_sync_service.dart';
import 'src/sync/cloud_sync_coordinator.dart';

part 'src/app_theme.dart';
part 'src/accounts/manage_accounts.dart';
part 'src/auth_service.dart';
part 'src/domain.dart';
part 'src/finance_home.dart';
part 'src/goals/goals_ui.dart';
part 'src/finance_store.dart';
part 'src/firestore_finance_repository.dart';
part 'src/local_finance_repository.dart';

final scheduledNotificationLaunchPayload = ValueNotifier<String?>(null);

/// Public presentation only. Internal identifiers and persistence keys remain
/// intentionally stable during the product rename.
const trackmarkMoneyName = 'Trackmark Money';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeTrackmarkBackgroundSync();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter startup error: ${details.exceptionAsString()}');
  };
  runApp(const MoneyTallyBootstrap());
}

class MoneyTallyBootstrap extends StatefulWidget {
  const MoneyTallyBootstrap({super.key});

  @override
  State<MoneyTallyBootstrap> createState() => _MoneyTallyBootstrapState();
}

class _MoneyTallyBootstrapState extends State<MoneyTallyBootstrap> {
  static const _minimumLaunchPresentation = Duration(milliseconds: 600);
  late final Future<AppStores> _startup = _load();

  Future<AppStores> _load() async {
    final launchStopwatch = Stopwatch()..start();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Trackmark's v2 repository is the durable offline source of truth.
    // Disabling Firestore's second disk cache prevents stale reads and pending
    // mutation queues from masquerading as a completed cloud sync.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler();
    try {
      final localNotificationScheduler = LocalNotificationScheduler(
        onNotificationSelected: (payload) {
          scheduledNotificationLaunchPayload.value = payload ?? 'scheduled';
        },
      );
      await localNotificationScheduler.initialize();
      notificationScheduler = localNotificationScheduler;
    } catch (error, stackTrace) {
      debugPrint('Local notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    final dataStore = await _loadV2Store(
      notificationScheduler: notificationScheduler,
    );
    try {
      await dataStore.refreshScheduledNotifications();
    } catch (error, stackTrace) {
      debugPrint('Scheduled notification refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    final stores = AppStores(dataStore: dataStore);
    final remainingPresentation =
        _minimumLaunchPresentation - launchStopwatch.elapsed;
    if (!remainingPresentation.isNegative) {
      await Future<void>.delayed(remainingPresentation);
    }
    return stores;
  }

  Future<FinanceDataStore> _loadV2Store({
    required NotificationScheduler notificationScheduler,
  }) async {
    return FinanceDataBootstrapper().loadStore(
      notificationScheduler: notificationScheduler,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: trackmarkMoneyName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: FutureBuilder<AppStores>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('$trackmarkMoneyName startup failed: ${snapshot.error}');
            return StartupErrorView(error: snapshot.error.toString());
          }
          final stores = snapshot.data;
          if (stores == null) {
            return const StartupLoadingView();
          }
          return MoneyTallyApp(
            dataStore: stores.dataStore,
            authService: FirebaseAuthService(),
            recordRepository: FirestoreRecordRepository(),
          );
        },
      ),
    );
  }
}

class AppStores {
  const AppStores({required this.dataStore});

  final FinanceDataStore dataStore;
}

/// Brand palette used only by the public launch and sign-in surfaces. The
/// operational product palette intentionally remains unchanged.
abstract final class TrackmarkBrandPalette {
  static const deepGreen = Color(0xFF0F3F2D);
  static const forestGreen = Color(0xFF173F2D);
  static const ivory = Color(0xFFF7F5F2);
  static const warmWhite = Color(0xFFF7F5F2);
  static const gold = Color(0xFFCA9B4A);
  static const paleGold = Color(0xFFE5C98F);
  static const slate = Color(0xFF6B6F72);
}

/// Shared production TM monogram for the public brand surfaces.
class TrackmarkBrandMark extends StatelessWidget {
  const TrackmarkBrandMark({this.size = 48, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$trackmarkMoneyName monogram',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/branding/trackmark_tm_monogram.png',
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// Editorial wordmark layout from the approved Trackmark identity.
class TrackmarkBrandLockup extends StatelessWidget {
  const TrackmarkBrandLockup({
    this.bright = false,
    this.markSize = 60,
    this.wordmarkSize = 28,
    super.key,
  });

  final bool bright;
  final double markSize;
  final double wordmarkSize;

  @override
  Widget build(BuildContext context) {
    final primary = bright
        ? TrackmarkBrandPalette.warmWhite
        : TrackmarkBrandPalette.deepGreen;
    return Semantics(
      label: trackmarkMoneyName,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TrackmarkBrandMark(size: markSize),
          SizedBox(height: markSize * 0.16),
          Text(
            'TRACKMARK',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primary,
              fontSize: wordmarkSize,
              fontWeight: FontWeight.w700,
              letterSpacing: wordmarkSize * 0.115,
              height: 1,
            ),
          ),
          SizedBox(height: wordmarkSize * 0.17),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BrandRule(color: TrackmarkBrandPalette.gold),
              const SizedBox(width: 12),
              Text(
                'MONEY',
                style: TextStyle(
                  color: TrackmarkBrandPalette.gold,
                  fontSize: wordmarkSize * 0.52,
                  fontWeight: FontWeight.w600,
                  letterSpacing: wordmarkSize * 0.145,
                  height: 1,
                ),
              ),
              const SizedBox(width: 12),
              _BrandRule(color: TrackmarkBrandPalette.gold),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandRule extends StatelessWidget {
  const _BrandRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 48, height: 1, color: color.withValues(alpha: 0.9));
}

class StartupLoadingView extends StatelessWidget {
  const StartupLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final safeInsets = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: TrackmarkBrandPalette.deepGreen,
      // The native launch storyboard and this surface both use the raw screen
      // center. Keeping a single, explicitly full-width composition here
      // avoids SafeArea/padding geometry changing the brand's horizontal
      // position during the native-to-Flutter handoff.
      body: SizedBox.expand(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            32,
            safeInsets.top + 28,
            32,
            safeInsets.bottom + 28,
          ),
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 4),
                const TrackmarkBrandLockup(
                  bright: true,
                  markSize: 92,
                  wordmarkSize: 34,
                ),
                const Spacer(flex: 4),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: TrackmarkBrandPalette.gold,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Smart today. Secure tomorrow.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: TrackmarkBrandPalette.paleGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.15,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartupErrorView extends StatelessWidget {
  const StartupErrorView({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    AppIcon.error,
                    color: AppTheme.rose,
                    size: AppIconSize.brand,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '$trackmarkMoneyName could not start',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.rose,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
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

class MoneyTallyApp extends StatelessWidget {
  factory MoneyTallyApp({
    // Retained for legacy widget-test fixtures only. Production bootstrap does
    // not construct or provide a v1 store.
    FinanceStore? store,
    FinanceDataStore? dataStore,
    AuthService? authService,
    FinanceRemoteRepository? remoteRepository,
    FinanceRecordRepository? recordRepository,
    Key? key,
  }) {
    // Widget fixtures historically construct MoneyTallyApp directly. Keep
    // their deterministic in-memory seed, while production bootstrap always
    // passes an already-loaded v2 store and never constructs this snapshot.
    final fixtureStore = store ?? FinanceStore.seeded();
    final financeDataStore =
        dataStore ??
        FinanceDataStore(
          dataSet: const V1SnapshotMigrator().migrate(
            fixtureStore.snapshot().toJson(),
          ),
        );
    return MoneyTallyApp._(
      store: store,
      dataStore: financeDataStore,
      authService: authService ?? LocalOnlyAuthService(),
      remoteRepository: remoteRepository,
      recordRepository: recordRepository,
      key: key,
    );
  }

  const MoneyTallyApp._({
    this.store,
    required this.dataStore,
    required this.authService,
    this.remoteRepository,
    this.recordRepository,
    super.key,
  });

  final FinanceStore? store;
  final FinanceDataStore dataStore;
  final AuthService authService;
  final FinanceRemoteRepository? remoteRepository;
  final FinanceRecordRepository? recordRepository;

  @override
  Widget build(BuildContext context) {
    final app = FinanceDataStoreScope(
      store: dataStore,
      child: Builder(
        builder: (context) {
          final preferences = FinanceDataStoreScope.watch(context).preferences;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: trackmarkMoneyName,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeModeFor(preferences.appearanceMode),
            home: AuthGate(
              authService: authService,
              remoteRepository: remoteRepository,
              recordRepository: recordRepository,
            ),
          );
        },
      ),
    );
    // The scope remains available only for historical widget fixtures while
    // the old UI classes are compiled. Production never supplies a v1 store.
    final legacyStore = store;
    return legacyStore == null
        ? app
        : FinanceStoreScope(store: legacyStore, child: app);
  }
}
