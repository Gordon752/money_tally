import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';

void main() {
  final day = DateTime(2026, 8, 24);

  test(
    'concurrent Paid states leave only the winning allocation effective',
    () {
      final losing = _allocation('allocation-a', day);
      final winning = _allocation('allocation-z', day);
      final dataSet = _dataSet(
        day: day,
        winningState: _state(
          day: day,
          status: ScheduledOccurrenceStatus.paid,
          operationId: 'paid-z',
          reservationOperationId: winning.id,
        ),
        operations: [losing, winning],
      );

      expect(dataSet.reservedForAccount('checking', asOf: day), 20000);
      expect(dataSet.availableToSpendForAccount('checking', asOf: day), 480000);
    },
  );

  test('winning Skip makes a losing Paid allocation inert', () {
    final losing = _allocation('allocation-a', day);
    final dataSet = _dataSet(
      day: day,
      winningState: _state(
        day: day,
        status: ScheduledOccurrenceStatus.skipped,
        operationId: 'skip-z',
      ),
      operations: [losing],
    );

    expect(dataSet.reservedForAccount('checking', asOf: day), 0);
    expect(dataSet.availableToSpendForAccount('checking', asOf: day), 500000);
  });

  test('winning Undo Pending makes prior allocation and reversal inert', () {
    final allocation = _allocation('allocation-a', day);
    final reversal = _reversal(
      id: 'reversal-z',
      day: day,
      allocationId: allocation.id,
    );
    final dataSet = _dataSet(
      day: day,
      winningState: _state(
        day: day,
        status: ScheduledOccurrenceStatus.pending,
        revision: 2,
        operationId: 'undo-z',
        reservationOperationId: reversal.id,
      ),
      operations: [allocation, reversal],
    );

    expect(dataSet.reservedForAccount('checking', asOf: day), 0);
  });

  test('Paid after Undo applies exactly the latest linked allocation', () {
    final first = _allocation('allocation-a', day);
    final reversal = _reversal(
      id: 'reversal-b',
      day: day,
      allocationId: first.id,
    );
    final latest = _allocation('allocation-z', day, revision: 3);
    final dataSet = _dataSet(
      day: day,
      winningState: _state(
        day: day,
        status: ScheduledOccurrenceStatus.paid,
        revision: 3,
        operationId: 'paid-z',
        reservationOperationId: latest.id,
      ),
      operations: [first, reversal, latest],
    );

    expect(dataSet.reservedForAccount('checking', asOf: day), 20000);
  });
}

FinanceDataSet _dataSet({
  required DateTime day,
  required ScheduledOccurrenceState winningState,
  required List<ReservationOperationRecord> operations,
}) {
  final sync = SyncMetadata.fresh(
    now: DateTime.utc(2026, 8, 1),
    deviceId: 'device-a',
  );
  return FinanceDataSet(
    accounts: [
      AccountRecord(
        id: 'checking',
        name: 'CTBI',
        type: AccountType.checking,
        openingBalanceMinor: 500000,
        sync: sync,
      ),
    ],
    categories: const [],
    transactions: const [],
    scheduledTransactions: [
      ScheduledTransactionRecord(
        id: 'schedule',
        type: TransactionType.goalFunding,
        accountId: 'checking',
        payee: 'Bills funding',
        amountMinor: 20000,
        nextDate: DateTime(2026, 9, 24),
        frequency: RecurrenceFrequency.monthly,
        reservationFundingContainerType: ReservationContainerType.fund,
        reservationFundingContainerId: 'bills',
        occurrenceStates: {occurrenceDayKey(day): winningState},
        sync: sync,
      ),
    ],
    budgets: const [],
    goals: const [],
    funds: [
      FundRecord(
        id: 'bills',
        name: 'Bills',
        fundingAccountId: 'checking',
        status: FundStatus.active,
        sync: sync,
      ),
    ],
    reservationOperations: operations,
    preferences: const UserPreferences(),
  );
}

ScheduledOccurrenceState _state({
  required DateTime day,
  required ScheduledOccurrenceStatus status,
  required String operationId,
  String? reservationOperationId,
  int revision = 1,
}) => ScheduledOccurrenceState(
  scheduledDate: day,
  plannedAmountMinor: 20000,
  status: status,
  actualAmountMinor: status == ScheduledOccurrenceStatus.paid ? 20000 : null,
  actualPaymentDate: status == ScheduledOccurrenceStatus.paid ? day : null,
  reservationOperationId: reservationOperationId,
  revision: revision,
  operationId: operationId,
  changedAt: DateTime.utc(2026, 8, 24),
  deviceId: 'device-a',
);

ReservationOperationRecord _allocation(
  String id,
  DateTime day, {
  int revision = 1,
}) => ReservationOperationRecord(
  id: id,
  containerType: ReservationContainerType.fund,
  containerId: 'bills',
  fundingAccountId: 'checking',
  kind: ReservationOperationKind.allocate,
  amountMinor: 20000,
  effectiveDate: day,
  revision: revision,
  baseRevision: revision - 1,
  operationId: id,
  deviceId: 'device-a',
  scheduledTransactionId: 'schedule',
  scheduledOccurrenceDate: day,
  sync: SyncMetadata.fresh(
    now: DateTime.utc(2026, 8, 24),
    deviceId: 'device-a',
  ),
);

ReservationOperationRecord _reversal({
  required String id,
  required DateTime day,
  required String allocationId,
}) => ReservationOperationRecord(
  id: id,
  containerType: ReservationContainerType.fund,
  containerId: 'bills',
  fundingAccountId: 'checking',
  kind: ReservationOperationKind.reversal,
  amountMinor: 20000,
  effectiveDate: day,
  revision: 2,
  baseRevision: 1,
  operationId: id,
  deviceId: 'device-a',
  scheduledTransactionId: 'schedule',
  scheduledOccurrenceDate: day,
  reversesOperationId: allocationId,
  sync: SyncMetadata.fresh(
    now: DateTime.utc(2026, 8, 24),
    deviceId: 'device-a',
  ),
);
