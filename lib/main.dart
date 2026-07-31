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
import 'src/design/category_icon_catalog.dart';
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
import 'src/design/widgets/scheduled_transaction_row.dart';
import 'src/design/widgets/transaction_row.dart';
import 'src/budgets/budget_calculator.dart';
import 'src/domain/budget.dart';
import 'src/domain/account.dart' as v2_account;
import 'src/domain/category.dart' as v2_category;
import 'src/domain/finance_data_set.dart';
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
import 'src/management/management_ledger_index.dart';
import 'src/ledger/ledger_projection.dart';
import 'src/notifications/local_notification_scheduler.dart';
import 'src/notifications/notification_scheduler.dart';
import 'src/persistence/backup_codec.dart';
import 'src/persistence/finance_record_repository.dart';
import 'src/persistence/firestore_record_repository.dart';
import 'src/persistence/local_finance_data_set_repository.dart';
import 'src/reporting/report_calculator.dart';
import 'src/store/finance_data_store.dart';
import 'src/store/finance_data_store_scope.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  late final Future<AppStores> _startup = _load();
  AppStores? _stores;

  Future<AppStores> _load() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
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
    final legacyStore = await FinanceStore.load();
    final dataStore = await _loadV2StoreFromLegacy(
      legacyStore,
      notificationScheduler: notificationScheduler,
    );
    try {
      await dataStore.refreshScheduledNotifications();
    } catch (error, stackTrace) {
      debugPrint('Scheduled notification refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    final mirror = LegacyV2StoreMirror(
      legacyStore: legacyStore,
      dataStore: dataStore,
    )..start();
    final stores = AppStores(
      legacyStore: legacyStore,
      dataStore: dataStore,
      mirror: mirror,
    );
    _stores = stores;
    return stores;
  }

  @override
  void dispose() {
    _stores?.mirror.dispose();
    super.dispose();
  }

  Future<FinanceDataStore> _loadV2StoreFromLegacy(
    FinanceStore legacyStore, {
    required NotificationScheduler notificationScheduler,
  }) async {
    final localRepository = const LocalFinanceDataSetRepository();
    final localDataSet = await localRepository.load();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataSet = localDataSet == null
        ? migrated
        : mergeDataSetsPreferCurrent(incoming: migrated, current: localDataSet);
    await localRepository.save(dataSet);
    final store = FinanceDataStore(
      dataSet: dataSet,
      localRepository: localRepository,
      notificationScheduler: notificationScheduler,
    );
    await store.migrateLegacyGoalsToAccounts();
    return store;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Money Tally',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: FutureBuilder<AppStores>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('Money Tally startup failed: ${snapshot.error}');
            return StartupErrorView(error: snapshot.error.toString());
          }
          final stores = snapshot.data;
          if (stores == null) {
            return const StartupLoadingView();
          }
          return MoneyTallyApp(
            store: stores.legacyStore,
            dataStore: stores.dataStore,
            authService: FirebaseAuthService(),
            remoteRepository: FirestoreFinanceRepository(),
            recordRepository: FirestoreRecordRepository(),
          );
        },
      ),
    );
  }
}

class AppStores {
  const AppStores({
    required this.legacyStore,
    required this.dataStore,
    required this.mirror,
  });

  final FinanceStore legacyStore;
  final FinanceDataStore dataStore;
  final LegacyV2StoreMirror mirror;
}

class LegacyV2StoreMirror {
  LegacyV2StoreMirror({required this.legacyStore, required this.dataStore});

  final FinanceStore legacyStore;
  final FinanceDataStore dataStore;
  var _isRefreshing = false;
  var _queuedRefresh = false;

  void start() {
    legacyStore.addListener(_queueRefresh);
  }

  void dispose() {
    legacyStore.removeListener(_queueRefresh);
  }

