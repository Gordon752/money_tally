import '../domain/scheduled_transaction.dart';
import '../domain/scheduled_occurrence_authority.dart';
import '../domain/transaction.dart';
import 'reminder_time_zone.dart';
import 'package:timezone/timezone.dart' as tz;

abstract interface class NotificationScheduler {
  Future<bool> requestPermissionIfNeeded();

  Future<List<int>> scheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  );

  Future<void> cancelScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  );

  Future<void> rescheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  );

  Future<void> updateBadgeCount(int dueOrOverdueCount);
}

class NoopNotificationScheduler implements NotificationScheduler {
  const NoopNotificationScheduler();

  @override
  Future<void> cancelScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {}

  @override
  Future<bool> requestPermissionIfNeeded() async => false;

  @override
  Future<void> rescheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {}

  @override
  Future<List<int>> scheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    return const [];
  }

  @override
  Future<void> updateBadgeCount(int dueOrOverdueCount) async {}
}

class ScheduledNotificationRequest {
  const ScheduledNotificationRequest({
    required this.id,
    required this.scheduledTransactionId,
    required this.occurrenceDate,
    required this.title,
    required this.body,
    required this.scheduledFor,
    this.repeatUntilResolved = false,
  });

  final int id;
  final String scheduledTransactionId;
  final DateTime occurrenceDate;
  final String title;
  final String body;
  final DateTime scheduledFor;
  final bool repeatUntilResolved;

  String get payload => ScheduledNotificationPayload(
    scheduledTransactionId: scheduledTransactionId,
    occurrenceDate: occurrenceDate,
  ).encode();
}

class ScheduledNotificationPayload {
  const ScheduledNotificationPayload({
    required this.scheduledTransactionId,
    this.occurrenceDate,
  });

  static const _prefix = 'trackmark-scheduled-v1';

  final String scheduledTransactionId;
  final DateTime? occurrenceDate;

  String encode() {
    final date = occurrenceDate;
    if (date == null) return scheduledTransactionId;
    final day = DateTime(date.year, date.month, date.day);
    return '$_prefix|${Uri.encodeComponent(scheduledTransactionId)}|${day.toIso8601String()}';
  }

  static ScheduledNotificationPayload? tryParse(String? payload) {
    if (payload == null || payload.trim().isEmpty || payload == 'scheduled') {
      return null;
    }
    final parts = payload.split('|');
    if (parts.length == 3 && parts.first == _prefix) {
      final date = DateTime.tryParse(parts[2]);
      if (date == null) return null;
      return ScheduledNotificationPayload(
        scheduledTransactionId: Uri.decodeComponent(parts[1]),
        occurrenceDate: DateTime(date.year, date.month, date.day),
      );
    }
    // Backward compatibility for notifications scheduled by older builds,
    // whose payload contained only the stable schedule id.
    return ScheduledNotificationPayload(scheduledTransactionId: payload);
  }
}

class ScheduledAlertOccurrence {
  const ScheduledAlertOccurrence({
    required this.scheduledTransaction,
    required this.occurrenceDate,
    required this.plannedAmountMinor,
    required this.alertDateTime,
  });

  final ScheduledTransactionRecord scheduledTransaction;
  final DateTime occurrenceDate;
  final int plannedAmountMinor;
  final DateTime alertDateTime;

  String get identity =>
      '${scheduledTransaction.id}:${occurrenceDate.year}-${occurrenceDate.month}-${occurrenceDate.day}';
}

class ScheduledNotificationPlanner {
  const ScheduledNotificationPlanner({
    this.defaultAlertTimeMinutes = 9 * 60,
    this.localCalendarDateTime = DateTime.new,
  });

  final int defaultAlertTimeMinutes;

  /// Civil-time constructor, injectable for deterministic timezone/DST tests.
  final DateTime Function(int, int, int, int, int) localCalendarDateTime;

  List<ScheduledNotificationRequest> plan(
    Iterable<ScheduledTransactionRecord> scheduledTransactions, {
    required DateTime now,
  }) {
    final requests = <ScheduledNotificationRequest>[];
    for (final transaction in scheduledTransactions) {
      final request = planOne(transaction, now: now);
      if (request != null) requests.add(request);
    }
    requests.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    return requests;
  }

