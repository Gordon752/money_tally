import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as v1;
import 'package:money_tally/src/domain/transaction.dart' as v2_transaction;
import 'package:money_tally/src/domain/account.dart' as v2_account;
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/migration/finance_data_bootstrapper.dart';
import 'package:money_tally/src/migration/v1_snapshot_migrator.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('v1 migration preserves visible account balances', () {
    final snapshot = v1.FinanceStore.seeded().snapshot();
    final migrated = const V1SnapshotMigrator().migrate(snapshot.toJson());

    for (final account in snapshot.accounts) {
      expect(migrated.balanceForAccount(account.id), account.balanceCents);
    }

    expect(migrated.accounts.first.id, snapshot.accounts.first.id);
    expect(
      migrated.transactions.first.type,
      v2_transaction.TransactionType.expense,
    );
    expect(migrated.transactions.first.amountMinor, 6428);
    expect(
      migrated.transactions.last.type,
      v2_transaction.TransactionType.income,
    );
    expect(migrated.transactions.last.amountMinor, 126400);
    expect(migrated.budgets.first.categoryIds, ['dining']);
  });

  test('v1 transfer without destination migrates as an adjustment', () {
    final sync = v1.SyncMetadata.fresh(now: DateTime(2026, 7, 6));
    final snapshot = v1.FinanceSnapshot(
      accounts: [
        v1.Account(
          id: 'checking',
          name: 'Checking',
          type: v1.AccountType.checking,
          balanceCents: 10000,
          sync: sync,
        ),
      ],
      categories: [
        v1.LedgerCategory(
          id: 'transfer',
          name: 'Transfer',
          kind: v1.CategoryKind.transfer,
          color: const Color(0xFF00796B),
          sync: sync,
        ),
      ],
      transactions: [
        v1.LedgerTransaction(
          id: 'legacy-transfer',
          accountId: 'checking',
          categoryId: 'transfer',
          date: DateTime(2026, 7, 6),
          payee: 'Legacy transfer',
          amountCents: -2500,
          isTransfer: true,
          sync: sync,
        ),
      ],
      scheduled: const [],
      budgets: const [],
    );

    final migrated = const V1SnapshotMigrator().migrate(snapshot.toJson());
    final transaction = migrated.transactions.single;

    expect(transaction.type, v2_transaction.TransactionType.adjustment);
    expect(transaction.categoryId, isNull);
    expect(transaction.amountMinor, -2500);
    expect(transaction.note, contains('Migrated transfer without destination'));
    expect(migrated.accounts.single.openingBalanceMinor, 12500);
    expect(migrated.balanceForAccount('checking'), 10000);
  });

  test(
    'bootstrapper imports legacy-only data once and marks v2 complete',
    () async {
      SharedPreferences.setMockInitialValues({});
      final v1Repository = const v1.LocalFinanceRepository();
      final v2Repository = const LocalFinanceDataSetRepository(
        storageKey: 'test_money_tally_v2',
      );
      final snapshot = v1.FinanceStore.seeded().snapshot();
      await v1Repository.save(snapshot);

      final bootstrapper = FinanceDataBootstrapper(
        localRepository: v2Repository,
      );

      final migrated = await bootstrapper.loadDataSet();
      final savedV2 = await v2Repository.load();

      expect(savedV2, isNotNull);
      expect(migrated.accounts.length, snapshot.accounts.length);
      expect(migrated.balanceForAccount('checking'), 185240);
      expect(migrated.preferences.legacyV1MigrationCompleted, isTrue);
      expect(savedV2!.preferences.legacyV1MigrationCompleted, isTrue);
    },
  );

  test(
    'completed migration never reads or merges the legacy snapshot again',
    () async {
      SharedPreferences.setMockInitialValues({});
      const repository = LocalFinanceDataSetRepository(
        storageKey: 'completed_migration_v2',
      );
      var legacyReads = 0;
      final snapshot = v1.FinanceStore.seeded().snapshot().toJson();
      final bootstrapper = FinanceDataBootstrapper(
        localRepository: repository,
        v1SnapshotLoader: () async {
          legacyReads++;
          return snapshot;
        },
      );

      final first = await bootstrapper.loadDataSet();
      final second = await bootstrapper.loadDataSet();

      expect(legacyReads, 1);
      expect(second.toJson(), first.toJson());
      expect(second.preferences.legacyV1MigrationCompleted, isTrue);
    },
  );

  test(
    'mixed migration retains every colliding v2 field and adds missing IDs',
    () async {
      SharedPreferences.setMockInitialValues({});
      const repository = LocalFinanceDataSetRepository(
        storageKey: 'mixed_migration_v2',
      );
      final legacySnapshot = v1.FinanceStore.seeded().snapshot().toJson();
      final currentAccount = v2_account.AccountRecord(
        id: 'checking',
        name: 'Primary Checking',
        type: v2_account.AccountType.creditCard,
        openingBalanceMinor: -12345,
        creditLimitMinor: 500000,
        includeInGroupBalance: false,
        includeInNetWorth: false,
        sortOrder: 700,
        sync: v2_sync.SyncMetadata.fresh(),
      );
      final current = FinanceDataSet(
        accounts: [currentAccount],
        categories: const [],
        transactions: const [],
        scheduledTransactions: const [],
        budgets: const [],
        preferences: const UserPreferences(),
      );
      await repository.save(current);

      final migrated = await FinanceDataBootstrapper(
        localRepository: repository,
        v1SnapshotLoader: () async => legacySnapshot,
      ).loadDataSet();

      expect(
        migrated.accounts
            .singleWhere((account) => account.id == currentAccount.id)
            .toJson(),
        currentAccount.toJson(),
      );
      expect(migrated.accounts.map((account) => account.id), contains('cash'));
      expect(migrated.preferences.legacyV1MigrationCompleted, isTrue);
    },
  );

  test(
    'an interrupted migration safely retries without duplicate records',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = _FailFirstSaveRepository(
        storageKey: 'interrupted_migration_v2',
      );
      final snapshot = v1.FinanceStore.seeded().snapshot().toJson();
      var legacyReads = 0;
      final bootstrapper = FinanceDataBootstrapper(
        localRepository: repository,
        v1SnapshotLoader: () async {
          legacyReads++;
          return snapshot;
        },
      );

      await expectLater(bootstrapper.loadDataSet(), throwsA(isA<StateError>()));
      final migrated = await bootstrapper.loadDataSet();
      final persisted = await repository.load();

      expect(legacyReads, 2);
      expect(persisted!.toJson(), migrated.toJson());
      expect(
        migrated.accounts.map((account) => account.id).toSet().length,
        migrated.accounts.length,
      );
      expect(migrated.preferences.legacyV1MigrationCompleted, isTrue);
    },
  );

  test(
    'v2 tombstones survive import and restart without a legacy reread',
    () async {
      SharedPreferences.setMockInitialValues({});
      const repository = LocalFinanceDataSetRepository(
        storageKey: 'tombstone_migration_v2',
      );
      final snapshot = v1.FinanceStore.seeded().snapshot().toJson();
      final migratedLegacy = const V1SnapshotMigrator().migrate(snapshot);
      final deleted = migratedLegacy.transactions.first.copyWith(
        sync: migratedLegacy.transactions.first.sync.deleted(),
      );
      await repository.save(
        migratedLegacy.copyWith(
          transactions: [deleted, ...migratedLegacy.transactions.skip(1)],
        ),
      );

      final first = await FinanceDataBootstrapper(
        localRepository: repository,
        v1SnapshotLoader: () async => snapshot,
      ).loadDataSet();
      final restored = await FinanceDataBootstrapper(
        localRepository: repository,
        v1SnapshotLoader: () async => throw StateError('legacy was reread'),
      ).loadDataSet();

      expect(
        first.transactions
            .singleWhere((transaction) => transaction.id == deleted.id)
            .isDeleted,
        isTrue,
      );
      expect(restored.toJson(), first.toJson());
    },
  );

  test('post-migration record sync uses v2 records only', () async {
    SharedPreferences.setMockInitialValues({});
    const repository = LocalFinanceDataSetRepository(
      storageKey: 'post_migration_sync_v2',
    );
    final snapshot = v1.FinanceStore.seeded().snapshot().toJson();
    final migrated = await FinanceDataBootstrapper(
      localRepository: repository,
      v1SnapshotLoader: () async => snapshot,
    ).loadDataSet();
    final remote = _MigrationRecordRepository();
    final store = FinanceDataStore(
      dataSet: migrated,
      localRepository: repository,
    );

    await store.attachRemoteSync(remoteRepository: remote, userId: 'user-1');

    expect(remote.accounts.map((record) => record.id), isNotEmpty);
    expect(remote.categories.map((record) => record.id), isNotEmpty);
    expect(remote.transactions.map((record) => record.id), isNotEmpty);
    expect(remote.scheduled.map((record) => record.id), isNotEmpty);
    expect(remote.budgets.map((record) => record.id), isNotEmpty);
    expect(remote.preferences?.legacyV1MigrationCompleted, isTrue);
  });

  test(
    'new legacy device keeps richer cloud v2 records authoritative',
    () async {
      SharedPreferences.setMockInitialValues({});
      const repository = LocalFinanceDataSetRepository(
        storageKey: 'legacy_device_cloud_v2',
      );
      final snapshot = v1.FinanceStore.seeded().snapshot().toJson();
      final bootstrapper = FinanceDataBootstrapper(
        localRepository: repository,
        v1SnapshotLoader: () async => snapshot,
      );
      final store = await bootstrapper.loadStore();
      final localChecking = store.accountById('checking');
      final cloudChecking = localChecking.copyWith(
        name: 'Cloud Checking',
        type: v2_account.AccountType.creditCard,
        openingBalanceMinor: -54321,
        creditLimitMinor: 900000,
        includeInGroupBalance: false,
        includeInNetWorth: false,
        sortOrder: 900,
      );
      final cloudGoal = GoalRecord(
        id: 'cloud-goal',
        name: 'Cloud Goal',
        targetAmountMinor: 500000,
        status: GoalStatus.active,
        fundingMethod: GoalFundingMethod.accountFunded,
        accountId: 'goal_account_cloud-goal',
        accountMigrationVersion: 1,
        sync: v2_sync.SyncMetadata.fresh(),
      );
      final cloudGoalAccount = v2_account.AccountRecord(
        id: 'goal_account_cloud-goal',
        name: 'Cloud Goal',
        type: v2_account.AccountType.savings,
        openingBalanceMinor: 25000,
        goalId: cloudGoal.id,
        includeInGroupBalance: false,
        includeInNetWorth: true,
        sortOrder: 910,
        sync: v2_sync.SyncMetadata.fresh(),
      );
      final cloudTombstone = store.transactions.first.copyWith(
        sync: store.transactions.first.sync.deleted(),
      );
      final cloudSchedule = store.scheduledTransactions.first.copyWith(
        payee: 'Cloud scheduled item',
      );
      final remote = _MigrationRecordRepository(
        remoteDataSet: FinanceDataSet(
          accounts: [cloudChecking, cloudGoalAccount],
          categories: store.categories,
          transactions: [cloudTombstone],
          scheduledTransactions: [cloudSchedule],
          budgets: store.budgets,
          goals: [cloudGoal],
          preferences: const UserPreferences(),
        ),
      );

      await store.attachRemoteSync(remoteRepository: remote, userId: 'user-1');

      expect(store.accountById('checking').toJson(), cloudChecking.toJson());
      expect(
        store.accountById(cloudGoalAccount.id).toJson(),
        cloudGoalAccount.toJson(),
      );
      expect(store.goalById(cloudGoal.id).toJson(), cloudGoal.toJson());
      expect(
        store.transactions
            .singleWhere((transaction) => transaction.id == cloudTombstone.id)
            .isDeleted,
        isTrue,
      );
      expect(
        store.scheduledTransactions
            .singleWhere((schedule) => schedule.id == cloudSchedule.id)
            .toJson(),
        cloudSchedule.toJson(),
      );
      expect(store.accounts.map((account) => account.id), contains('cash'));
      expect(
        store.accounts.map((account) => account.id).toSet().length,
        store.accounts.length,
      );
      expect(
        store.transactions.map((transaction) => transaction.id).toSet().length,
        store.transactions.length,
      );
    },
  );

  test('restored older v2 backup marks completion before restart', () async {
    SharedPreferences.setMockInitialValues({});
    const repository = LocalFinanceDataSetRepository(
      storageKey: 'restored_backup_v2',
    );
    final olderBackup = const V1SnapshotMigrator()
        .migrate(v1.FinanceStore.seeded().snapshot().toJson())
        .copyWith(preferences: const UserPreferences());
    final decodedBackup = const BackupCodec().decodeJson(
      const BackupCodec().encodeJson(olderBackup),
    );
    final store = FinanceDataStore(
      dataSet: const FinanceDataSet(
        accounts: [],
        categories: [],
        transactions: [],
        scheduledTransactions: [],
        budgets: [],
        preferences: UserPreferences(),
      ),
      localRepository: repository,
    );

    await store.restoreBackupDataSet(decodedBackup);
    final expected = store.dataSet;
    final restarted = await FinanceDataBootstrapper(
      localRepository: repository,
      v1SnapshotLoader: () async => throw StateError('legacy was reread'),
    ).loadDataSet();

    expect(expected.preferences.legacyV1MigrationCompleted, isTrue);
    expect(restarted.toJson(), expected.toJson());
  });
}

