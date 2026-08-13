import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/finance_data_set.dart';
import '../domain/user_preferences.dart';
import '../export/export_file_service.dart';
import 'backup_codec.dart';

class AutomaticBackupStatus {
  const AutomaticBackupStatus({
    this.lastSuccessfulAt,
    this.lastFailureAt,
    this.lastFailureMessage,
    this.latestSafetyBackupAt,
    this.latestSafetyBackupVersion,
  });

  final DateTime? lastSuccessfulAt;
  final DateTime? lastFailureAt;
  final String? lastFailureMessage;
  final DateTime? latestSafetyBackupAt;
  final String? latestSafetyBackupVersion;
}

class AutomaticBackupStateStore {
  const AutomaticBackupStateStore();

  static const _lastSuccessKey = 'trackmark_automatic_backup_last_success';
  static const _lastFailureKey = 'trackmark_automatic_backup_last_failure';
  static const _lastFailureMessageKey =
      'trackmark_automatic_backup_last_failure_message';
  static const _lastLaunchedVersionKey =
      'trackmark_last_successful_app_version_build';
  static const _pendingUpdateVersionKey =
      'trackmark_pending_update_version_build';
  static const _pendingUpdateBackupPathKey =
      'trackmark_pending_update_backup_path';
  static const _latestSafetyAtKey = 'trackmark_latest_safety_backup_at';
  static const _latestSafetyVersionKey =
      'trackmark_latest_safety_backup_version';

  Future<AutomaticBackupStatus> loadStatus() async {
    final storage = await SharedPreferences.getInstance();
    return AutomaticBackupStatus(
      lastSuccessfulAt: _date(storage.getString(_lastSuccessKey)),
      lastFailureAt: _date(storage.getString(_lastFailureKey)),
      lastFailureMessage: storage.getString(_lastFailureMessageKey),
      latestSafetyBackupAt: _date(storage.getString(_latestSafetyAtKey)),
      latestSafetyBackupVersion: storage.getString(_latestSafetyVersionKey),
    );
  }

