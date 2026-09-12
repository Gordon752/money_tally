import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/export/export_file_service.dart';
import 'package:money_tally/src/persistence/automatic_backup_service.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_storage.dart';

void main() {
  final validBackup = const BackupCodec().encodeJson(
    const FinanceDataSet(
      accounts: [],
      categories: [],
      transactions: [],
      scheduledTransactions: [],
      budgets: [],
      preferences: UserPreferences(),
    ),
  );

  test('AutomaticBackupService remains local by default', () {
    expect(AutomaticBackupService().storage, isA<LocalBackupStorage>());
  });

  test(
    'local storage write, read, list, delete, and prune are unchanged',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'trackmark_backup_storage_',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = LocalBackupStorage(
        fileService: BackupSafetyFileService(
          directoryProvider: () async => root,
        ),
      );
      final names = List.generate(
        3,
        (index) =>
            'trackmark_money_automatic_backup_2026-08-1${index + 1}_230000.json',
      );

      for (final name in names) {
        await storage.write(content: validBackup, fileName: name);
      }
      expect(await storage.read(names.first), validBackup);
      expect(await storage.list(), hasLength(3));
      await storage.prune(
        matches: (name) => name.contains('_automatic_backup_'),
        retain: 2,
      );
      expect(await storage.list(), hasLength(2));
      await storage.delete((await storage.list()).first.fileName);
      expect(await storage.list(), hasLength(1));
    },
  );

  test('iCloud unavailable and unsupported states are explicit', () async {
    final platform = _FakeICloudPlatform()
      ..availabilityPayload = {'state': 'unavailable'};
    expect(
      (await ICloudBackupStorage(
        platform: platform,
        isSupported: true,
      ).status()).state,
      BackupStorageState.unavailable,
    );
    expect(
      (await ICloudBackupStorage(
        platform: platform,
        isSupported: false,
      ).status()).state,
      BackupStorageState.unavailable,
    );
  });

  test(
    'iCloud storage writes, rereads, validates, lists, and deletes',
    () async {
      final platform = _FakeICloudPlatform();
      final storage = ICloudBackupStorage(
        platform: platform,
        isSupported: true,
      );
      const fileName =
          'trackmark_money_automatic_backup_2026-08-17_230000.json';

      final written = await storage.write(
        content: validBackup,
        fileName: fileName,
      );
      expect(written.fileName, fileName);
      expect(await storage.read(fileName), validBackup);
      expect((await storage.list()).single.fileName, fileName);
      await storage.delete(fileName);
      expect(await storage.list(), isEmpty);
    },
  );

  test('iCloud write rejects a mismatched verification reread', () async {
    final platform = _FakeICloudPlatform()..corruptReadAfterWrite = true;
    final storage = ICloudBackupStorage(platform: platform, isSupported: true);
    await expectLater(
      storage.write(
        content: validBackup,
        fileName: 'trackmark_money_automatic_backup_2026-08-17_230000.json',
      ),
      throwsA(
        isA<BackupStorageException>().having(
          (error) => error.code,
          'code',
          'verification_failed',
        ),
      ),
    );
  });

  test('download-required item is requested before read', () async {
    final platform = _FakeICloudPlatform()
      ..downloadState = 'downloadRequired'
      ..files['trackmark_money_automatic_backup_remote.json'] = validBackup;
    final storage = ICloudBackupStorage(platform: platform, isSupported: true);

    expect(
      await storage.read('trackmark_money_automatic_backup_remote.json'),
      validBackup,
    );
    expect(platform.downloadRequests, 1);
  });

  test('native upload and error states map without simulated timing', () async {
    final platform = _FakeICloudPlatform();
    final storage = ICloudBackupStorage(platform: platform, isSupported: true);
    platform.statusPayload = {'state': 'waitingForUpload'};
    expect(
      (await storage.backupStatus('trackmark_money_backup_test.json')).state,
      BackupStorageState.waitingForUpload,
    );
    platform.statusPayload = {'state': 'uploaded'};
    expect(
      (await storage.backupStatus('trackmark_money_backup_test.json')).state,
      BackupStorageState.uploaded,
    );
    platform.statusPayload = {'state': 'error', 'error': 'Storage full'};
    final error = await storage.backupStatus(
      'trackmark_money_backup_test.json',
    );
    expect(error.state, BackupStorageState.error);
    expect(error.message, 'Storage full');
  });

  test('platform failures propagate with their stable error code', () async {
    final storage = ICloudBackupStorage(
      platform: _FakeICloudPlatform()
        ..failure = const BackupStorageException(
          'container_unavailable',
          'No container',
        ),
      isSupported: true,
    );
    await expectLater(
      storage.list(),
      throwsA(
        isA<BackupStorageException>().having(
          (error) => error.code,
          'code',
          'container_unavailable',
        ),
      ),
    );
  });
}

class _FakeICloudPlatform implements ICloudBackupPlatform {
  Map<String, Object?> availabilityPayload = {'state': 'available'};
  Map<String, Object?> statusPayload = {'state': 'uploaded'};
  final Map<String, String> files = {};
  String downloadState = 'uploaded';
  int downloadRequests = 0;
  bool corruptReadAfterWrite = false;
  BackupStorageException? failure;

  Never _throwFailure() => throw failure!;

  @override
  Future<Map<String, Object?>> availability() async {
    if (failure != null) _throwFailure();
    return availabilityPayload;
  }

  @override
  Future<void> delete(String fileName) async {
    if (failure != null) _throwFailure();
    files.remove(fileName);
  }

  @override
  Future<Map<String, Object?>> downloadIfNeeded(String fileName) async {
    if (failure != null) _throwFailure();
    downloadRequests += 1;
    downloadState = 'uploaded';
    return {'state': downloadState};
  }

  @override
  Future<List<Map<String, Object?>>> list() async {
    if (failure != null) _throwFailure();
    return files.keys
        .map(
          (fileName) => <String, Object?>{
            'fileName': fileName,
            'modifiedAt': DateTime(2026, 8, 17).millisecondsSinceEpoch,
            'size': files[fileName]!.length,
            'state': 'uploaded',
          },
        )
        .toList();
  }

  @override
  Future<String> read(String fileName) async {
    if (failure != null) _throwFailure();
    if (corruptReadAfterWrite) return '${files[fileName]} ';
    return files[fileName]!;
  }

  @override
  Future<Map<String, Object?>> resolveContainer() async {
    if (failure != null) _throwFailure();
    return {'state': 'available', 'displayName': 'Trackmark Money/Backups'};
  }

  @override
  Future<Map<String, Object?>> runSmokeTest() async {
    if (failure != null) _throwFailure();
    return {'success': true, 'deleted': true};
  }

  @override
  Future<Map<String, Object?>> status(String fileName) async {
    if (failure != null) _throwFailure();
    return statusPayload;
  }

  @override
  Future<Map<String, Object?>> write({
    required String fileName,
    required String content,
  }) async {
    if (failure != null) _throwFailure();
    files[fileName] = content;
    return {
      'fileName': fileName,
      'modifiedAt': DateTime(2026, 8, 17).millisecondsSinceEpoch,
      'size': content.length,
      'state': 'waitingForUpload',
    };
  }
}
