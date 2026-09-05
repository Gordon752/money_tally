import 'dart:math';

import '../domain/fund.dart';
import '../domain/reservation.dart';
import '../domain/transaction.dart';

/// Derived, non-persisted progress for a recurring Fund target.
///
/// [reservedMinor] remains the authoritative reservation total. Consumption
/// only reduces the remaining requirement of the cycle to which the linked
/// transaction belongs; it never creates or restores reserved money.
class RecurringFundCycleProgress {
  const RecurringFundCycleProgress._({
    required this.reservedMinor,
    required this.completedCycles,
    required this.activeCycleFundedMinor,
    required this.cycleTargetMinor,
    required this.currentCycleTargetDate,
    required this.activeCycleTargetDate,
    required this.activeCycleFundingDeadline,
  });

  /// For a reservation without consumption history. Production callers with
  /// history use [calculateRecurringFundCycleProgress] instead.
  factory RecurringFundCycleProgress.fromReservation({
    required FundRecord fund,
    required int reservedMinor,
    DateTime? asOf,
  }) => RecurringFundCycleProgress._fromCoverage(
    fund: fund,
    currentCycleDate: effectiveFundTargetDate(fund, asOf: asOf),
    reservedMinor: reservedMinor,
    completedCycles: fund.targetBalanceMinor > 0
        ? reservedMinor ~/ fund.targetBalanceMinor
        : 0,
    activeCycleFundedMinor: fund.targetBalanceMinor > 0
        ? reservedMinor % fund.targetBalanceMinor
        : reservedMinor,
  );

  factory RecurringFundCycleProgress._fromCoverage({
    required FundRecord fund,
    required DateTime? currentCycleDate,
    required int reservedMinor,
    required int completedCycles,
    required int activeCycleFundedMinor,
  }) {
    DateTime? checkpoint(int offset) {
      if (currentCycleDate == null) return null;
      return fundTargetBoundary(
        fund,
        year: currentCycleDate.year,
        month: currentCycleDate.month + offset,
      );
    }

    return RecurringFundCycleProgress._(
      reservedMinor: reservedMinor,
      completedCycles: completedCycles,
      activeCycleFundedMinor: activeCycleFundedMinor,
      cycleTargetMinor: fund.targetBalanceMinor,
      currentCycleTargetDate: currentCycleDate,
      activeCycleTargetDate: checkpoint(completedCycles),
      // A cycle covers obligations after the preceding checkpoint through its
      // own checkpoint. Its funding must be ready at that preceding boundary.
      activeCycleFundingDeadline: checkpoint(completedCycles - 1),
    );
  }

  final int reservedMinor;
  final int completedCycles;
  final int activeCycleFundedMinor;
  final int cycleTargetMinor;
  final DateTime? currentCycleTargetDate;
  final DateTime? activeCycleTargetDate;
  final DateTime? activeCycleFundingDeadline;

  int get activeCycleRemainingMinor =>
      max(0, cycleTargetMinor - activeCycleFundedMinor);
  double get activeCycleProgress =>
      cycleTargetMinor > 0 ? activeCycleFundedMinor / cycleTargetMinor : 0;
  int get activeCyclePercent => cycleTargetMinor > 0
      ? ((activeCycleFundedMinor * 100 + cycleTargetMinor ~/ 2) ~/
                cycleTargetMinor)
            .clamp(0, 99)
      : 0;
  bool get isExactlyFunded =>
      completedCycles > 0 && activeCycleFundedMinor == 0;
  double get barProgress => completedCycles > 0 ? 1 : activeCycleProgress;
  bool get showsMovingCycleBoundary =>
      completedCycles > 0 && activeCycleFundedMinor > 0;
}

