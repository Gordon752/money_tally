import 'json_helpers.dart';
import 'reservation.dart';
import 'sync_metadata.dart';
import 'transaction.dart';

class ScheduledGoalFundingAllocation {
  const ScheduledGoalFundingAllocation({
    required this.id,
    required this.goalId,
    required this.amountMinor,
    required this.order,
  });

  final String id;
  final String goalId;
  final int amountMinor;
  final int order;

  Map<String, Object?> toJson() => {
    'id': id,
    'goalId': goalId,
    'amountMinor': amountMinor,
    'order': order,
  };

  factory ScheduledGoalFundingAllocation.fromJson(Map<String, Object?> json) =>
      ScheduledGoalFundingAllocation(
        id: json['id'] as String? ?? '',
        goalId: json['goalId'] as String? ?? '',
        amountMinor: json['amountMinor'] as int? ?? 0,
        order: json['order'] as int? ?? 0,
      );
}

enum RecurrenceFrequency { once, weekly, biweekly, monthly, yearly }

enum AlertPreference {
  none,
  sameDay,
  oneDayBefore,
  threeDaysBefore,
  oneWeekBefore,
  custom,
}

enum ScheduledAction { none, paid, skipped }

enum ScheduledOccurrenceStatus { pending, paid, skipped }

/// Causal authority boundary for scheduled-occurrence history.
///
/// Old schedules and backups implicitly belong to [legacy]. A history reset
/// advances this epoch so occurrence states from an earlier epoch can remain
/// in an offline/cloud replica without becoming authoritative again.
class ScheduledOccurrenceHistoryEpoch {
  const ScheduledOccurrenceHistoryEpoch({
    required this.revision,
    required this.operationId,
    required this.changedAt,
    required this.deviceId,
  });

  static final legacy = ScheduledOccurrenceHistoryEpoch(
    revision: 0,
    operationId: 'legacy',
    changedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    deviceId: 'legacy',
  );

  final int revision;
  final String operationId;
  final DateTime changedAt;
  final String deviceId;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'operationId': operationId,
    'changedAt': changedAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
  };

  factory ScheduledOccurrenceHistoryEpoch.fromJson(Map<String, Object?> json) {
    final revision = json['revision'] as int? ?? 0;
    return ScheduledOccurrenceHistoryEpoch(
      revision: revision,
      operationId: json['operationId'] as String? ?? 'legacy_$revision',
      changedAt: json['changedAt'] == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : dateTimeFromJson(json['changedAt']).toUtc(),
      deviceId: json['deviceId'] as String? ?? 'legacy',
    );
  }
}

ScheduledOccurrenceHistoryEpoch authoritativeOccurrenceHistoryEpoch(
  ScheduledOccurrenceHistoryEpoch left,
  ScheduledOccurrenceHistoryEpoch right,
) {
  if (left.revision != right.revision) {
    return left.revision > right.revision ? left : right;
  }
  return left.operationId.compareTo(right.operationId) >= 0 ? left : right;
}

bool sameOccurrenceHistoryEpoch(
  ScheduledOccurrenceHistoryEpoch left,
  ScheduledOccurrenceHistoryEpoch right,
) => left.revision == right.revision && left.operationId == right.operationId;

/// Independently versioned authority for one recurring schedule occurrence.
///
/// The enclosing schedule's [SyncMetadata] remains the authority for edits to
/// the schedule definition. Occurrence completion is instead ordered by
/// [revision], then by [operationId]. [changedAt] is diagnostic only and is
/// deliberately excluded from conflict resolution.
class ScheduledOccurrenceState {
  const ScheduledOccurrenceState({
    required this.scheduledDate,
    required this.plannedAmountMinor,
    required this.status,
    required this.revision,
    required this.operationId,
    required this.changedAt,
    required this.deviceId,
    this.historyEpochRevision = 0,
    this.historyEpochOperationId = 'legacy',
    this.actualAmountMinor,
    this.actualPaymentDate,
    this.transactionId,
    this.goalFundingEventId,
    this.reservationOperationId,
  });

