import 'dart:math';

import 'scheduled_transaction.dart';

/// Creates a globally unique, clock-independent operation identifier.
///
/// Lexical ordering is used only to converge concurrent operations that were
/// created from the same base revision; it is not intended to express time.
String newScheduledOccurrenceOperationId({Random? random}) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < 16; index += 1) {
    buffer.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

ScheduledOccurrenceHistoryEpoch occurrenceHistoryEpochFor(
  ScheduledTransactionRecord schedule,
) => schedule.occurrenceHistoryEpoch ?? ScheduledOccurrenceHistoryEpoch.legacy;

ScheduledOccurrenceHistoryEpoch nextOccurrenceHistoryEpoch({
  required ScheduledTransactionRecord schedule,
  required String deviceId,
  String? operationId,
  DateTime? changedAt,
}) {
  final current = occurrenceHistoryEpochFor(schedule);
  return ScheduledOccurrenceHistoryEpoch(
    revision: current.revision + 1,
    operationId: operationId ?? newScheduledOccurrenceOperationId(),
    changedAt: (changedAt ?? DateTime.now()).toUtc(),
    deviceId: deviceId,
  );
}

bool _stateBelongsToEpoch(
  ScheduledOccurrenceState state,
  ScheduledOccurrenceHistoryEpoch epoch,
) =>
    state.historyEpochRevision == epoch.revision &&
    state.historyEpochOperationId == epoch.operationId;

Map<String, ScheduledOccurrenceState> _occurrenceAuthorityForEpoch(
  ScheduledTransactionRecord schedule,
  ScheduledOccurrenceHistoryEpoch epoch,
) {
  final result = <String, ScheduledOccurrenceState>{
    for (final entry in schedule.occurrenceStates.entries)
      if (_stateBelongsToEpoch(entry.value, epoch)) entry.key: entry.value,
  };
  // Legacy occurrence mirrors have no epoch identity. They are authoritative
  // only before the first explicit history reset.
  if (!sameOccurrenceHistoryEpoch(
    epoch,
    ScheduledOccurrenceHistoryEpoch.legacy,
  )) {
    return result;
  }
  for (final occurrence in schedule.occurrences) {
    final key = occurrenceDayKey(occurrence.scheduledDate);
    if (result.containsKey(key)) continue;
    final resolved = occurrence.status != ScheduledOccurrenceStatus.pending;
    result[key] = ScheduledOccurrenceState(
      scheduledDate: occurrence.scheduledDate,
      plannedAmountMinor: occurrence.plannedAmountMinor,
      status: occurrence.status,
      actualAmountMinor: occurrence.actualAmountMinor,
      actualPaymentDate: occurrence.actualPaymentDate,
      transactionId: occurrence.transactionId,
      goalFundingEventId: occurrence.goalFundingEventId,
      reservationOperationId: occurrence.reservationOperationId,
      revision: resolved ? 1 : 0,
      operationId: 'legacy_${occurrence.status.name}_$key',
      changedAt:
          occurrence.actualPaymentDate?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deviceId: 'legacy',
    );
  }
  return result;
}

Map<String, ScheduledOccurrenceState> occurrenceAuthorityFor(
  ScheduledTransactionRecord schedule,
) =>
    _occurrenceAuthorityForEpoch(schedule, occurrenceHistoryEpochFor(schedule));

Map<String, ScheduledOccurrenceState> mergeOccurrenceAuthority(
  ScheduledTransactionRecord left,
  ScheduledTransactionRecord right,
) {
  final epoch = authoritativeOccurrenceHistoryEpoch(
    occurrenceHistoryEpochFor(left),
    occurrenceHistoryEpochFor(right),
  );
  final leftStates = _occurrenceAuthorityForEpoch(left, epoch);
  final rightStates = _occurrenceAuthorityForEpoch(right, epoch);
  final keys = {...leftStates.keys, ...rightStates.keys};
  return {
    for (final key in keys)
      key: switch ((leftStates[key], rightStates[key])) {
        (final left?, final right?) => authoritativeOccurrenceState(
          left,
          right,
        ),
        (final left?, null) => left,
        (null, final right?) => right,
        _ => throw StateError('Missing occurrence authority for $key'),
      },
  };
}

ScheduledOccurrenceState nextOccurrenceOperation({
  required ScheduledTransactionRecord schedule,
  required DateTime scheduledDate,
  required int plannedAmountMinor,
  required ScheduledOccurrenceStatus status,
  required String deviceId,
  String? operationId,
  DateTime? changedAt,
  int? actualAmountMinor,
  DateTime? actualPaymentDate,
  String? transactionId,
  String? goalFundingEventId,
  String? reservationOperationId,
}) {
  final key = occurrenceDayKey(scheduledDate);
  final current = occurrenceAuthorityFor(schedule)[key];
  return ScheduledOccurrenceState(
    scheduledDate: DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
    ),
    plannedAmountMinor: plannedAmountMinor,
    status: status,
    actualAmountMinor: actualAmountMinor,
    actualPaymentDate: actualPaymentDate,
    transactionId: transactionId,
    goalFundingEventId: goalFundingEventId,
    reservationOperationId: reservationOperationId,
    revision: (current?.revision ?? 0) + 1,
    operationId: operationId ?? newScheduledOccurrenceOperationId(),
    changedAt: (changedAt ?? DateTime.now()).toUtc(),
    deviceId: deviceId,
    historyEpochRevision: occurrenceHistoryEpochFor(schedule).revision,
    historyEpochOperationId: occurrenceHistoryEpochFor(schedule).operationId,
  );
}

