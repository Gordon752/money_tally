import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/notifications/local_notification_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const calendar = MethodChannel('trackmark/reminder_calendar');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final calendarCalls = <MethodCall>[];
  var calendarFails = false;
  var permissionAllowed = true;

  void usePlatform(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    if (platform == TargetPlatform.iOS) {
      IOSFlutterLocalNotificationsPlugin.registerWith();
    } else {
      MacOSFlutterLocalNotificationsPlugin.registerWith();
    }
  }

  setUp(() {
    calls.clear();
    calendarCalls.clear();
    calendarFails = false;
    permissionAllowed = true;
    reminderSchedulingError.value = null;
    messenger.setMockMethodCallHandler(notifications, (call) async {
      calls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'requestPermissions') return permissionAllowed;
      if (call.method == 'getNotificationAppLaunchDetails') {
        return {'notificationLaunchedApp': false};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(calendar, (call) async {
      calendarCalls.add(call);
      if (calendarFails) throw PlatformException(code: 'registration_failed');
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(notifications, null);
    messenger.setMockMethodCallHandler(calendar, null);
    reminderSchedulingError.value = null;
  });

  ScheduledTransactionRecord schedule({String? zone}) =>
      ScheduledTransactionRecord(
        id: 'native-test',
        type: TransactionType.expense,
        accountId: 'test',
        payee: 'Reminder test',
        amountMinor: 100,
        nextDate: DateTime(2099, 9, 17),
        frequency: RecurrenceFrequency.once,
        alertPreference: AlertPreference.sameDay,
        customAlertTimeMinutes: 700,
        reminderTimeZone: zone,
        sync: SyncMetadata.fresh(),
      );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test(
      '$platform initializes and requests alert, badge and sound permission',
      () async {
        usePlatform(platform);
        final scheduler = LocalNotificationScheduler();
        expect(await scheduler.requestPermissionIfNeeded(), isTrue);
        final initialization =
            calls.firstWhere((c) => c.method == 'initialize').arguments as Map;
        expect(initialization['requestAlertPermission'], isFalse);
        final permission =
            calls.firstWhere((c) => c.method == 'requestPermissions').arguments
                as Map;
        expect(permission['alert'], isTrue);
        expect(permission['badge'], isTrue);
        expect(permission['sound'], isTrue);
      },
    );

    test('$platform fixed timezone is passed to native scheduling', () async {
      usePlatform(platform);
      final ids = await LocalNotificationScheduler()
          .scheduleScheduledTransaction(schedule(zone: 'America/New_York'));
      expect(ids, hasLength(1));
      final args =
          calls.firstWhere((c) => c.method == 'zonedSchedule').arguments as Map;
      expect(args['timeZoneName'], 'America/New_York');
      expect((args['platformSpecifics'] as Map)['presentSound'], isTrue);
      expect(calendarCalls, isEmpty);
    });

    test('$platform local reminder replaces only calendar trigger', () async {
      usePlatform(platform);
      final ids = await LocalNotificationScheduler()
          .scheduleScheduledTransaction(schedule());
      expect(calendarCalls.single.method, 'useDeviceTimeZone');
      final args = calendarCalls.single.arguments as Map;
      expect(args['id'], ids.single.toString());
      expect(args['hour'], 11);
      expect(args['minute'], 40);
      expect(args.containsKey('timeZone'), isFalse);
    });

    test(
      '$platform failed floating conversion cancels incorrect pinned reminder',
      () async {
        usePlatform(platform);
        calendarFails = true;
        await expectLater(
          LocalNotificationScheduler().scheduleScheduledTransaction(schedule()),
          throwsA(isA<PlatformException>()),
        );
        expect(calls.where((c) => c.method == 'cancel'), hasLength(1));
        expect(reminderSchedulingError.value, isNotNull);
      },
    );
  }

  test('denied permission is visible rather than silently ignored', () async {
    usePlatform(TargetPlatform.macOS);
    permissionAllowed = false;
    expect(
      await LocalNotificationScheduler().requestPermissionIfNeeded(),
      isFalse,
    );
    expect(reminderSchedulingError.value, contains('not allowed'));
  });
}
