import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/firestore_record_repository.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/sync/sync_attempt_authority.dart';

import 'support/test_firestore.dart';

const _catalogKeys = {
  'savedPayeeNames',
  'archivedPayeeNames',
  'deletedPayeeNames',
  'payeeCatalogStates',
};
Map<String, Object?> _catalog(UserPreferences preferences) => {
  for (final entry in preferences.toJson().entries)
    if (_catalogKeys.contains(entry.key)) entry.key: entry.value,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final action in [
    'add',
    'edit',
    'archive',
    'restore',
    'delete',
    're-add',
  ]) {
    test(
      'failed payee $action persists locally and later normal sync reaches another device',
      () async {
        final cloud = TestFirestore();
        var initial = const UserPreferences(
          appearanceMode: AppearanceMode.dark,
          showLedgerIcons: true,
        );
        if (action != 'add') {
          initial = reconcilePayeeCatalogMutation(
            current: initial,
            requested: initial.copyWith(savedPayeeNames: ['Acme']),
            newOperationId: () => 'seed-active',
          );
        }
        if (action == 'restore' || action == 're-add') {
          initial = reconcilePayeeCatalogMutation(
            current: initial,
            requested: action == 'restore'
                ? initial.copyWith(archivedPayeeNames: {'acme'})
                : initial.copyWith(
                    savedPayeeNames: [],
                    deletedPayeeNames: {'acme'},
                  ),
            newOperationId: () => 'seed-$action',
          );
        }
        final seed = _data(initial);
        cloud.records['users/user/accounts/wallet'] = Map.from(
          seed.accounts.single.toJson(),
        );
        cloud.records['users/user/preferences/main'] = Map.from(
          initial
              .copyWith(
                appearanceMode: AppearanceMode.light,
                showLedgerIcons: false,
              )
              .toJson(),
        );
        const local = LocalFinanceDataSetRepository(
          storageKey: 'payee-device-a',
        );
        final remote = FirestoreRecordRepository(firestore: cloud);
        final store = FinanceDataStore(
          dataSet: seed,
          localRepository: local,
          remoteRepository: remote,
          userId: 'user',
          deviceId: 'device-a',
        );
        final requested = switch (action) {
          'add' => initial.copyWith(savedPayeeNames: ['Acme']),
          'edit' => initial.copyWith(
            savedPayeeNames: ['Acme Market'],
            deletedPayeeNames: {'acme'},
          ),
          'archive' => initial.copyWith(archivedPayeeNames: {'acme'}),
          'restore' => initial.copyWith(archivedPayeeNames: {}),
          'delete' => initial.copyWith(
            savedPayeeNames: [],
            deletedPayeeNames: {'acme'},
          ),
          _ => initial.copyWith(
            savedPayeeNames: ['Acme'],
            deletedPayeeNames: {},
          ),
        };
        cloud.failNextTransaction = true;
        await store.savePreferences(requested);
        final expected = store.preferences;
        expect(_catalog(expected), isNot(_catalog(initial)));
        expect(_catalog((await local.load())!.preferences), _catalog(expected));
        expect(
          _catalog(
            UserPreferences.fromJson(
              cloud.records['users/user/preferences/main']!,
            ),
          ),
          _catalog(initial),
        );

        await store.attachRemoteSync(remoteRepository: remote, userId: 'user');
        expect(_catalog(store.preferences), _catalog(expected));
        final second = FinanceDataStore(
          dataSet: _data(
            const UserPreferences(
              appearanceMode: AppearanceMode.light,
              launchScreen: LaunchScreen.ledger,
            ),
          ),
          deviceId: 'device-b',
        );
        await second.attachRemoteSync(
          remoteRepository: FirestoreRecordRepository(firestore: cloud),
          userId: 'user',
        );
        expect(_catalog(second.preferences), _catalog(expected));
        expect(store.preferences.appearanceMode, AppearanceMode.dark);
        expect(store.preferences.showLedgerIcons, isTrue);
        expect(second.preferences.appearanceMode, AppearanceMode.light);
        expect(second.preferences.launchScreen, LaunchScreen.ledger);
        store.dispose();
        second.dispose();
      },
    );
  }
  for (final bulk in [false, true]) {
    test(
      '${bulk ? "bulk" : "immediate"} publishes only shared fields and is idempotent',
      () async {
        final cloud = TestFirestore();
        const path = 'users/user/preferences/main';
        cloud.records[path] = Map.from(
          const UserPreferences(appearanceMode: AppearanceMode.light).toJson(),
        );
        final local = reconcilePayeeCatalogMutation(
          current: const UserPreferences(),
          requested: const UserPreferences(
            savedPayeeNames: ['Acme'],
            appearanceMode: AppearanceMode.dark,
            launchScreen: LaunchScreen.ledger,
            showLedgerIcons: true,
            notificationsEnabled: true,
          ),
          newOperationId: () => 'add-acme',
        );
        final repository = FirestoreRecordRepository(firestore: cloud);
        Future<void> publish() => bulk
            ? repository.saveDataSet(
                userId: 'user',
                dataSet: _data(local).copyWith(accounts: []),
              )
            : repository.savePreferences(userId: 'user', preferences: local);
        await publish();
        expect(cloud.committedPayloads.single.keys.toSet(), {
          ..._catalogKeys,
          '_trackmarkCloudUpdatedAt',
        });
        expect(cloud.records[path]!['appearanceMode'], 'light');
        expect(cloud.records[path]!['showLedgerIcons'], isFalse);
        expect(cloud.records[path]!['notificationsEnabled'], isFalse);
        final count = cloud.committedWrites;
        await publish();
        expect(cloud.committedWrites, count);
      },
    );
  }

  test('device-local preference change uploads no fields', () async {
    final cloud = TestFirestore();
    await FirestoreRecordRepository(firestore: cloud).savePreferences(
      userId: 'user',
      preferences: const UserPreferences(
        appearanceMode: AppearanceMode.dark,
        showLedgerIcons: true,
      ),
    );
    expect(cloud.committedWrites, 0);
    expect(cloud.records['users/user/preferences/main'], isNull);
  });

  for (final bulk in [false, true]) {
    test(
      '${bulk ? "bulk" : "immediate"} transaction retry preserves causal concurrent merge',
      () async {
        final cloud = TestFirestore();
        const path = 'users/user/preferences/main';
        const local = UserPreferences(
          payeeCatalogStates: {
            'acme': PayeeCatalogState(
              displayName: 'Acme',
              status: PayeeCatalogStatus.archived,
              revision: 2,
              operationId: 'device-a',
            ),
            'local': PayeeCatalogState(
              displayName: 'Local',
              status: PayeeCatalogStatus.active,
              revision: 1,
              operationId: 'local-add',
            ),
          },
        );
        const concurrent = UserPreferences(
          appearanceMode: AppearanceMode.dark,
          payeeCatalogStates: {
            'acme': PayeeCatalogState(
              displayName: 'ACME',
              status: PayeeCatalogStatus.active,
              revision: 2,
              operationId: 'device-z',
            ),
            'remote': PayeeCatalogState(
              displayName: 'Remote',
              status: PayeeCatalogStatus.deleted,
              revision: 4,
              operationId: 'remote-delete',
            ),
          },
        );
        cloud.beforeCommit = () {
          cloud.records[path] = Map.from(concurrent.toJson());
        };
        final repository = FirestoreRecordRepository(firestore: cloud);
        if (bulk) {
          await repository.saveDataSet(
            userId: 'user',
            dataSet: _data(local).copyWith(accounts: []),
          );
        } else {
          await repository.savePreferences(userId: 'user', preferences: local);
        }
        expect(cloud.retries, 1);
        final expected = mergePayeeCatalogPreferences(
          preferred: local,
          other: concurrent,
        );
        expect(
          _catalog(UserPreferences.fromJson(cloud.records[path]!)),
          _catalog(expected),
        );
        expect(cloud.records[path]!['appearanceMode'], 'dark');
        expect(cloud.committedPayloads.single.keys.toSet(), {
          ..._catalogKeys,
          '_trackmarkCloudUpdatedAt',
        });
      },
    );
  }

  test(
    'bulk retries catalog even when baseline already contains the local edit',
    () async {
      final cloud = TestFirestore();
      const local = UserPreferences(savedPayeeNames: ['Acme']);
      final data = _data(local).copyWith(accounts: []);
      await FirestoreRecordRepository(
        firestore: cloud,
      ).saveDataSet(userId: 'user', dataSet: data, baseline: data);
      expect(cloud.records['users/user/preferences/main']!['savedPayeeNames'], [
        'Acme',
      ]);
    },
  );

  test('timed-out payee read cannot publish its later result', () async {
    final cloud = TestFirestore();
    final started = Completer<void>();
    final resume = Completer<void>();
    cloud.beforeRead = () async {
      started.complete();
      await resume.future;
    };
    final authority = SyncAttemptAuthority();
    final result = authority.run(
      () => FirestoreRecordRepository(firestore: cloud).savePreferences(
        userId: 'user',
        preferences: const UserPreferences(savedPayeeNames: ['Acme']),
      ),
    );
    final rejected = expectLater(result, throwsA(isA<StaleSyncAttempt>()));
    await started.future;
    authority.invalidate(timedOut: true);
    resume.complete();
    await rejected;
    await authority.drain();
    expect(cloud.committedWrites, 0);
    expect(cloud.records['users/user/preferences/main'], isNull);
  });
}

FinanceDataSet _data(UserPreferences preferences) => FinanceDataSet(
  accounts: [
    AccountRecord(
      id: 'wallet',
      name: 'Wallet',
      type: AccountType.cash,
      openingBalanceMinor: 0,
      sync: SyncMetadata.fresh(now: DateTime.utc(2026, 1, 1)),
    ),
  ],
  transactions: [],
  categories: [],
  scheduledTransactions: [],
  budgets: [],
  preferences: preferences,
);
