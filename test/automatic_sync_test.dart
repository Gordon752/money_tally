import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/sync/automatic_sync_service.dart';
import 'package:money_tally/src/sync/cloud_sync_coordinator.dart';

void main() {
  group('automatic sync preferences and policy', () {
    test(
      'defaults off and persists preferred time through JSON and backup',
      () {
        const defaults = UserPreferences();
        expect(defaults.automaticSyncEnabled, isFalse);
        expect(defaults.preferredDailySyncMinutes, 22 * 60);

        final configured = defaults.copyWith(
          automaticSyncEnabled: true,
          preferredDailySyncMinutes: 23 * 60 + 15,
        );
        final restoredPreferences = UserPreferences.fromJson(
          configured.toJson(),
        );
        expect(restoredPreferences.automaticSyncEnabled, isTrue);
        expect(restoredPreferences.preferredDailySyncMinutes, 23 * 60 + 15);

        final restoredDataSet = const BackupCodec().decodeJson(
          const BackupCodec().encodeJson(_dataSet(preferences: configured)),
        );
        expect(restoredDataSet.preferences.automaticSyncEnabled, isTrue);
        expect(
          restoredDataSet.preferences.preferredDailySyncMinutes,
          23 * 60 + 15,
        );
      },
    );

    test('catch-up is due once after the preferred daily time', () {
      const preferences = UserPreferences(
        automaticSyncEnabled: true,
        preferredDailySyncMinutes: 22 * 60,
      );
      final before = DateTime(2026, 8, 11, 21, 59);
      final after = DateTime(2026, 8, 11, 22, 1);
      expect(
        AutomaticSyncPolicy.isCatchUpDue(
          preferences: preferences,
          now: before,
          lastSuccessfulSync: null,
        ),
        isFalse,
      );
      expect(
        AutomaticSyncPolicy.isCatchUpDue(
          preferences: preferences,
          now: after,
          lastSuccessfulSync: null,
        ),
        isTrue,
      );
      expect(
        AutomaticSyncPolicy.isCatchUpDue(
          preferences: preferences,
          now: after,
          lastSuccessfulSync: DateTime(2026, 8, 11, 22, 0, 30),
        ),
        isFalse,
      );
    });

    test(
      'next task uses the next preferred time without exact-time promise',
      () {
        expect(
          AutomaticSyncPolicy.nextPreferredTime(
            now: DateTime(2026, 8, 11, 12),
            preferredMinutes: 22 * 60,
          ),
          DateTime(2026, 8, 11, 22),
        );
        expect(
          AutomaticSyncPolicy.nextPreferredTime(
            now: DateTime(2026, 8, 11, 23),
            preferredMinutes: 22 * 60,
          ),
          DateTime(2026, 8, 12, 22),
        );
      },
    );
  });

  group('automatic sync task orchestration', () {
    const preferences = UserPreferences(
      automaticSyncEnabled: true,
      preferredDailySyncMinutes: 22 * 60,
    );
    final now = DateTime(2026, 8, 11, 22, 15);

    test('signed-out and Local-Only execution does no work', () async {
      final scheduler = _FakeScheduler();
      var syncCalls = 0;
      final result = await runAutomaticSyncAttempt(
        preferences: preferences,
        userId: null,
        now: now,
        lastSuccessfulSync: null,
        synchronize: () async {
          syncCalls += 1;
          return true;
        },
        scheduler: scheduler,
      );
      expect(result, isTrue);
      expect(syncCalls, 0);
      expect(scheduler.scheduleCalls, 0);
    });

    test(
      'successful and failed attempts both schedule the next opportunity',
      () async {
        final successfulScheduler = _FakeScheduler();
        expect(
          await runAutomaticSyncAttempt(
            preferences: preferences,
            userId: 'user-1',
            now: now,
            lastSuccessfulSync: null,
            synchronize: () async => true,
            scheduler: successfulScheduler,
          ),
          isTrue,
        );
        expect(successfulScheduler.scheduleCalls, 1);

        final failedScheduler = _FakeScheduler();
        expect(
          await runAutomaticSyncAttempt(
            preferences: preferences,
            userId: 'user-1',
            now: now,
            lastSuccessfulSync: null,
            synchronize: () async => false,
            scheduler: failedScheduler,
          ),
          isFalse,
        );
        expect(failedScheduler.scheduleCalls, 1);
      },
    );

    test('a successful same-window sync prevents duplicate work', () async {
      final scheduler = _FakeScheduler();
      var syncCalls = 0;
      final result = await runAutomaticSyncAttempt(
        preferences: preferences,
        userId: 'user-1',
        now: now,
        lastSuccessfulSync: DateTime(2026, 8, 11, 22, 5),
        synchronize: () async {
          syncCalls += 1;
          return true;
        },
        scheduler: scheduler,
      );
      expect(result, isTrue);
      expect(syncCalls, 0);
      expect(scheduler.scheduleCalls, 1);
    });
  });

  group('shared cloud sync coordinator', () {
    test('manual/background callers share one real sync operation', () async {
      final repository = _FakeRecordRepository(
        delay: const Duration(milliseconds: 20),
      );
      final stateStore = _MemorySyncStateStore();
      final coordinator = CloudSyncCoordinator(
        recordRepository: repository,
        executionStateStore: stateStore,
        now: () => DateTime.utc(2026, 8, 11, 22, 30),
      );
      final store = FinanceDataStore(dataSet: _dataSet());

      final first = coordinator.synchronize(userId: 'user-1', dataStore: store);
      final second = coordinator.synchronize(
        userId: 'user-1',
        dataStore: store,
      );
      expect(await Future.wait([first, second]), everyElement(isTrue));
      expect(repository.loadCalls, 1);
      expect(coordinator.status, CloudSyncStatus.synced);
      expect(stateStore.lastSuccess, DateTime.utc(2026, 8, 11, 22, 30));
    });

    test('failed real sync persists issue state and not success', () async {
      final repository = _FakeRecordRepository(fail: true);
      final stateStore = _MemorySyncStateStore();
      final coordinator = CloudSyncCoordinator(
        recordRepository: repository,
        executionStateStore: stateStore,
      );
      final result = await coordinator.synchronize(
        userId: 'user-1',
        dataStore: FinanceDataStore(dataSet: _dataSet()),
      );
      expect(result, isFalse);
      expect(coordinator.status, CloudSyncStatus.issue);
      expect(stateStore.lastSuccess, isNull);
      expect(stateStore.lastSucceeded, isFalse);
    });
  });
}

