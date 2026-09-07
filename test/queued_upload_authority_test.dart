import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  for (final boundary in ['restore', 'reset', 'sign-out/reconnect']) {
    testWidgets('queued edits cannot cross $boundary', (tester) async {
      final remote = _Remote();
      final store = FinanceDataStore(
        dataSet: _data(),
        remoteRepository: remote,
        userId: 'user',
      );
      final first = store.saveAccount(
        store.accounts.single.copyWith(name: 'First'),
      );
      await tester.pump();
      expect(remote.started, 1);
      final second = store.saveAccount(
        store.accounts.single.copyWith(name: 'Queued stale'),
      );
      final payee = store.savePreferences(
        store.preferences.copyWith(savedPayeeNames: const ['Old queued payee']),
      );
      await tester.pump();
      var finished = false;
      final Future<void> transition;
      if (boundary == 'sign-out/reconnect') {
        store.detachRemoteSync();
        transition = store.attachRemoteSync(
          remoteRepository: remote,
          userId: 'other',
        );
      } else {
        transition = boundary == 'reset'
            ? store.resetTrackmarkData()
            : store.restoreBackupDataSet(_data(name: 'Restored'));
      }
      final completion = transition.then((_) => finished = true);
      await tester.pump();
      final finishedBeforeOldWrite = finished;
      remote.release.complete();
      await tester.pump();
      await Future.wait([first, second, payee, completion]);
      expect(remote.names, isNot(contains('Queued stale')));
      expect(remote.payees, isNot(contains('Old queued payee')));
      expect(
        finishedBeforeOldWrite,
        isFalse,
        reason: 'Already submitted writes must settle before new authority',
      );
      expect(
        remote.events.indexOf('finished First'),
        lessThan(remote.events.indexOf('authority')),
      );
      final latest = _data(name: 'Fresh').accounts.single;
      await store.saveAccount(latest);
      expect(remote.names.last, 'Fresh', reason: 'New edits remain uploadable');
      store.dispose();
    });
  }
  testWidgets('queued transfer is dropped on reset without reviving records', (
    tester,
  ) async {
    final remote = _Remote();
    final initial = _data();
    final store = FinanceDataStore(
      dataSet: initial.copyWith(
        accounts: [
          initial.accounts.single,
          AccountRecord(
            id: 'destination',
            name: 'Destination',
            type: AccountType.checking,
            openingBalanceMinor: 0,
            sync: SyncMetadata.fresh(),
          ),
        ],
      ),
      remoteRepository: remote,
      userId: 'user',
    );
    final first = store.saveAccount(
      store.accounts.first.copyWith(name: 'First'),
    );
    await tester.pump();
    final transfer = store.saveTransaction(
      TransactionRecord(
        id: 'old-transfer',
        type: TransactionType.transfer,
        accountId: 'account',
        transferAccountId: 'destination',
        date: DateTime(2026, 9, 7),
        payee: 'Transfer',
        amountMinor: 100,
        sync: SyncMetadata.fresh(),
      ),
    );
    await tester.pump();
    final reset = store.resetTrackmarkData();
    await tester.pump();
    remote.release.complete();
    await tester.pump();
    await Future.wait([first, transfer, reset]);
    expect(remote.transactions, isEmpty);
    expect(store.transactions, isEmpty);
    expect(store.accounts, isEmpty);
    store.dispose();
  });
  testWidgets('normal queued edits still publish in order', (tester) async {
    final remote = _Remote();
    final store = FinanceDataStore(
      dataSet: _data(),
      remoteRepository: remote,
      userId: 'user',
    );
    final first = store.saveAccount(
      store.accounts.single.copyWith(name: 'First'),
    );
    await tester.pump();
    final second = store.saveAccount(
      store.accounts.single.copyWith(name: 'Second'),
    );
    await tester.pump();
    remote.release.complete();
    await tester.pump();
    await Future.wait([first, second]);
    expect(remote.names, ['First', 'Second']);
    store.dispose();
  });
}

FinanceDataSet _data({String name = 'Initial'}) => FinanceDataSet(
  accounts: [
    AccountRecord(
      id: 'account',
      name: name,
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
  final release = Completer<void>();
  final names = <String>[];
  final events = <String>[];
  final payees = <String>[];
  final transactions = <String>[];
  int started = 0;
  @override
  Future<void> saveAccount({
    required String userId,
    required AccountRecord account,
  }) async {
    if (++started == 1) await release.future;
    names.add(account.name);
    events.add('finished ${account.name}');
  }

  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async {
    events.add('authority');
    return 'restored';
  }

  @override
  Future<String?> activeRestoreGeneration(String userId) async {
    events.add('authority');
    return 'new-session';
  }

  @override
  Future<void> savePreferences({
    required String userId,
    required UserPreferences preferences,
  }) async {
    payees.addAll(preferences.savedPayeeNames);
  }

  @override
  Future<void> saveTransaction({
    required String userId,
    required TransactionRecord transaction,
  }) async {
    transactions.add(transaction.id);
  }

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async =>
      _data(name: 'Remote');
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
