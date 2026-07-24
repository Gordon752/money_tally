import 'json_helpers.dart';
import 'sync_metadata.dart';
import 'transaction.dart';

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

class ScheduledOccurrenceRecord {
  const ScheduledOccurrenceRecord({
    required this.scheduledDate,
    required this.plannedAmountMinor,
    required this.status,
    this.actualAmountMinor,
    this.actualPaymentDate,
    this.transactionId,
  });

  final DateTime scheduledDate;
  final int plannedAmountMinor;
  final ScheduledOccurrenceStatus status;
  final int? actualAmountMinor;
  final DateTime? actualPaymentDate;
  final String? transactionId;

  Map<String, Object?> toJson() {
    return {
      'scheduledDate': scheduledDate.toIso8601String(),
      'plannedAmountMinor': plannedAmountMinor,
      'status': status.name,
      'actualAmountMinor': actualAmountMinor,
      'actualPaymentDate': actualPaymentDate?.toIso8601String(),
      'transactionId': transactionId,
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
    this.endDate,
    this.alertPreference = AlertPreference.none,
    this.customAlertTimeMinutes,
    this.repeatAlertUntilResolved = false,
    this.scheduledNotificationIds = const [],
    this.lastReminderScheduledAt,
    this.lastAction = ScheduledAction.none,
    this.occurrences = const [],
  });

  final String id;
  final TransactionType type;
  final String accountId;
  final String? transferAccountId;
  final String? categoryId;
  final List<TransactionSplitLine> splitLines;
  final String payee;
  final String note;
  final int amountMinor;
  final DateTime nextDate;
  final RecurrenceFrequency frequency;
  final DateTime? endDate;
  final AlertPreference alertPreference;
  final int? customAlertTimeMinutes;
  final bool repeatAlertUntilResolved;
  final List<int> scheduledNotificationIds;
  final DateTime? lastReminderScheduledAt;
  final ScheduledAction lastAction;
  final List<ScheduledOccurrenceRecord> occurrences;
  final SyncMetadata sync;

  bool get hasAlert => alertPreference != AlertPreference.none;
  bool get isDeleted => sync.isDeleted;
  bool get isSplit => splitLines.isNotEmpty;

  int get splitTotalMinor {
    return splitLines.fold(0, (total, line) => total + line.amountMinor);
  }

  bool get hasValidSplitTotal {
    return !isSplit || splitTotalMinor == amountMinor.abs();
  }

  ScheduledTransactionRecord copyWith({
    TransactionType? type,
    String? accountId,
    String? transferAccountId,
    String? categoryId,
    List<TransactionSplitLine>? splitLines,
    String? payee,
    String? note,
    int? amountMinor,
    DateTime? nextDate,
    RecurrenceFrequency? frequency,
    DateTime? endDate,
    AlertPreference? alertPreference,
    int? customAlertTimeMinutes,
    bool? repeatAlertUntilResolved,
    List<int>? scheduledNotificationIds,
    DateTime? lastReminderScheduledAt,
    ScheduledAction? lastAction,
    List<ScheduledOccurrenceRecord>? occurrences,
    SyncMetadata? sync,
    bool clearTransferAccount = false,
    bool clearCategory = false,
    bool clearEndDate = false,
    bool clearCustomAlertTime = false,
    bool clearLastReminderScheduledAt = false,
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
      payee: payee ?? this.payee,
      note: note ?? this.note,
      amountMinor: amountMinor ?? this.amountMinor,
      nextDate: nextDate ?? this.nextDate,
      frequency: frequency ?? this.frequency,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      alertPreference: alertPreference ?? this.alertPreference,
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
      'payee': payee,
      'note': note,
      'amountMinor': amountMinor,
      'nextDate': nextDate.toIso8601String(),
      'frequency': frequency.name,
      'endDate': endDate?.toIso8601String(),
      'alertPreference': alertPreference.name,
      'customAlertTimeMinutes': customAlertTimeMinutes,
      'repeatAlertUntilResolved': repeatAlertUntilResolved,
      'scheduledNotificationIds': scheduledNotificationIds,
      'lastReminderScheduledAt': lastReminderScheduledAt?.toIso8601String(),
      'lastAction': lastAction.name,
      'occurrences': occurrences.map((item) => item.toJson()).toList(),
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
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
