import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as app;
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/notifications/notification_scheduler.dart';
import 'package:money_tally/src/notifications/reminder_time_zone.dart';
import 'package:money_tally/src/persistence/firestore_record_repository.dart';
import 'package:timezone/timezone.dart' as tz;

ScheduledTransactionRecord schedule(DateTime date, {String? zone}) =>
    ScheduledTransactionRecord(
      id: 'thursday-transfer',
      type: TransactionType.transfer,
      accountId: 'settlement',
      transferAccountId: 'bank',
      payee: 'Transfer',
      amountMinor: 100,
      nextDate: date,
      frequency: RecurrenceFrequency.weekly,
      alertPreference: AlertPreference.sameDay,
      customAlertTimeMinutes: 11 * 60 + 40,
      reminderTimeZone: zone,
      sync: SyncMetadata.fresh(now: DateTime.utc(2026)),
    );

void main() {
  test('every picker timezone resolves, including built-in UTC', () {
    for (final zone in reminderTimeZones.keys) {
      expect(validReminderTimeZone(zone), isTrue, reason: zone);
    }
  });
  test('Thursday 11:40 Eastern is 10:40 Central in winter and summer', () {
    for (final date in [
      DateTime(2026, 1, 8),
      DateTime(2026, 7, 9),
      DateTime(2026, 11, 5),
    ]) {
      final item = schedule(date, zone: 'America/New_York');
      final alert = const ScheduledNotificationPlanner().planOne(
        item,
        now: DateTime.utc(2025),
      )!;
      final central = tz.TZDateTime.from(
        alert.scheduledFor,
        reminderLocation('America/Chicago'),
      );
      expect(central.weekday, DateTime.thursday);
      expect(central.hour, 10);
      expect(central.minute, 40);
      expect(alert.occurrenceDate, date);
    }
  });

  test(
    'fixed zone ignores device civil-time constructor; local follows it',
    () {
      final date = DateTime(2026, 9, 17);
      ScheduledNotificationPlanner planner(String zone) =>
          ScheduledNotificationPlanner(
            localCalendarDateTime: (y, m, d, h, minute) =>
                tz.TZDateTime(reminderLocation(zone), y, m, d, h, minute),
          );
      final eastern = planner('America/New_York');
      final central = planner('America/Chicago');
      final fixed = schedule(date, zone: 'America/New_York');
      expect(
        eastern.alertDateTimeFor(fixed).toUtc(),
        central.alertDateTimeFor(fixed).toUtc(),
      );
      final local = schedule(date);
      expect(
        central
            .alertDateTimeFor(local)
            .difference(eastern.alertDateTimeFor(local)),
        const Duration(hours: 1),
      );
      expect(central.alertDateTimeFor(local).hour, 11);
    },
  );

  test('fixed zone subtracts calendar days across DST, not 24 hours', () {
    final item = schedule(DateTime(2026, 3, 9), zone: 'America/New_York')
        .copyWith(
          alertPreference: AlertPreference.custom,
          customAlertOffsetDays: 2,
        );
    final result = const ScheduledNotificationPlanner().alertDateTimeFor(item);
    expect(
      result,
      tz.TZDateTime(reminderLocation('America/New_York'), 2026, 3, 7, 11, 40),
    );
  });

  test(
    'timezone survives JSON, edits, cloud definitions and can be cleared',
    () {
      final original = schedule(
        DateTime(2026, 9, 17),
        zone: 'America/New_York',
      );
      final decoded = ScheduledTransactionRecord.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(
        decoded.copyWith(note: 'edited').reminderTimeZone,
        original.reminderTimeZone,
      );
      for (final exists in [true, false]) {
        final cloud = scheduledCloudJsonForSync(
          scheduledTransaction: decoded,
          existsInRemoteBaseline: exists,
        );
        expect(cloud['reminderTimeZone'], 'America/New_York');
      }
      expect(
        decoded.copyWith(clearReminderTimeZone: true).reminderTimeZone,
        isNull,
      );
      final legacy = original.toJson()..remove('reminderTimeZone');
      expect(
        ScheduledTransactionRecord.fromJson(legacy).reminderTimeZone,
        isNull,
      );
    },
  );

  test('unknown zone does not silently become local or UTC', () {
    final invalid = schedule(DateTime(2026, 9, 17), zone: 'Wrong/Zone');
    expect(invalid.hasValidReminderTiming, isFalse);
    expect(
      const ScheduledNotificationPlanner().planOne(
        invalid,
        now: DateTime.utc(2025),
      ),
      isNull,
    );
  });

  testWidgets(
    'same-day selection opens time and zone editor; fixed choice is returned',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? resultZone;
      int? resultTime;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final result = await app.pickReminderRule(
                    context,
                    preference: AlertPreference.none,
                    daysBefore: 0,
                    timeMinutes: 700,
                    scheduledTimeMinutes: 700,
                  );
                  resultZone = result?.timeZone;
                  resultTime = result?.timeMinutes;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Same day'));
      await tester.pumpAndSettle();
      expect(find.text('Reminder time'), findsOneWidget);
      expect(find.text('11:40 AM'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('reminder-timezone')),
      );
      await tester.tap(find.byKey(const ValueKey('reminder-timezone')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eastern — New York'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-reminder-save')));
      await tester.pumpAndSettle();
      expect(resultZone, 'America/New_York');
      expect(resultTime, 700);
    },
  );
}
