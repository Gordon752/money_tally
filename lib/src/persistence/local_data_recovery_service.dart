import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/finance_data_set.dart';
import '../export/export_file_service.dart';
import '../store/finance_data_store.dart';
import 'backup_restore_service.dart';
import 'finance_record_repository.dart';
import 'local_finance_data_set_repository.dart';

class RecoveryCloudTarget {
  const RecoveryCloudTarget({this.repository, this.userId})
    : assert((repository == null) == (userId == null));
  final FinanceRecordRepository? repository;
  final String? userId;
  bool get cloudEnabled => repository != null;
}

class LocalDataRecoveryResult {
  const LocalDataRecoveryResult({
    required this.originalPath,
    required this.sourceBackupPath,
  });
  final String originalPath;
  final String sourceBackupPath;
}

class LocalDataRecoveryException implements Exception {
  const LocalDataRecoveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LocalDataRecoveryService {
  LocalDataRecoveryService({
    required this.failure,
    LocalFinanceDataSetRepository? localRepository,
    BackupSafetyFileService? safetyFiles,
    this.validator = const BackupRestoreValidator(),
  }) : localRepository =
           localRepository ??
           LocalFinanceDataSetRepository(storageKey: failure.storageKey),
       safetyFiles = safetyFiles ?? BackupSafetyFileService();

  final UnreadableLocalFinanceData failure;
  final LocalFinanceDataSetRepository localRepository;
  final BackupSafetyFileService safetyFiles;
  final BackupRestoreValidator validator;
  bool _restoring = false;

  Future<LocalDataRecoveryResult> restore({
    required String backupJson,
    required RecoveryCloudTarget target,
  }) async {
    if (_restoring) throw StateError('Recovery is already in progress.');
    _restoring = true;
    FinanceDataStore? store;
    try {
      // The service validates again: callers cannot bypass schema/references
      // by constructing a ValidatedBackup object themselves.
      final backup = validator.validate(backupJson);
      if (await localRepository.readRaw() != failure.original) {
        throw const LocalDataRecoveryException(
          'Local data changed. Retry startup before restoring.',
        );
      }
      final originalPath = await _preserveOriginal();
      final source = await safetyFiles.saveVerifiedBackup(
        content: backup.originalJson,
        fileName:
            'trackmark-recovery-source-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      final staging = _RecoveryStagingRepository();
      // Seed with the validated selection, never an empty replacement for the
      // unreadable data. Financial restore and cloud generation logic remain
      // exclusively in the existing store operation.
      store = FinanceDataStore(
        dataSet: backup.dataSet,
        localRepository: staging,
        remoteRepository: target.repository,
        userId: target.userId,
      );
      var cloudActivated = false;
      try {
        await store.restoreBackupDataSet(backup.dataSet);
        cloudActivated = target.cloudEnabled;
        if (await localRepository.readRaw() != failure.original) {
          throw StateError('Local data changed during restore.');
        }
        final userId = target.userId;
        // Stage acknowledgement before the single final local-data commit.
        // Startup cannot use it until local decoding succeeds. Retain/restore
        // the previous marker if that final commit fails.
        final previousGeneration = userId == null
            ? null
            : await localRepository.loadAcknowledgedRestoreGeneration(userId);
        try {
          if (userId != null && staging.generation != null) {
            await localRepository.saveAcknowledgedRestoreGeneration(
              userId,
              staging.generation!,
            );
          }
          await localRepository.installRecoveredDataSet(
            staging.dataSet!,
            expectedOriginal: failure.original,
          );
        } catch (_) {
          if (userId != null) {
            if (previousGeneration == null) {
              await localRepository.clearAcknowledgedRestoreGeneration(userId);
            } else {
              await localRepository.saveAcknowledgedRestoreGeneration(
                userId,
                previousGeneration,
              );
            }
          }
          rethrow;
        }
      } catch (error) {
        final authorityChanged =
            cloudActivated ||
            error is AuthoritativeRestoreLocalInstallException;
        throw LocalDataRecoveryException(
          authorityChanged
              ? 'The validated backup became the cloud restore authority, but local recovery did not finish. Your original is preserved at $originalPath. Retry recovery with the same backup. Do not resume normal sync yet.'
              : 'Restore did not finish. Your unreadable original has not been replaced and is preserved at $originalPath. You can choose another backup or retry.',
        );
      }
      return LocalDataRecoveryResult(
        originalPath: originalPath,
        sourceBackupPath: source.path,
      );
    } finally {
      store?.dispose();
      _restoring = false;
    }
  }

  Future<String> _preserveOriginal() async {
    final directory = await safetyFiles.backupDirectory();
    final digest = sha256.convert(utf8.encode(failure.original));
    final file = File(
      '${directory.path}${Platform.pathSeparator}trackmark-unreadable-$digest.txt',
    );
    // Content-addressed and never pruned as a normal financial backup. An
    // existing raw copy is verified, never overwritten on another attempt.
    if (!await file.exists()) {
      final pending = File('${file.path}.pending');
      await pending.writeAsString(
        failure.original,
        encoding: utf8,
        flush: true,
      );
      if (await pending.readAsString(encoding: utf8) != failure.original) {
        throw StateError(
          'The original data preservation copy could not be verified.',
        );
      }
      await pending.rename(file.path);
    }
    if (await file.readAsString(encoding: utf8) != failure.original) {
      throw StateError(
        'The original data preservation copy could not be verified.',
      );
    }
    return file.path;
  }
}

class _RecoveryStagingRepository extends LocalFinanceDataSetRepository {
  FinanceDataSet? dataSet;
  String? generation;
  @override
  Future<void> save(FinanceDataSet value) async {
    dataSet = value;
  }

  @override
  Future<void> saveAcknowledgedRestoreGeneration(
    String userId,
    String value,
  ) async {
    generation = value;
  }
}