  final DateTime scheduledDate;
  final int plannedAmountMinor;
  final ScheduledOccurrenceStatus status;
  final int? actualAmountMinor;
  final DateTime? actualPaymentDate;
  final String? transactionId;
  final String? goalFundingEventId;
  final String? reservationOperationId;
  final int revision;
  final String operationId;
  final DateTime changedAt;
  final String deviceId;
  final int historyEpochRevision;
  final String historyEpochOperationId;

  bool get isResolved =>
      status == ScheduledOccurrenceStatus.paid ||
      status == ScheduledOccurrenceStatus.skipped;

  Map<String, Object?> toJson() => {
    'scheduledDate': scheduledDate.toIso8601String(),
    'plannedAmountMinor': plannedAmountMinor,
    'status': status.name,
    'actualAmountMinor': actualAmountMinor,
    'actualPaymentDate': actualPaymentDate?.toIso8601String(),
    'transactionId': transactionId,
    'goalFundingEventId': goalFundingEventId,
    'reservationOperationId': reservationOperationId,
    'revision': revision,
    'operationId': operationId,
    'changedAt': changedAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'historyEpochRevision': historyEpochRevision,
    'historyEpochOperationId': historyEpochOperationId,
  };

  factory ScheduledOccurrenceState.fromJson(Map<String, Object?> json) {
    final scheduledDate = dateTimeFromJson(json['scheduledDate']);
    final revision = json['revision'] as int? ?? 0;
    return ScheduledOccurrenceState(
      scheduledDate: scheduledDate,
      plannedAmountMinor: json['plannedAmountMinor'] as int? ?? 0,
      status: enumByName(
        ScheduledOccurrenceStatus.values,
        json['status'],
        ScheduledOccurrenceStatus.pending,
      ),
      actualAmountMinor: json['actualAmountMinor'] as int?,
      actualPaymentDate: json['actualPaymentDate'] == null
          ? null
          : dateTimeFromJson(json['actualPaymentDate']),
      transactionId: json['transactionId'] as String?,
      goalFundingEventId: json['goalFundingEventId'] as String?,
      reservationOperationId: json['reservationOperationId'] as String?,
      revision: revision,
      // Old/hand-authored additive payloads remain deterministic even if they
      // omitted the operation id. New writes always supply a random id.
      operationId:
          json['operationId'] as String? ??
          'legacy_${occurrenceDayKey(scheduledDate)}_$revision',
      changedAt: json['changedAt'] == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : dateTimeFromJson(json['changedAt']).toUtc(),
      deviceId: json['deviceId'] as String? ?? 'legacy',
      historyEpochRevision: json['historyEpochRevision'] as int? ?? 0,
      historyEpochOperationId:
          json['historyEpochOperationId'] as String? ?? 'legacy',
    );
  }

  ScheduledOccurrenceRecord toLegacyRecord() => ScheduledOccurrenceRecord(
    scheduledDate: scheduledDate,
    plannedAmountMinor: plannedAmountMinor,
    status: status,
    actualAmountMinor: actualAmountMinor,
    actualPaymentDate: actualPaymentDate,
    transactionId: transactionId,
    goalFundingEventId: goalFundingEventId,
    reservationOperationId: reservationOperationId,
  );
}

String occurrenceDayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}'
    '${date.month.toString().padLeft(2, '0')}'
    '${date.day.toString().padLeft(2, '0')}';

ScheduledOccurrenceState authoritativeOccurrenceState(
  ScheduledOccurrenceState left,
  ScheduledOccurrenceState right,
) {
  if (left.revision != right.revision) {
    return left.revision > right.revision ? left : right;
  }
  return left.operationId.compareTo(right.operationId) >= 0 ? left : right;
}

class ScheduledOccurrenceRecord {
  const ScheduledOccurrenceRecord({
    required this.scheduledDate,
    required this.plannedAmountMinor,
    required this.status,
    this.actualAmountMinor,
    this.actualPaymentDate,
    this.transactionId,
    this.goalFundingEventId,
    this.reservationOperationId,
  });

