import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as app;
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/scheduled_occurrence_authority.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/notifications/notification_scheduler.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/persistence/backup_restore_service.dart';
import 'package:money_tally/src/persistence/scheduled_notification_state_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final _now = DateTime(2026, 9, 1);
final _sync = SyncMetadata.fresh(now: _now);
ScheduledTransactionRecord _schedule({
  int days = 0,
  int time = 705,
  RecurrenceFrequency frequency = RecurrenceFrequency.weekly,
}) => ScheduledTransactionRecord(
  id: 'scheduled',
  type: TransactionType.expense,
  accountId: 'cash',
  categoryId: 'dining',
  payee: 'Bill',
  amountMinor: 10000,
  nextDate: DateTime(2026, 9, 11),
  frequency: frequency,
  alertPreference: AlertPreference.custom,
  customAlertOffsetDays: days,
  customAlertTimeMinutes: time,
  scheduledTimeMinutes: 12 * 60,
  sync: _sync,
);

FinanceDataSet _data(ScheduledTransactionRecord item) => FinanceDataSet(
  accounts: [
    AccountRecord(
      id: 'cash',
      name: 'Checking',
      type: AccountType.checking,
      openingBalanceMinor: 500000,
      sync: _sync,
    ),
  ],
  categories: [
    CategoryRecord(
      id: 'dining',
      name: 'Dining',
      kind: CategoryKind.expense,
      sync: _sync,
    ),
  ],
  transactions: const [],
  scheduledTransactions: [item],
  budgets: const [],
  preferences: const UserPreferences(notificationsEnabled: true),
);

