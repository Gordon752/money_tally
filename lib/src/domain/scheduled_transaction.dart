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
    this.transferAccountId,
    this.categoryId,
    this.endDate,
    this.alertPreference = AlertPreference.none,
    this.customAlertTimeMinutes,
    this.repeatAlertUntilResolved = false,
    this.scheduledNotificationIds = const [],
    this.lastReminderScheduledAt,
    this.lastAction = ScheduledAction.none,
  });

  final String id;
  final TransactionType type;
  final String accountId;
  final String? transferAccountId;
  final String? categoryId;
  final String payee;
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
  final SyncMetadata sync;

  bool get hasAlert => alertPreference != AlertPreference.none;
  bool get isDeleted => sync.isDeleted;

  ScheduledTransactionRecord copyWith({
    TransactionType? type,
    String? accountId,
    String? transferAccountId,
    String? categoryId,
    String? payee,
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
      payee: payee ?? this.payee,
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
      'payee': payee,
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
      payee: json['payee'] as String? ?? '',
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
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
