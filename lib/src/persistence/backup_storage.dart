import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../export/export_file_service.dart';
import 'backup_restore_service.dart';

enum BackupStorageState {
  available,
  unavailable,
  containerUnavailable,
  waitingForUpload,
  uploaded,
  downloadRequired,
  downloading,
  error,
}

class BackupStorageStatus {
  const BackupStorageStatus({required this.state, this.message});

  final BackupStorageState state;
  final String? message;
}

class BackupStorageEntry {
  const BackupStorageEntry({
    required this.fileName,
    required this.modifiedAt,
    required this.size,
    required this.status,
  });

  final String fileName;
  final DateTime modifiedAt;
  final int size;
  final BackupStorageStatus status;
}

class BackupStorageException implements Exception {
  const BackupStorageException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BackupStorageException($code): $message';
}

abstract interface class BackupStorage {
  Future<BackupStorageStatus> status();

  Future<BackupStorageEntry> write({
    required String content,
    required String fileName,
  });

  Future<String> read(String fileName);

  Future<List<BackupStorageEntry>> list();

  Future<void> delete(String fileName);

  Future<BackupStorageStatus> downloadIfNeeded(String fileName);

  Future<BackupStorageStatus> entryStatus(String fileName);

  Future<void> prune({
    required bool Function(String fileName) matches,
    required int retain,
  });
}

class LocalBackupStorage implements BackupStorage {
  LocalBackupStorage({BackupSafetyFileService? fileService})
    : fileService = fileService ?? BackupSafetyFileService();

  final BackupSafetyFileService fileService;

  @override
  Future<BackupStorageStatus> status() async =>
      const BackupStorageStatus(state: BackupStorageState.available);

  @override
  Future<BackupStorageEntry> write({
    required String content,
    required String fileName,
  }) async {
    final exported = await fileService.saveVerifiedBackup(
      content: content,
      fileName: fileName,
    );
    final file = File(exported.path);
    return BackupStorageEntry(
      fileName: fileName,
      modifiedAt: await file.lastModified(),
      size: await file.length(),
      status: const BackupStorageStatus(state: BackupStorageState.available),
    );
  }

  @override
  Future<String> read(String fileName) async {
    _validateFileName(fileName);
    final directory = await fileService.backupDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    ).readAsString(encoding: utf8);
  }

  @override
  Future<List<BackupStorageEntry>> list() async {
    final directory = await fileService.backupDirectory();
    final entries = <BackupStorageEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final fileName = entity.uri.pathSegments.last;
      if (!_isManagedFileName(fileName)) continue;
      entries.add(
        BackupStorageEntry(
          fileName: fileName,
          modifiedAt: await entity.lastModified(),
          size: await entity.length(),
          status: const BackupStorageStatus(
            state: BackupStorageState.available,
          ),
        ),
      );
    }
    entries.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return entries;
  }

  @override
  Future<void> delete(String fileName) async {
    _validateFileName(fileName);
    final directory = await fileService.backupDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    if (await file.exists()) await file.delete();
  }

  @override
  Future<BackupStorageStatus> downloadIfNeeded(String fileName) async {
    _validateFileName(fileName);
    return const BackupStorageStatus(state: BackupStorageState.available);
  }

  @override
  Future<BackupStorageStatus> entryStatus(String fileName) async {
    _validateFileName(fileName);
    return const BackupStorageStatus(state: BackupStorageState.available);
  }

  @override
  Future<void> prune({
    required bool Function(String fileName) matches,
    required int retain,
  }) => fileService.prune(matches: matches, retain: retain);
}

abstract interface class ICloudBackupPlatform {
  Future<Map<String, Object?>> availability();

  Future<Map<String, Object?>> resolveContainer();

  Future<Map<String, Object?>> write({
    required String fileName,
    required String content,
  });

  Future<String> read(String fileName);

  Future<List<Map<String, Object?>>> list();

  Future<void> delete(String fileName);

  Future<Map<String, Object?>> status(String fileName);

  Future<Map<String, Object?>> downloadIfNeeded(String fileName);

  Future<Map<String, Object?>> runSmokeTest();
}

class MethodChannelICloudBackupPlatform implements ICloudBackupPlatform {
  const MethodChannelICloudBackupPlatform({
    this.channel = const MethodChannel(
      'com.gordonbowles.moneytally/icloud_backup_storage',
    ),
  });

  final MethodChannel channel;

  @override
  Future<Map<String, Object?>> availability() => _map('isICloudAvailable');

  @override
  Future<Map<String, Object?>> resolveContainer() =>
      _map('resolveBackupContainer');

  @override
  Future<Map<String, Object?>> write({
    required String fileName,
    required String content,
  }) => _map('writeBackup', {'fileName': fileName, 'content': content});

  @override
  Future<String> read(String fileName) async =>
      (await channel.invokeMethod<String>('readBackup', {
        'fileName': fileName,
      })) ??
      (throw const BackupStorageException(
        'invalid_response',
        'iCloud returned no backup content.',
      ));

  @override
  Future<List<Map<String, Object?>>> list() async {
    try {
      final result = await channel.invokeListMethod<Object?>('listBackups');
      return (result ?? const [])
          .map((item) => Map<String, Object?>.from(item! as Map))
          .toList();
    } on PlatformException catch (error) {
      throw _exception(error);
    }
  }

  @override
  Future<void> delete(String fileName) async {
    try {
      await channel.invokeMethod<bool>('deleteBackup', {'fileName': fileName});
    } on PlatformException catch (error) {
      throw _exception(error);
    }
  }

