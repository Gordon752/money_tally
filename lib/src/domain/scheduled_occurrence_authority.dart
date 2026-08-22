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

Map<String, ScheduledOccurrenceState> occurrenceAuthorityFor(
  ScheduledTransactionRecord schedule,
) {
  final result = <String, ScheduledOccurrenceState>{
    ...schedule.occurrenceStates,
  };
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

Map<String, ScheduledOccurrenceState> mergeOccurrenceAuthority(
  ScheduledTransactionRecord left,
  ScheduledTransactionRecord right,
) {
  final leftStates = occurrenceAuthorityFor(left);
  final rightStates = occurrenceAuthorityFor(right);
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
    revision: (current?.revision ?? 0) + 1,
    operationId: operationId ?? newScheduledOccurrenceOperationId(),
    changedAt: (changedAt ?? DateTime.now()).toUtc(),
    deviceId: deviceId,
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
    final activeStates = occurrenceAuthorityFor(active);
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