  Future<void> recordAutomaticSuccess(DateTime at) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(_lastSuccessKey, at.toIso8601String());
    await storage.remove(_lastFailureKey);
    await storage.remove(_lastFailureMessageKey);
  }

  Future<void> recordAutomaticFailure(DateTime at, Object error) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(_lastFailureKey, at.toIso8601String());
    await storage.setString(_lastFailureMessageKey, error.toString());
  }

  Future<String?> loadLastSuccessfulAppVersion() async {
    final storage = await SharedPreferences.getInstance();
    return storage.getString(_lastLaunchedVersionKey);
  }

  Future<({String? version, String? path})> loadPendingUpdate() async {
    final storage = await SharedPreferences.getInstance();
    return (
      version: storage.getString(_pendingUpdateVersionKey),
      path: storage.getString(_pendingUpdateBackupPathKey),
    );
  }

  Future<void> recordPendingUpdate({
    required String version,
    required String path,
    required DateTime at,
  }) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(_pendingUpdateVersionKey, version);
    await storage.setString(_pendingUpdateBackupPathKey, path);
    await storage.setString(_latestSafetyAtKey, at.toIso8601String());
    await storage.setString(_latestSafetyVersionKey, version);
  }

  Future<void> markLaunchSuccessful(String version) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(_lastLaunchedVersionKey, version);
    await storage.remove(_pendingUpdateVersionKey);
    await storage.remove(_pendingUpdateBackupPathKey);
  }

  static DateTime? _date(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

abstract final class AutomaticBackupPolicy {
  static DateTime preferredTimeForDay({
    required DateTime day,
    required int preferredMinutes,
  }) => DateTime(
    day.year,
    day.month,
    day.day,
    preferredMinutes ~/ 60,
    preferredMinutes % 60,
  );

  static bool isDue({
    required UserPreferences preferences,
    required DateTime now,
    required DateTime? lastSuccessfulAt,
  }) {
    if (!preferences.automaticBackupsEnabled) return false;
    final todayWindow = preferredTimeForDay(
      day: now,
      preferredMinutes: preferences.preferredAutomaticBackupMinutes,
    );
    if (now.isBefore(todayWindow)) return false;
    if (lastSuccessfulAt == null) return true;
    final lastLocal = lastSuccessfulAt.toLocal();
    return switch (preferences.automaticBackupFrequency) {
      AutomaticBackupFrequency.daily => lastLocal.isBefore(todayWindow),
      AutomaticBackupFrequency.weekly => !now.isBefore(
        preferredTimeForDay(
          day: DateTime(lastLocal.year, lastLocal.month, lastLocal.day + 7),
          preferredMinutes: preferences.preferredAutomaticBackupMinutes,
        ),
      ),
    };
  }
}

class AutomaticBackupService {
  AutomaticBackupService({
    BackupSafetyFileService? fileService,
    this.stateStore = const AutomaticBackupStateStore(),
    this.codec = const BackupCodec(),
  }) : fileService = fileService ?? BackupSafetyFileService();

  final BackupSafetyFileService fileService;
  final AutomaticBackupStateStore stateStore;
  final BackupCodec codec;
  bool _isRunning = false;

  Future<bool> createIfDue({
    required FinanceDataSet dataSet,
    required DateTime now,
  }) async {
    if (_isRunning) return false;
    final status = await stateStore.loadStatus();
    if (!AutomaticBackupPolicy.isDue(
      preferences: dataSet.preferences,
      now: now,
      lastSuccessfulAt: status.lastSuccessfulAt,
    )) {
      return false;
    }
    _isRunning = true;
    try {
      final content = codec.encodeJson(dataSet, exportedAt: now);
      await fileService.saveVerifiedBackup(
        content: content,
        fileName: automaticBackupFileName(now),
      );
      final retain = switch (dataSet.preferences.automaticBackupFrequency) {
        AutomaticBackupFrequency.daily => 7,
        AutomaticBackupFrequency.weekly => 4,
      };
      await fileService.prune(
        matches: isTrackmarkAutomaticBackupFileName,
        retain: retain,
      );
      await stateStore.recordAutomaticSuccess(now);
      return true;
    } on Object catch (error) {
      await stateStore.recordAutomaticFailure(now, error);
      rethrow;
    } finally {
      _isRunning = false;
    }
  }
}

class AppVersionIdentity {
  const AppVersionIdentity(this.value);

  final String value;

  static Future<AppVersionIdentity> current() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersionIdentity('${info.version}+${info.buildNumber}');
  }
}

class PreUpdateBackupCoordinator {
  PreUpdateBackupCoordinator({
    BackupSafetyFileService? fileService,
    this.stateStore = const AutomaticBackupStateStore(),
    this.codec = const BackupCodec(),
  }) : fileService = fileService ?? BackupSafetyFileService();

  final BackupSafetyFileService fileService;
  final AutomaticBackupStateStore stateStore;
  final BackupCodec codec;

  Future<void> prepare({
    required AppVersionIdentity currentVersion,
    required FinanceDataSet? preMigrationDataSet,
    required DateTime now,
  }) async {
    final previous = await stateStore.loadLastSuccessfulAppVersion();
    if (previous == currentVersion.value) return;

    final pending = await stateStore.loadPendingUpdate();
    if (pending.version == currentVersion.value && pending.path != null) {
      final file = File(pending.path!);
      if (await file.exists()) {
        // Re-verification is mandatory before allowing migrations to resume.
        await fileService.verifyExistingBackup(file);
        return;
      }
    }

    if (preMigrationDataSet == null) {
      return;
    }
    final file = await fileService.saveVerifiedBackup(
      content: codec.encodeJson(preMigrationDataSet, exportedAt: now),
      fileName: preUpdateBackupFileName(
        oldVersion: previous ?? 'pre_tracking',
        newVersion: currentVersion.value,
        createdAt: now,
      ),
    );
    await fileService.prune(
      matches: isTrackmarkPreUpdateBackupFileName,
      retain: 3,
    );
    await stateStore.recordPendingUpdate(
      version: currentVersion.value,
      path: file.path,
      at: now,
    );
  }

  Future<void> markLaunchSuccessful(AppVersionIdentity currentVersion) =>
      stateStore.markLaunchSuccessful(currentVersion.value);
}
