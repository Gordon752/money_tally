import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/finance_data_set.dart';
import '../domain/user_preferences.dart';
import '../notifications/notification_scheduler.dart';
import '../persistence/finance_record_repository.dart';
import '../persistence/local_finance_data_set_repository.dart';
import '../persistence/scheduled_notification_state_repository.dart';
import '../store/finance_data_store.dart';
import 'v1_snapshot_migrator.dart';

typedef V1SnapshotJsonLoader = Future<Map<String, Object?>?> Function();

class FinanceDataBootstrapper {
  FinanceDataBootstrapper({
    this.localRepository = const LocalFinanceDataSetRepository(),
    V1SnapshotJsonLoader? v1SnapshotLoader,
    this.migrator = const V1SnapshotMigrator(),
  }) : v1SnapshotLoader =
           v1SnapshotLoader ?? const V1SnapshotLocalLoader().call;

  final LocalFinanceDataSetRepository localRepository;
  final V1SnapshotJsonLoader v1SnapshotLoader;
  final V1SnapshotMigrator migrator;
  var _didImportLegacyThisLaunch = false;

  Future<FinanceDataSet> loadDataSet() async {
    final current = await localRepository.load();
    if (current?.preferences.legacyV1MigrationCompleted == true) {
      return current!;
    }

    final legacy = await v1SnapshotLoader();
    _didImportLegacyThisLaunch = legacy != null;
    final migrated = legacy == null ? null : migrator.migrate(legacy);
    final resolved = current == null
        ? migrated ??
              const FinanceDataSet(
                accounts: [],
                categories: [],
                transactions: [],
                scheduledTransactions: [],
                budgets: [],
                preferences: UserPreferences(),
              )
        : migrated == null
        ? current
        : mergeLegacyDataSetIntoV2(incoming: migrated, current: current);
    final completed = resolved.copyWith(
      preferences: resolved.preferences.copyWith(
        legacyV1MigrationCompleted: true,
      ),
    );
    // The marker is only durable after the complete v2 data set is durable.
    // If saving is interrupted, the next launch repeats this ID-based import;
    // that operation cannot duplicate or overwrite v2 records.
    await localRepository.save(completed);
    return completed;
  }

  Future<FinanceDataStore> loadStore({
    FinanceRecordRepository? remoteRepository,
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler(),
    String? userId,
    String deviceId = 'local',
  }) async {
    final store = FinanceDataStore(
      dataSet: await loadDataSet(),
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      notificationScheduler: notificationScheduler,
      preferRemoteOnFirstSync: _didImportLegacyThisLaunch,
      userId: userId,
      deviceId: deviceId,
      notificationStateRepository:
          const SharedPreferencesScheduledNotificationStateRepository(),
    );
    await store.migrateLegacyGoalsToAccounts();
    return store;
  }
}

/// Imports a legacy snapshot exactly once without allowing its incomplete
/// records to replace records that already exist in v2. The legacy source is
/// only allowed to contribute IDs v2 does not yet know about.
FinanceDataSet mergeLegacyDataSetIntoV2({
  required FinanceDataSet incoming,
  required FinanceDataSet current,
}) {
  return current.copyWith(
    accounts: _addMissingById(incoming.accounts, current.accounts),
    categories: _addMissingById(incoming.categories, current.categories),
    transactions: _addMissingById(incoming.transactions, current.transactions),
    scheduledTransactions: _addMissingById(
      incoming.scheduledTransactions,
      current.scheduledTransactions,
    ),
    budgets: _addMissingById(incoming.budgets, current.budgets),
    goals: _addMissingById(incoming.goals, current.goals),
    goalContributions: _addMissingById(
      incoming.goalContributions,
      current.goalContributions,
    ),
    goalFundingEvents: _addMissingById(
      incoming.goalFundingEvents,
      current.goalFundingEvents,
    ),
  );
}

List<T> _addMissingById<T extends Object>(List<T> incoming, List<T> current) {
  final currentIds = {for (final item in current) _recordId(item)};
  return [
    ...current,
    for (final item in incoming)
      if (currentIds.add(_recordId(item))) item,
  ];
}

String _recordId(Object item) => switch (item) {
  final dynamic identifiable => identifiable.id as String,
};

class V1SnapshotLocalLoader {
  const V1SnapshotLocalLoader({
    this.storageKey = 'money_tally_finance_snapshot_v1',
  });

  final String storageKey;

  Future<Map<String, Object?>?> call() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null) return null;
    return (jsonDecode(raw) as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
}
