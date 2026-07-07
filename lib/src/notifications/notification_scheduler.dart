import '../domain/scheduled_transaction.dart';
import '../domain/transaction.dart';

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
    required this.title,
    required this.body,
    required this.scheduledFor,
    this.repeatUntilResolved = false,
  });

  final int id;
  final String scheduledTransactionId;
  final String title;
  final String body;
  final DateTime scheduledFor;
  final bool repeatUntilResolved;
}

class ScheduledNotificationPlanner {
  const ScheduledNotificationPlanner({this.defaultAlertTimeMinutes = 9 * 60});

  final int defaultAlertTimeMinutes;

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
        scheduledTransaction.alertPreference == AlertPreference.none ||
        scheduledTransaction.lastAction != ScheduledAction.none) {
      return null;
    }

    final scheduledFor = alertDateTimeFor(scheduledTransaction);
    if (!scheduledFor.isAfter(now)) return null;

    return ScheduledNotificationRequest(
      id: notificationIdFor(scheduledTransaction.id),
      scheduledTransactionId: scheduledTransaction.id,
      title: notificationTitleFor(scheduledTransaction),
      body: notificationBodyFor(scheduledTransaction),
      scheduledFor: scheduledFor,
      repeatUntilResolved: scheduledTransaction.repeatAlertUntilResolved,
    );
  }

  DateTime alertDateTimeFor(ScheduledTransactionRecord scheduledTransaction) {
    final dueDate = scheduledTransaction.nextDate;
    final offsetDays = switch (scheduledTransaction.alertPreference) {
      AlertPreference.none => 0,
      AlertPreference.sameDay => 0,
      AlertPreference.oneDayBefore => 1,
      AlertPreference.threeDaysBefore => 3,
      AlertPreference.oneWeekBefore => 7,
      AlertPreference.custom => 0,
    };
    final alertDate = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
    ).subtract(Duration(days: offsetDays));
    final minutes = scheduledTransaction.customAlertTimeMinutes;
    final timeMinutes = minutes == null || minutes < 0
        ? defaultAlertTimeMinutes
        : minutes;
    return alertDate.add(Duration(minutes: timeMinutes));
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
  return switch (scheduledTransaction.type) {
    TransactionType.income => 'Income due',
    TransactionType.transfer => 'Transfer due',
    TransactionType.adjustment => 'Balance adjustment due',
    TransactionType.expense => 'Payment due',
  };
}

String notificationBodyFor(ScheduledTransactionRecord scheduledTransaction) {
  return scheduledTransaction.payee.trim().isEmpty
      ? 'Scheduled transaction is due.'
      : '${scheduledTransaction.payee} is due.';
}
