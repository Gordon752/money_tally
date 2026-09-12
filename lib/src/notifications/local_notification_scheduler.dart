import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/scheduled_transaction.dart';
import 'notification_scheduler.dart';
import 'reminder_time_zone.dart';

final reminderSchedulingError = ValueNotifier<String?>(null);

class LocalNotificationScheduler implements NotificationScheduler {
  LocalNotificationScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    this.onNotificationSelected,
    this._planner = const ScheduledNotificationPlanner(),
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final ScheduledNotificationPlanner _planner;
  final void Function(String? payload)? onNotificationSelected;
  var _initialized = false;
  static const _calendarChannel = MethodChannel('trackmark/reminder_calendar');

  Future<void> initialize() async {
    if (_initialized) return;

    reminderLocation('UTC'); // Initialize the shared timezone database once.
    await refreshDeviceTimeZone();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) =>
          onNotificationSelected?.call(response.payload),
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      onNotificationSelected?.call(
        launchDetails?.notificationResponse?.payload,
      );
    }
    _initialized = true;
  }

  /// Floating Apple triggers already follow the system while suspended.
  /// Refresh the Dart conversion cache on resume, without cancelling those
  /// triggers or racing the sync coordinator's notification reconciliation.
  Future<void> refreshDeviceTimeZone() async {
    try {
      final timeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZone.identifier));
    } on Object {
      // Keep the last known zone. Fixed reminders resolve their own IANA zone;
      // floating Apple triggers have no pinned zone at all.
      debugPrint('Could not refresh the device timezone for reminders.');
    }
  }

  @override
  Future<bool> requestPermissionIfNeeded() async {
    try {
      final allowed = await _requestPermission();
      if (!allowed) {
        reminderSchedulingError.value =
            'Notifications are not allowed on this device. Enable alerts for Trackmark in system notification settings.';
      }
      return allowed;
    } on Object {
      reminderSchedulingError.value =
          'Reminders could not be initialized on this device. Restart Trackmark to retry.';
      rethrow;
    }
  }

  Future<bool> _requestPermission() async {
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    }
    return true;
  }

  @override
  Future<List<int>> scheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    try {
      return await _schedule(scheduledTransaction);
    } on Object {
      reminderSchedulingError.value =
          'Reminders could not be scheduled on this device. Check notification '
          'permissions, then restart Trackmark to retry. Your records are safe.';
      rethrow;
    }
  }

  Future<List<int>> _schedule(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    await initialize();
    final request = _planner.planOne(scheduledTransaction, now: DateTime.now());
    if (request == null) return const [];

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'scheduled_transactions',
        'Scheduled transactions',
        channelDescription: 'Trackmark Money payment and income reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'scheduled_transactions',
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'scheduled_transactions',
      ),
    );

    await _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      scheduledDate: tz.TZDateTime.from(
        request.scheduledFor,
        scheduledTransaction.reminderTimeZone == null
            ? tz.local
            : reminderLocation(scheduledTransaction.reminderTimeZone!),
      ),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: request.payload,
    );
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        scheduledTransaction.reminderTimeZone == null) {
      // The plugin always pins a timezone. Replace only the trigger with
      // floating calendar components; retain its content and tap payload.
      // The OS can then follow travel even while Flutter is not running.
      try {
        await _calendarChannel.invokeMethod<void>('useDeviceTimeZone', {
          'id': request.id.toString(),
          'year': request.scheduledFor.year,
          'month': request.scheduledFor.month,
          'day': request.scheduledFor.day,
          'hour': request.scheduledFor.hour,
          'minute': request.scheduledFor.minute,
        });
      } on Object {
        await _plugin.cancel(id: request.id);
        rethrow;
      }
    }
    reminderSchedulingError.value = null;
    return [request.id];
  }

  @override
  Future<void> cancelScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    await initialize();
    for (final id in scheduledTransaction.scheduledNotificationIds) {
      await _plugin.cancel(id: id);
    }
  }

  @override
  Future<void> rescheduleScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    await cancelScheduledTransaction(scheduledTransaction);
    await scheduleScheduledTransaction(scheduledTransaction);
  }

  @override
  Future<void> updateBadgeCount(int dueOrOverdueCount) async {
    // Trackmark renders its due count in-app. System notifications are
    // scheduled independently and iOS manages their presentation.
  }
}
