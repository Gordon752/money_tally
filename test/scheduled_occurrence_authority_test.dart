import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/scheduled_occurrence_authority.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/notifications/notification_scheduler.dart';

void main() {
  group('scheduled occurrence authority', () {
    test('higher revision defeats stale unresolved schedule state', () {
      final stale = schedule(nextDate: DateTime(2026, 8, 29));
      final paid = state(
        date: DateTime(2026, 8, 29),
        status: ScheduledOccurrenceStatus.paid,
        revision: 1,
        operationId: 'paid-a',
      );
      final advanced = withOccurrenceAuthority(
        stale.copyWith(nextDate: DateTime(2027, 8, 29), sync: stale.sync),
        paid,
      );

      final merged = mergeScheduledTransactionAuthority(
        incoming: advanced,
        current: stale.copyWith(
          sync: stale.sync.touched(now: DateTime(2026, 8, 22, 18, 27)),
        ),
        preferCurrentOnDefinitionTie: true,
      );

      expect(
        merged.occurrenceStates['20260829']?.status,
        ScheduledOccurrenceStatus.paid,
      );
      expect(effectiveNextActionableDate(merged), DateTime(2027, 8, 29));
    });

    test('equal revision converges by operation id, not receive order', () {
      final base = schedule();
      final paid = withOccurrenceAuthority(
        base,
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.paid,
          revision: 1,
          operationId: 'aaa',
        ),
      );
      final skipped = withOccurrenceAuthority(
        base,
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.skipped,
          revision: 1,
          operationId: 'zzz',
        ),
      );

      final leftFirst = mergeScheduledTransactionAuthority(
        incoming: paid,
        current: skipped,
        preferCurrentOnDefinitionTie: true,
      );
      final rightFirst = mergeScheduledTransactionAuthority(
        incoming: skipped,
        current: paid,
        preferCurrentOnDefinitionTie: true,
      );

      expect(
        leftFirst.occurrenceStates['20260829']?.status,
        ScheduledOccurrenceStatus.skipped,
      );
      expect(
        rightFirst.occurrenceStates['20260829']?.status,
        ScheduledOccurrenceStatus.skipped,
      );
    });

    test('newer Undo Pending legitimately reopens the earlier date', () {
      final base = schedule();
      final paid = withOccurrenceAuthority(
        base.copyWith(nextDate: DateTime(2027, 8, 29), sync: base.sync),
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.paid,
          revision: 1,
          operationId: 'paid',
        ),
      );
      final undone = withOccurrenceAuthority(
        paid,
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.pending,
          revision: 2,
          operationId: 'undo',
        ),
      );

      expect(effectiveNextActionableDate(undone), DateTime(2026, 8, 29));
      expect(undone.nextDate, DateTime(2026, 8, 29));
    });

    test('manual next-date edit cannot reopen a resolved occurrence', () {
      final base = schedule();
      final paid = withOccurrenceAuthority(
        base,
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.paid,
          revision: 1,
          operationId: 'paid',
        ),
      );
      final editedBack = paid.copyWith(
        nextDate: base.nextDate,
        sync: paid.sync,
      );

      expect(effectiveNextActionableDate(editedBack), DateTime(2027, 8, 29));
    });

    test('legacy resolved history lazily becomes revision one', () {
      final legacy = schedule().copyWith(
        occurrences: [
          ScheduledOccurrenceRecord(
            scheduledDate: DateTime(2026, 8, 29),
            plannedAmountMinor: 10000,
            status: ScheduledOccurrenceStatus.paid,
            transactionId: 'stable-transaction',
          ),
        ],
        sync: schedule().sync,
      );

      final converted = occurrenceAuthorityFor(legacy)['20260829'];
      expect(converted?.revision, 1);
      expect(converted?.transactionId, 'stable-transaction');
      expect(effectiveNextActionableDate(legacy), DateTime(2027, 8, 29));
    });

    test('notification planner uses effective unresolved recurrence', () {
      final base = schedule(alertPreference: AlertPreference.oneWeekBefore);
      final paid = withOccurrenceAuthority(
        base,
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.paid,
          revision: 1,
          operationId: 'paid',
        ),
      );

      final request = const ScheduledNotificationPlanner().planOne(
        paid,
        now: DateTime(2026, 8, 22, 8),
      );

      expect(request?.occurrenceDate, DateTime(2027, 8, 29));
      expect(request?.scheduledFor.year, 2027);
    });

    test('repeated A/B merges cannot resurrect stale occurrence', () {
      final base = schedule();
      var deviceA = withOccurrenceAuthority(
        base.copyWith(nextDate: DateTime(2027, 8, 29), sync: base.sync),
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.paid,
          revision: 1,
          operationId: 'paid',
        ),
      );
      var deviceB = base.copyWith(
        sync: base.sync.touched(now: DateTime(2026, 8, 22, 18, 27)),
      );
      for (var cycle = 0; cycle < 5; cycle += 1) {
        deviceB = mergeScheduledTransactionAuthority(
          incoming: deviceA,
          current: deviceB,
          preferCurrentOnDefinitionTie: true,
        );
        deviceA = mergeScheduledTransactionAuthority(
          incoming: deviceB,
          current: deviceA,
          preferCurrentOnDefinitionTie: true,
        );
      }
      expect(
        deviceA.occurrenceStates['20260829']?.status,
        ScheduledOccurrenceStatus.paid,
      );
      expect(effectiveNextActionableDate(deviceB), DateTime(2027, 8, 29));
    });

    test('stale definition timestamp cannot resurrect one-time completion', () {
      final base = schedule().copyWith(
        frequency: RecurrenceFrequency.once,
        sync: schedule().sync,
      );
      final paid = withOccurrenceAuthority(
        base.copyWith(sync: base.sync.deleted(deviceId: 'A')),
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.paid,
          revision: 1,
          operationId: 'paid-A',
        ),
      );
      final stale = base.copyWith(
        sync: base.sync.touched(now: DateTime(2026, 8, 22, 20)),
      );

      final merged = mergeScheduledTransactionAuthority(
        incoming: paid,
        current: stale,
        preferCurrentOnDefinitionTie: true,
      );

      expect(merged.isDeleted, isTrue);
      expect(effectiveNextActionableDate(merged), isNull);
    });

    test('newer Pending authority legitimately restores a tombstone', () {
      final base = schedule().copyWith(
        frequency: RecurrenceFrequency.once,
        sync: schedule().sync,
      );
      final paid = withOccurrenceAuthority(
        base.copyWith(sync: base.sync.deleted(deviceId: 'A')),
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.paid,
          revision: 1,
          operationId: 'paid-A',
        ),
      );
      final undone = withOccurrenceAuthority(
        paid.copyWith(sync: paid.sync.restored(deviceId: 'B')),
        state(
          date: base.nextDate,
          status: ScheduledOccurrenceStatus.pending,
          revision: 2,
          operationId: 'undo-B',
        ),
      );

      final merged = mergeScheduledTransactionAuthority(
        incoming: paid,
        current: undone,
        preferCurrentOnDefinitionTie: true,
      );

      expect(merged.isDeleted, isFalse);
      expect(effectiveNextActionableDate(merged), base.nextDate);
    });
  });
}

ScheduledTransactionRecord schedule({
  DateTime? nextDate,
  AlertPreference alertPreference = AlertPreference.none,
}) => ScheduledTransactionRecord(
  id: 'porkbun',
  type: TransactionType.expense,
  accountId: 'wallet',
  categoryId: 'subscriptions',
  payee: 'Porkbun',
  amountMinor: 10000,
  nextDate: nextDate ?? DateTime(2026, 8, 29),
  frequency: RecurrenceFrequency.yearly,
  alertPreference: alertPreference,
  sync: SyncMetadata.fresh(now: DateTime(2026, 8, 1), deviceId: 'phone'),
);

ScheduledOccurrenceState state({
  required DateTime date,
  required ScheduledOccurrenceStatus status,
  required int revision,
  required String operationId,
}) => ScheduledOccurrenceState(
  scheduledDate: date,
  plannedAmountMinor: 10000,
  status: status,
  revision: revision,
  operationId: operationId,
  changedAt: DateTime(2026, 8, 22),
  deviceId: 'test',
);
