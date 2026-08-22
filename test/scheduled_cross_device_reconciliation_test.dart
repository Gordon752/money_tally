import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/scheduled_occurrence_authority.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/notifications/notification_scheduler.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/persistence/scheduled_notification_state_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  group('cross-device scheduled occurrence reconciliation', () {
    test(
      'A pays, B cancels its stale request and converges without resurrection',
      () async {
        final occurrenceDate = DateTime(2099, 8, 29);
        final nextDate = DateTime(2100, 8, 29);
        final paid = _state(
          date: occurrenceDate,
          status: ScheduledOccurrenceStatus.paid,
          revision: 1,
          operationId: 'paid-A',
        );
        final remoteSchedule = _schedule(
          nextDate: nextDate,
          occurrenceStates: {occurrenceDayKey(occurrenceDate): paid},
          updatedAt: DateTime(2099, 8, 20),
        );
        // Device B's notification bookkeeping made its stale definition look
        // newer under the old whole-record merge.
        final staleSchedule = _schedule(
          nextDate: occurrenceDate,
          notificationIds: const [7711],
          updatedAt: DateTime(2099, 8, 22),
        );
        final remote = _SharedScheduleRepository(_dataSet(remoteSchedule));
        final scheduler = _StatefulNotificationScheduler();
        final localNotificationState =
            InMemoryScheduledNotificationStateRepository();
        await localNotificationState.save(
          staleSchedule.id,
          const DeviceScheduledNotificationState(notificationIds: [7711]),
        );
        final deviceB = FinanceDataStore(
          dataSet: _dataSet(staleSchedule),
          notificationScheduler: scheduler,
          notificationStateRepository: localNotificationState,
        );

        await deviceB.attachRemoteSync(
          remoteRepository: remote,
          userId: 'user',
        );

        final converged = deviceB.scheduledTransactions.single;
        expect(converged.nextDate, nextDate);
        expect(
          converged.occurrenceStates[occurrenceDayKey(occurrenceDate)]?.status,
          ScheduledOccurrenceStatus.paid,
        );
        expect(scheduler.cancelledScheduleIds, contains(converged.id));
        expect(scheduler.pendingBySchedule.keys, [converged.id]);
        expect(
          scheduler.pendingBySchedule[converged.id]?.occurrenceDate,
          nextDate,
        );
        expect(
          deviceB.activeScheduledAlerts(now: DateTime(2099, 8, 22, 12)),
          isEmpty,
        );
        expect(scheduler.badgeCounts.last, 0);

        // A repeated sync rebuilds one deterministic request, never a
        // duplicate, and cannot resurrect the old occurrence.
        await deviceB.attachRemoteSync(
          remoteRepository: remote,
          userId: 'user',
        );
        expect(scheduler.pendingBySchedule.length, 1);
        expect(deviceB.scheduledTransactions.single.nextDate, nextDate);
        expect(
          deviceB
              .scheduledTransactions
              .single
              .occurrenceStates[occurrenceDayKey(occurrenceDate)]
              ?.revision,
          1,
        );
      },
    );

    test('newer Undo on B reopens the occurrence on A', () async {
      final occurrenceDate = DateTime(2099, 8, 29);
      final nextDate = DateTime(2100, 8, 29);
      final paid = _state(
        date: occurrenceDate,
        status: ScheduledOccurrenceStatus.paid,
        revision: 1,
        operationId: 'paid-A',
      );
      final undone = _state(
        date: occurrenceDate,
        status: ScheduledOccurrenceStatus.pending,
        revision: 2,
        operationId: 'undo-B',
      );
      final paidSchedule = _schedule(
        nextDate: nextDate,
        occurrenceStates: {occurrenceDayKey(occurrenceDate): paid},
        updatedAt: DateTime(2099, 8, 20),
      );
      final remote = _SharedScheduleRepository(
        _dataSet(
          paidSchedule.copyWith(
            occurrenceStates: {occurrenceDayKey(occurrenceDate): undone},
            sync: paidSchedule.sync,
          ),
        ),
      );
      final scheduler = _StatefulNotificationScheduler();
      final deviceA = FinanceDataStore(
        dataSet: _dataSet(paidSchedule),
        notificationScheduler: scheduler,
      );

      await deviceA.attachRemoteSync(remoteRepository: remote, userId: 'user');

      final reopened = deviceA.scheduledTransactions.single;
      expect(reopened.nextDate, occurrenceDate);
      expect(
        reopened.occurrenceStates[occurrenceDayKey(occurrenceDate)]?.revision,
        2,
      );
      expect(
        deviceA.activeScheduledAlerts(now: DateTime(2099, 8, 22, 12)),
        hasLength(1),
      );
      expect(
        scheduler.pendingBySchedule[reopened.id]?.occurrenceDate,
        occurrenceDate,
      );
    });

    test('transaction arrival order cannot determine occurrence authority', () {
      final occurrenceDate = DateTime(2099, 8, 29);
      final paid = _state(
        date: occurrenceDate,
        status: ScheduledOccurrenceStatus.paid,
        revision: 1,
        operationId: 'paid-A',
      );
      final staleDefinition = _schedule(
        nextDate: occurrenceDate,
        updatedAt: DateTime(2099, 8, 22),
      );
      final resolvedDefinition = _schedule(
        nextDate: DateTime(2100, 8, 29),
        occurrenceStates: {occurrenceDayKey(occurrenceDate): paid},
        updatedAt: DateTime(2099, 8, 20),
      );

      final first = mergeScheduledTransactionAuthority(
        current: staleDefinition,
        incoming: resolvedDefinition,
        preferCurrentOnDefinitionTie: false,
      );
      final second = mergeScheduledTransactionAuthority(
        current: resolvedDefinition,
        incoming: staleDefinition,
        preferCurrentOnDefinitionTie: false,
      );

      expect(first.nextDate, DateTime(2100, 8, 29));
      expect(second.nextDate, DateTime(2100, 8, 29));
      expect(first.occurrenceStates, second.occurrenceStates);
    });
  });
}

