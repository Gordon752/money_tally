import 'dart:async';

import 'support/test_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/firestore_record_repository.dart';
import 'package:money_tally/src/persistence/cloud_record_conflict.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/sync/sync_attempt_authority.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final bulk in [false, true]) {
    for (final collection in ['accounts', 'transactions']) {
      for (final state in ['update', 'cloud deleted', 'local deleted']) {
        test(
          '$collection $state rejects stale ${bulk ? "bulk" : "single"} write',
          () async {
            final cloud = TestFirestore();
            final repository = FirestoreRecordRepository(firestore: cloud);
            final older = _record(
              collection,
              2,
              deleted: state == 'local deleted',
            );
            final newer = _record(
              collection,
              3,
              deleted: state == 'cloud deleted',
            );
            final path = 'users/user/$collection/record';
            cloud.records[path] = newer;
            final write = bulk
                ? repository.saveDataSet(
                    userId: 'user',
                    dataSet: _data(collection, older),
                    baseline: _data(collection, newer),
                  )
                : _save(repository, collection, older);
            // A conflict is surfaced, not silently acknowledged as uploaded.
            Object? conflict;
            try {
              await write;
            } catch (error) {
              conflict = error;
            }
            expect(cloud.records[path], newer);
            expect(conflict, isA<Exception>());
          },
        );
      }
    }
  }
  for (final bulk in [false, true]) {
    for (final collection in ['accounts', 'transactions']) {
      test(
        '$collection valid newer ${bulk ? "bulk" : "single"} write and idempotent repeat',
        () async {
          final cloud = TestFirestore();
          final repository = FirestoreRecordRepository(firestore: cloud);
          final original = _record(collection, 1);
          final newer = _record(collection, 2);
          final path = 'users/user/$collection/record';
          await _save(repository, collection, original);
          Future<void> write() => bulk
              ? repository.saveDataSet(
                  userId: 'user',
                  dataSet: _data(collection, newer),
                  baseline: _data(collection, original),
                )
              : _save(repository, collection, newer);
          await write();
          expect(canonicalCloudRecord(collection, cloud.records[path]!), newer);
          final writes = cloud.committedWrites;
          await write();
          expect(cloud.committedWrites, writes);
        },
      );

      test(
        '$collection ${bulk ? "bulk" : "single"} transaction retry rechecks server version',
        () async {
          final cloud = TestFirestore();
          final repository = FirestoreRecordRepository(firestore: cloud);
          final original = _record(collection, 1);
          final newer = _record(collection, 3);
          final path = 'users/user/$collection/record';
          await _save(repository, collection, original);
          cloud.beforeCommit = () {
            cloud.records[path] = newer;
          };
          final write = bulk
              ? repository.saveDataSet(
                  userId: 'user',
                  dataSet: _data(collection, _record(collection, 2)),
                  baseline: _data(collection, original),
                )
              : _save(repository, collection, _record(collection, 2));
          await expectLater(write, throwsA(isA<CloudRecordWriteConflict>()));
          expect(cloud.records[path], newer);
          expect(cloud.retries, 1);
        },
      );
    }
  }

  test(
    'same revision with different payload is a conflict, not idempotence',
    () async {
      final cloud = TestFirestore();
      final repository = FirestoreRecordRepository(firestore: cloud);
      final original = _record('accounts', 1);
      await _save(repository, 'accounts', original);
      await expectLater(
        _save(repository, 'accounts', {...original, 'name': 'Different'}),
        throwsA(isA<CloudRecordWriteConflict>()),
      );
      expect(
        cloud.records['users/user/accounts/record']!['name'],
        original['name'],
      );
    },
  );

  test('stale base cannot authorize even a higher local version', () async {
    final cloud = TestFirestore();
    final repository = FirestoreRecordRepository(firestore: cloud);
    final original = _record('accounts', 1);
    await _save(repository, 'accounts', original);
    cloud.records['users/user/accounts/record'] = _record('accounts', 2);
    await expectLater(
      _save(repository, 'accounts', _record('accounts', 9)),
      throwsA(isA<CloudRecordWriteConflict>()),
    );
    expect(cloud.records['users/user/accounts/record']!['name'], 'Version 2');
  });

  test('ordinary live write cannot resurrect observed tombstone', () async {
    final cloud = TestFirestore();
    final repository = FirestoreRecordRepository(firestore: cloud);
    final deleted = _record('accounts', 2, deleted: true);
    await _save(repository, 'accounts', deleted);
    await expectLater(
      _save(repository, 'accounts', _record('accounts', 3)),
      throwsA(isA<CloudRecordWriteConflict>()),
    );
    expect(
      canonicalCloudRecord(
        'accounts',
        cloud.records['users/user/accounts/record']!,
      ),
      deleted,
    );
  });

  test('legitimate deletion succeeds against observed live record', () async {
    final cloud = TestFirestore();
    final repository = FirestoreRecordRepository(firestore: cloud);
    await _save(repository, 'accounts', _record('accounts', 1));
    final deleted = _record('accounts', 2, deleted: true);
    await _save(repository, 'accounts', deleted);
    expect(
      canonicalCloudRecord(
        'accounts',
        cloud.records['users/user/accounts/record']!,
      ),
      deleted,
    );
  });

  test(
    'bulk conflict reconciles stale tombstone then retry is idempotent',
    () async {
      final cloud = TestFirestore();
      final repository = FirestoreRecordRepository(firestore: cloud);
      final newer = _record('accounts', 3);
      cloud.records['users/user/accounts/record'] = newer;
      final store = FinanceDataStore(
        dataSet: _data('accounts', _record('accounts', 2, deleted: true)),
        remoteRepository: repository,
        userId: 'user',
      );
      await expectLater(
        store.pushAllRecordsToRemote(baseline: _data('accounts', newer)),
        throwsA(isA<CloudRecordWriteConflict>()),
      );
      expect(store.accounts.single.toJson(), newer);
      await store.pushAllRecordsToRemote(baseline: _data('accounts', newer));
      expect(cloud.committedWrites, 0);
      // Adopting the server winner authorizes the next real local edit.
      await _save(repository, 'accounts', _record('accounts', 4));
      expect(cloud.records['users/user/accounts/record']!['name'], 'Version 4');
      store.dispose();
    },
  );

  test(
    'conflict reconciliation preserves an edit newer than rejected payload',
    () {
      final proposed = _record('accounts', 2);
      final newest = _record('accounts', 4);
      final current = _data('accounts', newest);
      final result = reconcileCloudRecordConflicts(
        current,
        CloudRecordWriteConflict([
          CloudRecordConflict(
            collection: 'accounts',
            proposed: proposed,
            authoritative: _record('accounts', 3),
          ),
        ]),
      );
      expect(result.accounts.single, same(current.accounts.single));
    },
  );

  test('timeout while transaction reads prevents staging any write', () async {
    final cloud = TestFirestore();
    final repository = FirestoreRecordRepository(firestore: cloud);
    await _save(repository, 'accounts', _record('accounts', 1));
    final started = Completer<void>();
    final resume = Completer<void>();
    cloud.beforeRead = () async {
      started.complete();
      await resume.future;
    };
    final authority = SyncAttemptAuthority();
    final pending = authority.run(
      () => _save(repository, 'accounts', _record('accounts', 2)),
    );
    final rejected = expectLater(pending, throwsA(isA<StaleSyncAttempt>()));
    await started.future;
    authority.invalidate(timedOut: true);
    resume.complete();
    await rejected;
    expect(cloud.records['users/user/accounts/record']!['name'], 'Version 1');
    await authority.drain();
  });

  test('server load establishes the immediate-write baseline', () async {
    final cloud = TestFirestore();
    cloud.records['users/user/accounts/record'] = _record('accounts', 1);
    final repository = FirestoreRecordRepository(firestore: cloud);
    await repository.loadDataSet('user');
    await _save(repository, 'accounts', _record('accounts', 2));
    expect(cloud.records['users/user/accounts/record']!['name'], 'Version 2');
  });

  test(
    'clock rollback does not reject a revision based on the observed parent',
    () async {
      final cloud = TestFirestore();
      final repository = FirestoreRecordRepository(firestore: cloud);
      await _save(repository, 'accounts', _record('accounts', 1));
      final next = _record('accounts', 2);
      next['sync'] = {
        ...next['sync'] as Map,
        'updatedAt': DateTime.utc(2026, 8).toIso8601String(),
      };
      await _save(repository, 'accounts', next);
      expect(cloud.records['users/user/accounts/record']!['name'], 'Version 2');
    },
  );

  test(
    'unpublished cached edit is retained and retried after a fresh cloud read',
    () async {
      final cloud = TestFirestore();
      final original = _record('accounts', 1);
      final unpublished = _record('accounts', 2);
      cloud.records['users/user/accounts/record'] = original;
      final first = FirestoreRecordRepository(firestore: cloud);
      final initial = await first.loadDataSetForSync('user');
      await first.acknowledgeIncrementalSync(
        userId: 'user',
        load: initial,
        resultingDataSet: _data('accounts', unpublished),
      );
      final repository = FirestoreRecordRepository(firestore: cloud);
      final cached = await repository.loadDataSetForSync('user');
      expect(cached.wasFullBootstrap, isFalse);
      final latest = _record('accounts', 3);
      final store = FinanceDataStore(
        dataSet: _data('accounts', latest),
        remoteRepository: repository,
        userId: 'user',
      );
      await expectLater(
        store.pushAllRecordsToRemote(baseline: cached.dataSet),
        throwsA(isA<CloudRecordWriteConflict>()),
      );
      expect(store.accounts.single.toJson(), latest);
      final refreshed = await repository.loadDataSetForSync('user');
      expect(refreshed.wasFullBootstrap, isTrue);
      expect(refreshed.dataSet.accounts.single.toJson(), original);
      await store.pushAllRecordsToRemote(baseline: refreshed.dataSet);
      expect(
        canonicalCloudRecord(
          'accounts',
          cloud.records['users/user/accounts/record']!,
        ),
        latest,
      );
      store.dispose();
    },
  );

  test(
    'immediate conflict adopts cloud winner and next user edit succeeds',
    () async {
      final cloud = TestFirestore();
      final repository = FirestoreRecordRepository(firestore: cloud);
      final older = _record('accounts', 2);
      final newer = _record('accounts', 3);
      cloud.records['users/user/accounts/record'] = newer;
      final store = FinanceDataStore(
        dataSet: _data('accounts', older),
        remoteRepository: repository,
        userId: 'user',
      );
      await store.saveAccount(AccountRecord.fromJson(older));
      expect(store.accounts.single.toJson(), newer);
      await store.saveAccount(AccountRecord.fromJson(_record('accounts', 4)));
      expect(cloud.records['users/user/accounts/record']!['name'], 'Version 4');
      store.dispose();
    },
  );

  test(
    'edit during rejected immediate upload survives reconciliation',
    () async {
      final cloud = TestFirestore();
      final repository = FirestoreRecordRepository(firestore: cloud);
      final older = _record('accounts', 2);
      final newer = _record('accounts', 3);
      cloud.records['users/user/accounts/record'] = newer;
      final started = Completer<void>();
      final resume = Completer<void>();
      cloud.beforeRead = () async {
        cloud.beforeRead = null;
        started.complete();
        await resume.future;
      };
      final store = FinanceDataStore(
        dataSet: _data('accounts', older),
        remoteRepository: repository,
        userId: 'user',
      );
      final first = store.saveAccount(AccountRecord.fromJson(older));
      await started.future;
      final latest = _record('accounts', 4);
      final second = store.saveAccount(AccountRecord.fromJson(latest));
      resume.complete();
      await Future.wait([first, second]);
      expect(store.accounts.single.toJson(), latest);
      expect(cloud.records['users/user/accounts/record'], newer);
      await store.pushAllRecordsToRemote(baseline: _data('accounts', newer));
      expect(
        canonicalCloudRecord(
          'accounts',
          cloud.records['users/user/accounts/record']!,
        ),
        latest,
      );
      store.dispose();
    },
  );
}