  ScheduledNotificationRequest? planOne(
    ScheduledTransactionRecord scheduledTransaction, {
    required DateTime now,
  }) {
    if (scheduledTransaction.isDeleted ||
        !scheduledTransaction.hasValidReminderTiming ||
        scheduledTransaction.alertPreference == AlertPreference.none) {
      return null;
    }

    final occurrenceDate = effectiveNextActionableDate(scheduledTransaction);
    if (occurrenceDate == null) return null;
    final scheduledFor = alertDateTimeForOccurrence(
      scheduledTransaction,
      occurrenceDate,
    );
    if (!scheduledFor.isAfter(now)) return null;

    return ScheduledNotificationRequest(
      id: notificationIdFor(scheduledTransaction.id),
      scheduledTransactionId: scheduledTransaction.id,
      occurrenceDate: occurrenceDate,
      title: notificationTitleFor(scheduledTransaction),
      body: notificationBodyFor(scheduledTransaction),
      scheduledFor: scheduledFor,
      repeatUntilResolved: scheduledTransaction.repeatAlertUntilResolved,
    );
  }

  DateTime alertDateTimeFor(ScheduledTransactionRecord scheduledTransaction) {
    return alertDateTimeForOccurrence(
      scheduledTransaction,
      scheduledTransaction.nextDate,
    );
  }

  DateTime alertDateTimeForOccurrence(
    ScheduledTransactionRecord scheduledTransaction,
    DateTime dueDate,
  ) {
    final offsetDays = switch (scheduledTransaction.alertPreference) {
      AlertPreference.none => 0,
      AlertPreference.sameDay => 0,
      AlertPreference.oneDayBefore => 1,
      AlertPreference.threeDaysBefore => 3,
      AlertPreference.oneWeekBefore => 7,
      AlertPreference.custom => scheduledTransaction.customAlertOffsetDays,
    };
    final minutes = scheduledTransaction.customAlertTimeMinutes;
    final timeMinutes = minutes == null || minutes < 0 || minutes >= 24 * 60
        ? defaultAlertTimeMinutes
        : minutes;
    // Subtract calendar dates, not 24-hour durations: DST days can contain
    // 23/25 hours. Construct the chosen wall clock directly on the result day.
    final zone = scheduledTransaction.reminderTimeZone;
    if (zone != null) {
      return tz.TZDateTime(
        reminderLocation(zone),
        dueDate.year,
        dueDate.month,
        dueDate.day - offsetDays,
        timeMinutes ~/ 60,
        timeMinutes % 60,
      );
    }
    return localCalendarDateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day - offsetDays,
      timeMinutes ~/ 60,
      timeMinutes % 60,
    );
  }
}

int notificationIdFor(String scheduledTransactionId) {
  var hash = 0;
  for (final codeUnit in scheduledTransactionId.codeUnits) {
    hash = 0x1fffffff & (hash + codeUnit);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash ^= hash >> 11;
  hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  return hash == 0 ? 1 : hash;
}

String notificationTitleFor(ScheduledTransactionRecord scheduledTransaction) {
  if (scheduledTransaction.isScheduledFundFunding) {
    final name = scheduledTransaction.payee.trim();
    return name.isEmpty ? 'Fund funding due' : '$name funding due';
  }
  return switch (scheduledTransaction.type) {
    TransactionType.income => 'Income due',
    TransactionType.transfer => 'Transfer due',
    TransactionType.goalFunding => 'Goal funding due',
    TransactionType.adjustment => 'Balance adjustment due',
    TransactionType.expense => 'Payment due',
  };
}

String notificationBodyFor(ScheduledTransactionRecord scheduledTransaction) {
  if (scheduledTransaction.isScheduledFundFunding) {
    final amount = (scheduledTransaction.amountMinor.abs() / 100)
        .toStringAsFixed(2);
    return 'Allocate \$$amount to your Fund.';
  }
  if (scheduledTransaction.type == TransactionType.goalFunding) {
    final count = scheduledTransaction.goalFundingAllocations.length;
    final amount = (scheduledTransaction.amountMinor.abs() / 100)
        .toStringAsFixed(2);
    return count == 1
        ? 'Fund \$$amount to your Goal.'
        : 'Fund \$$amount across $count Goals.';
  }
  return scheduledTransaction.payee.trim().isEmpty
      ? 'Scheduled transaction is due.'
      : '${scheduledTransaction.payee} is due.';
}