void main() {
  test(
    'fixed-zone backup uses schema 8 and preserves zone; legacy stays schema 7',
    () {
      final local = _data(_schedule());
      expect(
        jsonDecode(const BackupCodec().encodeJson(local))['schemaVersion'],
        7,
      );
      final fixed = _data(
        _schedule().copyWith(reminderTimeZone: 'America/New_York'),
      );
      final raw = const BackupCodec().encodeJson(fixed);
      expect(jsonDecode(raw)['schemaVersion'], 8);
      final validated = const BackupRestoreValidator().validate(raw);
      expect(
        validated.dataSet.scheduledTransactions.single.reminderTimeZone,
        'America/New_York',
      );
      final invalid = _data(
        _schedule().copyWith(reminderTimeZone: 'Invalid/Zone'),
      );
      expect(
        () => const BackupRestoreValidator().validate(
          const BackupCodec().encodeJson(invalid),
        ),
        throwsA(isA<BackupValidationException>()),
      );
    },
  );

  for (final (days, time, label) in [
    (0, 705, 'Same day · 11:45 AM · Device time'),
    (1, 1080, '1 day before · 6:00 PM · Device time'),
    (3, 480, '3 days before · 8:00 AM · Device time'),
    (7, 570, '7 days before · 9:30 AM · Device time'),
  ]) {
    test(
      'custom $label resolves to an exact local occurrence-relative time',
      () {
        final item = _schedule(days: days, time: time);
        final planned = const ScheduledNotificationPlanner().planOne(
          item,
          now: _now,
        )!;
        expect(
          planned.scheduledFor,
          DateTime(2026, 9, 11 - days, time ~/ 60, time % 60),
        );
        expect(planned.scheduledFor.isUtc, isFalse);
        expect(planned.occurrenceDate, item.nextDate);
        expect(
          app.reminderRuleLabel(
            item.alertPreference,
            daysBefore: days,
            timeMinutes: time,
          ),
          label,
        );
      },
    );
  }

  test('preset offsets and saved clock remain unchanged', () {
    for (final (preset, days) in [
      (AlertPreference.sameDay, 0),
      (AlertPreference.oneDayBefore, 1),
      (AlertPreference.threeDaysBefore, 3),
      (AlertPreference.oneWeekBefore, 7),
    ]) {
      final item = _schedule(
        days: 42,
        time: 1080,
      ).copyWith(alertPreference: preset);
      expect(
        const ScheduledNotificationPlanner()
            .planOne(item, now: _now)!
            .scheduledFor,
        DateTime(2026, 9, 11 - days, 18),
      );
    }
    expect(
      const ScheduledNotificationPlanner().planOne(
        _schedule().copyWith(alertPreference: AlertPreference.none),
        now: _now,
      ),
      isNull,
    );
  });

  test(
    'legacy Custom defaults to same day at saved time, with independent clocks after loading',
    () {
      final legacy = _schedule(days: 3, time: 1080).toJson()
        ..remove('customAlertOffsetDays')
        ..remove('scheduledTimeMinutes');
      final loaded = ScheduledTransactionRecord.fromJson(legacy);
      expect(loaded.customAlertOffsetDays, 0);
      expect(loaded.customAlertTimeMinutes, 1080);
      expect(loaded.scheduledTimeMinutes, 1080);
      final edited = loaded.copyWith(
        customAlertTimeMinutes: 480,
        customAlertOffsetDays: 3,
      );
      expect(edited.scheduledTimeMinutes, 1080);
      expect(
        edited.copyWith(scheduledTimeMinutes: 600).customAlertTimeMinutes,
        480,
      );
      expect(
        ScheduledTransactionRecord.fromJson(edited.toJson()).toJson(),
        edited.toJson(),
      );
      legacy.remove('customAlertTimeMinutes');
      final noTime = ScheduledTransactionRecord.fromJson(legacy);
      expect(
        const ScheduledNotificationPlanner().alertDateTimeFor(noTime),
        DateTime(2026, 9, 11, 9),
      );
    },
  );

  test(
    'v6 backup migrates same-day; v7 backup restores both clocks and custom offset',
    () {
      final data = _data(_schedule(days: 3, time: 480));
      final old = data.toJson()..['schemaVersion'] = 6;
      old['scheduledTransactions'] = [
        data.scheduledTransactions.single.toJson()
          ..remove('customAlertOffsetDays')
          ..remove('scheduledTimeMinutes'),
      ];
      final migrated = const BackupRestoreValidator().validate(jsonEncode(old));
      expect(migrated.schemaVersion, currentBackupSchemaVersion);
      expect(
        migrated.dataSet.scheduledTransactions.single.customAlertOffsetDays,
        0,
      );
      expect(
        migrated.dataSet.scheduledTransactions.single.scheduledTimeMinutes,
        480,
      );
      final restored = const BackupRestoreValidator().validate(
        const BackupCodec().encodeJson(data),
      );
      final schedule = restored.dataSet.scheduledTransactions.single;
      expect(schedule.customAlertOffsetDays, 3);
      expect(schedule.customAlertTimeMinutes, 480);
      expect(schedule.scheduledTimeMinutes, 720);
      expect(schedule.scheduledNotificationIds, isEmpty);
    },
  );

  for (final frequency in [
    RecurrenceFrequency.weekly,
    RecurrenceFrequency.monthly,
  ]) {
    test(
      '$frequency Paid/Skipped advance and rebuild the same custom rule; Undo restores it',
      () async {
        final item = _schedule(days: 3, time: 480, frequency: frequency);
        final scheduler = _RecordingScheduler();
        final local = InMemoryScheduledNotificationStateRepository();
        final store = FinanceDataStore(
          dataSet: _data(item),
          notificationScheduler: scheduler,
          notificationStateRepository: local,
        );
        await store.refreshScheduledNotifications();
        expect(scheduler.active.single.scheduledFor, DateTime(2026, 9, 8, 8));
        final next = nextScheduledOccurrenceDate(item.nextDate, frequency)!;
        await store.saveScheduledOccurrence(
          scheduledTransaction: item,
          occurrence: ScheduledOccurrenceRecord(
            scheduledDate: item.nextDate,
            plannedAmountMinor: item.amountMinor,
            status: ScheduledOccurrenceStatus.paid,
            actualAmountMinor: item.amountMinor,
            actualPaymentDate: item.nextDate,
          ),
        );
        expect(scheduler.cancelled, isNotEmpty);
        expect(scheduler.active.single.occurrenceDate, next);
        expect(
          scheduler.active.single.scheduledFor,
          DateTime(next.year, next.month, next.day - 3, 8),
        );
        await store.saveScheduledOccurrence(
          scheduledTransaction: store.scheduledTransactions.single,
          occurrence: ScheduledOccurrenceRecord(
            scheduledDate: next,
            plannedAmountMinor: item.amountMinor,
            status: ScheduledOccurrenceStatus.skipped,
          ),
        );
        final third = nextScheduledOccurrenceDate(next, frequency)!;
        expect(scheduler.active.single.occurrenceDate, third);
        await store.refreshScheduledNotifications();
        expect(
          scheduler.active.single.scheduledFor,
          DateTime(third.year, third.month, third.day - 3, 8),
        );
        await store.saveScheduledOccurrence(
          scheduledTransaction: store.scheduledTransactions.single,
          occurrence: ScheduledOccurrenceRecord(
            scheduledDate: item.nextDate,
            plannedAmountMinor: item.amountMinor,
            status: ScheduledOccurrenceStatus.pending,
          ),
        );
        expect(scheduler.active.single.occurrenceDate, item.nextDate);
        expect((await local.load(item.id))!.notificationIds, [
          notificationIdFor(item.id),
        ]);
        expect(
          store.scheduledTransactions.single.scheduledNotificationIds,
          isEmpty,
        );
      },
    );
  }

  test(
    'editing custom rule cancels old local notification and rebuilds at the new time',
    () async {
      final item = _schedule();
      final scheduler = _RecordingScheduler();
      final store = FinanceDataStore(
        dataSet: _data(item),
        notificationScheduler: scheduler,
      );
      await store.refreshScheduledNotifications();
      final edited = item.copyWith(
        customAlertOffsetDays: 1,
        customAlertTimeMinutes: 1080,
      );
      await store.saveScheduledTransaction(edited);
      expect(scheduler.cancelled, contains(notificationIdFor(item.id)));
      expect(scheduler.active.single.scheduledFor, DateTime(2026, 9, 10, 18));
      await store.savePreferences(
        store.preferences.copyWith(notificationsEnabled: false),
      );
      expect(scheduler.active, isEmpty);
      await store.savePreferences(
        store.preferences.copyWith(notificationsEnabled: true),
      );
      expect(scheduler.active.single.scheduledFor, DateTime(2026, 9, 10, 18));
    },
  );

  test(
    'custom reminders retain wall clock across spring/fall DST and month boundaries',
    () {
      tz_data.initializeTimeZones();
      final location = tz.getLocation('America/New_York');
      final planner = ScheduledNotificationPlanner(
        localCalendarDateTime: (y, m, d, h, min) =>
            tz.TZDateTime(location, y, m, d, h, min),
      );
      for (final (month, day, offset) in [
        (3, 8, 0),
        (3, 9, 1),
        (11, 1, 0),
        (11, 2, 1),
        (3, 1, 1),
      ]) {
        final result = planner.alertDateTimeForOccurrence(
          _schedule(days: offset, time: 570),
          tz.TZDateTime(location, 2026, month, day),
        );
        expect(
          result,
          tz.TZDateTime(location, 2026, month, day - offset, 9, 30),
        );
        expect(result.hour, 9);
        expect(result.minute, 30);
      }
    },
  );

  test(
    'invalid offsets/times cannot be saved, restored, or scheduled',
    () async {
      final store = FinanceDataStore(dataSet: _data(_schedule()));
      for (final item in [
        _schedule(days: -1),
        _schedule(days: 36501),
        _schedule(time: 1440),
      ]) {
        expect(
          const ScheduledNotificationPlanner().planOne(item, now: _now),
          isNull,
        );
        await expectLater(
          store.saveScheduledTransaction(item),
          throwsA(isA<FinanceDataValidationException>()),
        );
        expect(
          () => const BackupRestoreValidator().validate(
            const BackupCodec().encodeJson(_data(item)),
          ),
          throwsA(isA<BackupValidationException>()),
        );
      }
    },
  );

  testWidgets(
    'Custom opens editor, saves the rule, and reopens with values; scheduled time stays independent',
    (tester) async {
      final item = _schedule().copyWith(alertPreference: AlertPreference.none);
      final store = FinanceDataStore(dataSet: _data(item));
      await _open(
        tester,
        store,
        (context) =>
            app.showScheduledTransactionDialog(context, existing: item),
      );
      await _tap(tester, find.byKey(const ValueKey('scheduled-alert')));
      await _tap(tester, find.text('Custom'));
      expect(find.text('Custom Reminder'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('custom-reminder-days')),
        '3',
      );
      await _tap(tester, find.byKey(const ValueKey('custom-reminder-time')));
      await _chooseTime(tester, const TimeOfDay(hour: 8, minute: 0));
      await _tap(tester, find.byKey(const ValueKey('custom-reminder-save')));
      expect(
        find.text('3 days before · 8:00 AM · Device time'),
        findsOneWidget,
      );
      expect(find.text('12:00 PM'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('scheduled-alert')));
      await _tap(tester, find.textContaining('Custom ·'));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('custom-reminder-days')),
            )
            .controller!
            .text,
        '3',
      );
      expect(find.text('8:00 AM'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('custom-reminder-save')));
      await _tap(tester, find.byKey(const ValueKey('scheduled-alert-time')));
      await _chooseTime(tester, const TimeOfDay(hour: 15, minute: 30));
      expect(
        find.text('3 days before · 8:00 AM · Device time'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Save').last);
      final saved = store.scheduledTransactions.single;
      expect(saved.customAlertOffsetDays, 3);
      expect(saved.customAlertTimeMinutes, 480);
      expect(saved.scheduledTimeMinutes, 930);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same-day custom warns at/after scheduled time; invalid offset disables Save',
    (tester) async {
      await _open(
        tester,
        FinanceDataStore(dataSet: _data(_schedule())),
        (context) => app.showCustomReminderDialog(
          context,
          daysBefore: 0,
          timeMinutes: 720,
          scheduledTimeMinutes: 720,
        ),
      );
      expect(
        find.byKey(const ValueKey('custom-reminder-time-warning')),
        findsOneWidget,
      );
      final save = find.byKey(const ValueKey('custom-reminder-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      for (final invalid in ['-1', '1.5', '', '36501']) {
        await tester.enterText(
          find.byKey(const ValueKey('custom-reminder-days')),
          invalid,
        );
        await tester.pump();
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
      }
      await tester.enterText(
        find.byKey(const ValueKey('custom-reminder-days')),
        '1',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('custom-reminder-time-warning')),
        findsNothing,
      );
    },
  );

  for (final inline in [false, true]) {
    testWidgets(
      '${inline ? 'inline future' : 'new Scheduled'} creation persists the custom rule',
      (tester) async {
        final store = FinanceDataStore(
          dataSet: _data(_schedule()).copyWith(scheduledTransactions: []),
        );
        await _open(tester, store, (context) async {
          if (inline) {
            await app.showTransactionDialog(
              context,
              initialIsExpense: true,
              initialScheduleFutureOccurrences: true,
            );
          } else {
            await app.showScheduledTransactionDialog(
              context,
              initialDate: DateTime.now().add(const Duration(days: 32)),
            );
          }
          return null;
        });
        final prefix = inline ? 'transaction' : 'scheduled';
        await _tap(tester, find.text('Choose account'));
        await _tap(tester, find.text('Checking').last);
        await tester.enterText(find.byKey(ValueKey('$prefix-amount')), '10000');
        await tester.enterText(
          find.byKey(ValueKey('$prefix-payee')),
          'Custom bill',
        );
        await _tap(tester, find.text('Choose category'));
        await _tap(tester, find.text('Dining').last);
        final reminderKey = inline
            ? 'transaction-schedule-alert'
            : 'scheduled-alert';
        await _tap(tester, find.byKey(ValueKey(reminderKey)));
        await _tap(tester, find.text('Custom'));
        await tester.enterText(
          find.byKey(const ValueKey('custom-reminder-days')),
          '7',
        );
        expect(find.text('Reminder time'), findsOneWidget);
        await _tap(tester, find.byKey(const ValueKey('custom-reminder-time')));
        await _chooseTime(tester, const TimeOfDay(hour: 9, minute: 30));
        await _tap(tester, find.byKey(const ValueKey('custom-reminder-save')));
        expect(
          find.text('7 days before · 9:30 AM · Device time'),
          findsOneWidget,
        );
        await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
        final saved = store.scheduledTransactions.single;
        expect(saved.alertPreference, AlertPreference.custom);
        expect(saved.customAlertOffsetDays, 7);
        expect(saved.customAlertTimeMinutes, 570);
        expect(saved.scheduledTimeMinutes, 540);
        expect(saved.frequency, RecurrenceFrequency.monthly);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'legacy Custom reopens same-day; cancelling does not change its rule',
    (tester) async {
      final json = _schedule(time: 1080).toJson()
        ..remove('customAlertOffsetDays')
        ..remove('scheduledTimeMinutes');
      final item = ScheduledTransactionRecord.fromJson(json);
      final store = FinanceDataStore(dataSet: _data(item));
      await _open(
        tester,
        store,
        (context) =>
            app.showScheduledTransactionDialog(context, existing: item),
      );
      expect(find.text('Same day · 6:00 PM · Device time'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('scheduled-alert')));
      await _tap(
        tester,
        find.text('Custom · Same day · 6:00 PM · Device time'),
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('custom-reminder-days')),
            )
            .controller!
            .text,
        '0',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('custom-reminder-time')),
          matching: find.text('6:00 PM'),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-reminder-days')),
        '3',
      );
      await _tap(tester, find.text('Cancel').last);
      expect(find.text('Same day · 6:00 PM · Device time'), findsOneWidget);
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      final saved = store.scheduledTransactions.single;
      expect(saved.customAlertOffsetDays, 0);
      expect(saved.customAlertTimeMinutes, 1080);
      expect(saved.scheduledTimeMinutes, 1080);
      expect(tester.takeException(), isNull);
    },
  );
}

