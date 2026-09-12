import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money_tally/src/sync/account_deletion_state.dart';
import 'package:money_tally/src/sync/cloud_sync_coordinator.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'request phase and identity survive retries and fresh preference reads',
    () async {
      expect(await AccountDeletionState.pendingUser(), isNull);
      await AccountDeletionState.begin('deleted-user');
      expect(await AccountDeletionState.requestWasSent(), isFalse);
      await AccountDeletionState.markRequestSent();
      await AccountDeletionState.begin('deleted-user');
      expect(await AccountDeletionState.pendingUser(), 'deleted-user');
      expect(await AccountDeletionState.requestWasSent(), isTrue);
      await expectLater(
        AccountDeletionState.begin('other-user'),
        throwsStateError,
      );
      expect(await AccountDeletionState.pendingUser(), 'deleted-user');
      await AccountDeletionState.markConfirmed();
      expect(await AccountDeletionState.isConfirmed(), isTrue);
      await AccountDeletionState.clear();
      expect(await AccountDeletionState.pendingUser(), isNull);
      expect(await AccountDeletionState.requestWasSent(), isFalse);
      expect(await AccountDeletionState.isConfirmed(), isFalse);
    },
  );

  test('fresh authentication rejection permits another verification', () async {
    await AccountDeletionState.begin('user');
    await AccountDeletionState.markRequestSent();
    await AccountDeletionState.markRequestSent(sent: false);
    expect(await AccountDeletionState.pendingUser(), 'user');
    expect(await AccountDeletionState.requestWasSent(), isFalse);
  });

  for (final trigger in CloudSyncTrigger.values) {
    test(
      '$trigger cannot sync while any account deletion is pending',
      () async {
        await AccountDeletionState.begin('deleted-user');
        final remote = _NoCloudAccess();
        final coordinator = CloudSyncCoordinator(recordRepository: remote);
        final store = FinanceDataStore(dataSet: _empty);
        expect(
          await coordinator.synchronize(
            userId: 'other-user',
            dataStore: store,
            trigger: trigger,
          ),
          isFalse,
        );
        expect(coordinator.status, CloudSyncStatus.issue);
        expect(remote.calls, 0);
        store.dispose();
        coordinator.dispose();
      },
    );
  }

  test('corrupt recovery state fails closed without cloud access', () async {
    SharedPreferences.setMockInitialValues({
      'trackmark.accountDeletion': '{bad',
    });
    final remote = _NoCloudAccess();
    final coordinator = CloudSyncCoordinator(recordRepository: remote);
    final store = FinanceDataStore(dataSet: _empty);
    expect(
      await coordinator.synchronize(userId: 'user', dataStore: store),
      isFalse,
    );
    expect(remote.calls, 0);
    store.dispose();
    coordinator.dispose();
  });
}

class _NoCloudAccess implements FinanceRecordRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Unexpected cloud access during deletion');
  }
}

const _empty = FinanceDataSet(
  accounts: [],
  categories: [],
  transactions: [],
  scheduledTransactions: [],
  budgets: [],
  preferences: UserPreferences(),
);