  final DateTime scheduledDate;
  final int plannedAmountMinor;
  final ScheduledOccurrenceStatus status;
  final int? actualAmountMinor;
  final DateTime? actualPaymentDate;
  final String? transactionId;

  /// Present only when this occurrence was explicitly funded as a Goal event.
  final String? goalFundingEventId;

  /// Present when this occurrence allocated money through the shared
  /// reservation engine rather than creating a Ledger transaction.
  final String? reservationOperationId;

  Map<String, Object?> toJson() {
    return {
      'scheduledDate': scheduledDate.toIso8601String(),
      'plannedAmountMinor': plannedAmountMinor,
      'status': status.name,
      'actualAmountMinor': actualAmountMinor,
      'actualPaymentDate': actualPaymentDate?.toIso8601String(),
      'transactionId': transactionId,
      'goalFundingEventId': goalFundingEventId,
      'reservationOperationId': reservationOperationId,
    };
  }

  factory ScheduledOccurrenceRecord.fromJson(Map<String, Object?> json) {
    return ScheduledOccurrenceRecord(
      scheduledDate: dateTimeFromJson(json['scheduledDate']),
      plannedAmountMinor: json['plannedAmountMinor'] as int? ?? 0,
      status: enumByName(
        ScheduledOccurrenceStatus.values,
        json['status'],
        ScheduledOccurrenceStatus.paid,
      ),
      actualAmountMinor: json['actualAmountMinor'] as int?,
      actualPaymentDate: json['actualPaymentDate'] == null
          ? null
          : dateTimeFromJson(json['actualPaymentDate']),
      transactionId: json['transactionId'] as String?,
      goalFundingEventId: json['goalFundingEventId'] as String?,
      reservationOperationId: json['reservationOperationId'] as String?,
    );
  }
}

class ScheduledTransactionRecord {
  const ScheduledTransactionRecord({
    required this.id,
    required this.type,
    required this.accountId,
    required this.payee,
    required this.amountMinor,
    required this.nextDate,
    required this.frequency,
    required this.sync,
    this.note = '',
    this.transferAccountId,
    this.categoryId,
    this.splitLines = const [],
    this.goalFundingAllocations = const [],
    this.goalId,
    this.endDate,
    this.alertPreference = AlertPreference.none,
    this.customAlertTimeMinutes,
    this.customAlertOffsetDays = 0,
    int? scheduledTimeMinutes,
    this.repeatAlertUntilResolved = false,
    this.scheduledNotificationIds = const [],
    this.lastReminderScheduledAt,
    this.lastAction = ScheduledAction.none,
    this.occurrences = const [],
    this.occurrenceStates = const {},
    this.occurrenceHistoryEpoch,
    this.reservationContainerType,
    this.reservationContainerId,
    this.reservationFundingContainerType,
    this.reservationFundingContainerId,
  }) : scheduledTimeMinutes =
           scheduledTimeMinutes ?? customAlertTimeMinutes ?? 9 * 60;

  final String id;
  final TransactionType type;
  final String accountId;
  final String? transferAccountId;
  final String? categoryId;
  final List<TransactionSplitLine> splitLines;

  /// Allocation plan for a scheduled [TransactionType.goalFunding] record.
  final List<ScheduledGoalFundingAllocation> goalFundingAllocations;

  /// Marks a normal scheduled transfer as Goal funding for presentation and
  /// Goal-specific reminder language. Financially it remains a transfer.
  final String? goalId;
  final String payee;
  final String note;
  final int amountMinor;
  final DateTime nextDate;
  final RecurrenceFrequency frequency;
  final DateTime? endDate;
  final AlertPreference alertPreference;

  /// Reminder wall clock in local minutes after midnight, for presets and
  /// Custom alike. Retain the existing field so old reminders keep their time.
  final int? customAlertTimeMinutes;

  /// Civil calendar days before each occurrence; legacy Custom meant same day.
  final int customAlertOffsetDays;

