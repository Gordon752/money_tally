import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/finance_data_set.dart';
import '../domain/user_preferences.dart';
import '../export/export_file_service.dart';
import 'backup_codec.dart';
import 'backup_restore_service.dart';
import 'backup_storage.dart';

enum AutomaticBackupResult {
  savedOnDevice,
  uploadedToICloud,
  waitingForICloud,
  iCloudUnavailableSavedOnDevice,
  backupFailed,
}

class AutomaticBackupStatus {
  const AutomaticBackupStatus({
    this.lastSuccessfulAt,
    this.lastFailureAt,
    this.lastFailureMessage,
    this.lastResultAt,
    this.lastResult,
    this.lastFileName,
    this.latestSafetyBackupAt,
    this.latestSafetyBackupVersion,
  });

  final DateTime? lastSuccessfulAt;
  final DateTime? lastFailureAt;
  final String? lastFailureMessage;
  final DateTime? lastResultAt;
  final AutomaticBackupResult? lastResult;
  final String? lastFileName;
  final DateTime? latestSafetyBackupAt;
  final String? latestSafetyBackupVersion;
}

class AutomaticBackupStateStore {
  const AutomaticBackupStateStore();

  static const _lastSuccessKey = 'trackmark_automatic_backup_last_success';
  static const _lastFailureKey = 'trackmark_automatic_backup_last_failure';
  static const _lastFailureMessageKey =
      'trackmark_automatic_backup_last_failure_message';
  static const _lastResultAtKey = 'trackmark_automatic_backup_last_result_at';
  static const _lastResultKey = 'trackmark_automatic_backup_last_result';
  static const _lastFileNameKey = 'trackmark_automatic_backup_last_file_name';
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
      lastResultAt: _date(storage.getString(_lastResultAtKey)),
      lastResult: _result(storage.getString(_lastResultKey)),
      lastFileName: storage.getString(_lastFileNameKey),
      latestSafetyBackupAt: _date(storage.getString(_latestSafetyAtKey)),
      latestSafetyBackupVersion: storage.getString(_latestSafetyVersionKey),
    );
  }

  Future<void> recordAutomaticSuccess(
    DateTime at, {
    required AutomaticBackupResult result,
    required String fileName,
  }) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(_lastSuccessKey, at.toIso8601String());
    await storage.setString(_lastResultAtKey, at.toIso8601String());
    await storage.setString(_lastResultKey, result.name);
    await storage.setString(_lastFileNameKey, fileName);
    await storage.remove(_lastFailureKey);
    await storage.remove(_lastFailureMessageKey);
  }

  Future<void> recordAutomaticFailure(DateTime at, Object error) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(_lastFailureKey, at.toIso8601String());
    await storage.setString(_lastFailureMessageKey, error.toString());
    await storage.setString(_lastResultAtKey, at.toIso8601String());
    await storage.setString(
      _lastResultKey,
      AutomaticBackupResult.backupFailed.name,
    );
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

  static AutomaticBackupResult? _result(String? value) {
    if (value == null) return null;
    for (final result in AutomaticBackupResult.values) {
      if (result.name == value) return result;
    }
    return null;
  }
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
    BackupStorage? storage,
    BackupStorage? localStorage,
    BackupStorage? iCloudStorage,
    this.stateStore = const AutomaticBackupStateStore(),
    this.codec = const BackupCodec(),
    this.validator = const BackupRestoreValidator(),
  }) : assert(fileService == null || storage == null),
       assert(fileService == null || localStorage == null),
       localStorage =
           storage ??
           localStorage ??
           LocalBackupStorage(
             fileService: fileService ?? BackupSafetyFileService(),
           ),
       iCloudStorage = storage ?? iCloudStorage ?? ICloudBackupStorage();

  final BackupStorage localStorage;
  final BackupStorage iCloudStorage;
  final AutomaticBackupStateStore stateStore;
  final BackupCodec codec;
  final BackupRestoreValidator validator;
  bool _isRunning = false;

  /// Kept for source compatibility with Stage 1 callers. Production routing
  /// is selected per execution from [UserPreferences.automaticBackupLocation].
  BackupStorage get storage => localStorage;

  Future<AutomaticBackupStatus> loadStatus() async {
    var status = await stateStore.loadStatus();
    if (status.lastResult != AutomaticBackupResult.waitingForICloud ||
        status.lastFileName == null ||
        status.lastSuccessfulAt == null) {
      return status;
    }
    try {
      final current = await iCloudStorage.entryStatus(status.lastFileName!);
      if (current.state == BackupStorageState.uploaded) {
        await stateStore.recordAutomaticSuccess(
          status.lastSuccessfulAt!,
          result: AutomaticBackupResult.uploadedToICloud,
          fileName: status.lastFileName!,
        );
        status = await stateStore.loadStatus();
      }
    } on Object {
      // A status refresh must never invalidate a verified backup or disturb
      // Settings. The next automatic opportunity will retry normally.
    }
    return status;
  }

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
      validator.validate(content);
      final fileName = automaticBackupFileName(now);
      final retain = switch (dataSet.preferences.automaticBackupFrequency) {
        AutomaticBackupFrequency.daily => 7,
        AutomaticBackupFrequency.weekly => 4,
      };

      if (dataSet.preferences.automaticBackupLocation ==
          AutomaticBackupLocation.iCloud) {
        final iCloudEntry = await _tryCreateICloud(
          content: content,
          fileName: fileName,
        );
        if (iCloudEntry != null) {
          final uploadStatus = await _safeEntryStatus(
            iCloudStorage,
            iCloudEntry.fileName,
            fallback: iCloudEntry.status,
          );
          final uploaded = uploadStatus.state == BackupStorageState.uploaded;
          if (uploaded) {
            // Pruning happens only after the new backup is verified and known
            // to be uploaded. Enumeration failure deliberately leaves extras.
            try {
              await iCloudStorage.prune(
                matches: isTrackmarkAutomaticBackupFileName,
                retain: retain,
              );
            } on Object {
              // Retaining too many known-good backups is safer than deleting
              // from an incomplete shared iCloud enumeration.
            }
          }
          await stateStore.recordAutomaticSuccess(
            now,
            result: uploaded
                ? AutomaticBackupResult.uploadedToICloud
                : AutomaticBackupResult.waitingForICloud,
            fileName: iCloudEntry.fileName,
          );
          return true;
        }

        final fallback = await _createVerified(
          localStorage,
          content: content,
          fileName: fileName,
        );
        await localStorage.prune(
          matches: isTrackmarkAutomaticBackupFileName,
          retain: retain,
        );
        await stateStore.recordAutomaticSuccess(
          now,
          result: AutomaticBackupResult.iCloudUnavailableSavedOnDevice,
          fileName: fallback.fileName,
        );
        return true;
      }

      final local = await _createVerified(
        localStorage,
        content: content,
        fileName: fileName,
      );
      await localStorage.prune(
        matches: isTrackmarkAutomaticBackupFileName,
        retain: retain,
      );
      await stateStore.recordAutomaticSuccess(
        now,
        result: AutomaticBackupResult.savedOnDevice,
        fileName: local.fileName,
      );
      return true;
    } on Object catch (error) {
      await stateStore.recordAutomaticFailure(now, error);
      rethrow;
    } finally {
      _isRunning = false;
    }
  }

  Future<BackupStorageEntry?> _tryCreateICloud({
    required String content,
    required String fileName,
  }) async {
    try {
      final availability = await iCloudStorage.status();
      if (availability.state != BackupStorageState.available &&
          availability.state != BackupStorageState.uploaded &&
          availability.state != BackupStorageState.waitingForUpload) {
        return null;
      }
      return await _createVerified(
        iCloudStorage,
        content: content,
        fileName: fileName,
      );
    } on Object {
      return null;
    }
  }

  Future<BackupStorageEntry> _createVerified(
    BackupStorage target, {
    required String content,
    required String fileName,
  }) async {
    validator.validate(content);
    final entry = await target.write(content: content, fileName: fileName);
    try {
      final reread = await target.read(entry.fileName);
      validator.validate(reread);
      if (reread != content) {
        throw const BackupStorageException(
          'verification_failed',
          'The stored backup did not match the Trackmark backup payload.',
        );
      }
      return entry;
    } on Object {
      try {
        await target.delete(entry.fileName);
      } on Object {
        // Preserve the verification error while leaving prior backups intact.
      }
      rethrow;
    }
  }

  Future<BackupStorageStatus> _safeEntryStatus(
    BackupStorage target,
    String fileName, {
    required BackupStorageStatus fallback,
  }) async {
    try {
      return await target.entryStatus(fileName);
    } on Object {
      return fallback;
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
