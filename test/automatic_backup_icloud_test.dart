import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/automatic_backup_service.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'backup location defaults local and survives JSON/backup round trip',
    () {
      const defaults = UserPreferences();
      expect(defaults.automaticBackupLocation, AutomaticBackupLocation.local);

      final configured = defaults.copyWith(
        automaticBackupsEnabled: true,
        automaticBackupLocation: AutomaticBackupLocation.iCloud,
      );
      final jsonRoundTrip = UserPreferences.fromJson(configured.toJson());
      expect(
        jsonRoundTrip.automaticBackupLocation,
        AutomaticBackupLocation.iCloud,
      );
      final backupRoundTrip = const BackupCodec().decodeJson(
        const BackupCodec().encodeJson(_dataSet(configured)),
      );
      expect(
        backupRoundTrip.preferences.automaticBackupLocation,
        AutomaticBackupLocation.iCloud,
      );
      expect(
        UserPreferences.fromJson(const {}).automaticBackupLocation,
        AutomaticBackupLocation.local,
      );
    },
  );

  test('local preference routes only to local storage', () async {
    final local = _MemoryBackupStorage();
    final iCloud = _MemoryBackupStorage();
    final service = AutomaticBackupService(
      localStorage: local,
      iCloudStorage: iCloud,
    );

    expect(
      await service.createIfDue(
        dataSet: _dataSet(_enabled(location: AutomaticBackupLocation.local)),
        now: DateTime(2026, 8, 18, 23, 5),
      ),
      isTrue,
    );
    expect(local.files, hasLength(1));
    expect(iCloud.files, isEmpty);
    expect(
      (await service.loadStatus()).lastResult,
      AutomaticBackupResult.savedOnDevice,
    );
  });

  test(
    'iCloud write is reread, validated, and records uploaded state',
    () async {
      final local = _MemoryBackupStorage();
      final iCloud = _MemoryBackupStorage(
        entryState: BackupStorageState.uploaded,
      );
      final service = AutomaticBackupService(
        localStorage: local,
        iCloudStorage: iCloud,
      );

      await service.createIfDue(
        dataSet: _dataSet(_enabled(location: AutomaticBackupLocation.iCloud)),
        now: DateTime(2026, 8, 18, 23, 5),
      );

      expect(local.files, isEmpty);
      expect(iCloud.files, hasLength(1));
      expect(iCloud.readCount, greaterThanOrEqualTo(1));
      expect(
        const BackupCodec().decodeJson(iCloud.files.values.single).preferences,
        isA<UserPreferences>(),
      );
      final status = await service.loadStatus();
      expect(status.lastResult, AutomaticBackupResult.uploadedToICloud);
      expect(status.lastFileName, iCloud.files.keys.single);
    },
  );

  test('waiting upload is honest and does not prune known-good files', () async {
    final iCloud = _MemoryBackupStorage(
      entryState: BackupStorageState.waitingForUpload,
    );
    for (var day = 1; day <= 8; day++) {
      iCloud.seed(
        'trackmark_money_automatic_backup_2026-08-${day.toString().padLeft(2, '0')}_230000.json',
      );
    }
    final service = AutomaticBackupService(
      localStorage: _MemoryBackupStorage(),
      iCloudStorage: iCloud,
    );
    await service.createIfDue(
      dataSet: _dataSet(_enabled(location: AutomaticBackupLocation.iCloud)),
      now: DateTime(2026, 8, 18, 23, 5),
    );

    expect(iCloud.files, hasLength(9));
    expect(iCloud.pruneCount, 0);
    expect(
      (await service.loadStatus()).lastResult,
      AutomaticBackupResult.waitingForICloud,
    );
  });

  test(
    'waiting state refreshes to uploaded using real storage state',
    () async {
      final iCloud = _MemoryBackupStorage(
        entryState: BackupStorageState.waitingForUpload,
      );
      final service = AutomaticBackupService(
        localStorage: _MemoryBackupStorage(),
        iCloudStorage: iCloud,
      );
      await service.createIfDue(
        dataSet: _dataSet(_enabled(location: AutomaticBackupLocation.iCloud)),
        now: DateTime(2026, 8, 18, 23, 5),
      );
      expect(
        (await service.loadStatus()).lastResult,
        AutomaticBackupResult.waitingForICloud,
      );
      iCloud.entryState = BackupStorageState.uploaded;
      expect(
        (await service.loadStatus()).lastResult,
        AutomaticBackupResult.uploadedToICloud,
      );
    },
  );

  test(
    'unavailable iCloud creates verified local fallback without changing preference',
    () async {
      final local = _MemoryBackupStorage();
      final iCloud = _MemoryBackupStorage(
        availabilityState: BackupStorageState.unavailable,
      );
      final preferences = _enabled(location: AutomaticBackupLocation.iCloud);
      final service = AutomaticBackupService(
        localStorage: local,
        iCloudStorage: iCloud,
      );

      await service.createIfDue(
        dataSet: _dataSet(preferences),
        now: DateTime(2026, 8, 18, 23, 5),
      );

      expect(local.files, hasLength(1));
      expect(iCloud.files, isEmpty);
      expect(
        preferences.automaticBackupLocation,
        AutomaticBackupLocation.iCloud,
      );
      expect(
        (await service.loadStatus()).lastResult,
        AutomaticBackupResult.iCloudUnavailableSavedOnDevice,
      );
    },
  );

  test(
    'iCloud write failure falls back and retains previous backups',
    () async {
      final local = _MemoryBackupStorage();
      final iCloud = _MemoryBackupStorage()..writeFailure = true;
      iCloud.seed('trackmark_money_automatic_backup_2026-08-17_230000.json');
      final service = AutomaticBackupService(
        localStorage: local,
        iCloudStorage: iCloud,
      );
      await service.createIfDue(
        dataSet: _dataSet(_enabled(location: AutomaticBackupLocation.iCloud)),
        now: DateTime(2026, 8, 18, 23, 5),
      );
      expect(
        iCloud.files.keys,
        contains('trackmark_money_automatic_backup_2026-08-17_230000.json'),
      );
      expect(local.files, hasLength(1));
    },
  );

  test(
    'uploaded iCloud daily retention keeps 7 and ignores unrelated files',
    () async {
      final iCloud = _MemoryBackupStorage(
        entryState: BackupStorageState.uploaded,
      );
      for (var day = 1; day <= 8; day++) {
        iCloud.seed(
          'trackmark_money_automatic_backup_2026-08-${day.toString().padLeft(2, '0')}_230000.json',
          modifiedAt: DateTime(2026, 8, day),
        );
      }
      iCloud.seed('trackmark_money_backup_2026-08-01_120000.json');
      iCloud.seed('trackmark_money_pre_restore_backup_2026-08-01_120000.json');
      iCloud.seed(
        'trackmark_money_pre_update_backup_1_to_2_2026-08-01_120000.json',
      );
      final service = AutomaticBackupService(
        localStorage: _MemoryBackupStorage(),
        iCloudStorage: iCloud,
      );
      await service.createIfDue(
        dataSet: _dataSet(_enabled(location: AutomaticBackupLocation.iCloud)),
        now: DateTime(2026, 8, 18, 23, 5),
      );

      expect(
        iCloud.files.keys.where((name) => name.contains('_automatic_backup_')),
        hasLength(7),
      );
      expect(
        iCloud.files.keys,
        contains('trackmark_money_backup_2026-08-01_120000.json'),
      );
      expect(
        iCloud.files.keys,
        contains('trackmark_money_pre_restore_backup_2026-08-01_120000.json'),
      );
      expect(
        iCloud.files.keys,
        contains(
          'trackmark_money_pre_update_backup_1_to_2_2026-08-01_120000.json',
        ),
      );
    },
  );

  test('uploaded iCloud weekly retention keeps 4', () async {
    final iCloud = _MemoryBackupStorage(
      entryState: BackupStorageState.uploaded,
    );
    for (var week = 1; week <= 5; week++) {
      iCloud.seed(
        'trackmark_money_automatic_backup_2026-07-${(week * 5).toString().padLeft(2, '0')}_230000.json',
        modifiedAt: DateTime(2026, 7, week * 5),
      );
    }
    final service = AutomaticBackupService(
      localStorage: _MemoryBackupStorage(),
      iCloudStorage: iCloud,
    );
    await service.createIfDue(
      dataSet: _dataSet(
        _enabled(
          location: AutomaticBackupLocation.iCloud,
          frequency: AutomaticBackupFrequency.weekly,
        ),
      ),
      now: DateTime(2026, 8, 18, 23, 5),
    );
    expect(iCloud.files, hasLength(4));
  });

  test('collision-safe writes preserve both device candidates', () async {
    final storage = _MemoryBackupStorage();
    const name = 'trackmark_money_automatic_backup_2026-08-18_230000.json';
    final first = await storage.write(content: '{}', fileName: name);
    final second = await storage.write(content: '{}', fileName: name);
    expect(first.fileName, name);
    expect(second.fileName, isNot(name));
    expect(storage.files, hasLength(2));
  });

  test(
    'changing destination does not migrate or delete either location',
    () async {
      final local = _MemoryBackupStorage()
        ..seed('trackmark_money_automatic_backup_2026-08-16_230000.json');
      final iCloud = _MemoryBackupStorage(
        entryState: BackupStorageState.uploaded,
      )..seed('trackmark_money_automatic_backup_2026-08-17_230000.json');
      final service = AutomaticBackupService(
        localStorage: local,
        iCloudStorage: iCloud,
      );
      await service.createIfDue(
        dataSet: _dataSet(_enabled(location: AutomaticBackupLocation.iCloud)),
        now: DateTime(2026, 8, 18, 23, 5),
      );
      expect(
        local.files.keys,
        contains('trackmark_money_automatic_backup_2026-08-16_230000.json'),
      );
      SharedPreferences.setMockInitialValues({});
      await service.createIfDue(
        dataSet: _dataSet(_enabled(location: AutomaticBackupLocation.local)),
        now: DateTime(2026, 8, 19, 23, 5),
      );
      expect(
        iCloud.files.keys,
        contains('trackmark_money_automatic_backup_2026-08-17_230000.json'),
      );
    },
  );
}