  @override
  Future<Map<String, Object?>> status(String fileName) =>
      _map('backupStatus', {'fileName': fileName});

  @override
  Future<Map<String, Object?>> downloadIfNeeded(String fileName) =>
      _map('downloadBackupIfNeeded', {'fileName': fileName});

  @override
  Future<Map<String, Object?>> runSmokeTest() => _map('runSmokeTest');

  Future<Map<String, Object?>> _map(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      if (result == null) {
        throw const BackupStorageException(
          'invalid_response',
          'iCloud returned no result.',
        );
      }
      return result;
    } on PlatformException catch (error) {
      throw _exception(error);
    }
  }

  BackupStorageException _exception(PlatformException error) =>
      BackupStorageException(
        error.code,
        error.message ?? 'The iCloud backup operation failed.',
      );
}

class ICloudBackupStorage implements BackupStorage {
  ICloudBackupStorage({
    ICloudBackupPlatform? platform,
    bool? isSupported,
    this.validator = const BackupRestoreValidator(),
  }) : _platform = platform ?? const MethodChannelICloudBackupPlatform(),
       _isSupported =
           isSupported ?? defaultTargetPlatform == TargetPlatform.iOS;

  final ICloudBackupPlatform _platform;
  final bool _isSupported;
  final BackupRestoreValidator validator;

  @override
  Future<BackupStorageStatus> status() async {
    if (!_isSupported) {
      return const BackupStorageStatus(state: BackupStorageState.unavailable);
    }
    return _statusFrom(await _platform.availability());
  }

  Future<Map<String, Object?>> resolveContainer() {
    _requireSupported();
    return _platform.resolveContainer();
  }

  @override
  Future<BackupStorageEntry> write({
    required String content,
    required String fileName,
  }) async {
    _requireSupported();
    validator.validate(content);
    final entry = _entryFrom(
      await _platform.write(fileName: fileName, content: content),
    );
    try {
      final verified = await _platform.read(entry.fileName);
      if (verified != content) {
        throw const BackupStorageException(
          'verification_failed',
          'The iCloud backup did not match the data that Trackmark wrote.',
        );
      }
      validator.validate(verified);
      return entry;
    } on Object {
      // Only the newly created candidate is removed. Existing known-good
      // backups remain untouched if candidate verification fails.
      try {
        await _platform.delete(entry.fileName);
      } on Object {
        // Preserve the original verification failure.
      }
      rethrow;
    }
  }

  @override
  Future<String> read(String fileName) async {
    _requireSupported();
    final fileStatus = await downloadIfNeeded(fileName);
    if (fileStatus.state == BackupStorageState.downloadRequired ||
        fileStatus.state == BackupStorageState.downloading) {
      throw const BackupStorageException(
        'download_incomplete',
        'The iCloud backup is not downloaded yet.',
      );
    }
    return _platform.read(fileName);
  }

  @override
  Future<List<BackupStorageEntry>> list() async {
    _requireSupported();
    return (await _platform.list()).map(_entryFrom).toList()
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
  }

  @override
  Future<void> delete(String fileName) {
    _requireSupported();
    return _platform.delete(fileName);
  }

  @override
  Future<BackupStorageStatus> downloadIfNeeded(String fileName) async {
    _requireSupported();
    return _statusFrom(await _platform.downloadIfNeeded(fileName));
  }

  @override
  Future<BackupStorageStatus> entryStatus(String fileName) async {
    _requireSupported();
    return _statusFrom(await _platform.status(fileName));
  }

  Future<BackupStorageStatus> backupStatus(String fileName) =>
      entryStatus(fileName);

  Future<Map<String, Object?>> runSmokeTest() {
    _requireSupported();
    return _platform.runSmokeTest();
  }

  @override
  Future<void> prune({
    required bool Function(String fileName) matches,
    required int retain,
  }) async {
    final entries = (await list()).where((entry) => matches(entry.fileName));
    for (final entry in entries.skip(retain)) {
      await delete(entry.fileName);
    }
  }

  void _requireSupported() {
    if (!_isSupported) {
      throw const BackupStorageException(
        'unsupported_platform',
        'iCloud backup storage is only available on iPhone and iPad.',
      );
    }
  }
}

BackupStorageEntry _entryFrom(Map<String, Object?> value) {
  final modifiedMilliseconds = (value['modifiedAt'] as num?)?.toDouble() ?? 0;
  return BackupStorageEntry(
    fileName: value['fileName'] as String? ?? '',
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(
      modifiedMilliseconds.round(),
    ),
    size: (value['size'] as num?)?.toInt() ?? 0,
    status: _statusFrom(value),
  );
}

BackupStorageStatus _statusFrom(Map<String, Object?> value) {
  final raw = value['state'] as String? ?? 'error';
  final state = BackupStorageState.values.firstWhere(
    (candidate) => candidate.name == raw,
    orElse: () => BackupStorageState.error,
  );
  return BackupStorageStatus(state: state, message: value['error'] as String?);
}

void _validateFileName(String fileName) {
  if (!_isManagedFileName(fileName) ||
      fileName.contains('/') ||
      fileName.contains('\\')) {
    throw ArgumentError.value(fileName, 'fileName', 'Invalid backup file name');
  }
}

bool _isManagedFileName(String fileName) =>
    fileName.startsWith('trackmark_money_') && fileName.endsWith('.json');