ScheduledOccurrenceState rebasePendingOccurrenceState(
  ScheduledOccurrenceState state,
  ScheduledOccurrenceHistoryEpoch epoch,
) {
  if (state.status != ScheduledOccurrenceStatus.pending) {
    throw ArgumentError('Only Pending occurrence state can cross a reset.');
  }
  return ScheduledOccurrenceState(
    scheduledDate: state.scheduledDate,
    plannedAmountMinor: state.plannedAmountMinor,
    status: state.status,
    revision: state.revision,
    operationId: state.operationId,
    changedAt: state.changedAt,
    deviceId: state.deviceId,
    historyEpochRevision: epoch.revision,
    historyEpochOperationId: epoch.operationId,
    actualAmountMinor: state.actualAmountMinor,
    actualPaymentDate: state.actualPaymentDate,
    transactionId: state.transactionId,
    goalFundingEventId: state.goalFundingEventId,
    reservationOperationId: state.reservationOperationId,
  );
}

DateTime? effectiveNextActionableDate(ScheduledTransactionRecord schedule) {
  if (schedule.isDeleted) return null;
  final states = occurrenceAuthorityFor(schedule);
  var candidate = schedule.nextDate;

  // A newer explicit Pending operation is Undo authority. It can reopen a
  // resolved date earlier than the stored compatibility nextDate.
  final reopened =
      states.values
          .where(
            (state) =>
                state.status == ScheduledOccurrenceStatus.pending &&
                state.revision > 0,
          )
          .map((state) => state.scheduledDate)
          .where((date) => date.isBefore(candidate))
          .toList(growable: false)
        ..sort();
  if (reopened.isNotEmpty) candidate = reopened.first;

  for (var iteration = 0; iteration < 12000; iteration += 1) {
    final endDate = schedule.endDate;
    if (endDate != null && candidate.isAfter(endDate)) return null;
    final state = states[occurrenceDayKey(candidate)];
    if (state == null || state.status == ScheduledOccurrenceStatus.pending) {
      return candidate;
    }
    final next = nextScheduledOccurrenceDate(candidate, schedule.frequency);
    if (next == null || !next.isAfter(candidate)) return null;
    candidate = next;
  }
  return null;
}

DateTime? nextScheduledOccurrenceDate(
  DateTime date,
  RecurrenceFrequency frequency,
) => switch (frequency) {
  RecurrenceFrequency.once => null,
  RecurrenceFrequency.weekly => date.add(const Duration(days: 7)),
  RecurrenceFrequency.biweekly => date.add(const Duration(days: 14)),
  RecurrenceFrequency.monthly => DateTime(date.year, date.month + 1, date.day),
  RecurrenceFrequency.yearly => DateTime(date.year + 1, date.month, date.day),
};