UserPreferences _enabled({
  required AutomaticBackupLocation location,
  AutomaticBackupFrequency frequency = AutomaticBackupFrequency.daily,
}) => UserPreferences(
  automaticBackupsEnabled: true,
  automaticBackupFrequency: frequency,
  preferredAutomaticBackupMinutes: 0,
  automaticBackupLocation: location,
);

FinanceDataSet _dataSet(UserPreferences preferences) => FinanceDataSet(
  accounts: const [],
  categories: const [],
  transactions: const [],
  scheduledTransactions: const [],
  budgets: const [],
  preferences: preferences,
);

class _MemoryBackupStorage implements BackupStorage {
  _MemoryBackupStorage({
    this.availabilityState = BackupStorageState.available,
    this.entryState = BackupStorageState.available,
  });

  BackupStorageState availabilityState;
  BackupStorageState entryState;
  bool writeFailure = false;
  int readCount = 0;
  int pruneCount = 0;
  final Map<String, String> files = {};
  final Map<String, DateTime> modified = {};

  void seed(String fileName, {DateTime? modifiedAt}) {
    files[fileName] = const BackupCodec().encodeJson(
      _dataSet(const UserPreferences()),
    );
    modified[fileName] = modifiedAt ?? DateTime(2026, 8, 1);
  }