  /// Independent of the reminder clock. Legacy records displayed the latter
  /// in the transaction Time row, so preserve that value when first loaded.
  final int scheduledTimeMinutes;
  final bool repeatAlertUntilResolved;
  final List<int> scheduledNotificationIds;
  final DateTime? lastReminderScheduledAt;
  final ScheduledAction lastAction;
  final List<ScheduledOccurrenceRecord> occurrences;
  final Map<String, ScheduledOccurrenceState> occurrenceStates;
  final ScheduledOccurrenceHistoryEpoch? occurrenceHistoryEpoch;
  final ReservationContainerType? reservationContainerType;
  final String? reservationContainerId;

  /// Optional target for a scheduled reservation allocation. This is
  /// deliberately separate from [reservationContainerType] and
  /// [reservationContainerId], which mean that a real scheduled transaction
  /// consumes already-reserved money when it is marked Paid.
  final ReservationContainerType? reservationFundingContainerType;
  final String? reservationFundingContainerId;
  final SyncMetadata sync;

  bool get hasAlert => alertPreference != AlertPreference.none;
  bool get hasValidReminderTiming =>
      customAlertOffsetDays >= 0 &&
      customAlertOffsetDays <= 36500 &&
      scheduledTimeMinutes >= 0 &&
      scheduledTimeMinutes < 24 * 60 &&
      (customAlertTimeMinutes == null ||
          (customAlertTimeMinutes! >= 0 && customAlertTimeMinutes! < 24 * 60));
  bool get isDeleted => sync.isDeleted;
  bool get isScheduledFundFunding =>
      type == TransactionType.goalFunding &&
      reservationFundingContainerType == ReservationContainerType.fund &&
      (reservationFundingContainerId?.trim().isNotEmpty ?? false);
  bool get isScheduledGoalFunding =>
      type == TransactionType.goalFunding && !isScheduledFundFunding;
  bool get isReservationFunding =>
      isScheduledGoalFunding || isScheduledFundFunding;
  bool get isGoalFunding =>
      isScheduledGoalFunding || (goalId != null && goalId!.isNotEmpty);
  List<TransactionSplitLine> get effectiveCategoryAllocations {
    return resolveEffectiveCategoryAllocations(
      type: type,
      categoryId: categoryId,
      amountMinor: amountMinor,
      splitLines: splitLines,
    );
  }

  bool get isCategorySplit => effectiveCategoryAllocations.length > 1;
  bool get isSplit => isCategorySplit;

  int get splitTotalMinor {
    return effectiveCategoryAllocations.fold(
      0,
      (total, line) => total + line.amountMinor,
    );
  }

  bool get hasStoredCategoryAllocationPayload {
    return splitLines.any(
      (line) => line.categoryId.trim().isNotEmpty && line.amountMinor != 0,
    );
  }

  bool get hasValidSplitTotal {
    return !hasStoredCategoryAllocationPayload ||
        splitTotalMinor == amountMinor.abs();
  }

  int get goalFundingAllocationTotalMinor => goalFundingAllocations.fold(
    0,
    (total, allocation) => total + allocation.amountMinor.abs(),
  );

  bool get hasValidGoalFundingAllocations {
    if (!isScheduledGoalFunding) return true;
    final ids = <String>{};
    return goalFundingAllocations.isNotEmpty &&
        goalFundingAllocations.every(
          (allocation) =>
              allocation.goalId.trim().isNotEmpty &&
              allocation.amountMinor > 0 &&
              ids.add(allocation.goalId),
        ) &&
        goalFundingAllocationTotalMinor == amountMinor.abs();
  }

