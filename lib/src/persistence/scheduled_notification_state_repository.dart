import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceScheduledNotificationState {
  const DeviceScheduledNotificationState({
    required this.notificationIds,
    this.lastScheduledAt,
  });

  final List<int> notificationIds;
  final DateTime? lastScheduledAt;

  Map<String, Object?> toJson() => {
    'notificationIds': notificationIds,
    'lastScheduledAt': lastScheduledAt?.toUtc().toIso8601String(),
  };

  factory DeviceScheduledNotificationState.fromJson(
    Map<String, Object?> json,
  ) => DeviceScheduledNotificationState(
    notificationIds: (json['notificationIds'] as List<Object?>? ?? const [])
        .whereType<int>()
        .toList(growable: false),
    lastScheduledAt: json['lastScheduledAt'] == null
        ? null
        : DateTime.tryParse(json['lastScheduledAt'] as String),
  );
}

abstract interface class ScheduledNotificationStateRepository {
  Future<DeviceScheduledNotificationState?> load(String scheduleId);

  Future<void> save(String scheduleId, DeviceScheduledNotificationState state);

  Future<void> remove(String scheduleId);
}

class InMemoryScheduledNotificationStateRepository
    implements ScheduledNotificationStateRepository {
  final Map<String, DeviceScheduledNotificationState> _states = {};

  @override
  Future<DeviceScheduledNotificationState?> load(String scheduleId) async =>
      _states[scheduleId];

  @override
  Future<void> save(
    String scheduleId,
    DeviceScheduledNotificationState state,
  ) async {
    _states[scheduleId] = state;
  }

  @override
  Future<void> remove(String scheduleId) async {
    _states.remove(scheduleId);
  }
}

class SharedPreferencesScheduledNotificationStateRepository
    implements ScheduledNotificationStateRepository {
  const SharedPreferencesScheduledNotificationStateRepository();

  static const _key = 'trackmark.deviceScheduledNotificationState.v1';

  Future<Map<String, Object?>> _loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : <String, Object?>{};
  }

  Future<void> _saveAll(Map<String, Object?> states) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(states));
  }

  @override
  Future<DeviceScheduledNotificationState?> load(String scheduleId) async {
    final states = await _loadAll();
    final raw = states[scheduleId];
    return raw is Map
        ? DeviceScheduledNotificationState.fromJson(
            Map<String, Object?>.from(raw),
          )
        : null;
  }

  @override
  Future<void> save(
    String scheduleId,
    DeviceScheduledNotificationState state,
  ) async {
    final states = await _loadAll();
    states[scheduleId] = state.toJson();
    await _saveAll(states);
  }

  @override
  Future<void> remove(String scheduleId) async {
    final states = await _loadAll();
    if (states.remove(scheduleId) != null) await _saveAll(states);
  }
}