FinanceDataSet _dataSet({
  UserPreferences preferences = const UserPreferences(),
}) {
  return FinanceDataSet(
    accounts: const [],
    categories: const [],
    transactions: const [],
    scheduledTransactions: const [],
    budgets: const [],
    preferences: preferences,
  );
}

class _FakeScheduler implements AutomaticSyncTaskScheduler {
  int scheduleCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  Future<void> schedule({required int preferredMinutes, DateTime? now}) async {
    scheduleCalls += 1;
  }
}

class _MemorySyncStateStore implements SyncExecutionStateStore {
  DateTime? lastSuccess;
  bool? lastSucceeded;
  bool leased = false;

  @override
  Future<DateTime?> loadLastSuccessfulSync(String userId) async => lastSuccess;

  @override
  Future<bool?> loadLastSyncSucceeded(String userId) async => lastSucceeded;

  @override
  Future<void> saveLastSuccessfulSync(String userId, DateTime value) async {
    lastSuccess = value;
    lastSucceeded = true;
  }

  @override
  Future<void> saveLastSyncFailed(String userId) async {
    lastSucceeded = false;
  }

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
}

class _FakeRecordRepository implements FinanceRecordRepository {
  _FakeRecordRepository({this.fail = false, this.delay = Duration.zero});

  final bool fail;
  final Duration delay;
  int loadCalls = 0;

  @override
  Future<String?> activeRestoreGeneration(String userId) async => null;

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async {
    loadCalls += 1;
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw StateError('offline');
    return _dataSet();
  }

  @override
  Stream<FinanceDataSet> watchDataSet(String userId) =>
      Stream.value(_dataSet());

  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async => 'generation';

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
  }) async {}
}