  @override
  Future<BackupStorageStatus> status() async =>
      BackupStorageStatus(state: availabilityState);

  @override
  Future<BackupStorageEntry> write({
    required String content,
    required String fileName,
  }) async {
    if (writeFailure) {
      throw const BackupStorageException('write_failed', 'Test failure');
    }
    var actualName = fileName;
    if (files.containsKey(actualName)) {
      actualName = '${fileName.substring(0, fileName.length - 5)}_device2.json';
    }
    files[actualName] = content;
    modified[actualName] = DateTime(2026, 8, 18, 23, 5);
    return _entry(actualName);
  }

  @override
  Future<String> read(String fileName) async {
    readCount += 1;
    return files[fileName]!;
  }

  @override
  Future<List<BackupStorageEntry>> list() async {
    final result = files.keys.map(_entry).toList();
    result.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return result;
  }

  @override
  Future<void> delete(String fileName) async {
    files.remove(fileName);
    modified.remove(fileName);
  }

  @override
  Future<BackupStorageStatus> downloadIfNeeded(String fileName) async =>
      BackupStorageStatus(state: entryState);

  @override
  Future<BackupStorageStatus> entryStatus(String fileName) async =>
      BackupStorageStatus(state: entryState);

  @override
  Future<void> prune({
    required bool Function(String fileName) matches,
    required int retain,
  }) async {
    pruneCount += 1;
    final entries = (await list()).where((entry) => matches(entry.fileName));
    for (final entry in entries.skip(retain)) {
      await delete(entry.fileName);
    }
  }

  BackupStorageEntry _entry(String fileName) => BackupStorageEntry(
    fileName: fileName,
    modifiedAt: modified[fileName]!,
    size: files[fileName]!.length,
    status: BackupStorageStatus(state: entryState),
  );
}