  void _queueRefresh() {
    if (dataStore.userId != null) return;
    if (_isRefreshing) {
      _queuedRefresh = true;
      return;
    }
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    _isRefreshing = true;
    try {
      do {
        _queuedRefresh = false;
        final migrated = const V1SnapshotMigrator().migrate(
          legacyStore.snapshot().toJson(),
        );
        final dataSet = mergeDataSetsPreferCurrent(
          incoming: migrated,
          current: dataStore.dataSet,
        );
        // Persist the tombstone-preserving merge. Legacy code must never write
        // a raw migrated snapshot directly over the v2 data set.
        await dataStore.replaceDataSet(dataSet);
      } while (_queuedRefresh);
    } finally {
      _isRefreshing = false;
    }
  }
}

FinanceDataSet mergeDataSetsPreferCurrent({
  required FinanceDataSet incoming,
  required FinanceDataSet current,
}) {
  return incoming.copyWith(
    accounts: mergeAccountsPreferCurrent(
      incoming: incoming.accounts,
      current: current.accounts,
    ),
    categories: mergeCategoriesPreferCurrent(
      incoming: incoming.categories,
      current: current.categories,
    ),
    transactions: mergeTransactionsPreferCurrent(
      incoming: incoming.transactions,
      current: current.transactions,
    ),
    scheduledTransactions: mergeScheduledTransactionsPreferCurrent(
      incoming: incoming.scheduledTransactions,
      current: current.scheduledTransactions,
    ),
    budgets: mergeBudgetsPreferCurrent(
      incoming: incoming.budgets,
      current: current.budgets,
    ),
    goals: current.goals,
    goalContributions: current.goalContributions,
    goalFundingEvents: current.goalFundingEvents,
    preferences: current.preferences,
  );
}

T _preferCurrentRecord<T>({
  required T incoming,
  required T current,
  required v2_sync.SyncMetadata Function(T item) syncOf,
}) {
  final currentSync = syncOf(current);
  final incomingSync = syncOf(incoming);
  if (currentSync.isDeleted) return current;
  if (incomingSync.isDeleted) return incoming;
  return currentSync.updatedAt.isAfter(incomingSync.updatedAt) ||
          currentSync.updatedAt.isAtSameMomentAs(incomingSync.updatedAt)
      ? current
      : incoming;
}

List<TransactionRecord> mergeV2OnlyTransactions({
  required List<TransactionRecord> migrated,
  required List<TransactionRecord> current,
}) {
  return mergeTransactionsPreferCurrent(incoming: migrated, current: current);
}

List<TransactionRecord> mergeTransactionsPreferCurrent({
  required List<TransactionRecord> incoming,
  required List<TransactionRecord> current,
}) {
  final currentById = {
    for (final transaction in current) transaction.id: transaction,
  };
  final incomingIds = incoming.map((transaction) => transaction.id).toSet();
  return [
    for (final transaction in incoming)
      if (currentById[transaction.id] case final currentTransaction?)
        _preferCurrentRecord(
          incoming: transaction,
          current: currentTransaction,
          syncOf: (item) => item.sync,
        )
      else
        transaction,
    for (final transaction in current)
      if (!incomingIds.contains(transaction.id)) transaction,
  ];
}

List<v2_account.AccountRecord> mergeAccountsPreferCurrent({
  required List<v2_account.AccountRecord> incoming,
  required List<v2_account.AccountRecord> current,
}) {
  final currentById = {for (final account in current) account.id: account};
  final incomingIds = incoming.map((account) => account.id).toSet();
  return [
    for (final account in incoming)
      if (currentById[account.id] case final currentAccount?)
        _preferCurrentRecord(
          incoming: account,
          current: currentAccount,
          syncOf: (item) => item.sync,
        )
      else
        account,
    for (final account in current)
      if (!incomingIds.contains(account.id)) account,
  ];
}