class _RecordingScheduler implements NotificationScheduler {
  final active = <ScheduledNotificationRequest>[];
  final cancelled = <int>[];
  @override
  Future<bool> requestPermissionIfNeeded() async => true;
  @override
  Future<void> updateBadgeCount(int count) async {}
  @override
  Future<void> cancelScheduledTransaction(
    ScheduledTransactionRecord item,
  ) async {
    cancelled.addAll(item.scheduledNotificationIds);
    active.removeWhere(
      (request) => item.scheduledNotificationIds.contains(request.id),
    );
  }

  @override
  Future<List<int>> scheduleScheduledTransaction(
    ScheduledTransactionRecord item,
  ) async {
    final request = const ScheduledNotificationPlanner().planOne(
      item,
      now: _now,
    );
    if (request == null) return [];
    active.add(request);
    return [request.id];
  }

  @override
  Future<void> rescheduleScheduledTransaction(
    ScheduledTransactionRecord item,
  ) async {
    await cancelScheduledTransaction(item);
    await scheduleScheduledTransaction(item);
  }
}

Future<void> _open(
  WidgetTester tester,
  FinanceDataStore store,
  Future<Object?> Function(BuildContext) action,
) async {
  tester.view.physicalSize = const Size(393, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    FinanceDataStoreScope(
      store: store,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => action(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _chooseTime(WidgetTester tester, TimeOfDay time) async {
  await _tap(tester, find.byIcon(Icons.keyboard_outlined));
  final fields = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(
    fields.at(0),
    '${time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod}',
  );
  await tester.enterText(fields.at(1), '${time.minute}'.padLeft(2, '0'));
  await _tap(tester, find.text(time.period == DayPeriod.am ? 'AM' : 'PM').last);
  await _tap(tester, find.text('OK'));
}
