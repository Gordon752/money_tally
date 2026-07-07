import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'firebase_options.dart';
import 'src/design/design_tokens.dart';
import 'src/design/money_format.dart';
import 'src/design/widgets/budget_progress_bar.dart';
import 'src/design/widgets/account_card.dart';
import 'src/design/widgets/floating_action_button.dart';
import 'src/design/widgets/floating_action_menu.dart';
import 'src/design/widgets/scheduled_transaction_row.dart';
import 'src/design/widgets/section_header.dart';
import 'src/design/widgets/transaction_row.dart';
import 'src/domain/budget.dart';
import 'src/domain/account.dart' as v2_account;
import 'src/domain/category.dart' as v2_category;
import 'src/domain/money.dart';
import 'src/domain/scheduled_transaction.dart' as v2_scheduled;
import 'src/domain/sync_metadata.dart' as v2_sync;
import 'src/domain/transaction.dart';
import 'src/domain/user_preferences.dart';
import 'src/migration/v1_snapshot_migrator.dart';
import 'src/persistence/backup_codec.dart';
import 'src/persistence/finance_record_repository.dart';
import 'src/persistence/firestore_record_repository.dart';
import 'src/persistence/local_finance_data_set_repository.dart';
import 'src/store/finance_data_store.dart';
import 'src/store/finance_data_store_scope.dart';

part 'src/app_theme.dart';
part 'src/auth_service.dart';
part 'src/domain.dart';
part 'src/finance_home.dart';
part 'src/finance_store.dart';
part 'src/firestore_finance_repository.dart';
part 'src/local_finance_repository.dart';

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
    final legacyStore = await FinanceStore.load();
    final dataStore = await _loadV2StoreFromLegacy(legacyStore);
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
    FinanceStore legacyStore,
  ) async {
    final localRepository = const LocalFinanceDataSetRepository();
    final dataSet = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    await localRepository.save(dataSet);
    return FinanceDataStore(dataSet: dataSet, localRepository: localRepository);
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
        final dataSet = migrated.copyWith(
          accounts: mergeAccountsPreferCurrent(
            migrated: migrated.accounts,
            current: dataStore.accounts,
          ),
          categories: mergeCategoriesPreferCurrent(
            migrated: migrated.categories,
            current: dataStore.categories,
          ),
          transactions: mergeV2OnlyTransactions(
            migrated: migrated.transactions,
            current: dataStore.transactions,
          ),
          scheduledTransactions: mergeV2OnlyScheduledTransactions(
            migrated: migrated.scheduledTransactions,
            current: dataStore.scheduledTransactions,
          ),
          preferences: dataStore.preferences,
        );
        await dataStore.replaceDataSet(dataSet, persistLocal: false);
      } while (_queuedRefresh);
    } finally {
      _isRefreshing = false;
    }
  }
}

List<TransactionRecord> mergeV2OnlyTransactions({
  required List<TransactionRecord> migrated,
  required List<TransactionRecord> current,
}) {
  final currentById = {
    for (final transaction in current) transaction.id: transaction,
  };
  final migratedIds = migrated.map((transaction) => transaction.id).toSet();
  return [
    for (final transaction in migrated)
      if (currentById[transaction.id] case final current?)
        current.sync.updatedAt.isAfter(transaction.sync.updatedAt)
            ? current
            : transaction
      else
        transaction,
    for (final transaction in current)
      if (!migratedIds.contains(transaction.id)) transaction,
  ];
}

List<v2_account.AccountRecord> mergeAccountsPreferCurrent({
  required List<v2_account.AccountRecord> migrated,
  required List<v2_account.AccountRecord> current,
}) {
  final currentById = {for (final account in current) account.id: account};
  final migratedIds = migrated.map((account) => account.id).toSet();
  return [
    for (final account in migrated)
      if (currentById[account.id] case final current?)
        v2_account.AccountRecord(
          id: account.id,
          name: account.name,
          type: account.type,
          openingBalanceMinor: account.openingBalanceMinor,
          isArchived: account.isArchived,
          includeInGroupBalance: current.includeInGroupBalance,
          includeInNetWorth: current.includeInNetWorth,
          sortOrder: current.sortOrder,
          sync: account.sync,
        )
      else
        account,
    for (final account in current)
      if (!migratedIds.contains(account.id)) account,
  ];
}

List<v2_category.CategoryRecord> mergeCategoriesPreferCurrent({
  required List<v2_category.CategoryRecord> migrated,
  required List<v2_category.CategoryRecord> current,
}) {
  final currentById = {for (final category in current) category.id: category};
  final migratedIds = migrated.map((category) => category.id).toSet();
  return [
    for (final category in migrated) currentById[category.id] ?? category,
    for (final category in current)
      if (!migratedIds.contains(category.id)) category,
  ];
}

List<v2_scheduled.ScheduledTransactionRecord> mergeV2OnlyScheduledTransactions({
  required List<v2_scheduled.ScheduledTransactionRecord> migrated,
  required List<v2_scheduled.ScheduledTransactionRecord> current,
}) {
  final migratedIds = migrated.map((scheduled) => scheduled.id).toSet();
  return [
    ...migrated,
    for (final scheduled in current)
      if (!migratedIds.contains(scheduled.id)) scheduled,
  ];
}

class StartupLoadingView extends StatelessWidget {
  const StartupLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              color: AppTheme.accent,
              size: 48,
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
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppTheme.rose,
                    size: 48,
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
