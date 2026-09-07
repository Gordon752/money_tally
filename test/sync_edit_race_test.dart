import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/persistence/scheduled_notification_state_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  for (final preferRemote in [false, true]) {
    for (final pauseSave in [1, 2]) {
      for (final type in [
        TransactionType.income,
        TransactionType.expense,
        TransactionType.transfer,
      ]) {
        for (final editing in [false, true]) {
          test(
            '$type ${editing ? "edit" : "creation"} survives sync save $pauseSave (first import: $preferRemote)',
            () async {
              final sync = SyncMetadata.fresh(now: DateTime.utc(2026, 1, 1));
              final original = TransactionRecord(
                id: 'transaction',
                type: type,
                accountId: 'a',
                transferAccountId: type == TransactionType.transfer
                    ? 'b'
                    : null,
                date: DateTime(2026, 1, 1),
                payee: 'Original',
                amountMinor: 100,
                sync: sync,
                categoryId: type != TransactionType.transfer
                    ? 'category'
                    : null,
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
                categories: [
                  CategoryRecord(
                    id: 'category',
                    name: 'Category',
                    kind: type == TransactionType.expense
                        ? CategoryKind.expense
                        : CategoryKind.income,
                    sync: sync,
                  ),
                ],
                transactions: [if (editing) original],
                scheduledTransactions: const [],
                budgets: const [],
                preferences: const UserPreferences(),
              );
              final local = _PausedStorage(initial, pauseSave: pauseSave);
              final store = FinanceDataStore(
                dataSet: initial,
                localRepository: local,
                preferRemoteOnFirstSync: preferRemote,
              );
              final syncing = store.attachRemoteSync(
                remoteRepository: _Remote(
                  initial.copyWith(
                    accounts: [
                      initial.accounts.first,
                      initial.accounts.last.copyWith(
                        name: 'Remote change',
                        sync: sync.touched(now: DateTime.utc(2026, 1, 2)),
                      ),
                    ],
                  ),
                ),
                userId: 'user',
              );
              await local.prepared.future;
              final mutation = original.copyWith(
                amountMinor: 250,
                payee: 'Changed',
                sync: sync.touched(now: DateTime.utc(2026, 1, 2)),
              );
              await store.saveTransaction(mutation);
              local.resume.complete();
              await syncing;
              expect(store.transactions.single.toJson(), mutation.toJson());
              expect(store.accountById('b').name, 'Remote change');
              final reloaded = await FinanceDataStore.load(
                localRepository: local,
              );
              expect(reloaded.transactions.single.toJson(), mutation.toJson());
            },
          );
        }
      }
    }
  }
  test('schedule edit survives notification reconciliation', () async {
    final sync = SyncMetadata.fresh(now: DateTime.utc(2026, 1, 1));
    final schedule = ScheduledTransactionRecord(
      id: 'schedule',
      type: TransactionType.transfer,
      accountId: 'a',
      transferAccountId: 'b',
      payee: 'Original',
      amountMinor: 100,
      nextDate: DateTime(2026, 10, 1),
      frequency: RecurrenceFrequency.monthly,
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
      categories: const [],
      transactions: const [],
      scheduledTransactions: [schedule],
      budgets: const [],
      preferences: const UserPreferences(),
    );
    final local = _PausedStorage(initial, pauseSave: -1);
    final notifications = _PausedNotifications();
    final store = FinanceDataStore(
      dataSet: initial,
      localRepository: local,
      notificationStateRepository: notifications,
    );
    final syncing = store.attachRemoteSync(
      remoteRepository: _Remote(initial),
      userId: 'user',
    );
    await notifications.prepared.future;
    final changed = schedule.copyWith(
      payee: 'Changed',
      amountMinor: 250,
      sync: sync.touched(now: DateTime.utc(2026, 1, 2)),
    );
    await store.saveScheduledTransaction(changed);
    notifications.resume.complete();
    await syncing;
    expect(store.scheduledTransactions.single.payee, 'Changed');
    expect((await local.load()).scheduledTransactions.single.amountMinor, 250);
  });
}

class _PausedStorage extends LocalFinanceDataSetRepository {
  _PausedStorage(this.saved, {this.pauseSave = 1});
  final int pauseSave;
  FinanceDataSet saved;
  final prepared = Completer<void>();
  final resume = Completer<void>();
  int saves = 0;
  @override
  Future<FinanceDataSet> load() async => saved;
  @override
  Future<String?> loadAcknowledgedRestoreGeneration(String userId) async =>
      null;
  @override
  Future<void> save(FinanceDataSet dataSet) async {
    if (++saves == pauseSave) {
      prepared.complete();
      await resume.future;
    }
    saved = FinanceDataSet.fromJson(dataSet.toJson());
  }
}

class _PausedNotifications
    extends InMemoryScheduledNotificationStateRepository {
  final prepared = Completer<void>();
  final resume = Completer<void>();
  int loads = 0;
  @override
  Future<DeviceScheduledNotificationState?> load(String scheduleId) async {
    if (++loads == 2) {
      prepared.complete();
      await resume.future;
    }
    return super.load(scheduleId);
  }
}

class _Remote implements FinanceRecordRepository {
  _Remote(this.data);
  final FinanceDataSet data;
  @override
  Future<String?> activeRestoreGeneration(String userId) async => null;
  @override
  Future<FinanceDataSet> loadDataSet(String userId) async => data;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
