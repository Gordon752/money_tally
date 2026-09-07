import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/export/export_file_service.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_restore_service.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/persistence/local_data_recovery_service.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const raw = '{unreadable original\n';
const key = 'recovery-test-data';
const failure = UnreadableLocalFinanceData(storageKey: key, original: raw);

FinanceDataSet recoveryFixture() => FinanceDataSet(
  accounts: [
    AccountRecord(
      id: 'wallet',
      name: 'Recovered wallet',
      type: AccountType.cash,
      openingBalanceMinor: 12345,
      sync: SyncMetadata.fresh(now: DateTime.utc(2026, 1, 1)),
    ),
  ],
  categories: [],
  transactions: [],
  scheduledTransactions: [],
  budgets: [],
  preferences: const UserPreferences(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late BackupSafetyFileService safety;
  late String valid;
  setUp(() async {
    SharedPreferences.setMockInitialValues({key: raw});
    directory = await Directory.systemTemp.createTemp(
      'trackmark-recovery-test-',
    );
    safety = BackupSafetyFileService(directoryProvider: () async => directory);
    valid = const BackupCodec().encodeJson(
      recoveryFixture(),
      exportedAt: DateTime.utc(2026, 9, 7),
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  for (final signedIn in [false, true]) {
    test(
      '${signedIn ? "signed-in" : "local-only"} recovery preserves original and uses validated restore',
      () async {
        final remote = RecoveryRemote();
        final service = LocalDataRecoveryService(
          failure: failure,
          safetyFiles: safety,
        );
        final result = await service.restore(
          backupJson: valid,
          target: signedIn
              ? RecoveryCloudTarget(repository: remote, userId: 'user')
              : const RecoveryCloudTarget(),
        );
        expect(await File(result.originalPath).readAsString(), raw);
        expect(await File(result.sourceBackupPath).readAsString(), valid);
        final loaded = await const LocalFinanceDataSetRepository(
          storageKey: key,
        ).load();
        expect(loaded!.accounts.single.openingBalanceMinor, 12345);
        expect(loaded.preferences.legacyV1MigrationCompleted, isTrue);
        expect(remote.replacements, signedIn ? 1 : 0);
        if (signedIn) {
          expect(
            await const LocalFinanceDataSetRepository(
              storageKey: key,
            ).loadAcknowledgedRestoreGeneration('user'),
            'recovered-generation',
          );
          expect(
            remote.installed!.accounts.single.toJson(),
            loaded.accounts.single.toJson(),
          );
        }
      },
    );
  }

  for (final invalidKind in ['json', 'schema', 'reference']) {
    test(
      'invalid $invalidKind backup cannot write local, safety or cloud data',
      () async {
        final json = jsonDecode(valid) as Map<String, dynamic>;
        if (invalidKind == 'schema') json['schemaVersion'] = 999;
        if (invalidKind == 'reference') {
          json['accounts'] = [];
          json['transactions'] = [
            {
              'id': 'bad-reference',
              'type': 'income',
              'accountId': 'missing',
              'date': '2026-09-07T00:00:00.000',
              'payee': 'Test',
              'amountMinor': 100,
              'sync': SyncMetadata.fresh(
                now: DateTime.utc(2026, 1, 1),
              ).toJson(),
            },
          ];
        }
        final remote = RecoveryRemote();
        final service = LocalDataRecoveryService(
          failure: failure,
          safetyFiles: safety,
        );
        await expectLater(
          service.restore(
            backupJson: invalidKind == 'json' ? 'bad' : jsonEncode(json),
            target: RecoveryCloudTarget(repository: remote, userId: 'user'),
          ),
          throwsA(isA<BackupValidationException>()),
        );
        expect(
          await const LocalFinanceDataSetRepository(storageKey: key).readRaw(),
          raw,
        );
        expect(remote.replacements, 0);
        expect(await directory.list().toList(), isEmpty);
      },
    );
  }

  test('cloud failure retains original and permits another attempt', () async {
    final remote = RecoveryRemote()..fail = true;
    final service = LocalDataRecoveryService(
      failure: failure,
      safetyFiles: safety,
    );
    final target = RecoveryCloudTarget(repository: remote, userId: 'user');
    await expectLater(
      service.restore(backupJson: valid, target: target),
      throwsA(isA<LocalDataRecoveryException>()),
    );
    expect(
      await const LocalFinanceDataSetRepository(storageKey: key).readRaw(),
      raw,
    );
    remote.fail = false;
    final result = await service.restore(backupJson: valid, target: target);
    expect(await File(result.originalPath).readAsString(), raw);
    expect(
      (await directory.list(recursive: true).toList()).whereType<File>().where(
        (file) => file.path.endsWith('.txt'),
      ),
      hasLength(1),
    );
    expect(remote.replacements, 2);
  });

  test(
    'local installation failure retains raw and rolls back generation acknowledgement',
    () async {
      final local = FailingRecoveryLocal();
      await local.saveAcknowledgedRestoreGeneration(
        'user',
        'previous-generation',
      );
      final remote = RecoveryRemote();
      final service = LocalDataRecoveryService(
        failure: failure,
        localRepository: local,
        safetyFiles: safety,
      );
      await expectLater(
        service.restore(
          backupJson: valid,
          target: RecoveryCloudTarget(repository: remote, userId: 'user'),
        ),
        throwsA(
          isA<LocalDataRecoveryException>().having(
            (e) => e.message,
            'authority explanation',
            contains('became the cloud restore authority'),
          ),
        ),
      );
      expect(await local.readRaw(), raw);
      expect(
        await local.loadAcknowledgedRestoreGeneration('user'),
        'previous-generation',
      );
      expect(remote.replacements, 1);
      local.fail = false;
      await service.restore(
        backupJson: valid,
        target: RecoveryCloudTarget(repository: remote, userId: 'user'),
      );
      expect((await local.load())!.accounts.single.name, 'Recovered wallet');
    },
  );

  test('safety-copy failure blocks local and cloud replacement', () async {
    final remote = RecoveryRemote();
    final service = LocalDataRecoveryService(
      failure: failure,
      safetyFiles: BrokenSafety(),
    );
    await expectLater(
      service.restore(
        backupJson: valid,
        target: RecoveryCloudTarget(repository: remote, userId: 'user'),
      ),
      throwsA(anything),
    );
    expect(
      await const LocalFinanceDataSetRepository(storageKey: key).readRaw(),
      raw,
    );
    expect(remote.replacements, 0);
  });

  test(
    'changed local data cannot be overwritten by an old recovery screen',
    () async {
      final remote = RecoveryRemote();
      final service = LocalDataRecoveryService(
        failure: failure,
        safetyFiles: safety,
      );
      await (await SharedPreferences.getInstance()).setString(key, valid);
      await expectLater(
        service.restore(
          backupJson: valid,
          target: RecoveryCloudTarget(repository: remote, userId: 'user'),
        ),
        throwsA(isA<LocalDataRecoveryException>()),
      );
      expect(
        await const LocalFinanceDataSetRepository(storageKey: key).readRaw(),
        valid,
      );
      expect(remote.replacements, 0);
    },
  );
}

class RecoveryRemote implements FinanceRecordRepository {
  int replacements = 0;
  bool fail = false;
  FinanceDataSet? installed;
  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async {
    replacements++;
    if (fail) throw StateError('Cloud unavailable');
    installed = dataSet;
    return 'recovered-generation';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FailingRecoveryLocal extends LocalFinanceDataSetRepository {
  FailingRecoveryLocal() : super(storageKey: key);
  bool fail = true;
  @override
  Future<void> installRecoveredDataSet(
    FinanceDataSet dataSet, {
    required String expectedOriginal,
  }) async {
    if (fail) throw StateError('Device storage unavailable');
    await super.installRecoveredDataSet(
      dataSet,
      expectedOriginal: expectedOriginal,
    );
  }
}

class BrokenSafety extends BackupSafetyFileService {
  @override
  Future<Directory> backupDirectory() async =>
      throw const FileSystemException('Storage unavailable');
}
