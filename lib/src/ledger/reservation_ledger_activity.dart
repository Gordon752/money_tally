import '../domain/finance_data_set.dart';
import '../domain/fund.dart';
import '../domain/goal.dart';
import '../domain/reservation.dart';
import '../domain/scheduled_transaction.dart';
import '../domain/transaction.dart';

/// A non-financial Goal or Fund reservation movement shown in the Ledger.
///
/// This projection deliberately has no financial-summary contribution. The
/// underlying reservation operation changes the job assigned to existing
/// money; it does not create income, expense, or an account-balance delta.
class LedgerReservationActivityProjection {
  const LedgerReservationActivityProjection({
    required this.reservationOperationId,
    required this.containerType,
    required this.containerId,
    required this.containerName,
    required this.fundingAccountId,
    required this.kind,
    required this.amountMinor,
    required this.effectiveDate,
    required this.createdAt,
    this.causationId,
    this.note = '',
  }) : assert(
         kind == ReservationOperationKind.allocate ||
             kind == ReservationOperationKind.returnFunds,
       );

  final String reservationOperationId;
  final ReservationContainerType containerType;
  final String containerId;
  final String containerName;
  final String fundingAccountId;
  final ReservationOperationKind kind;
  final int amountMinor;
  final DateTime effectiveDate;
  final DateTime createdAt;
  final String? causationId;
  final String note;

  bool get isAllocation => kind == ReservationOperationKind.allocate;
  bool get isReturn => kind == ReservationOperationKind.returnFunds;
}

/// Projects authoritative reservation allocations and returns for Ledger UI.
///
/// Operations are resolved independently per stable Goal/Fund identity through
/// [effectiveReservationOperationsForContainer], then accepted/reversed state
/// is reconstructed by [calculateReservationLedger]. Consumption is represented
/// by its linked real transaction elsewhere in the Ledger, while reversal
/// records only select which original operation remains effective.
///
/// The returned activities are newest first. Deleted container tombstones are
/// intentionally retained when supplied so their historical names can remain
/// visible after a Goal or Fund is deleted.
List<LedgerReservationActivityProjection> projectLedgerReservationActivities({
  required Iterable<GoalRecord> goals,
  required Iterable<FundRecord> funds,
  required Iterable<ReservationOperationRecord> operations,
  required Iterable<TransactionRecord> transactions,
  Iterable<ScheduledTransactionRecord> scheduledTransactions = const [],
}) {
  final containerNames = <_ReservationContainerKey, String>{
    for (final goal in goals)
      _ReservationContainerKey(ReservationContainerType.goal, goal.id):
          goal.name,
    for (final fund in funds)
      _ReservationContainerKey(ReservationContainerType.fund, fund.id):
          fund.name,
  };
  final operationsByContainer =
      <_ReservationContainerKey, List<ReservationOperationRecord>>{};
  for (final operation in operations) {
    final key = _ReservationContainerKey(
      operation.containerType,
      operation.containerId,
    );
    operationsByContainer.putIfAbsent(key, () => []).add(operation);
  }

  final transactionRecords = transactions.toList(growable: false);
  final scheduleRecords = scheduledTransactions.toList(growable: false);
  final activities = <LedgerReservationActivityProjection>[];

  for (final entry in operationsByContainer.entries) {
    final key = entry.key;
    final effective = effectiveReservationOperationsForContainer(
      operations: entry.value,
      transactions: transactionRecords,
      scheduledTransactions: scheduleRecords,
      containerType: key.type,
      containerId: key.id,
    );
    final ledger = calculateReservationLedger(operations: effective);
    for (final operation in effective) {
      if (!ledger.acceptedOperationIds.contains(operation.id) ||
          ledger.reversedOperationIds.contains(operation.id) ||
          (operation.kind != ReservationOperationKind.allocate &&
              operation.kind != ReservationOperationKind.returnFunds)) {
        continue;
      }
      activities.add(
        LedgerReservationActivityProjection(
          reservationOperationId: operation.id,
          containerType: operation.containerType,
          containerId: operation.containerId,
          containerName:
              containerNames[key] ??
              (key.type == ReservationContainerType.goal ? 'Goal' : 'Fund'),
          fundingAccountId: operation.fundingAccountId,
          kind: operation.kind,
          amountMinor: operation.amountMinor,
          effectiveDate: operation.effectiveDate,
          createdAt: operation.sync.createdAt,
          causationId: operation.causationId,
          note: operation.note,
        ),
      );
    }
  }

  activities.sort((left, right) {
    final dateOrder = right.effectiveDate.compareTo(left.effectiveDate);
    if (dateOrder != 0) return dateOrder;
    final createdOrder = right.createdAt.compareTo(left.createdAt);
    if (createdOrder != 0) return createdOrder;
    return right.reservationOperationId.compareTo(left.reservationOperationId);
  });
  return List.unmodifiable(activities);
}

class _ReservationContainerKey {
  const _ReservationContainerKey(this.type, this.id);

  final ReservationContainerType type;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is _ReservationContainerKey && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}
