import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../persistence/finance_record_repository.dart';
import '../store/finance_data_store.dart';

enum CloudSyncStatus { idle, syncing, synced, issue }

enum CloudSyncTrigger {
  unknown,
  initial,
  manual,
  foregroundCatchUp,
  background,
}

class CloudSyncDiagnostic {
  const CloudSyncDiagnostic({
    required this.completedAt,
    required this.trigger,
    required this.succeeded,
    required this.attemptCount,
    required this.metrics,
    this.errorDescription,
  });

  final DateTime completedAt;
  final CloudSyncTrigger trigger;
  final bool succeeded;
  final int attemptCount;
  final CloudSyncRepositoryMetrics metrics;
  final String? errorDescription;

  Map<String, Object?> toJson() => {
    'completedAt': completedAt.toUtc().toIso8601String(),
    'trigger': trigger.name,
    'succeeded': succeeded,
    'attemptCount': attemptCount,
    'metrics': metrics.toJson(),
    'errorDescription': errorDescription,
  };

  factory CloudSyncDiagnostic.fromJson(Map<String, Object?> json) {
    return CloudSyncDiagnostic(
      completedAt: DateTime.parse(json['completedAt']! as String).toUtc(),
      trigger: CloudSyncTrigger.values.firstWhere(
        (value) => value.name == json['trigger'],
        orElse: () => CloudSyncTrigger.unknown,
      ),
      succeeded: json['succeeded'] as bool? ?? false,
      attemptCount: json['attemptCount'] as int? ?? 1,
      metrics: CloudSyncRepositoryMetrics.fromJson(
        Map<String, Object?>.from(json['metrics']! as Map),
      ),
      errorDescription: json['errorDescription'] as String?,
    );
  }

  String get conciseDescription {
    final mode = switch (metrics.loadMode) {
      CloudSyncLoadMode.fullBootstrap => 'Full download',
      CloudSyncLoadMode.incremental => 'Incremental',
      CloudSyncLoadMode.unknown => 'Sync activity unavailable',
    };
    final triggerLabel = switch (trigger) {
      CloudSyncTrigger.initial => 'app launch',
      CloudSyncTrigger.manual => 'manual',
      CloudSyncTrigger.foregroundCatchUp => 'foreground',
      CloudSyncTrigger.background => 'background',
      CloudSyncTrigger.unknown => 'unknown trigger',
    };
    final readLabel = metrics.estimatedReads == 1 ? 'read' : 'reads';
    final writeLabel = metrics.estimatedWrites == 1 ? 'write' : 'writes';
    final counts =
        '~${metrics.estimatedReads} $readLabel · '
        '${metrics.estimatedWrites} $writeLabel';
    final retry = attemptCount > 1 ? ' · $attemptCount attempts' : '';
    final reason =
        metrics.loadMode == CloudSyncLoadMode.fullBootstrap &&
            metrics.fullBootstrapReason != null
        ? '\nReason: ${metrics.fullBootstrapReason}'
        : '';
    final collectionEntries = metrics.uploadedByCollection.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        return byCount != 0 ? byCount : left.key.compareTo(right.key);
      });
    final writeBreakdown = collectionEntries.isEmpty
        ? ''
        : '\nWrites: ${collectionEntries.map((entry) => '${entry.key} ${entry.value}').join(' · ')}';
    final changedFieldEntries =
        metrics.changedFieldsByCollection.entries
            .where((entry) => entry.value.isNotEmpty)
            .toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    final fieldBreakdown = changedFieldEntries.isEmpty
        ? ''
        : '\nFields: ${changedFieldEntries.map((entry) {
            final fields = entry.value.entries.toList()..sort((left, right) {
              final byCount = right.value.compareTo(left.value);
              return byCount != 0 ? byCount : left.key.compareTo(right.key);
            });
            return '${entry.key} [${fields.map((field) => '${field.key} ${field.value}').join(', ')}]';
          }).join(' · ')}';
    return '$mode · $counts · $triggerLabel$retry$reason$writeBreakdown$fieldBreakdown';
  }
}

class SyncExecutionStateStore {
  const SyncExecutionStateStore();