/// Reconstructs recurring-cycle presentation from authoritative reservation
/// history and linked transactions without maintaining monthly balances.
///
/// The remaining reservation is applied oldest-cycle-first. Effective Fund
/// consumption reduces only its attributed cycle's remaining requirement.
/// Each attribution date is first resolved through the Fund's anchored target
/// checkpoints; it is never bucketed by calendar month alone. Scheduled
/// transactions use their occurrence date, while ordinary/manual transactions
/// use their effective transaction date.
RecurringFundCycleProgress calculateRecurringFundCycleProgress({
  required FundRecord fund,
  required Iterable<ReservationOperationRecord> effectiveOperations,
  required Iterable<TransactionRecord> transactions,
  required DateTime asOf,
}) {
  final operations = effectiveOperations.toList(growable: false);
  final ledger = calculateReservationLedger(operations: operations, asOf: asOf);
  final reserved = ledger.reservedMinor;
  final target = fund.targetBalanceMinor;
  final currentCycleDate = effectiveFundTargetDate(fund, asOf: asOf);
  RecurringFundCycleProgress snapshot(int completed, int activeFunded) =>
      RecurringFundCycleProgress._fromCoverage(
        fund: fund,
        currentCycleDate: currentCycleDate,
        reservedMinor: reserved,
        completedCycles: completed,
        activeCycleFundedMinor: activeFunded,
      );
  if (target <= 0 ||
      fund.targetCadence != FundTargetCadence.monthly ||
      currentCycleDate == null) {
    return snapshot(
      target > 0 ? reserved ~/ target : 0,
      target > 0 ? reserved % target : reserved,
    );
  }

  final transactionById = {
    for (final transaction in transactions) transaction.id: transaction,
  };
  final consumedByCycle = <int, int>{};
  for (final operation in operations) {
    if (operation.kind != ReservationOperationKind.consume ||
        !ledger.acceptedOperationIds.contains(operation.id) ||
        ledger.reversedOperationIds.contains(operation.id)) {
      continue;
    }
    final transactionId = operation.transactionId;
    final transaction = transactionId == null
        ? null
        : transactionById[transactionId];
    if (transaction == null || transaction.isDeleted) continue;

    // A recorded occurrence is authoritative even when it was paid early or
    // late. A transaction used to create future occurrences has no occurrence
    // date, so it remains an ordinary transaction attributed by its own date.
    final attributionDate =
        transaction.scheduledOccurrenceDate ??
        operation.scheduledOccurrenceDate ??
        transaction.date;
    final attributedCycleDate = effectiveFundTargetDate(
      fund,
      asOf: attributionDate,
    );
    if (attributedCycleDate == null) continue;
    final cycleIndex = _monthlyCycleDistance(
      currentCycleDate,
      attributedCycleDate,
    );
    if (cycleIndex < 0) continue;
    consumedByCycle.update(
      cycleIndex,
      (amount) => min(target, amount + operation.amountMinor),
      ifAbsent: () => min(target, operation.amountMinor),
    );
  }

  var remainingReserved = reserved;
  var completedCycles = 0;
  var cycleIndex = 0;
  final consumedCycles = consumedByCycle.keys.toList(growable: false)..sort();

  for (final consumedCycleIndex in consumedCycles) {
    final emptyCycleCount = consumedCycleIndex - cycleIndex;
    if (emptyCycleCount > 0) {
      final fundableEmptyCycles = min(
        emptyCycleCount,
        remainingReserved ~/ target,
      );
      completedCycles += fundableEmptyCycles;
      remainingReserved -= fundableEmptyCycles * target;
      cycleIndex += fundableEmptyCycles;
      if (fundableEmptyCycles < emptyCycleCount) {
        return snapshot(completedCycles, remainingReserved);
      }
    }

    final consumed = consumedByCycle[consumedCycleIndex]!;
    final remainingRequirement = target - consumed;
    final reservedForCycle = min(remainingReserved, remainingRequirement);
    remainingReserved -= reservedForCycle;
    final funded = consumed + reservedForCycle;
    if (funded < target) {
      return snapshot(completedCycles, funded);
    }
    completedCycles += 1;
    cycleIndex += 1;
  }

  completedCycles += remainingReserved ~/ target;
  return snapshot(completedCycles, remainingReserved % target);
}

int _monthlyCycleDistance(DateTime from, DateTime to) =>
    (to.year - from.year) * 12 + to.month - from.month;