ScheduledOccurrenceState _state({
  required DateTime date,
  required ScheduledOccurrenceStatus status,
  required int revision,
  required String operationId,
}) {
  return ScheduledOccurrenceState(
    scheduledDate: date,
    plannedAmountMinor: 9900,
    status: status,
    revision: revision,
    operationId: operationId,
    changedAt: DateTime(2099, 8, 22),
    deviceId: operationId.endsWith('A') ? 'A' : 'B',
  );
}

ScheduledTransactionRecord _schedule({
  required DateTime nextDate,
  Map<String, ScheduledOccurrenceState> occurrenceStates = const {},
  List<int> notificationIds = const [],
  required DateTime updatedAt,
}) {
  return ScheduledTransactionRecord(
    id: 'porkbun-test',
    type: TransactionType.expense,
    accountId: 'checking',
    categoryId: 'subscriptions',
    payee: 'Fictional Hosting',
    amountMinor: 9900,
    nextDate: nextDate,
    frequency: RecurrenceFrequency.yearly,
    alertPreference: AlertPreference.oneWeekBefore,
    repeatAlertUntilResolved: true,
    occurrenceStates: occurrenceStates,
    scheduledNotificationIds: notificationIds,
    sync: SyncMetadata(
      createdAt: DateTime(2099, 1, 1),
      updatedAt: updatedAt,
      deviceId: 'test',
      version: 1,
    ),
  );
}

FinanceDataSet _dataSet(ScheduledTransactionRecord schedule) {
  final sync = SyncMetadata.fresh(now: DateTime(2099, 1, 1));
  return FinanceDataSet(
    accounts: [
      AccountRecord(
        id: 'checking',
        name: 'Checking',
        type: AccountType.checking,
        openingBalanceMinor: 100000,
        sync: sync,
      ),
    ],
    categories: [
      CategoryRecord(
        id: 'subscriptions',
        name: 'Subscriptions',
        kind: CategoryKind.expense,
        sync: sync,
      ),
    ],
    transactions: const [],
    scheduledTransactions: [schedule],
    budgets: const [],
    preferences: const UserPreferences(notificationsEnabled: true),
  );
}

class _StatefulNotificationScheduler implements NotificationScheduler {
  final Map<String, ScheduledNotificationRequest> pendingBySchedule = {};
  final List<String> cancelledScheduleIds = [];
  final List<int> badgeCounts = [];

  @override
  Future<void> cancelScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    cancelledScheduleIds.add(scheduledTransaction.id);
    pendingBySchedule.remove(scheduledTransaction.id);
  }

  @override
  Future<bool> requestPermissionIfNeeded() async => true;

  @override
  Future<void> rescheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    await cancelScheduledTransaction(scheduledTransaction);
    await scheduleScheduledTransaction(scheduledTransaction);
  }

  @override
  Future<List<int>> scheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    final request = const ScheduledNotificationPlanner().planOne(
      scheduledTransaction,
      now: DateTime(2099, 1, 1),
    );
    if (request == null) return const [];
    pendingBySchedule[scheduledTransaction.id] = request;
    return [notificationIdFor(scheduledTransaction.id)];
  }

  @override
  Future<void> updateBadgeCount(int dueOrOverdueCount) async {
    badgeCounts.add(dueOrOverdueCount);
  }
}

class _SharedScheduleRepository
    implements FinanceRecordRepository, ScheduledOccurrenceStateRepository {
  _SharedScheduleRepository(this.dataSet);

  FinanceDataSet dataSet;

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async => dataSet;

  @override
  Stream<FinanceDataSet> watchDataSet(String userId) => const Stream.empty();

  @override
  Future<String?> activeRestoreGeneration(String userId) async => null;

  @override
  Future<ScheduledOccurrenceState> saveScheduledOccurrenceState({
    required String userId,
    required String scheduledTransactionId,
    required String dayKey,
    required ScheduledOccurrenceState occurrenceState,
  }) async {
    final schedule = dataSet.scheduledTransactions.singleWhere(
      (item) => item.id == scheduledTransactionId,
    );
    final current = schedule.occurrenceStates[dayKey];
    final winner = current == null
        ? occurrenceState
        : authoritativeOccurrenceState(current, occurrenceState);
    dataSet = dataSet.copyWith(
      scheduledTransactions: [
        schedule.copyWith(
          occurrenceStates: {...schedule.occurrenceStates, dayKey: winner},
          sync: schedule.sync,
        ),
      ],
    );
    return winner;
  }

  @override
  Future<void> saveScheduledTransaction({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {
    final current = dataSet.scheduledTransactions.single;
    dataSet = dataSet.copyWith(
      scheduledTransactions: [
        scheduledTransaction.copyWith(
          occurrenceStates: current.occurrenceStates,
          sync: scheduledTransaction.sync,
        ),
      ],
    );
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
  Future<void> saveTransaction({
    required String userId,
    required TransactionRecord transaction,
  }) async {}

  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async {
    this.dataSet = dataSet;
    return 'test-generation';
  }
}