  ScheduledTransactionRecord copyWith({
    TransactionType? type,
    String? accountId,
    String? transferAccountId,
    String? categoryId,
    List<TransactionSplitLine>? splitLines,
    List<ScheduledGoalFundingAllocation>? goalFundingAllocations,
    String? goalId,
    String? payee,
    String? note,
    int? amountMinor,
    DateTime? nextDate,
    RecurrenceFrequency? frequency,
    DateTime? endDate,
    AlertPreference? alertPreference,
    int? customAlertTimeMinutes,
    int? customAlertOffsetDays,
    int? scheduledTimeMinutes,
    bool? repeatAlertUntilResolved,
    List<int>? scheduledNotificationIds,
    DateTime? lastReminderScheduledAt,
    ScheduledAction? lastAction,
    List<ScheduledOccurrenceRecord>? occurrences,
    Map<String, ScheduledOccurrenceState>? occurrenceStates,
    ScheduledOccurrenceHistoryEpoch? occurrenceHistoryEpoch,
    ReservationContainerType? reservationContainerType,
    String? reservationContainerId,
    ReservationContainerType? reservationFundingContainerType,
    String? reservationFundingContainerId,
    SyncMetadata? sync,
    bool clearTransferAccount = false,
    bool clearCategory = false,
    bool clearGoalId = false,
    bool clearEndDate = false,
    bool clearCustomAlertTime = false,
    bool clearLastReminderScheduledAt = false,
    bool clearReservationContainer = false,
    bool clearReservationFundingContainer = false,
  }) {
    return ScheduledTransactionRecord(
      id: id,
      type: type ?? this.type,
      accountId: accountId ?? this.accountId,
      transferAccountId: clearTransferAccount
          ? null
          : transferAccountId ?? this.transferAccountId,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      splitLines: splitLines ?? this.splitLines,
      goalFundingAllocations:
          goalFundingAllocations ?? this.goalFundingAllocations,
      goalId: clearGoalId ? null : goalId ?? this.goalId,
      payee: payee ?? this.payee,
      note: note ?? this.note,
      amountMinor: amountMinor ?? this.amountMinor,
      nextDate: nextDate ?? this.nextDate,
      frequency: frequency ?? this.frequency,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      alertPreference: alertPreference ?? this.alertPreference,
      customAlertOffsetDays:
          customAlertOffsetDays ?? this.customAlertOffsetDays,
      scheduledTimeMinutes: scheduledTimeMinutes ?? this.scheduledTimeMinutes,
      customAlertTimeMinutes: clearCustomAlertTime
          ? null
          : customAlertTimeMinutes ?? this.customAlertTimeMinutes,
      repeatAlertUntilResolved:
          repeatAlertUntilResolved ?? this.repeatAlertUntilResolved,
      scheduledNotificationIds:
          scheduledNotificationIds ?? this.scheduledNotificationIds,
      lastReminderScheduledAt: clearLastReminderScheduledAt
          ? null
          : lastReminderScheduledAt ?? this.lastReminderScheduledAt,
      lastAction: lastAction ?? this.lastAction,
      occurrences: occurrences ?? this.occurrences,
      occurrenceStates: occurrenceStates ?? this.occurrenceStates,
      occurrenceHistoryEpoch:
          occurrenceHistoryEpoch ?? this.occurrenceHistoryEpoch,
      reservationContainerType: clearReservationContainer
          ? null
          : reservationContainerType ?? this.reservationContainerType,
      reservationContainerId: clearReservationContainer
          ? null
          : reservationContainerId ?? this.reservationContainerId,
      reservationFundingContainerType: clearReservationFundingContainer
          ? null
          : reservationFundingContainerType ??
                this.reservationFundingContainerType,
      reservationFundingContainerId: clearReservationFundingContainer
          ? null
          : reservationFundingContainerId ?? this.reservationFundingContainerId,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.name,
      'accountId': accountId,
      'transferAccountId': transferAccountId,
      'categoryId': categoryId,
      'splitLines': splitLines.map((line) => line.toJson()).toList(),
      'goalFundingAllocations': goalFundingAllocations
          .map((allocation) => allocation.toJson())
          .toList(),
      'goalId': goalId,
      'payee': payee,
      'note': note,
      'amountMinor': amountMinor,
      'nextDate': nextDate.toIso8601String(),
      'frequency': frequency.name,
      'endDate': endDate?.toIso8601String(),
      'alertPreference': alertPreference.name,
      'customAlertTimeMinutes': customAlertTimeMinutes,
      'customAlertOffsetDays': customAlertOffsetDays,
      'scheduledTimeMinutes': scheduledTimeMinutes,
      'repeatAlertUntilResolved': repeatAlertUntilResolved,
      'scheduledNotificationIds': scheduledNotificationIds,
      'lastReminderScheduledAt': lastReminderScheduledAt?.toIso8601String(),
      'lastAction': lastAction.name,
      'occurrences': occurrences.map((item) => item.toJson()).toList(),
      if (occurrenceStates.isNotEmpty)
        'occurrenceStates': {
          for (final entry in occurrenceStates.entries)
            entry.key: entry.value.toJson(),
        },
      if (occurrenceHistoryEpoch != null)
        'occurrenceHistoryEpoch': occurrenceHistoryEpoch!.toJson(),
      'reservationContainerType': reservationContainerType?.name,
      'reservationContainerId': reservationContainerId,
      'reservationFundingContainerType': reservationFundingContainerType?.name,
      'reservationFundingContainerId': reservationFundingContainerId,
      'sync': sync.toJson(),
    };
  }

