import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/sync/cloud_sync_coordinator.dart';

void main() {
  testWidgets(
    'timed-out persistence cannot leave a concurrent edit stale on disk',
    (tester) async {
      final remote = _Remote();
      final local = _Local(_data('initial'));
      final store = FinanceDataStore(
        dataSet: local.saved,
        localRepository: local,
      );
      final coordinator = CloudSyncCoordinator(
        recordRepository: remote,
        executionStateStore: _State(),
      );
      final a = coordinator.synchronize(
        userId: 'user',
        dataStore: store,
        timeout: const Duration(seconds: 1),
      );
      await tester.pump();
      remote.loads.single.complete(_data('stale'));
      await tester.pump();
      await store.saveAccount(store.accounts.single.copyWith(name: 'Edited'));
      await tester.pump(const Duration(seconds: 1));
      expect(await a, isFalse);
      local.finish.complete();
      await tester.pump();
      expect(store.accounts.single.name, 'Edited');
      expect(local.saved.toJson(), store.dataSet.toJson());
    },
  );
  for (final signOut in [false, true]) {
    testWidgets(
      'authority loss before timeout rejects a delayed result ($signOut)',
      (tester) async {
        final remote = _Remote();
        final coordinator = CloudSyncCoordinator(
          recordRepository: remote,
          executionStateStore: _State(),
        );
        final store = FinanceDataStore(dataSet: _data('initial'));
        final pending = coordinator.synchronize(
          userId: 'user',
          dataStore: store,
        );
        await tester.pump();
        if (signOut) {
          store.detachRemoteSync();
          coordinator.reset();
        } else {
          await store.resetTrackmarkData();
        }
        final expected = store.dataSet.toJson();
        remote.loads.single.complete(_data('stale'));
        await tester.pump();
        expect(await pending, isFalse);
        expect(store.dataSet.toJson(), expected);
        expect(coordinator.status, CloudSyncStatus.idle);
      },
    );
  }
  testWidgets('repeated retries cannot bypass an in-flight write fence', (
    tester,
  ) async {
    final remote = _WritingRemote();
    final state = _State();
    final coordinator = CloudSyncCoordinator(
      recordRepository: remote,
      executionStateStore: state,
    );
    final store = FinanceDataStore(dataSet: _data('initial'));
    final a = coordinator.synchronize(
      userId: 'user',
      dataStore: store,
      timeout: const Duration(seconds: 1),
    );
    await tester.pump();
    remote.loads.single.complete(_data('a'));
    await tester.pump();
    expect(remote.startedWrites, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(await a, isFalse);
    final b = coordinator.synchronize(
      userId: 'user',
      dataStore: store,
      timeout: const Duration(seconds: 1),
    );
    await tester.pump();
    expect(remote.loads, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(await b, isFalse);
    final c = coordinator.synchronize(userId: 'user', dataStore: store);
    await tester.pump();
    expect(remote.loads, hasLength(1));
    remote.finishWrite.complete();
    await tester.pump();
    expect(remote.loads, hasLength(2));
    remote.loads.last.complete(_data('winner'));
    await tester.pump();
    expect(await c, isTrue);
    expect(remote.startedWrites, 2);
    expect(coordinator.status, CloudSyncStatus.synced);
  });

  for (final reset in [false, true]) {
    testWidgets(
      'late local persistence settles before ${reset ? "reset" : "restore"}',
      (tester) async {
        final remote = _Remote();
        final local = _Local(_data('initial'));
        final store = FinanceDataStore(
          dataSet: local.saved,
          localRepository: local,
        );
        final coordinator = CloudSyncCoordinator(
          recordRepository: remote,
          executionStateStore: _State(),
        );
        final a = coordinator.synchronize(
          userId: 'user',
          dataStore: store,
          timeout: const Duration(seconds: 1),
        );
        await tester.pump();
        remote.loads.single.complete(_data('stale'));
        await tester.pump();
        expect(local.started, isTrue);
        await tester.pump(const Duration(seconds: 1));
        expect(await a, isFalse);
        var restored = false;
        final restore =
            (reset
                    ? store.resetTrackmarkData()
                    : store.restoreBackupDataSet(_data('restored')))
                .then((_) => restored = true);
        await tester.pump();
        expect(restored, isFalse);
        local.finish.complete();
        await tester.pump();
        await restore;
        expect(store.accounts.map((x) => x.id), reset ? isEmpty : ['restored']);
        expect(local.saved.toJson(), store.dataSet.toJson());
      },
    );
  }
  for (final boundary in [
    'new attempt',
    'sign out',
    'restore',
    'reset',
    'repeated attempts',
  ]) {
    testWidgets('late timed-out load cannot apply after $boundary', (
      tester,
    ) async {
      final remote = _Remote();
      final state = _State();
      final coordinator = CloudSyncCoordinator(
        recordRepository: remote,
        executionStateStore: state,
      );
      final store = FinanceDataStore(dataSet: _data('initial'));
      final a = coordinator.synchronize(
        userId: 'user',
        dataStore: store,
        timeout: const Duration(seconds: 1),
      );
      await tester.pump();
      expect(remote.loads, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(await a, isFalse);
      expect(state.leased, isFalse);

      if (boundary == 'sign out') {
        store.detachRemoteSync();
        coordinator.reset();
      } else if (boundary == 'restore') {
        await store.restoreBackupDataSet(_data('restored'));
      } else if (boundary == 'reset') {
        await store.resetTrackmarkData();
      } else {
        if (boundary == 'repeated attempts') {
          final b = coordinator.synchronize(
            userId: 'user',
            dataStore: store,
            timeout: const Duration(seconds: 1),
          );
          final duplicate = coordinator.synchronize(
            userId: 'user',
            dataStore: store,
          );
          expect(identical(b, duplicate), isTrue);
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(await b, isFalse);
        }
        final latest = coordinator.synchronize(
          userId: 'user',
          dataStore: store,
        );
        await tester.pump();
        remote.loads.last.complete(_data('winner'));
        await tester.pump();
        expect(await latest, isTrue);
      }
      final expected = store.dataSet.toJson();
      final writes = remote.writes;
      for (final load in remote.loads.where((x) => !x.isCompleted)) {
        load.complete(_data('stale'));
      }
      await tester.pump();
      expect(
        store.dataSet.toJson(),
        expected,
        reason: 'stale work installed a dataset',
      );
      expect(remote.writes, writes, reason: 'stale work published records');
      if (boundary == 'sign out') {
        expect(coordinator.status, CloudSyncStatus.idle);
        expect(store.hasRemoteSync, isFalse);
      }
    });
  }
}

FinanceDataSet _data(String id) => FinanceDataSet(
  accounts: [
    AccountRecord(
      id: id,
      name: id,
      type: AccountType.checking,
      openingBalanceMinor: 10000,
      sync: SyncMetadata.fresh(),
    ),
  ],
  categories: const [],
  transactions: const [],
  scheduledTransactions: const [],
  budgets: const [],
  preferences: const UserPreferences(),
);

class _Remote implements FinanceRecordRepository {
  final loads = <Completer<FinanceDataSet>>[];
  int writes = 0;
  @override
  Future<String?> activeRestoreGeneration(String userId) async => null;
  @override
  Future<FinanceDataSet> loadDataSet(String userId) {
    final load = Completer<FinanceDataSet>();
    loads.add(load);
    return load.future;
  }

  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async => 'restored';
  @override
  dynamic noSuchMethod(Invocation invocation) {
    writes++;
    return Future<void>.value();
  }
}

class _State implements SyncExecutionStateStore {
  bool leased = false;
  @override
  Future<bool> tryAcquireLease(
    String userId, {
    required DateTime now,
    Duration duration = const Duration(minutes: 2),
  }) async {
    if (leased) return false;
    leased = true;
    return true;
  }

  @override
  Future<void> releaseLease(String userId) async {
    leased = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _WritingRemote extends _Remote implements BulkFinanceRecordRepository {
  final finishWrite = Completer<void>();
  int startedWrites = 0;
  @override
  Future<void> saveDataSet({
    required String userId,
    required FinanceDataSet dataSet,
    FinanceDataSet? baseline,
  }) async {
    if (++startedWrites == 1) await finishWrite.future;
  }
}

class _Local extends LocalFinanceDataSetRepository {
  _Local(this.saved);
  FinanceDataSet saved;
  final finish = Completer<void>();
  bool started = false;
  @override
  Future<void> save(FinanceDataSet dataSet) async {
    if (!started) {
      started = true;
      await finish.future;
    }
    saved = dataSet;
  }

  @override
  Future<String?> loadAcknowledgedRestoreGeneration(String userId) async =>
      null;
  @override
  Future<void> saveAcknowledgedRestoreGeneration(
    String userId,
    String generation,
  ) async {}
}
