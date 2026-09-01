import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/finance_data_set.dart';

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
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    return FinanceDataSet.fromJson(decoded);
  }

  Future<void> save(FinanceDataSet dataSet) async {
    final preferences = await SharedPreferences.getInstance();
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
    await preferences.setString(_restoreGenerationKey(userId), generation);
  }

  Future<void> clearAcknowledgedRestoreGeneration(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_restoreGenerationKey(userId));
  }
}
