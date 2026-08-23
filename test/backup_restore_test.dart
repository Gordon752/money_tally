import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/export/export_file_service.dart';
import 'package:money_tally/src/notifications/notification_scheduler.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_restore_service.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('authoritative backup restore', () {
    test(
      'reset replaces local and cloud financial data while preserving preferences',
      () async {
        SharedPreferences.setMockInitialValues({});
        final original = _richDataSet();
        final remote = _AuthoritativeFakeRepository(original);
        final store = FinanceDataStore(
          dataSet: original,
          remoteRepository: remote,
          userId: 'user-1',
        );

        await store.resetTrackmarkData();

        for (final dataSet in [store.dataSet, remote.remoteDataSet]) {
          expect(dataSet.accounts, isEmpty);
          expect(dataSet.categories, isEmpty);
          expect(dataSet.transactions, isEmpty);
          expect(dataSet.scheduledTransactions, isEmpty);
          expect(dataSet.budgets, isEmpty);
          expect(dataSet.goals, isEmpty);
          expect(dataSet.funds, isEmpty);
          expect(dataSet.reservationOperations, isEmpty);
          expect(dataSet.goalContributions, isEmpty);
          expect(dataSet.goalFundingEvents, isEmpty);
          expect(
            dataSet.preferences.toJson(),
            original.preferences
                .copyWith(legacyV1MigrationCompleted: true)
                .toJson(),
          );
        }
        expect(remote.authoritativeWrites, 1);
      },
    );

    test('failed cloud reset retains the complete local data set', () async {
      SharedPreferences.setMockInitialValues({});
      final original = _richDataSet();
      final remote = _AuthoritativeFakeRepository(original, failReplace: true);
      final store = FinanceDataStore(
        dataSet: original,
        remoteRepository: remote,
        userId: 'user-1',
      );

      await expectLater(store.resetTrackmarkData(), throwsStateError);

      expect(store.dataSet.toJson(), original.toJson());
      expect(remote.remoteDataSet.toJson(), original.toJson());
      expect(remote.authoritativeWrites, 0);
    });

    test('rich backup round trip preserves every persisted field', () async {
      SharedPreferences.setMockInitialValues({});
      final original = _richDataSet();
      final json = const BackupCodec().encodeJson(
        original,
        exportedAt: DateTime.utc(2026, 8, 8, 12, 34, 56),
      );
      final validated = const BackupRestoreValidator().validate(json);
      const repository = LocalFinanceDataSetRepository(
        storageKey: 'rich_restore_round_trip',
      );
      final store = FinanceDataStore(
        dataSet: _emptyDataSet(),
        localRepository: repository,
      );

      await store.restoreBackupDataSet(validated.dataSet);
      final reloaded = await repository.load();

      expect(validated.exportedAt, DateTime.utc(2026, 8, 8, 12, 34, 56));
      expect(validated.sourceSchemaVersion, currentBackupSchemaVersion);
      final expected = _withoutDeviceLocalNotificationMetadata(original);
      expect(store.dataSet.toJson(), expected.toJson());
      expect(reloaded?.toJson(), expected.toJson());
      expect(store.balanceForAccount('checking'), 502500);
      expect(store.balanceForAccount('card'), -125000);
      expect(
        store.transactions.firstWhere((item) => item.id == 'expense-1').status,
        TransactionStatus.pending,
      );
    });

    test('supported backup without transaction status defaults to cleared', () {
      final legacy = _richDataSet().toJson();
      final transactions = legacy['transactions']! as List<Object?>;
      transactions[0] = Map<String, Object?>.from(transactions[0]! as Map)
        ..remove('status');

      final restored = const BackupRestoreValidator().validate(
        jsonEncode(legacy),
      );

      expect(
        restored.dataSet.transactions.first.status,
        TransactionStatus.cleared,
      );
    });

    test(
      'occurrence authority round trips while device notification state is omitted',
      () {
        final original = _richDataSet();
        final schedule = original.scheduledTransactions.first;
        final occurrenceDate = DateTime(2026, 8, 8);
        final withAuthority = original.copyWith(
          scheduledTransactions: [
            schedule.copyWith(
              occurrenceStates: {
                occurrenceDayKey(occurrenceDate): ScheduledOccurrenceState(
                  scheduledDate: occurrenceDate,
                  plannedAmountMinor: 10000,
                  status: ScheduledOccurrenceStatus.paid,
                  actualAmountMinor: 10000,
                  actualPaymentDate: occurrenceDate,
                  transactionId: 'scheduled-ledger-1',
                  revision: 3,
                  operationId: 'operation-a',
                  changedAt: DateTime.utc(2026, 8, 8, 12),
                  deviceId: 'phone',
                ),
              },
              sync: schedule.sync,
            ),
            ...original.scheduledTransactions.skip(1),
          ],
        );

        final encoded = const BackupCodec().encodeJson(withAuthority);
        final raw = jsonDecode(encoded) as Map<String, Object?>;
        final rawSchedule =
            (raw['scheduledTransactions'] as List<Object?>).first
                as Map<String, Object?>;
        expect(rawSchedule, isNot(contains('scheduledNotificationIds')));
        expect(rawSchedule, isNot(contains('lastReminderScheduledAt')));

        final restored = const BackupRestoreValidator().validate(encoded);
        final state = restored
            .dataSet
            .scheduledTransactions
            .first
            .occurrenceStates[occurrenceDayKey(occurrenceDate)];
        expect(state?.revision, 3);
        expect(state?.operationId, 'operation-a');
        expect(state?.transactionId, 'scheduled-ledger-1');
      },
    );

    test('existing local data is replaced rather than merged', () async {
      final store = FinanceDataStore(dataSet: _fictionalDataSet());

      await store.restoreBackupDataSet(_richDataSet());

      expect(
        store.accounts.map((item) => item.id),
        isNot(contains('fictional')),
      );
      expect(
        store.dataSet.toJson(),
        _withoutDeviceLocalNotificationMetadata(_richDataSet()).toJson(),
      );
    });

    test(
      'corrupt, incomplete, duplicate, and orphaned backups are rejected',
      () {
        const validator = BackupRestoreValidator();
        expect(
          () => validator.validate('not json'),
          throwsA(isA<BackupValidationException>()),
        );
        expect(
          () => validator.validate(
            jsonEncode({'schemaVersion': 4, 'accounts': []}),
          ),
          throwsA(isA<BackupValidationException>()),
        );

        final duplicate = _richDataSet().toJson();
        (duplicate['accounts']! as List<Object?>).add(
          (duplicate['accounts']! as List<Object?>).first,
        );
        expect(
          () => validator.validate(jsonEncode(duplicate)),
          throwsA(isA<BackupValidationException>()),
        );

        final orphaned = _richDataSet().toJson();
        final transaction = Map<String, Object?>.from(
          (orphaned['transactions']! as List<Object?>).first as Map,
        )..['accountId'] = 'missing-account';
        (orphaned['transactions']! as List<Object?>)[0] = transaction;
        expect(
          () => validator.validate(jsonEncode(orphaned)),
          throwsA(isA<BackupValidationException>()),
        );
      },
    );

    test('schema 2 migrates explicitly and future schema is rejected', () {
      final schema2 =
          _richDataSet()
              .copyWith(
                goals: const [],
                goalContributions: const [],
                goalFundingEvents: const [],
                accounts: _richDataSet().accounts
                    .where((item) => !item.isInternalGoalAccount)
                    .toList(),
              )
              .toJson()
            ..['schemaVersion'] = 2
            ..remove('goals')
            ..remove('goalContributions')
            ..remove('goalFundingEvents');

      final restored = const BackupRestoreValidator().validate(
        jsonEncode(schema2),
      );
      expect(restored.sourceSchemaVersion, 2);
      expect(restored.schemaVersion, currentBackupSchemaVersion);
      expect(restored.dataSet.goals, isEmpty);

      final future = _richDataSet().toJson()..['schemaVersion'] = 99;
      expect(
        () => const BackupRestoreValidator().validate(jsonEncode(future)),
        throwsA(
          isA<BackupValidationException>().having(
            (error) => error.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test(
      'repairs real blank split IDs without changing financial allocations',
      () {
        final source = _richDataSet();
        final recordSync = source.transactions.first.sync;
        final dataSet = source.copyWith(
          categories: [
            ...source.categories,
            CategoryRecord(
              id: 'dining',
              name: 'Dining',
              kind: CategoryKind.expense,
              sync: recordSync,
            ),
            CategoryRecord(
              id: 'maintenance',
              name: 'Maintenance',
              kind: CategoryKind.expense,
              sync: recordSync,
            ),
            CategoryRecord(
              id: 'sales-tax',
              name: 'Sales Tax',
              kind: CategoryKind.expense,
              sync: recordSync,
            ),
          ],
          transactions: [
            ...source.transactions,
            TransactionRecord(
              id: 'txn_1786393981825072',
              type: TransactionType.expense,
              accountId: 'cash',
              categoryId: 'dining',
              date: DateTime(2026, 8, 10, 15, 33, 1),
              payee: 'Pizza Hut',
              amountMinor: 2304,
              splitLines: const [
                TransactionSplitLine(
                  id: '',
                  categoryId: 'dining',
                  amountMinor: 2128,
                ),
                TransactionSplitLine(
                  id: 'split_1786394123220666_1',
                  categoryId: 'sales-tax',
                  amountMinor: 176,
                ),
              ],
              sync: recordSync,
            ),
            TransactionRecord(
              id: 'txn_1786412936472197',
              type: TransactionType.expense,
              accountId: 'card',
              categoryId: 'maintenance',
              date: DateTime(2026, 8, 10, 20, 48, 56),
              payee: 'Travel Centers Of America',
              amountMinor: 100000,
              note: 'Shocks and metal hose leak',
              splitLines: const [
                TransactionSplitLine(
                  id: '   ',
                  categoryId: 'maintenance',
                  amountMinor: 88958,
                ),
                TransactionSplitLine(
                  id: 'split_1786416511003681_1',
                  categoryId: 'sales-tax',
                  amountMinor: 11042,
                ),
              ],
              sync: recordSync,
            ),
          ],
        );

        final restored = const BackupRestoreValidator().validate(
          const BackupCodec().encodeJson(dataSet),
        );
        final pizza = restored.dataSet.transactions.firstWhere(
          (item) => item.id == 'txn_1786393981825072',
        );
        final travelCenter = restored.dataSet.transactions.firstWhere(
          (item) => item.id == 'txn_1786412936472197',
        );

        expect(pizza.amountMinor, 2304);
        expect(pizza.splitLines.map((line) => line.id), [
          'split_txn_1786393981825072_0',
          'split_1786394123220666_1',
        ]);
        expect(
          pizza.splitLines.map(
            (line) => (line.categoryId, line.amountMinor, line.note),
          ),
          [('dining', 2128, ''), ('sales-tax', 176, '')],
        );
        expect(travelCenter.amountMinor, 100000);
        expect(travelCenter.note, 'Shocks and metal hose leak');
        expect(travelCenter.splitLines.map((line) => line.id), [
          'split_txn_1786412936472197_0',
          'split_1786416511003681_1',
        ]);
        expect(
          travelCenter.splitLines.map(
            (line) => (line.categoryId, line.amountMinor, line.note),
          ),
          [('maintenance', 88958, ''), ('sales-tax', 11042, '')],
        );
        expect(pizza.hasValidSplitTotal, isTrue);
        expect(travelCenter.hasValidSplitTotal, isTrue);
      },
    );

    test('duplicate nonblank split IDs remain invalid', () {
      final raw = _richDataSet().toJson();
      final transactions = raw['transactions']! as List<Object?>;
      final splitIndex = transactions.indexWhere(
        (item) => (item as Map)['id'] == 'split-1',
      );
      final split = Map<String, Object?>.from(transactions[splitIndex] as Map);
      final lines = (split['splitLines']! as List<Object?>)
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList();
      lines[1]['id'] = lines[0]['id'];
      split['splitLines'] = lines;
      transactions[splitIndex] = split;

      expect(
        () => const BackupRestoreValidator().validate(jsonEncode(raw)),
        throwsA(
          isA<BackupValidationException>().having(
            (error) => error.message,
            'message',
            'A transaction contains an invalid split allocation.',
          ),
        ),
      );
    });

    test('saving a split transaction replaces blank IDs stably', () async {
      final source = _richDataSet();
      final store = FinanceDataStore(dataSet: source);
      final transaction = TransactionRecord(
        id: 'new-split',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'groceries',
        date: DateTime(2026, 8, 11, 9, 30),
        payee: 'Split merchant',
        amountMinor: 2500,
        splitLines: const [
          TransactionSplitLine(
            id: '',
            categoryId: 'groceries',
            amountMinor: 2000,
            note: 'Primary',
          ),
          TransactionSplitLine(
            id: 'existing-line',
            categoryId: 'snacks',
            amountMinor: 500,
            note: 'Secondary',
          ),
        ],
        sync: source.transactions.first.sync,
      );

      await store.saveTransaction(transaction);
      final saved = store.transactions.firstWhere(
        (item) => item.id == transaction.id,
      );

      expect(saved.splitLines.map((line) => line.id), [
        'split_new-split_0',
        'existing-line',
      ]);
      expect(
        saved.splitLines.every((line) => line.id.trim().isNotEmpty),
        isTrue,
      );
      expect(saved.splitLines.map((line) => line.amountMinor), [2000, 500]);
      expect(saved.splitLines.map((line) => line.note), [
        'Primary',
        'Secondary',
      ]);
    });

    test(
      'deleted Goal tombstones may outlive their removed hidden accounts',
      () {
        final source = _richDataSet();
        final goal = source.goals.single;
        final tombstone = goal.copyWith(
          sync: goal.sync.deleted(deviceId: 'test-device'),
        );
        final withoutHiddenAccount = source.copyWith(
          goals: [tombstone],
          accounts: source.accounts
              .where((account) => account.id != goal.accountId)
              .toList(),
        );

        final restored = const BackupRestoreValidator().validate(
          const BackupCodec().encodeJson(withoutHiddenAccount),
        );

        expect(restored.dataSet.goals.single.id, goal.id);
        expect(restored.dataSet.goals.single.isDeleted, isTrue);
        expect(
          restored.dataSet.accounts.where(
            (account) => account.id == goal.accountId,
          ),
          isEmpty,
        );
      },
    );

    test('live Goals still require their linked hidden account', () {
      final source = _richDataSet();
      final goal = source.goals.single;
      final withoutHiddenAccount = source.copyWith(
        accounts: source.accounts
            .where((account) => account.id != goal.accountId)
            .toList(),
      );

      expect(
        () => const BackupRestoreValidator().validate(
          const BackupCodec().encodeJson(withoutHiddenAccount),
        ),
        throwsA(
          isA<BackupValidationException>().having(
            (error) => error.message,
            'message',
            'A Goal is not linked to its expected hidden account.',
          ),
        ),
      );
    });

    test(
      'authoritative cloud replacement defeats newer records, extras, and tombstones',
      () async {
        final remote = _AuthoritativeFakeRepository(
          _contaminatedCloudDataSet(),
        );
        final store = FinanceDataStore(
          dataSet: _contaminatedCloudDataSet(),
          remoteRepository: remote,
          userId: 'user-1',
        );

        await store.restoreBackupDataSet(_richDataSet());
        await store.attachRemoteSync(
          remoteRepository: remote,
          userId: 'user-1',
        );

        expect(remote.authoritativeWrites, 1);
        expect(remote.remoteDataSet.toJson(), _richDataSet().toJson());
        expect(
          store.dataSet.toJson(),
          _withoutDeviceLocalNotificationMetadata(_richDataSet()).toJson(),
        );
        expect(
          store.accounts.map((item) => item.id),
          isNot(contains('fictional')),
        );
        expect(
          store.transactions.map((item) => item.id),
          isNot(contains('fictional-tombstone')),
        );
        expect(store.accountById('card').creditLimitMinor, 500000);
        expect(
          store.transactions
              .firstWhere((item) => item.id == 'expense-1')
              .amountMinor,
          12500,
        );
      },
    );

    test(
      'real backup replaces a complete fictional screenshot session',
      () async {
        final screenshotData = _contaminatedCloudDataSet();
        final remote = _AuthoritativeFakeRepository(screenshotData);
        final store = FinanceDataStore(
          dataSet: screenshotData,
          remoteRepository: remote,
          userId: 'user-1',
        );

        await store.restoreBackupDataSet(_richDataSet());

        expect(
          store.dataSet.toJson(),
          _withoutDeviceLocalNotificationMetadata(_richDataSet()).toJson(),
        );
        expect(remote.remoteDataSet.toJson(), _richDataSet().toJson());
        expect(store.accounts.where((item) => item.id == 'fictional'), isEmpty);
        expect(
          store.transactions.where((item) => item.id.startsWith('fictional')),
          isEmpty,
        );
      },
    );

    test(
      'stale second device accepts a new generation once without republishing old records',
      () async {
        SharedPreferences.setMockInitialValues({});
        final datasetA = _contaminatedCloudDataSet();
        final datasetB = _richDataSet();
        final remote = _AuthoritativeFakeRepository(datasetA);
        const restoringLocal = LocalFinanceDataSetRepository(
          storageKey: 'restoring-device',
        );
        final restoringDevice = FinanceDataStore(
          dataSet: datasetA,
          localRepository: restoringLocal,
          remoteRepository: remote,
          userId: 'user-1',
        );
        await restoringDevice.restoreBackupDataSet(datasetB);

        const staleLocal = LocalFinanceDataSetRepository(
          storageKey: 'stale-second-device',
        );
        await staleLocal.save(datasetA);
        final secondDevice = FinanceDataStore(
          dataSet: datasetA,
          localRepository: staleLocal,
        );

        await secondDevice.attachRemoteSync(
          remoteRepository: remote,
          userId: 'user-1',
        );

        expect(
          secondDevice.dataSet.toJson(),
          _withoutDeviceLocalNotificationMetadata(datasetB).toJson(),
        );
        expect(
          secondDevice.accounts.map((item) => item.id),
          isNot(contains('fictional')),
        );
        expect(
          await staleLocal.loadAcknowledgedRestoreGeneration('user-1'),
          remote.activeGeneration,
        );

        final postRestoreTransaction = TransactionRecord.fromJson(
          Map<String, Object?>.from(datasetB.transactions.first.toJson())
            ..['id'] = 'post-restore-transaction'
            ..['sync'] = SyncMetadata.fresh(
              now: DateTime.utc(2026, 8, 9),
              deviceId: 'second-device',
            ).toJson(),
        );
        await secondDevice.replaceDataSet(
          datasetB.copyWith(
            transactions: [...datasetB.transactions, postRestoreTransaction],
          ),
        );
        await secondDevice.attachRemoteSync(
          remoteRepository: remote,
          userId: 'user-1',
        );

        expect(
          secondDevice.transactions.map((item) => item.id),
          contains('post-restore-transaction'),
        );
        expect(
          remote.remoteDataSet.transactions.map((item) => item.id),
          contains('post-restore-transaction'),
        );
      },
    );

    test('cloud authority failure rolls local data back', () async {
      final before = _fictionalDataSet();
      final remote = _AuthoritativeFakeRepository(before, failReplace: true);
      final store = FinanceDataStore(
        dataSet: before,
        remoteRepository: remote,
        userId: 'user-1',
      );

      await expectLater(
        store.restoreBackupDataSet(_richDataSet()),
        throwsA(isA<StateError>()),
      );
      expect(store.dataSet.toJson(), before.toJson());
      expect(remote.remoteDataSet.toJson(), before.toJson());
    });

    test('local install failure cannot reactivate stale cloud data', () async {
      final before = _fictionalDataSet();
      final remote = _AuthoritativeFakeRepository(before);
      final store = FinanceDataStore(
        dataSet: before,
        localRepository: const _FailingLocalRepository(),
        remoteRepository: remote,
        userId: 'user-1',
      );

      await expectLater(
        store.restoreBackupDataSet(_richDataSet()),
        throwsA(isA<AuthoritativeRestoreLocalInstallException>()),
      );

      expect(store.dataSet.toJson(), before.toJson());
      expect(remote.remoteDataSet.toJson(), _richDataSet().toJson());
    });

    test('pre-restore safety backup is written and verified', () async {
      final directory = await Directory.systemTemp.createTemp(
        'trackmark_safety_backup_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final service = BackupSafetyFileService(
        directoryProvider: () async => directory,
      );
      final content = const BackupCodec().encodeJson(
        _richDataSet(),
        exportedAt: DateTime.utc(2026, 8, 8, 9),
      );

      final saved = await service.savePreRestoreBackup(
        content: content,
        createdAt: DateTime(2026, 8, 8, 9, 5, 6),
      );

      expect(saved.fileName, startsWith('trackmark_money_pre_restore_backup_'));
      expect(await File(saved.path).readAsString(), content);
      expect(
        const BackupRestoreValidator().validate(content).dataSet.toJson(),
        _withoutDeviceLocalNotificationMetadata(_richDataSet()).toJson(),
      );
    });

    test('pre-reset safety backup is written and verified', () async {
      final directory = await Directory.systemTemp.createTemp(
        'trackmark_pre_reset_backup_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final service = BackupSafetyFileService(
        directoryProvider: () async => directory,
      );
      final content = const BackupCodec().encodeJson(
        _richDataSet(),
        exportedAt: DateTime.utc(2026, 8, 23, 9),
      );

      final saved = await service.savePreResetBackup(
        content: content,
        createdAt: DateTime(2026, 8, 23, 9, 5, 6),
      );

      expect(saved.fileName, startsWith('trackmark_money_pre_reset_backup_'));
      expect(await File(saved.path).readAsString(), content);
      expect(
        const BackupRestoreValidator().validate(content).dataSet.toJson(),
        _withoutDeviceLocalNotificationMetadata(_richDataSet()).toJson(),
      );
    });

    test(
      'notification configuration is reconstructable after restore',
      () async {
        final scheduler = _RecordingNotificationScheduler();
        final store = FinanceDataStore(
          dataSet: _emptyDataSet(),
          notificationScheduler: scheduler,
        );

        await store.restoreBackupDataSet(_richDataSet());
        await store.refreshScheduledNotifications();

        expect(store.preferences.notificationsEnabled, isTrue);
        expect(store.preferences.automaticSyncEnabled, isTrue);
        expect(store.preferences.preferredDailySyncMinutes, 22 * 60 + 30);
        expect(scheduler.permissionRequests, greaterThan(0));
        expect(scheduler.scheduledIds, contains('scheduled-expense'));
      },
    );
  });
}

FinanceDataSet _withoutDeviceLocalNotificationMetadata(FinanceDataSet dataSet) {
  return dataSet.copyWith(
    scheduledTransactions: dataSet.scheduledTransactions
        .map(
          (schedule) => schedule.copyWith(
            scheduledNotificationIds: const [],
            clearLastReminderScheduledAt: true,
            sync: schedule.sync,
          ),
        )
        .toList(growable: false),
  );
}

FinanceDataSet _richDataSet() {
  final now = DateTime.utc(2026, 8, 8, 12, 30);
  SyncMetadata sync() => SyncMetadata.fresh(now: now, deviceId: 'test-device');
  final accounts = [
    AccountRecord(
      id: 'checking',
      name: 'Primary Checking',
      type: AccountType.checking,
      openingBalanceMinor: 500000,
      creditCardIconId: 'bank',
      creditCardAccentId: 'teal',
      includeInGroupBalance: true,
      includeInNetWorth: true,
      sortOrder: 100,
      sync: sync(),
    ),
    AccountRecord(
      id: 'cash',
      name: 'Wallet',
      type: AccountType.cash,
      openingBalanceMinor: 10000,
      creditCardIconId: 'wallet',
      creditCardAccentId: 'gold',
      includeInGroupBalance: false,
      includeInNetWorth: true,
      sortOrder: 200,
      sync: sync(),
    ),
    AccountRecord(
      id: 'card',
      name: 'Everyday Card',
      type: AccountType.creditCard,
      openingBalanceMinor: -150000,
      creditLimitMinor: 500000,
      interestEstimationEnabled: true,
      creditInsightsDisclosureAcknowledged: true,
      annualPercentageRate: 28.49,
      statementClosingDay: 8,
      paymentDueDay: 4,
      creditCardIconId: 'creditCardFill',
      creditCardAccentId: 'indigo',
      sortOrder: 300,
      sync: sync(),
    ),
    AccountRecord(
      id: 'loan',
      name: 'Auto Loan',
      type: AccountType.loan,
      openingBalanceMinor: -2000000,
      originalLoanAmountMinor: 2500000,
      creditCardIconId: 'car',
      creditCardAccentId: 'slate',
      sortOrder: 400,
      sync: sync(),
    ),
    AccountRecord(
      id: 'goal-account',
      name: 'Emergency Goal',
      type: AccountType.savings,
      openingBalanceMinor: 25000,
      goalId: 'goal-1',
      sortOrder: 500,
      sync: sync(),
    ),
  ];
  final categories = [
    CategoryRecord(
      id: 'income',
      name: 'Income',
      kind: CategoryKind.income,
      iconName: 'briefcase',
      colorValue: 0xFF0F766E,
      sync: sync(),
    ),
    CategoryRecord(
      id: 'groceries',
      name: 'Groceries',
      kind: CategoryKind.expense,
      iconName: 'cart',
      colorValue: 0xFF2563EB,
      sync: sync(),
    ),
    CategoryRecord(
      id: 'snacks',
      name: 'Snacks',
      kind: CategoryKind.expense,
      parentCategoryId: 'groceries',
      iconName: 'food',
      colorValue: 0xFFD97706,
      isArchived: true,
      sync: sync(),
    ),
  ];
  final transactions = [
    TransactionRecord(
      id: 'income-1',
      type: TransactionType.income,
      accountId: 'checking',
      categoryId: 'income',
      date: DateTime(2026, 8, 1, 8, 42),
      payee: 'Payroll',
      amountMinor: 100000,
      note: 'August pay',
      status: TransactionStatus.reconciled,
      sync: sync(),
    ),
    TransactionRecord(
      id: 'expense-1',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'groceries',
      date: DateTime(2026, 8, 2, 19, 15),
      payee: 'Market',
      amountMinor: 12500,
      note: 'Weekly shop',
      status: TransactionStatus.pending,
      sync: sync(),
    ),
    TransactionRecord(
      id: 'transfer-1',
      type: TransactionType.transfer,
      accountId: 'checking',
      transferAccountId: 'card',
      date: DateTime(2026, 8, 3, 10, 11),
      payee: 'Everyday Card',
      amountMinor: 25000,
      note: 'Card payment',
      sync: sync(),
    ),
    TransactionRecord(
      id: 'adjustment-1',
      type: TransactionType.adjustment,
      accountId: 'cash',
      date: DateTime(2026, 8, 4, 12, 1),
      payee: 'Balance adjustment',
      amountMinor: -100,
      note: 'Counted wallet',
      sync: sync(),
    ),
    TransactionRecord(
      id: 'split-1',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'groceries',
      date: DateTime(2026, 8, 5, 21, 9),
      payee: 'Superstore',
      amountMinor: 25000,
      splitLines: const [
        TransactionSplitLine(
          id: 'split-line-1',
          categoryId: 'groceries',
          amountMinor: 20000,
          note: 'Groceries',
        ),
        TransactionSplitLine(
          id: 'split-line-2',
          categoryId: 'snacks',
          amountMinor: 5000,
          note: 'Snacks',
        ),
      ],
      sync: sync(),
    ),
    TransactionRecord(
      id: 'scheduled-ledger-1',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'groceries',
      date: DateTime(2026, 7, 8, 9, 30),
      payee: 'Scheduled Market',
      amountMinor: 10000,
      scheduledTransactionId: 'scheduled-expense',
      scheduledOccurrenceDate: DateTime(2026, 7, 8),
      scheduledPlannedAmountMinor: 10000,
      sync: sync(),
    ),
  ];
  final scheduled = [
    ScheduledTransactionRecord(
      id: 'scheduled-expense',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'groceries',
      payee: 'Scheduled Market',
      amountMinor: 10000,
      nextDate: DateTime(2026, 9, 8),
      frequency: RecurrenceFrequency.monthly,
      alertPreference: AlertPreference.oneDayBefore,
      repeatAlertUntilResolved: true,
      scheduledNotificationIds: const [1234],
      lastReminderScheduledAt: DateTime(2026, 8, 7, 9),
      occurrences: [
        ScheduledOccurrenceRecord(
          scheduledDate: DateTime(2026, 7, 8),
          plannedAmountMinor: 10000,
          status: ScheduledOccurrenceStatus.paid,
          actualAmountMinor: 10000,
          actualPaymentDate: DateTime(2026, 7, 8, 9, 30),
          transactionId: 'scheduled-ledger-1',
        ),
      ],
      sync: sync(),
    ),
    ScheduledTransactionRecord(
      id: 'scheduled-transfer',
      type: TransactionType.transfer,
      accountId: 'checking',
      transferAccountId: 'card',
      payee: 'Everyday Card',
      amountMinor: 20000,
      nextDate: DateTime(2026, 8, 28),
      frequency: RecurrenceFrequency.monthly,
      sync: sync(),
    ),
    ScheduledTransactionRecord(
      id: 'scheduled-split',
      type: TransactionType.expense,
      accountId: 'checking',
      categoryId: 'groceries',
      payee: 'Split Store',
      amountMinor: 3000,
      nextDate: DateTime(2026, 8, 15),
      frequency: RecurrenceFrequency.weekly,
      splitLines: const [
        TransactionSplitLine(
          id: 'scheduled-split-1',
          categoryId: 'groceries',
          amountMinor: 2000,
        ),
        TransactionSplitLine(
          id: 'scheduled-split-2',
          categoryId: 'snacks',
          amountMinor: 1000,
        ),
      ],
      sync: sync(),
    ),
  ];
  final goal = GoalRecord(
    id: 'goal-1',
    name: 'Emergency Fund',
    description: 'Three months of expenses',
    targetAmountMinor: 500000,
    status: GoalStatus.active,
    fundingMethod: GoalFundingMethod.accountFunded,
    goalType: GoalType.reachTarget,
    targetDate: DateTime(2027, 1, 1),
    defaultFundingAccountId: 'checking',
    accountId: 'goal-account',
    accountMigrationVersion: 1,
    sync: sync(),
  );
  final fundingEvent = GoalFundingEventRecord(
    id: 'funding-event-1',
    sourceAccountId: 'checking',
    totalAmountMinor: 25000,
    date: DateTime(2026, 8, 6, 17, 30),
    note: 'Initial funding',
    allocations: const [
      GoalFundingAllocation(
        id: 'funding-allocation-1',
        fundingEventId: 'funding-event-1',
        goalId: 'goal-1',
        amountMinor: 25000,
        order: 0,
      ),
    ],
    sync: sync(),
  );
  final budget = BudgetRecord(
    id: 'budget-1',
    name: 'Groceries',
    period: BudgetPeriod.biweekly,
    amountMinor: 40000,
    categoryIds: const ['groceries'],
    startDate: DateTime(2026, 8, 1),
    anchorDate: DateTime(2026, 8, 1),
    weekStartDay: DateTime.saturday,
    rolloverEnabled: true,
    includeSubcategories: true,
    lowBudgetAlertEnabled: true,
    lowBudgetAlertThresholdBasisPoints: 500,
    note: 'Food plan',
    configurationRevisions: [
      BudgetConfigurationRevision(
        id: 'budget-revision-1',
        effectiveDate: DateTime(2026, 8, 1),
        period: BudgetPeriod.biweekly,
        amountMinor: 40000,
        categoryIds: const ['groceries'],
        startDate: DateTime(2026, 8, 1),
        anchorDate: DateTime(2026, 8, 1),
        weekStartDay: DateTime.saturday,
        rolloverEnabled: true,
      ),
    ],
    sync: sync(),
  );
  return FinanceDataSet(
    accounts: accounts,
    categories: categories,
    transactions: transactions,
    scheduledTransactions: scheduled,
    budgets: [budget],
    goals: [goal],
    goalContributions: [
      GoalContributionRecord(
        id: 'goal-contribution-1',
        goalId: 'goal-1',
        amountMinor: 25000,
        date: DateTime(2026, 8, 6, 17, 30),
        sourceAccountId: 'checking',
        fundingMethod: GoalFundingMethod.accountFunded,
        note: 'Legacy-compatible history',
        sync: sync(),
      ),
    ],
    goalFundingEvents: [fundingEvent],
    preferences: const UserPreferences(
      launchScreen: LaunchScreen.accounts,
      preferredPlanSegment: PlanSegment.goals,
      appearanceMode: AppearanceMode.dark,
      floatingAddButtonPosition: FloatingAddButtonPosition.left,
      currency: CurrencyFormatSettings(
        currencyCode: 'USD',
        symbol: r'$',
        decimalPlaces: 2,
      ),
      defaultTransactionType: DefaultTransactionType.expense,
      defaultTransactionAccountMode: AccountDefaultMode.specific,
      defaultTransactionAccountId: 'checking',
      defaultTransferSourceMode: AccountDefaultMode.specific,
      defaultTransferSourceAccountId: 'checking',
      notificationsEnabled: true,
      automaticSyncEnabled: true,
      preferredDailySyncMinutes: 22 * 60 + 30,
      collapsedAccountGroupNames: {'loans'},
      accountGroupOrderNames: ['cash', 'banking', 'creditCards', 'loans'],
      accountGroupLabelOverrides: {'banking': 'Banking'},
      savedPayeeNames: ['Payroll', 'Market'],
      archivedPayeeNames: {'old payee'},
      deletedPayeeNames: {'deleted payee'},
      legacyV1MigrationCompleted: true,
    ),
  );
}

FinanceDataSet _fictionalDataSet() {
  final sync = SyncMetadata.fresh(now: DateTime.utc(2026, 8, 9));
  return FinanceDataSet(
    accounts: [
      AccountRecord(
        id: 'fictional',
        name: 'Screenshot Checking',
        type: AccountType.checking,
        openingBalanceMinor: 999999,
        sync: sync,
      ),
    ],
    categories: const [],
    transactions: [
      TransactionRecord(
        id: 'fictional-tombstone',
        type: TransactionType.adjustment,
        accountId: 'fictional',
        date: DateTime(2026, 8, 9),
        payee: 'Test',
        amountMinor: 1,
        sync: sync.deleted(now: DateTime.utc(2026, 8, 10)),
      ),
    ],
    scheduledTransactions: const [],
    budgets: const [],
    preferences: const UserPreferences(legacyV1MigrationCompleted: true),
  );
}

FinanceDataSet _contaminatedCloudDataSet() {
  final rich = _richDataSet();
  final newer = SyncMetadata(
    createdAt: DateTime.utc(2026, 8, 8),
    updatedAt: DateTime.utc(2026, 8, 10),
    deviceId: 'cloud-before-restore',
    version: 999,
  );
  final fictional = _fictionalDataSet();
  return rich.copyWith(
    accounts: [
      for (final account in rich.accounts)
        if (account.id == 'card')
          account.copyWith(
            name: 'Stale Cloud Card',
            creditLimitMinor: 9999999,
            sortOrder: 999,
            sync: newer,
          )
        else
          account,
      ...fictional.accounts,
    ],
    transactions: [
      for (final transaction in rich.transactions)
        if (transaction.id == 'expense-1')
          transaction.copyWith(amountMinor: 990000, sync: newer)
        else
          transaction,
      ...fictional.transactions,
    ],
  );
}

FinanceDataSet _emptyDataSet() => const FinanceDataSet(
  accounts: [],
  categories: [],
  transactions: [],
  scheduledTransactions: [],
  budgets: [],
  preferences: UserPreferences(),
);

class _AuthoritativeFakeRepository implements FinanceRecordRepository {
  _AuthoritativeFakeRepository(this.remoteDataSet, {this.failReplace = false});

  FinanceDataSet remoteDataSet;
  final bool failReplace;
  var authoritativeWrites = 0;
  String? activeGeneration;

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async => remoteDataSet;

  @override
  Future<String?> activeRestoreGeneration(String userId) async =>
      activeGeneration;

  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async {
    if (failReplace) throw StateError('Cloud replacement failed');
    authoritativeWrites += 1;
    remoteDataSet = dataSet;
    return activeGeneration = 'restore-$authoritativeWrites';
  }

  @override
  Future<void> saveAccount({
    required String userId,
    required AccountRecord account,
  }) async {}
  @override
  Future<void> saveBudget({
    required String userId,
    required BudgetRecord budget,
  }) async {}
  @override
  Future<void> saveCategory({
    required String userId,
    required CategoryRecord category,
  }) async {}
  @override
  Future<void> saveGoal({
    required String userId,
    required GoalRecord goal,
  }) async {}
  @override
  Future<void> saveGoalContribution({
    required String userId,
    required GoalContributionRecord contribution,
  }) async {}
  @override
  Future<void> saveGoalFundingEvent({
    required String userId,
    required GoalFundingEventRecord fundingEvent,
  }) async {}
  @override
  Future<void> savePreferences({
    required String userId,
    required UserPreferences preferences,
  }) async {}
  @override
  Future<void> saveScheduledTransaction({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {}
  @override
  Future<void> saveTransaction({
    required String userId,
    required TransactionRecord transaction,
  }) async {
    remoteDataSet = remoteDataSet.copyWith(
      transactions: _replaceById(
        remoteDataSet.transactions,
        transaction,
        (item) => item.id,
      ),
    );
  }

  List<T> _replaceById<T>(
    List<T> records,
    T replacement,
    String Function(T item) idOf,
  ) {
    return [
      for (final record in records)
        if (idOf(record) == idOf(replacement)) replacement else record,
      if (!records.any((record) => idOf(record) == idOf(replacement)))
        replacement,
    ];
  }

  @override
  Stream<FinanceDataSet> watchDataSet(String userId) async* {
    yield remoteDataSet;
  }
}

class _RecordingNotificationScheduler implements NotificationScheduler {
  var permissionRequests = 0;
  final scheduledIds = <String>[];

  @override
  Future<void> cancelScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {}
  @override
  Future<bool> requestPermissionIfNeeded() async {
    permissionRequests += 1;
    return true;
  }

  @override
  Future<void> rescheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {}
  @override
  Future<List<int>> scheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    scheduledIds.add(scheduledTransaction.id);
    return [scheduledTransaction.id.hashCode];
  }

  @override
  Future<void> updateBadgeCount(int dueOrOverdueCount) async {}
}

class _FailingLocalRepository extends LocalFinanceDataSetRepository {
  const _FailingLocalRepository();

  @override
  Future<void> save(FinanceDataSet dataSet) {
    throw StateError('Local storage unavailable');
  }
}