List<ScheduledOccurrenceRecord> legacyOccurrencesFromAuthority(
  Iterable<ScheduledOccurrenceState> states,
) {
  final result = states.map((state) => state.toLegacyRecord()).toList()
    ..sort((left, right) => left.scheduledDate.compareTo(right.scheduledDate));
  return result;
}

ScheduledTransactionRecord withOccurrenceAuthority(
  ScheduledTransactionRecord schedule,
  ScheduledOccurrenceState state, {
  bool normalizeNextDate = true,
}) {
  final epoch = occurrenceHistoryEpochFor(schedule);
  if (!_stateBelongsToEpoch(state, epoch)) {
    throw StateError('Occurrence operation belongs to stale history epoch.');
  }
  final states = occurrenceAuthorityFor(schedule);
  final key = occurrenceDayKey(state.scheduledDate);
  final current = states[key];
  states[key] = current == null
      ? state
      : authoritativeOccurrenceState(current, state);
  var updated = schedule.copyWith(
    occurrenceStates: states,
    occurrences: legacyOccurrencesFromAuthority(states.values),
    sync: schedule.sync,
  );
  if (normalizeNextDate) {
    final effective = effectiveNextActionableDate(updated);
    if (effective != null) {
      updated = updated.copyWith(
        nextDate: effective,
        lastAction: ScheduledAction.none,
        sync: schedule.sync,
      );
    }
  }
  return updated;
}

ScheduledTransactionRecord mergeScheduledTransactionAuthority({
  required ScheduledTransactionRecord incoming,
  required ScheduledTransactionRecord current,
  required bool preferCurrentOnDefinitionTie,
}) {
  final incomingSync = incoming.sync;
  final currentSync = current.sync;
  final historyEpoch = authoritativeOccurrenceHistoryEpoch(
    occurrenceHistoryEpochFor(incoming),
    occurrenceHistoryEpochFor(current),
  );
  var definition =
      currentSync.updatedAt.isAfter(incomingSync.updatedAt) ||
          (preferCurrentOnDefinitionTie &&
              currentSync.updatedAt.isAtSameMomentAs(incomingSync.updatedAt))
      ? current
      : incoming;
  final states = mergeOccurrenceAuthority(incoming, current);
  if (incoming.isDeleted != current.isDeleted) {
    final deleted = incoming.isDeleted ? incoming : current;
    final active = incoming.isDeleted ? current : incoming;
    final deletedStates = occurrenceAuthorityFor(deleted);
    final activeStates =
        sameOccurrenceHistoryEpoch(
          occurrenceHistoryEpochFor(active),
          historyEpoch,
        )
        ? _occurrenceAuthorityForEpoch(active, historyEpoch)
        : const <String, ScheduledOccurrenceState>{};
    final hasCausalUndo = activeStates.entries.any((entry) {
      final activeState = entry.value;
      if (activeState.status != ScheduledOccurrenceStatus.pending ||
          activeState.revision <= 0) {
        return false;
      }
      final deletedState = deletedStates[entry.key];
      return deletedState != null &&
          identical(
            authoritativeOccurrenceState(deletedState, activeState),
            activeState,
          ) &&
          (activeState.revision != deletedState.revision ||
              activeState.operationId != deletedState.operationId);
    });
    // A tombstone remains authoritative unless a newer Pending occurrence
    // operation explicitly restores it. Definition timestamps alone cannot
    // resurrect a completed or manually deleted schedule.
    definition = hasCausalUndo ? active : deleted;
  }
  var merged = definition.copyWith(
    occurrenceStates: states,
    occurrences: legacyOccurrencesFromAuthority(states.values),
    occurrenceHistoryEpoch:
        incoming.occurrenceHistoryEpoch == null &&
            current.occurrenceHistoryEpoch == null
        ? null
        : historyEpoch,
    // Notification bookkeeping is device local in the new model.
    scheduledNotificationIds: const [],
    clearLastReminderScheduledAt: true,
    sync: definition.sync,
  );
  final effective = effectiveNextActionableDate(merged);
  if (effective != null) {
    merged = merged.copyWith(
      nextDate: effective,
      lastAction: ScheduledAction.none,
      sync: definition.sync,
    );
  }
  return merged;
}
