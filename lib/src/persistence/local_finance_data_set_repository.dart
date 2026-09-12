import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/finance_data_set.dart';
import '../sync/sync_attempt_authority.dart';
import 'local_finance_data_structure.dart';

class UnreadableLocalFinanceData implements Exception {
  const UnreadableLocalFinanceData({
    required this.storageKey,
    required this.original,
  });
  final String storageKey;
  final String original;
  @override
  String toString() =>
      'The saved local finance data could not be read. It has not been reset or replaced.';
}

class LocalFinanceDataSetRepository {
  const LocalFinanceDataSetRepository({
    this.storageKey = 'money_tally_finance_data_set_v2',
  });

  final String storageKey;

  String _restoreGenerationKey(String userId) =>
      '${storageKey}_restore_generation_$userId';

  Future<FinanceDataSet?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      validateLocalFinanceDataStructure(decoded);
      return FinanceDataSet.fromJson(decoded);
    } on Object {
      throw UnreadableLocalFinanceData(storageKey: storageKey, original: raw);
    }
  }

  Future<String?> readRaw() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(storageKey);
  }

  /// Final recovery commit only. The existing restore operation has already
  /// finished against staging, and exact raw/source safety copies exist.
  Future<void> installRecoveredDataSet(
    FinanceDataSet dataSet, {
    required String expectedOriginal,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    if (preferences.getString(storageKey) != expectedOriginal) {
      throw StateError(
        'Local data changed during recovery. Retry startup before restoring.',
      );
    }
    final encoded = jsonEncode(dataSet.toJson());
    try {
      if (!await preferences.setString(storageKey, encoded)) {
        throw StateError('Recovered local data could not be saved.');
      }
    } on Object {
      // SharedPreferences updates its memory cache before reporting a failed
      // platform write. Restore that cache/value too; the raw file copy remains
      // available even if the storage device cannot accept the rollback.
      await preferences.setString(storageKey, expectedOriginal);
      rethrow;
    }
  }

  Future<void> save(FinanceDataSet dataSet) async {
    final preferences = await SharedPreferences.getInstance();
    SyncAttemptAuthority.checkCurrent();
    await preferences.setString(storageKey, jsonEncode(dataSet.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }

  Future<String?> loadAcknowledgedRestoreGeneration(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_restoreGenerationKey(userId));
  }

  Future<void> saveAcknowledgedRestoreGeneration(
    String userId,
    String generation,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    SyncAttemptAuthority.checkCurrent();
    await preferences.setString(_restoreGenerationKey(userId), generation);
  }

  Future<void> clearAcknowledgedRestoreGeneration(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_restoreGenerationKey(userId));
  }
}