List<v2_category.CategoryRecord> mergeCategoriesPreferCurrent({
  required List<v2_category.CategoryRecord> incoming,
  required List<v2_category.CategoryRecord> current,
}) {
  final currentById = {for (final category in current) category.id: category};
  final incomingIds = incoming.map((category) => category.id).toSet();
  return [
    for (final category in incoming)
      if (currentById[category.id] case final currentCategory?)
        _preferCurrentRecord(
          incoming: category,
          current: currentCategory,
          syncOf: (item) => item.sync,
        )
      else
        category,
    for (final category in current)
      if (!incomingIds.contains(category.id)) category,
  ];
}

List<v2_scheduled.ScheduledTransactionRecord> mergeV2OnlyScheduledTransactions({
  required List<v2_scheduled.ScheduledTransactionRecord> migrated,
  required List<v2_scheduled.ScheduledTransactionRecord> current,
}) {
  return mergeScheduledTransactionsPreferCurrent(
    incoming: migrated,
    current: current,
  );
}

List<v2_scheduled.ScheduledTransactionRecord>
mergeScheduledTransactionsPreferCurrent({
  required List<v2_scheduled.ScheduledTransactionRecord> incoming,
  required List<v2_scheduled.ScheduledTransactionRecord> current,
}) {
  final currentById = {for (final item in current) item.id: item};
  final incomingIds = incoming.map((scheduled) => scheduled.id).toSet();
  return [
    for (final scheduled in incoming)
      if (currentById[scheduled.id] case final currentScheduled?)
        _preferCurrentRecord(
          incoming: scheduled,
          current: currentScheduled,
          syncOf: (item) => item.sync,
        )
      else
        scheduled,
    for (final scheduled in current)
      if (!incomingIds.contains(scheduled.id)) scheduled,
  ];
}

List<BudgetRecord> mergeBudgetsPreferCurrent({
  required List<BudgetRecord> incoming,
  required List<BudgetRecord> current,
}) {
  final currentById = {for (final budget in current) budget.id: budget};
  final incomingIds = incoming.map((budget) => budget.id).toSet();
  return [
    for (final budget in incoming)
      if (currentById[budget.id] case final currentBudget?)
        _preferCurrentRecord(
          incoming: budget,
          current: currentBudget,
          syncOf: (item) => item.sync,
        )
      else
        budget,
    for (final budget in current)
      if (!incomingIds.contains(budget.id)) budget,
  ];
}

class StartupLoadingView extends StatelessWidget {
  const StartupLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcon.wallet,
              color: AppTheme.accent,
              size: AppIconSize.brand,
            ),
            SizedBox(height: 16),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Opening Money Tally',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
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
                    'Money Tally could not start',
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
    FinanceStore? store,
    FinanceDataStore? dataStore,
    AuthService? authService,
    FinanceRemoteRepository? remoteRepository,
    FinanceRecordRepository? recordRepository,
    Key? key,
  }) {
    final legacyStore = store ?? FinanceStore.seeded();
    final financeDataStore =
        dataStore ??
        FinanceDataStore(
          dataSet: const V1SnapshotMigrator().migrate(
            legacyStore.snapshot().toJson(),
          ),
        );
    return MoneyTallyApp._(
      store: legacyStore,
      dataStore: financeDataStore,
      authService: authService ?? LocalOnlyAuthService(),
      remoteRepository: remoteRepository,
      recordRepository: recordRepository,
      key: key,
    );
  }

  const MoneyTallyApp._({
    required this.store,
    required this.dataStore,
    required this.authService,
    this.remoteRepository,
    this.recordRepository,
    super.key,
  });

  final FinanceStore store;
  final FinanceDataStore dataStore;
  final AuthService authService;
  final FinanceRemoteRepository? remoteRepository;
  final FinanceRecordRepository? recordRepository;

  @override
  Widget build(BuildContext context) {
    return FinanceStoreScope(
      store: store,
      child: FinanceDataStoreScope(
        store: dataStore,
        child: Builder(
          builder: (context) {
            final preferences = FinanceDataStoreScope.watch(
              context,
            ).preferences;
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Money Tally',
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
      ),
    );
  }
}
