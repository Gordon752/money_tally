import 'dart:math';

import 'json_helpers.dart';
import 'sync_metadata.dart';

/// Globally unique and clock-independent. Lexical ordering is used only to
/// make concurrent operations deterministic; it does not imply chronology.
String newReservationOperationId({Random? random}) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < 16; index += 1) {
    buffer.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

enum ReservationContainerType { goal, fund }

enum ReservationOperationKind { allocate, returnFunds, consume, reversal }

class ReservationOperationRecord {
  const ReservationOperationRecord({
    required this.id,
    required this.containerType,
    required this.containerId,
    required this.fundingAccountId,
    required this.kind,
    required this.amountMinor,
    required this.effectiveDate,
    required this.revision,
    required this.baseRevision,
    required this.operationId,
    required this.deviceId,
    required this.sync,
    this.transactionId,
    this.scheduledTransactionId,
    this.scheduledOccurrenceDate,
    this.reversesOperationId,
    this.causationId,
    this.note = '',
  });

  final String id;
  final ReservationContainerType containerType;
  final String containerId;
  final String fundingAccountId;
  final ReservationOperationKind kind;
  final int amountMinor;
  final DateTime effectiveDate;

  /// Lamport-style container revision. Concurrent operations may share a
  /// revision and converge through [operationId] ordering.
  final int revision;
  final int baseRevision;
  final String operationId;
  final String deviceId;
  final String? transactionId;
  final String? scheduledTransactionId;
  final DateTime? scheduledOccurrenceDate;
  final String? reversesOperationId;
  final String? causationId;
  final String note;
  final SyncMetadata sync;

  bool get isDeleted => sync.isDeleted;
  bool get isActive => !isDeleted;

  ReservationOperationRecord copyWith({SyncMetadata? sync}) =>
      ReservationOperationRecord(
        id: id,
        containerType: containerType,
        containerId: containerId,
        fundingAccountId: fundingAccountId,
        kind: kind,
        amountMinor: amountMinor,
        effectiveDate: effectiveDate,
        revision: revision,
        baseRevision: baseRevision,
        operationId: operationId,
        deviceId: deviceId,
        transactionId: transactionId,
        scheduledTransactionId: scheduledTransactionId,
        scheduledOccurrenceDate: scheduledOccurrenceDate,
        reversesOperationId: reversesOperationId,
        causationId: causationId,
        note: note,
        sync: sync ?? this.sync,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'containerType': containerType.name,
    'containerId': containerId,
    'fundingAccountId': fundingAccountId,
    'kind': kind.name,
    'amountMinor': amountMinor,
    'effectiveDate': effectiveDate.toIso8601String(),
    'revision': revision,
    'baseRevision': baseRevision,
    'operationId': operationId,
    'deviceId': deviceId,
    'transactionId': transactionId,
    'scheduledTransactionId': scheduledTransactionId,
    'scheduledOccurrenceDate': scheduledOccurrenceDate?.toIso8601String(),
    'reversesOperationId': reversesOperationId,
    'causationId': causationId,
    'note': note,
    'sync': sync.toJson(),
  };

  factory ReservationOperationRecord.fromJson(Map<String, Object?> json) =>
      ReservationOperationRecord(
        id: json['id'] as String,
        containerType: enumByName(
          ReservationContainerType.values,
          json['containerType'],
          ReservationContainerType.goal,
        ),
        containerId: json['containerId'] as String? ?? '',
        fundingAccountId: json['fundingAccountId'] as String? ?? '',
        kind: enumByName(
          ReservationOperationKind.values,
          json['kind'],
          ReservationOperationKind.allocate,
        ),
        amountMinor: json['amountMinor'] as int? ?? 0,
        effectiveDate: dateTimeFromJson(json['effectiveDate']),
        revision: json['revision'] as int? ?? 0,
        baseRevision: json['baseRevision'] as int? ?? 0,
        operationId: json['operationId'] as String? ?? json['id'] as String,
        deviceId: json['deviceId'] as String? ?? '',
        transactionId: json['transactionId'] as String?,
        scheduledTransactionId: json['scheduledTransactionId'] as String?,
        scheduledOccurrenceDate: json['scheduledOccurrenceDate'] == null
            ? null
            : dateTimeFromJson(json['scheduledOccurrenceDate']),
        reversesOperationId: json['reversesOperationId'] as String?,
        causationId: json['causationId'] as String?,
        note: json['note'] as String? ?? '',
        sync: SyncMetadata.fromJson(stringMap(json['sync'])),
      );
}

class ReservationLedgerResult {
  const ReservationLedgerResult({
    required this.reservedMinor,
    required this.latestRevision,
    required this.acceptedOperationIds,
    required this.conflictedOperationIds,
    required this.reversedOperationIds,
  });

  final int reservedMinor;
  final int latestRevision;
  final Set<String> acceptedOperationIds;
  final Set<String> conflictedOperationIds;
  final Set<String> reversedOperationIds;
}

/// Deterministically reconstructs a reservation without persisting a cached
/// financial total. Negative operations that race beyond the remaining
/// reservation are retained as explicit conflicts rather than being clamped.
ReservationLedgerResult calculateReservationLedger({
  required Iterable<ReservationOperationRecord> operations,
  DateTime? asOf,
}) {
  final cutoff = asOf == null
      ? null
      : DateTime(asOf.year, asOf.month, asOf.day);
  final ordered =
      operations
          .where((operation) {
            if (!operation.isActive || operation.amountMinor <= 0) return false;
            if (cutoff == null) return true;
            final day = DateTime(
              operation.effectiveDate.year,
              operation.effectiveDate.month,
              operation.effectiveDate.day,
            );
            return !day.isAfter(cutoff);
          })
          .toList(growable: false)
        ..sort(_compareReservationOperations);

  final accepted = <String>{};
  final conflicted = <String>{};
  final operationById = {
    for (final operation in ordered) operation.id: operation,
  };
  final reversedTargets = <String>{};
  var reserved = 0;
  var latestRevision = 0;

  for (final operation in ordered) {
    if (operation.revision > latestRevision) {
      latestRevision = operation.revision;
    }
    int delta;
    switch (operation.kind) {
      case ReservationOperationKind.allocate:
        delta = operation.amountMinor;
      case ReservationOperationKind.returnFunds:
      case ReservationOperationKind.consume:
        delta = -operation.amountMinor;
      case ReservationOperationKind.reversal:
        final targetId = operation.reversesOperationId;
        final target = targetId == null ? null : operationById[targetId];
        if (target == null ||
            !accepted.contains(target.id) ||
            !reversedTargets.add(target.id)) {
          conflicted.add(operation.id);
          continue;
        }
        delta = -_baseReservationDelta(target);
    }
    if (reserved + delta < 0) {
      conflicted.add(operation.id);
      if (operation.kind == ReservationOperationKind.reversal &&
          operation.reversesOperationId != null) {
        reversedTargets.remove(operation.reversesOperationId);
      }
      continue;
    }
    reserved += delta;
    accepted.add(operation.id);
  }

  return ReservationLedgerResult(
    reservedMinor: reserved,
    latestRevision: latestRevision,
    acceptedOperationIds: Set.unmodifiable(accepted),
    conflictedOperationIds: Set.unmodifiable(conflicted),
    reversedOperationIds: Set.unmodifiable(reversedTargets),
  );
}

int _baseReservationDelta(ReservationOperationRecord operation) =>
    switch (operation.kind) {
      ReservationOperationKind.allocate => operation.amountMinor,
      ReservationOperationKind.returnFunds ||
      ReservationOperationKind.consume => -operation.amountMinor,
      ReservationOperationKind.reversal => 0,
    };

int _compareReservationOperations(
  ReservationOperationRecord left,
  ReservationOperationRecord right,
) {
  final revisionOrder = left.revision.compareTo(right.revision);
  if (revisionOrder != 0) return revisionOrder;
  final operationOrder = left.operationId.compareTo(right.operationId);
  if (operationOrder != 0) return operationOrder;
  return left.id.compareTo(right.id);
}
