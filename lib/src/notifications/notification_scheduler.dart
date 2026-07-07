import '../domain/scheduled_transaction.dart';

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
