import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/export/export_file_service.dart';
import 'package:money_tally/src/persistence/automatic_backup_service.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_restore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('automatic backup defaults off and preferences survive backup', () {
    const defaults = UserPreferences();
    expect(defaults.automaticBackupsEnabled, isFalse);
    expect(defaults.automaticBackupFrequency, AutomaticBackupFrequency.weekly);
    expect(defaults.preferredAutomaticBackupMinutes, 23 * 60);

    final configured = defaults.copyWith(
      automaticBackupsEnabled: true,
      automaticBackupFrequency: AutomaticBackupFrequency.daily,
      preferredAutomaticBackupMinutes: 21 * 60 + 15,
    );
    final restored = const BackupCodec().decodeJson(
      const BackupCodec().encodeJson(_dataSet(configured)),
    );
    expect(restored.preferences.automaticBackupsEnabled, isTrue);
    expect(
      restored.preferences.automaticBackupFrequency,
      AutomaticBackupFrequency.daily,
    );
    expect(restored.preferences.preferredAutomaticBackupMinutes, 21 * 60 + 15);
  });

  test('daily and weekly due windows do not duplicate', () {
    final now = DateTime(2026, 8, 13, 23, 30);
    const daily = UserPreferences(
      automaticBackupsEnabled: true,
      automaticBackupFrequency: AutomaticBackupFrequency.daily,
      preferredAutomaticBackupMinutes: 23 * 60,
    );
    expect(
      AutomaticBackupPolicy.isDue(
        preferences: daily,
        now: now,
        lastSuccessfulAt: null,
      ),
      isTrue,
    );
    expect(
      AutomaticBackupPolicy.isDue(
        preferences: daily,
        now: now,
        lastSuccessfulAt: DateTime(2026, 8, 13, 23, 5),
      ),
      isFalse,
    );

    final weekly = daily.copyWith(
      automaticBackupFrequency: AutomaticBackupFrequency.weekly,
    );
    expect(
      AutomaticBackupPolicy.isDue(
        preferences: weekly,
        now: now,
        lastSuccessfulAt: DateTime(2026, 8, 7, 23, 5),
      ),
      isFalse,
    );
    expect(
      AutomaticBackupPolicy.isDue(
        preferences: weekly,
        now: DateTime(2026, 8, 14, 23, 5),
        lastSuccessfulAt: DateTime(2026, 8, 7, 23, 5),
      ),
      isTrue,
    );
  });

  test(
    'automatic backup is verified, importable, and retention is narrow',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trackmark_automatic_backup_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final fileService = BackupSafetyFileService(
        directoryProvider: () async => directory,
      );
      final service = AutomaticBackupService(fileService: fileService);
      const preferences = UserPreferences(
        automaticBackupsEnabled: true,
        automaticBackupFrequency: AutomaticBackupFrequency.daily,
        preferredAutomaticBackupMinutes: 0,
      );
      final dataSet = _dataSet(preferences);

      for (var day = 1; day <= 9; day++) {
        SharedPreferences.setMockInitialValues({});
        await service.createIfDue(
          dataSet: dataSet,
          now: DateTime(2026, 8, day, 12),
        );
      }
      final backupDirectory = Directory('${directory.path}/Trackmark Backups');
      await File(
        '${backupDirectory.path}/manual_notes.json',
      ).writeAsString('keep');
      await File(
        '${backupDirectory.path}/trackmark_money_backup_2026-08-01_120000.json',
      ).writeAsString('keep');
      await fileService.prune(
        matches: isTrackmarkAutomaticBackupFileName,
        retain: 7,
      );

      final names = await backupDirectory
          .list()
          .map((file) => file.uri.pathSegments.last)
          .toList();
      final automatic = names
          .where(isTrackmarkAutomaticBackupFileName)
          .toList();
      expect(automatic, hasLength(7));
      expect(names, contains('manual_notes.json'));
      expect(names, contains('trackmark_money_backup_2026-08-01_120000.json'));
      final content = await File(
        '${backupDirectory.path}/${automatic.first}',
      ).readAsString();
      expect(
        const BackupRestoreValidator().validate(content).dataSet.toJson(),
        dataSet.toJson(),
      );
    },
  );

  test('failed candidate verification preserves a known-good backup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trackmark_failed_backup_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = BackupSafetyFileService(
      directoryProvider: () async => directory,
    );
    final knownGood = await service.saveVerifiedBackup(
      content: const BackupCodec().encodeJson(
        _dataSet(const UserPreferences()),
      ),
      fileName: automaticBackupFileName(DateTime(2026, 8, 12, 23)),
    );

    await expectLater(
      service.saveVerifiedBackup(
        content: '{"schemaVersion":4}',
        fileName: automaticBackupFileName(DateTime(2026, 8, 13, 23)),
      ),
      throwsA(isA<BackupValidationException>()),
    );
    expect(await File(knownGood.path).exists(), isTrue);
    expect(
      await File(
        '${directory.path}/Trackmark Backups/'
        '${automaticBackupFileName(DateTime(2026, 8, 13, 23))}',
      ).exists(),
      isFalse,
    );
  });

  test(
    'legacy filename remains importable because content decides validity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trackmark_legacy_named_backup_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}/money_tally_backup_2026-08-11_1324.json',
      );
      await file.writeAsString(
        const BackupCodec().encodeJson(_dataSet(const UserPreferences())),
      );
      final imported = await BackupImportFileService(
        picker: () async => XFile(file.path),
      ).selectBackup();
      expect(imported!.name, startsWith('money_tally_backup_'));
      expect(
        const BackupRestoreValidator()
            .validate(imported.content)
            .dataSet
            .toJson(),
        _dataSet(const UserPreferences()).toJson(),
      );
    },
  );

  test('version change creates one verified pre-update backup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trackmark_pre_update_backup_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = await SharedPreferences.getInstance();
    await storage.setString(
      'trackmark_last_successful_app_version_build',
      '1.0.0+1',
    );
    final coordinator = PreUpdateBackupCoordinator(
      fileService: BackupSafetyFileService(
        directoryProvider: () async => directory,
      ),
    );
    const current = AppVersionIdentity('1.1.0+2');
    final dataSet = _dataSet(const UserPreferences());

    await coordinator.prepare(
      currentVersion: current,
      preMigrationDataSet: dataSet,
      now: DateTime(2026, 8, 13, 8),
    );
    await coordinator.prepare(
      currentVersion: current,
      preMigrationDataSet: dataSet,
      now: DateTime(2026, 8, 13, 9),
    );

    final files = await Directory(
      '${directory.path}/Trackmark Backups',
    ).list().where((entry) => entry is File).cast<File>().toList();
    expect(files, hasLength(1));
    expect(
      files.single.uri.pathSegments.last,
      startsWith('trackmark_money_pre_update_backup_1.0.0_1_to_1.1.0_2_'),
    );
    expect(
      const BackupRestoreValidator()
          .validate(await files.single.readAsString())
          .dataSet
          .toJson(),
      dataSet.toJson(),
    );

    await coordinator.markLaunchSuccessful(current);
    await coordinator.prepare(
      currentVersion: current,
      preMigrationDataSet: dataSet,
      now: DateTime(2026, 8, 13, 10),
    );
    expect(
      await Directory(
        '${directory.path}/Trackmark Backups',
      ).list().where((entry) => entry is File).length,
      1,
    );
  });
}

FinanceDataSet _dataSet(UserPreferences preferences) => FinanceDataSet(
  accounts: const [],
  categories: const [],
  transactions: const [],
  scheduledTransactions: const [],
  budgets: const [],
  preferences: preferences,
);