Map<String, dynamic> _record(
  String collection,
  int version, {
  bool deleted = false,
}) {
  final date = DateTime.utc(2026, 9, version);
  final sync = SyncMetadata(
    createdAt: DateTime.utc(2026),
    updatedAt: date,
    deviceId: 'device',
    version: version,
    deletedAt: deleted ? date : null,
  );
  return Map<String, dynamic>.from(
    collection == 'accounts'
        ? AccountRecord(
            id: 'record',
            name: 'Version $version',
            type: AccountType.checking,
            openingBalanceMinor: 0,
            sync: sync,
          ).toJson()
        : TransactionRecord(
            id: 'record',
            type: TransactionType.income,
            accountId: 'account',
            date: DateTime(2026, 9, 1),
            payee: 'Version $version',
            amountMinor: version * 100,
            sync: sync,
          ).toJson(),
  );
}

FinanceDataSet _data(String collection, Map<String, dynamic> record) =>
    FinanceDataSet(
      accounts: collection == 'accounts'
          ? [AccountRecord.fromJson(record)]
          : [],
      transactions: collection == 'transactions'
          ? [TransactionRecord.fromJson(record)]
          : [],
      categories: [],
      scheduledTransactions: [],
      budgets: [],
      preferences: const UserPreferences(),
    );

Future<void> _save(
  FirestoreRecordRepository repository,
  String collection,
  Map<String, dynamic> record,
) => collection == 'accounts'
    ? repository.saveAccount(
        userId: 'user',
        account: AccountRecord.fromJson(record),
      )
    : repository.saveTransaction(
        userId: 'user',
        transaction: TransactionRecord.fromJson(record),
      );

// Exercises the production repository paths. Transactions stage writes, and
// can later be extended to retry against a deterministically changed server.
