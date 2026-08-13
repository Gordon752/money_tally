import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/scheduled_transaction.dart';
import 'notification_scheduler.dart';

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

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      final timeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZone.identifier));
    } on Object {
      tz.setLocalLocation(tz.UTC);
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(
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

  @override
  Future<bool> requestPermissionIfNeeded() async {
    await initialize();
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (Platform.isAndroid) {
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
    );

    await _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      scheduledDate: tz.TZDateTime.from(request.scheduledFor, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: request.scheduledTransactionId,
    );
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