class _FailFirstSaveRepository extends LocalFinanceDataSetRepository {
  _FailFirstSaveRepository({required super.storageKey});

  var _shouldFail = true;

  @override
  Future<void> save(FinanceDataSet dataSet) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('Simulated interrupted migration write');
    }
    await super.save(dataSet);
  }
}

class _MigrationRecordRepository implements FinanceRecordRepository {
  _MigrationRecordRepository({FinanceDataSet? remoteDataSet})
    : remoteDataSet =
          remoteDataSet ??
          const FinanceDataSet(
            accounts: [],
            categories: [],
            transactions: [],
            scheduledTransactions: [],
            budgets: [],
            preferences: UserPreferences(),
          );

  final FinanceDataSet remoteDataSet;
  final accounts = <v2_account.AccountRecord>[];
  final categories = <CategoryRecord>[];
  final transactions = <TransactionRecord>[];
  final scheduled = <ScheduledTransactionRecord>[];
  final budgets = <BudgetRecord>[];
  UserPreferences? preferences;

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async => remoteDataSet;

  @override
  Future<void> saveAccount({
    required String userId,
    required v2_account.AccountRecord account,
  }) async => accounts.add(account);

  @override
  Future<void> saveBudget({
    required String userId,
    required BudgetRecord budget,
  }) async => budgets.add(budget);

  @override
  Future<void> saveCategory({
    required String userId,
    required CategoryRecord category,
  }) async => categories.add(category);

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
  }) async => this.preferences = preferences;

  @override
  Future<void> saveScheduledTransaction({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async => scheduled.add(scheduledTransaction);

  @override
  Future<void> saveTransaction({
    required String userId,
    required TransactionRecord transaction,
  }) async => transactions.add(transaction);

  @override
  Stream<FinanceDataSet> watchDataSet(String userId) => const Stream.empty();
}
