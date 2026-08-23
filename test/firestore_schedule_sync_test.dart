import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/persistence/firestore_record_repository.dart';

void main() {
  test('new cloud schedule is initialized with occurrence epoch authority', () {
    final epoch = ScheduledOccurrenceHistoryEpoch(
      revision: 1,
      operationId: 'reset-phone',
      changedAt: DateTime.utc(2026, 8, 23),
      deviceId: 'phone',
    );
    final pending = ScheduledOccurrenceState(
      scheduledDate: DateTime(2026, 9, 1),
      plannedAmountMinor: 5000,
      status: ScheduledOccurrenceStatus.pending,
      revision: 0,
      operationId: 'pending-wallet',
      changedAt: DateTime.utc(2026, 8, 23),
      deviceId: 'phone',
      historyEpochRevision: epoch.revision,
      historyEpochOperationId: epoch.operationId,
    );
    final schedule = ScheduledTransactionRecord(
      id: 'local-only-wallet-schedule',
      type: TransactionType.expense,
      accountId: 'wallet',
      categoryId: 'test',
      payee: 'Test',
      amountMinor: 5000,
      nextDate: DateTime(2026, 9, 1),
      frequency: RecurrenceFrequency.monthly,
      occurrenceHistoryEpoch: epoch,
      occurrenceStates: {'20260901': pending},
      sync: SyncMetadata.fresh(
        now: DateTime.utc(2026, 8, 23),
        deviceId: 'phone',
      ),
    );

    final initialCreate = scheduledCloudJsonForSync(
      scheduledTransaction: schedule,
      existsInRemoteBaseline: false,
    );
    final existingUpdate = scheduledCloudJsonForSync(
      scheduledTransaction: schedule,
      existsInRemoteBaseline: true,
    );

    expect(initialCreate['occurrenceHistoryEpoch'], epoch.toJson());
    expect(
      (initialCreate['occurrenceStates'] as Map)['20260901'],
      pending.toJson(),
    );
    expect(existingUpdate, isNot(contains('occurrenceHistoryEpoch')));
    expect(existingUpdate, isNot(contains('occurrenceStates')));
  });

  test('newer merged epoch wins for an existing cloud schedule', () {
    final remoteEpoch = ScheduledOccurrenceHistoryEpoch(
      revision: 1,
      operationId: 'reset-ipad',
      changedAt: DateTime.utc(2026, 8, 23),
      deviceId: 'ipad',
    );
    final mergedEpoch = ScheduledOccurrenceHistoryEpoch(
      revision: 2,
      operationId: 'reset-phone',
      changedAt: DateTime.utc(2026, 8, 23, 1),
      deviceId: 'phone',
    );

    ScheduledTransactionRecord scheduleWithEpoch(
      String id,
      ScheduledOccurrenceHistoryEpoch epoch,
    ) => ScheduledTransactionRecord(
      id: id,
      type: TransactionType.expense,
      accountId: 'wallet',
      categoryId: 'test',
      payee: 'Test',
      amountMinor: 5000,
      nextDate: DateTime(2026, 9, 1),
      frequency: RecurrenceFrequency.monthly,
      occurrenceHistoryEpoch: epoch,
      sync: SyncMetadata.fresh(
        now: DateTime.utc(2026, 8, 23),
        deviceId: epoch.deviceId,
      ),
    );

    expect(
      shouldAdvanceScheduledHistoryEpoch(
        scheduledTransaction: scheduleWithEpoch('schedule', mergedEpoch),
        remoteBaseline: scheduleWithEpoch('schedule', remoteEpoch),
      ),
      isTrue,
    );
    expect(
      shouldAdvanceScheduledHistoryEpoch(
        scheduledTransaction: scheduleWithEpoch('schedule', remoteEpoch),
        remoteBaseline: scheduleWithEpoch('schedule', mergedEpoch),
      ),
      isFalse,
    );
  });
}