  factory ScheduledTransactionRecord.fromJson(Map<String, Object?> json) {
    return ScheduledTransactionRecord(
      id: json['id'] as String,
      type: enumByName(
        TransactionType.values,
        json['type'],
        TransactionType.expense,
      ),
      accountId: json['accountId'] as String,
      transferAccountId: json['transferAccountId'] as String?,
      categoryId: json['categoryId'] as String?,
      splitLines: stringMapList(
        json['splitLines'],
      ).map(TransactionSplitLine.fromJson).toList(),
      goalFundingAllocations: stringMapList(
        json['goalFundingAllocations'],
      ).map(ScheduledGoalFundingAllocation.fromJson).toList(),
      goalId: json['goalId'] as String?,
      payee: json['payee'] as String? ?? '',
      note: json['note'] as String? ?? '',
      amountMinor: json['amountMinor'] as int? ?? 0,
      nextDate: dateTimeFromJson(json['nextDate']),
      frequency: enumByName(
        RecurrenceFrequency.values,
        json['frequency'],
        RecurrenceFrequency.monthly,
      ),
      endDate: json['endDate'] == null
          ? null
          : dateTimeFromJson(json['endDate']),
      alertPreference: enumByName(
        AlertPreference.values,
        json['alertPreference'],
        AlertPreference.none,
      ),
      customAlertTimeMinutes: json['customAlertTimeMinutes'] as int?,
      customAlertOffsetDays: json['customAlertOffsetDays'] as int? ?? 0,
      scheduledTimeMinutes: json['scheduledTimeMinutes'] as int?,
      repeatAlertUntilResolved:
          json['repeatAlertUntilResolved'] as bool? ?? false,
      scheduledNotificationIds:
          (json['scheduledNotificationIds'] as List<Object?>? ?? const [])
              .whereType<int>()
              .toList(),
      lastReminderScheduledAt: json['lastReminderScheduledAt'] == null
          ? null
          : dateTimeFromJson(json['lastReminderScheduledAt']),
      lastAction: enumByName(
        ScheduledAction.values,
        json['lastAction'],
        ScheduledAction.none,
      ),
      occurrences: stringMapList(
        json['occurrences'],
      ).map(ScheduledOccurrenceRecord.fromJson).toList(),
      occurrenceStates: {
        for (final entry in stringMap(json['occurrenceStates']).entries)
          if (entry.value is Map)
            entry.key: ScheduledOccurrenceState.fromJson(
              stringMap(entry.value),
            ),
      },
      occurrenceHistoryEpoch: json['occurrenceHistoryEpoch'] is Map
          ? ScheduledOccurrenceHistoryEpoch.fromJson(
              stringMap(json['occurrenceHistoryEpoch']),
            )
          : null,
      reservationContainerType: json['reservationContainerType'] == null
          ? null
          : enumByName(
              ReservationContainerType.values,
              json['reservationContainerType'],
              ReservationContainerType.goal,
            ),
      reservationContainerId: json['reservationContainerId'] as String?,
      reservationFundingContainerType:
          json['reservationFundingContainerType'] == null
          ? null
          : enumByName(
              ReservationContainerType.values,
              json['reservationFundingContainerType'],
              ReservationContainerType.fund,
            ),
      reservationFundingContainerId:
          json['reservationFundingContainerId'] as String?,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
