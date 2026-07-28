import 'json_helpers.dart';
import 'sync_metadata.dart';

class GoalFundingAllocation {
  const GoalFundingAllocation({
    required this.id,
    required this.fundingEventId,
    required this.goalId,
    required this.amountMinor,
    required this.order,
  });

  final String id;
  final String fundingEventId;
  final String goalId;
  final int amountMinor;
  final int order;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'fundingEventId': fundingEventId,
      'goalId': goalId,
      'amountMinor': amountMinor,
      'order': order,
    };
  }

  factory GoalFundingAllocation.fromJson(Map<String, Object?> json) {
    return GoalFundingAllocation(
      id: json['id'] as String,
      fundingEventId: json['fundingEventId'] as String? ?? '',
      goalId: json['goalId'] as String,
      amountMinor: json['amountMinor'] as int? ?? 0,
      order: json['order'] as int? ?? 0,
    );
  }
}

class GoalFundingEventRecord {
  const GoalFundingEventRecord({
    required this.id,
    required this.sourceAccountId,
    required this.totalAmountMinor,
    required this.date,
    required this.allocations,
    required this.sync,
    this.note = '',
    this.isMigrationEvent = false,
    this.scheduledTransactionId,
    this.scheduledOccurrenceDate,
    this.scheduledPlannedAmountMinor,
  });

  final String id;
  final String sourceAccountId;
  final int totalAmountMinor;
  final DateTime date;
  final String note;
  final List<GoalFundingAllocation> allocations;
  final bool isMigrationEvent;
  final String? scheduledTransactionId;
  final DateTime? scheduledOccurrenceDate;
  final int? scheduledPlannedAmountMinor;
  final SyncMetadata sync;

  bool get isDeleted => sync.isDeleted;
  bool get isActive => !isDeleted;
  DateTime get createdDate => sync.createdAt;
  DateTime get updatedDate => sync.updatedAt;

  int get allocationTotalMinor => allocations.fold(
    0,
    (total, allocation) => total + allocation.amountMinor,
  );

  GoalFundingEventRecord copyWith({
    String? sourceAccountId,
    int? totalAmountMinor,
    DateTime? date,
    String? note,
    List<GoalFundingAllocation>? allocations,
    bool? isMigrationEvent,
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    int? scheduledPlannedAmountMinor,
    SyncMetadata? sync,
  }) {
    return GoalFundingEventRecord(
      id: id,
      sourceAccountId: sourceAccountId ?? this.sourceAccountId,
      totalAmountMinor: totalAmountMinor ?? this.totalAmountMinor,
      date: date ?? this.date,
      note: note ?? this.note,
      allocations: allocations ?? this.allocations,
      isMigrationEvent: isMigrationEvent ?? this.isMigrationEvent,
      scheduledTransactionId:
          scheduledTransactionId ?? this.scheduledTransactionId,
      scheduledOccurrenceDate:
          scheduledOccurrenceDate ?? this.scheduledOccurrenceDate,
      scheduledPlannedAmountMinor:
          scheduledPlannedAmountMinor ?? this.scheduledPlannedAmountMinor,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'sourceAccountId': sourceAccountId,
      'totalAmountMinor': totalAmountMinor,
      'date': date.toIso8601String(),
      'note': note,
      'allocations': allocations.map((item) => item.toJson()).toList(),
      'isMigrationEvent': isMigrationEvent,
      'scheduledTransactionId': scheduledTransactionId,
      'scheduledOccurrenceDate': scheduledOccurrenceDate?.toIso8601String(),
      'scheduledPlannedAmountMinor': scheduledPlannedAmountMinor,
      'sync': sync.toJson(),
    };
  }

  factory GoalFundingEventRecord.fromJson(Map<String, Object?> json) {
    return GoalFundingEventRecord(
      id: json['id'] as String,
      sourceAccountId: json['sourceAccountId'] as String? ?? '',
      totalAmountMinor: json['totalAmountMinor'] as int? ?? 0,
      date: dateTimeFromJson(json['date']),
      note: json['note'] as String? ?? '',
      allocations: stringMapList(
        json['allocations'],
      ).map(GoalFundingAllocation.fromJson).toList(growable: false),
      isMigrationEvent: json['isMigrationEvent'] as bool? ?? false,
      scheduledTransactionId: json['scheduledTransactionId'] as String?,
      scheduledOccurrenceDate: json['scheduledOccurrenceDate'] == null
          ? null
          : dateTimeFromJson(json['scheduledOccurrenceDate']),
      scheduledPlannedAmountMinor: json['scheduledPlannedAmountMinor'] as int?,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
