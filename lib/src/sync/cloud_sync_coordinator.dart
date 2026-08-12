import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../persistence/finance_record_repository.dart';
import '../store/finance_data_store.dart';

enum CloudSyncStatus { idle, syncing, synced, issue }

class SyncExecutionStateStore {
  const SyncExecutionStateStore();

  static const _lastSuccessPrefix = 'trackmark_last_successful_sync_';
  static const _lastOutcomePrefix = 'trackmark_last_sync_succeeded_';
  static const _leasePrefix = 'trackmark_sync_lease_';

  Future<DateTime?> loadLastSuccessfulSync(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final value = preferences.getString('$_lastSuccessPrefix$userId');
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> saveLastSuccessfulSync(String userId, DateTime value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_lastSuccessPrefix$userId',
      value.toUtc().toIso8601String(),
    );
    await preferences.setBool('$_lastOutcomePrefix$userId', true);
  }

  Future<bool?> loadLastSyncSucceeded(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getBool('$_lastOutcomePrefix$userId');
  }

  Future<void> saveLastSyncFailed(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_lastOutcomePrefix$userId', false);
  }

  Future<bool> tryAcquireLease(
    String userId, {
    required DateTime now,
    Duration duration = const Duration(minutes: 2),
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final key = '$_leasePrefix$userId';
    final existing = DateTime.tryParse(preferences.getString(key) ?? '');
    if (existing != null && existing.isAfter(now.toUtc())) return false;
    await preferences.setString(
      key,
      now.toUtc().add(duration).toIso8601String(),
    );
    return true;
  }

  Future<void> releaseLease(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_leasePrefix$userId');
  }
}

/// The single entry point for foreground, manual, and background cloud sync.
/// FinanceDataStore remains responsible for generation authority and merging.
class CloudSyncCoordinator extends ChangeNotifier {
  CloudSyncCoordinator({
    required this.recordRepository,
    this.executionStateStore = const SyncExecutionStateStore(),
    this.now = DateTime.now,
  });

  final FinanceRecordRepository recordRepository;
  final SyncExecutionStateStore executionStateStore;
  final DateTime Function() now;

  CloudSyncStatus _status = CloudSyncStatus.idle;
  DateTime? _lastSuccessfulSyncAt;
  String? _currentUserId;
  Future<bool>? _activeSync;

  CloudSyncStatus get status => _status;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  bool get isSyncing => _activeSync != null;

  Future<void> loadStateForUser(String userId, {bool force = false}) async {
    if (!force && _currentUserId == userId && _lastSuccessfulSyncAt != null) {
      return;
    }
    _currentUserId = userId;
    _status = CloudSyncStatus.idle;
    _lastSuccessfulSyncAt = await executionStateStore.loadLastSuccessfulSync(
      userId,
    );
    final succeeded = await executionStateStore.loadLastSyncSucceeded(userId);
    if (succeeded == false) {
      _status = CloudSyncStatus.issue;
    } else if (_lastSuccessfulSyncAt != null) {
      _status = CloudSyncStatus.synced;
    }
    notifyListeners();
  }

  void reset() {
    _currentUserId = null;
    _lastSuccessfulSyncAt = null;
    _status = CloudSyncStatus.idle;
    notifyListeners();
  }

  Future<bool> synchronize({
    required String userId,
    required FinanceDataStore dataStore,
    bool retryAfterTransientFailure = false,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final active = _activeSync;
    if (active != null) return active;
    final operation = _run(
      userId: userId,
      dataStore: dataStore,
      retryAfterTransientFailure: retryAfterTransientFailure,
      timeout: timeout,
    );
    _activeSync = operation;
    unawaited(
      operation.then(
        (_) {
          if (identical(_activeSync, operation)) _activeSync = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_activeSync, operation)) _activeSync = null;
        },
      ),
    );
    return operation;
  }

  Future<bool> _run({
    required String userId,
    required FinanceDataStore dataStore,
    required bool retryAfterTransientFailure,
    required Duration timeout,
  }) async {
    final acquired = await executionStateStore.tryAcquireLease(
      userId,
      now: now(),
      duration: timeout + const Duration(seconds: 30),
    );
    // Another foreground/background entry point already owns this sync. That
    // is a successful no-op, not a failure that should trigger another task.
    if (!acquired) return true;

    _currentUserId = userId;
    _setStatus(CloudSyncStatus.syncing);
    try {
      try {
        await _attach(userId, dataStore, timeout);
      } on Object {
        if (!retryAfterTransientFailure) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await _attach(userId, dataStore, timeout);
      }

      final completedAt = now();
      _lastSuccessfulSyncAt = completedAt;
      await executionStateStore.saveLastSuccessfulSync(userId, completedAt);
      _setStatus(CloudSyncStatus.synced);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Cloud record sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      await executionStateStore.saveLastSyncFailed(userId);
      _setStatus(CloudSyncStatus.issue);
      return false;
    } finally {
      try {
        await executionStateStore.releaseLease(userId);
      } on Object catch (error) {
        debugPrint('Could not release the cloud-sync lease: $error');
      }
    }
  }

  Future<void> _attach(
    String userId,
    FinanceDataStore dataStore,
    Duration timeout,
  ) {
    return dataStore
        .attachRemoteSync(remoteRepository: recordRepository, userId: userId)
        .timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'Cloud sync did not finish within ${timeout.inSeconds} seconds.',
          ),
        );
  }

  void _setStatus(CloudSyncStatus value) {
    _status = value;
    notifyListeners();
  }
}
