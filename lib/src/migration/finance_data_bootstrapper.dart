import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/finance_data_set.dart';
import '../domain/user_preferences.dart';
import '../persistence/finance_record_repository.dart';
import '../persistence/local_finance_data_set_repository.dart';
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

  Future<FinanceDataSet> loadDataSet() async {
    final current = await localRepository.load();
    if (current != null) return current;

    final legacy = await v1SnapshotLoader();
    if (legacy != null) {
      final migrated = migrator.migrate(legacy);
      await localRepository.save(migrated);
      return migrated;
    }

    return const FinanceDataSet(
      accounts: [],
      categories: [],
      transactions: [],
      scheduledTransactions: [],
      budgets: [],
      preferences: UserPreferences(),
    );
  }

  Future<FinanceDataStore> loadStore({
    FinanceRecordRepository? remoteRepository,
    String? userId,
    String deviceId = 'local',
  }) async {
    return FinanceDataStore(
      dataSet: await loadDataSet(),
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      userId: userId,
      deviceId: deviceId,
    );
  }
}

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