  static const _lastSuccessPrefix = 'trackmark_last_successful_sync_';
  static const _lastOutcomePrefix = 'trackmark_last_sync_succeeded_';
  static const _leasePrefix = 'trackmark_sync_lease_';
  static const _lastErrorPrefix = 'trackmark_last_sync_error_';
  static const _lastDiagnosticPrefix = 'trackmark_last_sync_diagnostic_';

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
    await preferences.remove('$_lastErrorPrefix$userId');
  }

  Future<bool?> loadLastSyncSucceeded(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getBool('$_lastOutcomePrefix$userId');
  }

  Future<String?> loadLastSyncError(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString('$_lastErrorPrefix$userId');
  }

  Future<void> saveLastSyncFailed(String userId, String description) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_lastOutcomePrefix$userId', false);
    await preferences.setString('$_lastErrorPrefix$userId', description);
  }

  Future<CloudSyncDiagnostic?> loadLastSyncDiagnostic(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final encoded = preferences.getString('$_lastDiagnosticPrefix$userId');
    if (encoded == null) return null;
    try {
      return CloudSyncDiagnostic.fromJson(
        Map<String, Object?>.from(jsonDecode(encoded) as Map),
      );
    } on Object catch (error) {
      debugPrint('Discarding unreadable sync diagnostic: $error');
      await preferences.remove('$_lastDiagnosticPrefix$userId');
      return null;
    }
  }

  Future<void> saveLastSyncDiagnostic(
    String userId,
    CloudSyncDiagnostic diagnostic,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_lastDiagnosticPrefix$userId',
      jsonEncode(diagnostic.toJson()),
    );
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

  Future<void> clearForDeletedUser(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove('$_lastSuccessPrefix$userId'),
      preferences.remove('$_lastOutcomePrefix$userId'),
      preferences.remove('$_leasePrefix$userId'),
      preferences.remove('$_lastErrorPrefix$userId'),
      preferences.remove('$_lastDiagnosticPrefix$userId'),
    ]);
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
  String? _lastErrorDescription;
  CloudSyncDiagnostic? _lastDiagnostic;
  Future<bool>? _activeSync;

  CloudSyncStatus get status => _status;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  bool get isSyncing => _activeSync != null;
  String? get lastErrorDescription => _lastErrorDescription;
  CloudSyncDiagnostic? get lastDiagnostic => _lastDiagnostic;

  Future<void> loadStateForUser(String userId, {bool force = false}) async {
    if (!force && _currentUserId == userId && _lastSuccessfulSyncAt != null) {
      return;
    }
    _currentUserId = userId;
    _status = CloudSyncStatus.idle;
    _lastSuccessfulSyncAt = await executionStateStore.loadLastSuccessfulSync(
      userId,
    );
    _lastErrorDescription = await executionStateStore.loadLastSyncError(userId);
    _lastDiagnostic = await executionStateStore.loadLastSyncDiagnostic(userId);
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
    _lastErrorDescription = null;
    _lastDiagnostic = null;
    _status = CloudSyncStatus.idle;
    notifyListeners();
  }

  Future<bool> synchronize({
    required String userId,
    required FinanceDataStore dataStore,
    bool retryAfterTransientFailure = false,
    CloudSyncTrigger trigger = CloudSyncTrigger.unknown,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final active = _activeSync;
    if (active != null) return active;
    final operation = _run(
      userId: userId,
      dataStore: dataStore,
      retryAfterTransientFailure: retryAfterTransientFailure,
      trigger: trigger,
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
    required CloudSyncTrigger trigger,
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
    final metricsProvider = recordRepository is CloudSyncMetricsProvider
        ? recordRepository as CloudSyncMetricsProvider
        : null;
    metricsProvider?.beginSyncMetrics();
    var attemptCount = 0;
    try {
      try {
        attemptCount += 1;
        await _attach(userId, dataStore, timeout);
      } on Object {
        if (!retryAfterTransientFailure) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 900));
        attemptCount += 1;
        await _attach(userId, dataStore, timeout);
      }

      final completedAt = now();
      _lastSuccessfulSyncAt = completedAt;
      _lastErrorDescription = null;
      await executionStateStore.saveLastSuccessfulSync(userId, completedAt);
      _lastDiagnostic = CloudSyncDiagnostic(
        completedAt: completedAt,
        trigger: trigger,
        succeeded: true,
        attemptCount: attemptCount,
        metrics:
            metricsProvider?.currentSyncMetrics ??
            const CloudSyncRepositoryMetrics(),
      );
      await executionStateStore.saveLastSyncDiagnostic(
        userId,
        _lastDiagnostic!,
      );
      _setStatus(CloudSyncStatus.synced);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Cloud record sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _lastErrorDescription = _describeSyncError(error);
      await executionStateStore.saveLastSyncFailed(
        userId,
        _lastErrorDescription!,
      );
      _lastDiagnostic = CloudSyncDiagnostic(
        completedAt: now(),
        trigger: trigger,
        succeeded: false,
        attemptCount: attemptCount,
        metrics:
            metricsProvider?.currentSyncMetrics ??
            const CloudSyncRepositoryMetrics(),
        errorDescription: _lastErrorDescription,
      );
      await executionStateStore.saveLastSyncDiagnostic(
        userId,
        _lastDiagnostic!,
      );
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

  String _describeSyncError(Object error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'resource-exhausted' =>
          'Firestore quota exhausted (resource-exhausted)',
        'unavailable' => 'Cloud service temporarily unavailable (unavailable)',
        'permission-denied' => 'Cloud access was denied (permission-denied)',
        'deadline-exceeded' => 'Cloud sync timed out (deadline-exceeded)',
        _ => '${error.message ?? 'Cloud sync failed'} (${error.code})',
      };
    }
    if (error is TimeoutException) {
      return 'Cloud sync timed out';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}
