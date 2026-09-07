import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/firestore_record_repository.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'support/test_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final immediateFails in [true, false]) {
    for (final kind in ['account', 'new transfer', 'edited transfer']) {
      test(
        '$kind during upload converges after restart (immediate fails: $immediateFails)',
        () async {
          final cloud = TestFirestore();
          final sync = SyncMetadata.fresh(now: DateTime.utc(2026, 1, 1));
          final original = TransactionRecord(
            id: 'transfer',
            type: TransactionType.transfer,
            accountId: 'a',
            transferAccountId: 'b',
            date: DateTime(2026, 1, 1),
            payee: 'Transfer',
            amountMinor: 100,
            sync: sync,
          );
          final initial = FinanceDataSet(
            accounts: [
              for (final id in ['a', 'b'])
                AccountRecord(
                  id: id,
                  name: id,
                  type: AccountType.checking,
                  openingBalanceMinor: 10000,
                  sync: sync,
                ),
            ],
            transactions: [if (kind == 'edited transfer') original],
            categories: [],
            scheduledTransactions: [],
            budgets: [],
            preferences: const UserPreferences(),
          );
          for (final account in initial.accounts) {
            cloud.records['users/user/accounts/${account.id}'] = account
                .toJson();
          }
          if (initial.transactions.isNotEmpty) {
            cloud.records['users/user/transactions/transfer'] = original
                .toJson();
          }
          final repository = _PausedUpload(cloud);
          const local = LocalFinanceDataSetRepository(storageKey: 'ack-test');
          final store = FinanceDataStore(
            dataSet: initial,
            localRepository: local,
          );
          final syncing = store.attachRemoteSync(
            remoteRepository: repository,
            userId: 'user',
          );
          await repository.started.future;
          cloud.failNextTransaction = immediateFails;
          if (kind == 'account') {
            await store.saveAccount(
              store.accounts.first.copyWith(
                name: 'Edited',
                sync: sync.touched(),
              ),
            );
          } else {
            await store.saveTransaction(
              original.copyWith(amountMinor: 250, sync: sync.touched()),
            );
          }
          final retained = store.dataSet;
          expect((await local.load())!.toJson(), retained.toJson());
          if (immediateFails) {
            expect(cloud.records['users/user/accounts/a']!['name'], 'a');
            expect(
              cloud.records['users/user/transactions/transfer']?['amountMinor'],
              kind == 'edited transfer' ? 100 : null,
            );
          }
          repository.resume.complete();
          await syncing;
          // Restart with the persisted incremental cache: retry must not depend
          // on an in-memory dirty flag or a forced full bootstrap.
          final nextRepository = FirestoreRecordRepository(firestore: cloud);
          final next = FinanceDataStore(
            dataSet: retained,
            localRepository: local,
          );
          await next.attachRemoteSync(
            remoteRepository: nextRepository,
            userId: 'user',
          );
          if (kind == 'account') {
            expect(cloud.records['users/user/accounts/a']!['name'], 'Edited');
          } else {
            expect(
              cloud.records['users/user/transactions/transfer']!['amountMinor'],
              250,
            );
          }
          final otherDevice = await FirestoreRecordRepository(
            firestore: cloud,
          ).loadDataSet('user');
          expect(
            otherDevice.accounts.first.name,
            kind == 'account' ? 'Edited' : 'a',
          );
          if (kind != 'account') {
            expect(otherDevice.transactions.single.amountMinor, 250);
          }
          final writes = cloud.committedWrites;
          await next.attachRemoteSync(
            remoteRepository: nextRepository,
            userId: 'user',
          );
          expect(
            cloud.committedWrites,
            writes,
            reason: 'Confirmed retry is idempotent',
          );
          store.dispose();
          next.dispose();
        },
      );
    }
  }
}

class _PausedUpload extends FirestoreRecordRepository {
  _PausedUpload(TestFirestore cloud) : super(firestore: cloud);
  final started = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<void> saveDataSet({
    required String userId,
    required FinanceDataSet dataSet,
    FinanceDataSet? baseline,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await resume.future;
    }
    await super.saveDataSet(
      userId: userId,
      dataSet: dataSet,
      baseline: baseline,
    );
  }
}
