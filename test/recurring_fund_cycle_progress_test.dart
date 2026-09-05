import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart'
    show completeScheduledTransactionPayment, fundTargetPresentation;
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/funds/recurring_fund_cycle_calculator.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  final september = DateTime(2026, 9, 4);

  test(
    'explicit EOM Spend and Return keep the whole active snapshot aligned',
    () async {
      final store = _store(targetDayRule: FundTargetDayRule.endOfMonth);
      await _allocate(store, 1170000);
      final before = store.recurringFundCycleProgress('bills', asOf: september);
      await _expense(store, id: 'september-obligation', amountMinor: 30000);
      final spent = store.recurringFundCycleProgress('bills', asOf: september);
      expect(spent.reservedMinor, before.reservedMinor - 30000);
      expect(spent.completedCycles, before.completedCycles);
      expect(spent.activeCycleFundedMinor, before.activeCycleFundedMinor);
      expect(spent.activeCycleFundingDeadline, DateTime(2026, 11, 30));

      for (final step in [
        (
          returned: 325169,
          completed: 2,
          funded: 124831,
          month: 11,
          percent: 35,
        ),
        (returned: 64831, completed: 2, funded: 60000, month: 11, percent: 17),
        (
          returned: 180000,
          completed: 1,
          funded: 240000,
          month: 10,
          percent: 67,
        ),
        (returned: 360000, completed: 0, funded: 240000, month: 9, percent: 67),
      ]) {
        await store.returnReservation(
          containerType: ReservationContainerType.fund,
          containerId: 'bills',
          amountMinor: step.returned,
          date: september,
        );
        final cycle = store.recurringFundCycleProgress(
          'bills',
          asOf: september,
        );
        final text = fundTargetPresentation(
          fund: store.fundById('bills'),
          currentMinor: cycle.reservedMinor,
          currency: store.preferences.currency,
          recurringCycleProgress: cycle,
        );
        expect(cycle.completedCycles, step.completed);
        expect(cycle.activeCycleFundedMinor, step.funded);
        expect(cycle.activeCycleRemainingMinor, 360000 - step.funded);
        expect(cycle.activeCyclePercent, step.percent);
        expect(cycle.activeCycleTargetDate, DateTime(2026, step.month + 1, 0));
        expect(text.fundingDeadline, DateTime(2026, step.month, 0));
        expect(text.activeCycleProgress, step.funded / 360000);
        expect(text.barProgress, cycle.barProgress);
        expect(text.showsMovingCycleBoundary, step.completed > 0);
        if (step.completed > 0) {
          final monthName = step.month == 11 ? 'November' : 'October';
          expect(text.secondaryStatus, '$monthName ${step.percent}% funded');
          expect(text.status, contains('needed for $monthName'));
        } else {
          expect(text.status, r'$1,200.00 needed to fully fund');
        }
      }
    },
  );

  for (final scenario in [
    (
      occurrence: DateTime(2026, 10, 3),
      paid: DateTime(2026, 9, 28),
      allocated: 600000,
      completed: 1,
      funded: 240000,
      cycle: DateTime(2026, 10, 31),
    ),
    (
      occurrence: DateTime(2026, 9, 28),
      paid: DateTime(2026, 10, 2),
      allocated: 600000,
      completed: 1,
      funded: 210000,
      cycle: DateTime(2026, 11, 30),
    ),
    // These distinguish true EOM attribution from the old fixed 30th boundary.
    (
      occurrence: DateTime(2026, 10, 31),
      paid: DateTime(2026, 10, 2),
      allocated: 300000,
      completed: 0,
      funded: 300000,
      cycle: DateTime(2026, 10, 31),
    ),
    (
      occurrence: DateTime(2026, 10, 31),
      paid: DateTime(2026, 11, 2),
      allocated: 300000,
      completed: 0,
      funded: 270000,
      cycle: DateTime(2026, 11, 30),
    ),
  ]) {
    test(
      'EOM occurrence ${scenario.occurrence} paid ${scenario.paid}',
      () async {
        final store = _store(targetDayRule: FundTargetDayRule.endOfMonth);
        await _allocate(store, scenario.allocated);
        final schedule = await _saveSchedule(
          store,
          id: 'eom-scheduled',
          occurrenceDate: scenario.occurrence,
        );
        await completeScheduledTransactionPayment(
          store,
          schedule,
          scheduledDate: scenario.occurrence,
          actualAmountMinor: 30000,
          paymentDate: scenario.paid,
          payee: 'EOM bill',
          note: '',
        );
        final cycle = store.recurringFundCycleProgress(
          'bills',
          asOf: scenario.paid,
        );
        expect(cycle.reservedMinor, scenario.allocated - 30000);
        expect(cycle.completedCycles, scenario.completed);
        expect(cycle.activeCycleFundedMinor, scenario.funded);
        expect(cycle.activeCycleTargetDate, scenario.cycle);
        expect(
          cycle.activeCycleFundingDeadline,
          DateTime(scenario.cycle.year, scenario.cycle.month, 0),
        );
      },
    );
  }

  test('manual EOM spending on the 31st stays in that cycle', () async {
    final store = _store(targetDayRule: FundTargetDayRule.endOfMonth);
    await _allocate(store, 300000);
    await _expense(
      store,
      id: 'october-manual',
      amountMinor: 30000,
      date: DateTime(2026, 10, 31),
    );
    final cycle = store.recurringFundCycleProgress(
      'bills',
      asOf: DateTime(2026, 10, 31, 23),
    );
    expect(cycle.reservedMinor, 270000);
    expect(cycle.activeCycleFundedMinor, 300000);
    expect(cycle.activeCycleTargetDate, DateTime(2026, 10, 31));
    expect(cycle.activeCycleFundingDeadline, DateTime(2026, 9, 30));
  });

  for (final scenario in [
    (
      amount: 300000,
      completed: 0,
      funded: 300000,
      cycle: 9,
      percent: 83,
      status: r'$600.00 needed to fully fund',
      secondary: null,
    ),
    (
      amount: 360000,
      completed: 1,
      funded: 0,
      cycle: 10,
      percent: 0,
      status: 'Target met',
      secondary: null,
    ),
    (
      amount: 540000,
      completed: 1,
      funded: 180000,
      cycle: 10,
      percent: 50,
      status: r'September fully funded · $1,800.00 needed for October',
      secondary: 'October 50% funded',
    ),
    (
      amount: 844831,
      completed: 2,
      funded: 124831,
      cycle: 11,
      percent: 35,
      status: r'2 months fully funded · $2,351.69 needed for November',
      secondary: 'November 35% funded',
    ),
    (
      amount: 1080000,
      completed: 3,
      funded: 0,
      cycle: 12,
      percent: 0,
      status: '3 months fully funded',
      secondary: null,
    ),
    (
      amount: 1170000,
      completed: 3,
      funded: 90000,
      cycle: 12,
      percent: 25,
      status: r'3 months fully funded · $2,700.00 needed for December',
      secondary: 'December 25% funded',
    ),
    (
      amount: 1530000,
      completed: 4,
      funded: 90000,
      cycle: 13,
      percent: 25,
      status: r'4 months fully funded · $2,700.00 needed for January',
      secondary: 'January 25% funded',
    ),
  ]) {
    test(
      'snapshot aligns funding deadline at ${scenario.amount} minor units',
      () async {
        final store = _store(nextTargetDate: DateTime(2026, 8, 31));
        final canonicalFund = store.fundById('bills').toJson();
        await _allocate(store, scenario.amount);
        final cycle = store.recurringFundCycleProgress(
          'bills',
          asOf: september,
        );
        final deadline = DateTime(2026, scenario.cycle, 0);

        expect(cycle.currentCycleTargetDate, DateTime(2026, 9, 30));
        expect(cycle.completedCycles, scenario.completed);
        expect(cycle.activeCycleFundedMinor, scenario.funded);
        expect(cycle.activeCycleRemainingMinor, 360000 - scenario.funded);
        expect(cycle.activeCyclePercent, scenario.percent);
        expect(
          cycle.activeCycleTargetDate,
          DateTime(2026, scenario.cycle + 1, 0),
        );
        expect(cycle.activeCycleFundingDeadline, deadline);
        final text = fundTargetPresentation(
          fund: store.fundById('bills'),
          currentMinor: cycle.reservedMinor,
          currency: store.preferences.currency,
          // A later UI clock must not advance any part of an existing snapshot.
          asOf: DateTime(2027, 1, 1),
          recurringCycleProgress: cycle,
        );
        expect(text.status, scenario.status);
        expect(text.secondaryStatus, scenario.secondary);
        expect(text.fundingDeadline, cycle.isExactlyFunded ? null : deadline);
        expect(text.barProgress, cycle.barProgress);
        expect(text.activeCycleProgress, scenario.funded / 360000);
        expect(
          text.showsMovingCycleBoundary,
          scenario.completed > 0 && scenario.funded > 0,
        );
        expect(text.status, isNot(contains(r'$0.00 needed')));
        expect(store.fundById('bills').toJson(), canonicalFund);
      },
    );
  }

  test(
    'returns move the entire snapshot backwards through several cycles',
    () async {
      final store = _store(nextTargetDate: DateTime(2026, 8, 31));
      await _allocate(store, 1170000);
      for (final step in [
        (
          returned: 325169,
          completed: 2,
          funded: 124831,
          cycle: 11,
          percent: 35,
        ),
        (returned: 64831, completed: 2, funded: 60000, cycle: 11, percent: 17),
        (
          returned: 180000,
          completed: 1,
          funded: 240000,
          cycle: 10,
          percent: 67,
        ),
        (returned: 360000, completed: 0, funded: 240000, cycle: 9, percent: 67),
      ]) {
        await store.returnReservation(
          containerType: ReservationContainerType.fund,
          containerId: 'bills',
          amountMinor: step.returned,
          date: september,
        );
        final cycle = store.recurringFundCycleProgress(
          'bills',
          asOf: september,
        );
        expect(cycle.completedCycles, step.completed);
        expect(cycle.activeCycleFundedMinor, step.funded);
        expect(cycle.activeCycleRemainingMinor, 360000 - step.funded);
        expect(cycle.activeCyclePercent, step.percent);
        expect(cycle.activeCycleTargetDate, DateTime(2026, step.cycle + 1, 0));
        expect(cycle.activeCycleFundingDeadline, DateTime(2026, step.cycle, 0));
        expect(cycle.activeCycleProgress, step.funded / 360000);
      }
    },
  );

  test(
    'Spend preserves future deadline while Return can move it backwards',
    () async {
      final spendStore = _store(nextTargetDate: DateTime(2026, 8, 31));
      final returnStore = _store(nextTargetDate: DateTime(2026, 8, 31));
      await _allocate(spendStore, 730000);
      await _allocate(returnStore, 730000);
      final before = spendStore.recurringFundCycleProgress(
        'bills',
        asOf: september,
      );
      await _expense(spendStore, id: 'current-obligation', amountMinor: 30000);
      await returnStore.returnReservation(
        containerType: ReservationContainerType.fund,
        containerId: 'bills',
        amountMinor: 30000,
        date: september,
      );
      final spent = spendStore.recurringFundCycleProgress(
        'bills',
        asOf: september,
      );
      final returned = returnStore.recurringFundCycleProgress(
        'bills',
        asOf: september,
      );
      expect(spent.reservedMinor, returned.reservedMinor);
      expect(spent.completedCycles, before.completedCycles);
      expect(spent.activeCycleFundedMinor, before.activeCycleFundedMinor);
      expect(spent.activeCycleTargetDate, DateTime(2026, 11, 30));
      expect(spent.activeCycleFundingDeadline, DateTime(2026, 10, 31));
      expect(returned.completedCycles, 1);
      expect(returned.activeCycleTargetDate, DateTime(2026, 10, 31));
      expect(returned.activeCycleFundingDeadline, DateTime(2026, 9, 30));
    },
  );

  test(
    'deadlines retain fixed target days and restore 31st after February',
    () async {
      for (final scenario in [
        (
          anchor: DateTime(2026, 9, 15),
          asOf: DateTime(2026, 9, 20),
          active: DateTime(2026, 11, 15),
          deadline: DateTime(2026, 10, 15),
        ),
        (
          anchor: DateTime(2026, 9, 30),
          asOf: DateTime(2026, 9, 4),
          active: DateTime(2026, 10, 30),
          deadline: DateTime(2026, 9, 30),
        ),
        (
          anchor: DateTime(2026, 8, 31),
          asOf: DateTime(2027, 2, 4),
          active: DateTime(2027, 3, 31),
          deadline: DateTime(2027, 2, 28),
        ),
        (
          anchor: DateTime(2026, 8, 31),
          asOf: DateTime(2028, 2, 4),
          active: DateTime(2028, 3, 31),
          deadline: DateTime(2028, 2, 29),
        ),
        (
          anchor: DateTime(2026, 9, 30),
          asOf: DateTime(2027, 2, 4),
          active: DateTime(2027, 3, 30),
          deadline: DateTime(2027, 2, 28),
        ),
      ]) {
        final store = _store(nextTargetDate: scenario.anchor);
        await _allocate(store, 540000);
        final cycle = store.recurringFundCycleProgress(
          'bills',
          asOf: scenario.asOf,
        );
        expect(cycle.activeCycleTargetDate, scenario.active);
        expect(cycle.activeCycleFundingDeadline, scenario.deadline);
      }
    },
  );

  test('exact target funds the current recurring cycle', () async {
    final store = _store();
    await _allocate(store, 360000);

    final progress = store.recurringFundCycleProgress('bills', asOf: september);

    expect(progress.reservedMinor, 360000);
    expect(progress.completedCycles, 1);
    expect(progress.activeCycleFundedMinor, 0);
  });

  test('raw 6000 funds one cycle plus about 67 percent', () async {
    final store = _store();
    await _allocate(store, 600000);

    final progress = store.recurringFundCycleProgress('bills', asOf: september);

    expect(progress.reservedMinor, 600000);
    expect(progress.completedCycles, 1);
    expect(progress.activeCycleFundedMinor, 240000);
  });

  test('current-cycle consumption preserves next-cycle progress', () async {
    final store = _store();
    await _allocate(store, 600000);

    await _expense(store, id: 'september-bill', amountMinor: 30000);
    final progress = store.recurringFundCycleProgress('bills', asOf: september);

    expect(progress.reservedMinor, 570000);
    expect(progress.completedCycles, 1);
    expect(progress.activeCycleFundedMinor, 240000);
    expect(
      fundTargetPresentation(
        fund: store.fundById('bills'),
        currentMinor: progress.reservedMinor,
        currency: store.preferences.currency,
        asOf: september,
        recurringCycleProgress: progress,
      ).status,
      r'September fully funded · $1,200.00 needed for October',
    );
    expect(
      fundTargetPresentation(
        fund: store.fundById('bills'),
        currentMinor: progress.reservedMinor,
        currency: store.preferences.currency,
        asOf: september,
        recurringCycleProgress: progress,
      ).secondaryStatus,
      'October 67% funded',
    );
  });

  test('several current-cycle bills preserve next-cycle progress', () async {
    final store = _store();
    await _allocate(store, 600000);

    await _expense(store, id: 'bill-a', amountMinor: 30000);
    await _expense(store, id: 'bill-b', amountMinor: 45000);
    await _expense(store, id: 'bill-c', amountMinor: 25000);
    final progress = store.recurringFundCycleProgress('bills', asOf: september);

    expect(progress.reservedMinor, 500000);
    expect(progress.completedCycles, 1);
    expect(progress.activeCycleFundedMinor, 240000);
  });

  test('returning money reduces subsequent-cycle progress', () async {
    final store = _store();
    await _allocate(store, 600000);

    await store.returnReservation(
      containerType: ReservationContainerType.fund,
      containerId: 'bills',
      amountMinor: 30000,
      date: september,
    );
    final progress = store.recurringFundCycleProgress('bills', asOf: september);

    expect(progress.reservedMinor, 570000);
    expect(progress.completedCycles, 1);
    expect(progress.activeCycleFundedMinor, 210000);
  });

  test(
    'Scheduled current-cycle payment preserves next-cycle progress',
    () async {
      final store = _store();
      await _allocate(store, 600000);
      final schedule = await _saveSchedule(
        store,
        id: 'september-schedule',
        occurrenceDate: DateTime(2026, 9, 15),
      );

      await completeScheduledTransactionPayment(
        store,
        schedule,
        scheduledDate: DateTime(2026, 9, 15),
        actualAmountMinor: 30000,
        paymentDate: september,
        payee: 'September bill',
        note: '',
      );
      final progress = store.recurringFundCycleProgress(
        'bills',
        asOf: september,
      );

      expect(progress.reservedMinor, 570000);
      expect(progress.completedCycles, 1);
      expect(progress.activeCycleFundedMinor, 240000);
      expect(progress.activeCycleTargetDate, DateTime(2026, 10, 30));
      expect(progress.activeCycleFundingDeadline, DateTime(2026, 9, 30));
    },
  );

  test(
    'next-cycle Scheduled bill paid early consumes the next cycle',
    () async {
      final store = _store();
      await _allocate(store, 600000);
      final schedule = await _saveSchedule(
        store,
        id: 'october-schedule',
        occurrenceDate: DateTime(2026, 10, 3),
      );

      await completeScheduledTransactionPayment(
        store,
        schedule,
        scheduledDate: DateTime(2026, 10, 3),
        actualAmountMinor: 30000,
        paymentDate: DateTime(2026, 9, 28),
        payee: 'October bill paid early',
        note: '',
      );
      final progress = store.recurringFundCycleProgress(
        'bills',
        asOf: DateTime(2026, 9, 28),
      );

      expect(progress.reservedMinor, 570000);
      expect(progress.completedCycles, 1);
      expect(progress.activeCycleFundedMinor, 240000);
    },
  );

  test(
    'prior-cycle Scheduled bill paid late is not charged to current cycle',
    () async {
      final store = _store();
      await _allocate(store, 600000);
      final schedule = await _saveSchedule(
        store,
        id: 'late-september-schedule',
        occurrenceDate: DateTime(2026, 9, 28),
      );

      await completeScheduledTransactionPayment(
        store,
        schedule,
        scheduledDate: DateTime(2026, 9, 28),
        actualAmountMinor: 30000,
        paymentDate: DateTime(2026, 10, 2),
        payee: 'September bill paid late',
        note: '',
      );
      final progress = store.recurringFundCycleProgress(
        'bills',
        asOf: DateTime(2026, 10, 2),
      );

      expect(progress.reservedMinor, 570000);
      expect(progress.completedCycles, 1);
      expect(progress.activeCycleFundedMinor, 210000);
      expect(progress.activeCycleTargetDate, DateTime(2026, 11, 30));
      expect(progress.activeCycleFundingDeadline, DateTime(2026, 10, 30));
    },
  );

  test(
    'manual Fund-backed transaction resolves from its effective date',
    () async {
      final store = _store();
      await _allocate(store, 600000);

      final transaction = await _expense(
        store,
        id: 'manual-bill',
        amountMinor: 30000,
      );
      final operation = store.reservationOperations.singleWhere(
        (item) => item.transactionId == transaction.id,
      );
      final progress = store.recurringFundCycleProgress(
        'bills',
        asOf: september,
      );

      expect(operation.scheduledOccurrenceDate, isNull);
      expect(operation.effectiveDate, september);
      expect(progress.activeCycleFundedMinor, 240000);
    },
  );

  test(
    'cycle attribution follows the target-day anchor, not month number',
    () async {
      final store = _store(nextTargetDate: DateTime(2026, 9, 15));
      await _allocate(store, 600000);

      await _expense(
        store,
        id: 'after-september-checkpoint',
        amountMinor: 30000,
        date: DateTime(2026, 9, 20),
      );
      final progress = store.recurringFundCycleProgress(
        'bills',
        asOf: DateTime(2026, 9, 20),
      );

      expect(progress.reservedMinor, 570000);
      expect(progress.completedCycles, 1);
      expect(progress.activeCycleFundedMinor, 240000);
    },
  );

  test(
    'same-month future cycle spending cannot fund the earlier cycle',
    () async {
      final store = _store(nextTargetDate: DateTime(2026, 9, 15));
      await _allocate(store, 360000);
      final schedule = await _saveSchedule(
        store,
        id: 'same-month-future-cycle',
        occurrenceDate: DateTime(2026, 9, 20),
      );

      await completeScheduledTransactionPayment(
        store,
        schedule,
        scheduledDate: DateTime(2026, 9, 20),
        actualAmountMinor: 30000,
        paymentDate: DateTime(2026, 9, 10),
        payee: 'Next cycle paid early',
        note: '',
      );
      final progress = store.recurringFundCycleProgress(
        'bills',
        asOf: DateTime(2026, 9, 10),
      );

      expect(progress.reservedMinor, 330000);
      expect(progress.completedCycles, 0);
      expect(progress.activeCycleFundedMinor, 330000);
    },
  );

  test(
    'pending consumption counts once and clearing does not consume twice',
    () async {
      final store = _store();
      await _allocate(store, 600000);
      final pending = await _expense(
        store,
        id: 'pending-bill',
        amountMinor: 30000,
        status: TransactionStatus.pending,
      );
      final beforeCount = store.reservationOperations.length;
      final before = store.recurringFundCycleProgress('bills', asOf: september);

      await store.setTransactionStatus(pending.id, TransactionStatus.cleared);
      final after = store.recurringFundCycleProgress('bills', asOf: september);

      expect(before.reservedMinor, 570000);
      expect(before.activeCycleFundedMinor, 240000);
      expect(store.reservationOperations, hasLength(beforeCount));
      expect(after.reservedMinor, before.reservedMinor);
      expect(after.completedCycles, before.completedCycles);
      expect(after.activeCycleFundedMinor, before.activeCycleFundedMinor);
    },
  );

  test('future-dated consumption does not affect today prematurely', () async {
    final store = _store();
    await _allocate(store, 600000);
    await _expense(
      store,
      id: 'future-bill',
      amountMinor: 30000,
      date: DateTime(2026, 10, 3),
    );

    final today = store.recurringFundCycleProgress('bills', asOf: september);
    final future = store.recurringFundCycleProgress(
      'bills',
      asOf: DateTime(2026, 10, 3),
    );

    expect(today.reservedMinor, 600000);
    expect(today.activeCycleFundedMinor, 240000);
    expect(future.reservedMinor, 570000);
    expect(future.completedCycles, 1);
    expect(future.activeCycleFundedMinor, 240000);
  });

  test('transaction undo restores reservation and cycle state', () async {
    final store = _store();
    await _allocate(store, 600000);
    final transaction = await _expense(
      store,
      id: 'undo-bill',
      amountMinor: 30000,
    );

    await store.saveTransaction(
      transaction.copyWith(
        sync: transaction.sync.deleted(deviceId: store.deviceId),
      ),
    );
    final progress = store.recurringFundCycleProgress('bills', asOf: september);

    expect(progress.reservedMinor, 600000);
    expect(progress.completedCycles, 1);
    expect(progress.activeCycleFundedMinor, 240000);
  });

  test(
    'future-cycle spending cannot conceal current-cycle shortfall',
    () async {
      final store = _store();
      await _allocate(store, 360000);
      final schedule = await _saveSchedule(
        store,
        id: 'future-shortfall',
        occurrenceDate: DateTime(2026, 10, 3),
      );

      await completeScheduledTransactionPayment(
        store,
        schedule,
        scheduledDate: DateTime(2026, 10, 3),
        actualAmountMinor: 30000,
        paymentDate: september,
        payee: 'Future bill',
        note: '',
      );
      final progress = store.recurringFundCycleProgress(
        'bills',
        asOf: september,
      );

      expect(progress.reservedMinor, 330000);
      expect(progress.completedCycles, 0);
      expect(progress.activeCycleFundedMinor, 330000);
    },
  );

  test('consumption credit is capped and cannot fund a later cycle', () async {
    final store = _store();
    await _allocate(store, 720000);

    await _expense(store, id: 'overspend', amountMinor: 400000);
    final progress = store.recurringFundCycleProgress('bills', asOf: september);

    expect(progress.reservedMinor, 320000);
    expect(progress.completedCycles, 1);
    expect(progress.activeCycleFundedMinor, 320000);
  });

  test(
    'two-plus-cycle moving progress survives current-cycle spending',
    () async {
      final store = _store();
      await _allocate(store, 900000);
      final before = store.recurringFundCycleProgress('bills', asOf: september);

      await _expense(store, id: 'two-cycle-bill', amountMinor: 30000);
      final after = store.recurringFundCycleProgress('bills', asOf: september);

      expect(before.completedCycles, 2);
      expect(before.activeCycleFundedMinor, 180000);
      expect(after.reservedMinor, 870000);
      expect(after.completedCycles, 2);
      expect(after.activeCycleFundedMinor, 180000);
    },
  );

  test(
    'identical records derive identical progress in any input order',
    () async {
      final store = _store();
      await _allocate(store, 600000);
      await _expense(store, id: 'deterministic-a', amountMinor: 30000);
      await _expense(store, id: 'deterministic-b', amountMinor: 20000);
      final effective = effectiveReservationOperationsForContainer(
        operations: store.reservationOperations,
        transactions: store.transactions,
        scheduledTransactions: store.scheduledTransactions,
        containerType: ReservationContainerType.fund,
        containerId: 'bills',
      );

      final first = calculateRecurringFundCycleProgress(
        fund: store.fundById('bills'),
        effectiveOperations: effective,
        transactions: store.transactions,
        asOf: september,
      );
      final second = calculateRecurringFundCycleProgress(
        fund: store.fundById('bills'),
        effectiveOperations: effective.reversed,
        transactions: store.transactions.reversed,
        asOf: september,
      );

      expect(second.reservedMinor, first.reservedMinor);
      expect(second.completedCycles, first.completedCycles);
      expect(second.activeCycleFundedMinor, first.activeCycleFundedMinor);
    },
  );
}

FinanceDataStore _store({
  DateTime? nextTargetDate,
  FundTargetDayRule targetDayRule = FundTargetDayRule.fixedDay,
}) {
  final sync = SyncMetadata.fresh(
    now: DateTime.utc(2026, 9, 4),
    deviceId: 'test',
  );
  return FinanceDataStore(
    dataSet: FinanceDataSet(
      accounts: [
        AccountRecord(
          id: 'checking',
          name: 'CTBI',
          type: AccountType.checking,
          openingBalanceMinor: 2000000,
          sync: sync,
        ),
      ],
      categories: [
        CategoryRecord(
          id: 'bills-category',
          name: 'Bills',
          kind: CategoryKind.expense,
          sync: sync,
        ),
      ],
      transactions: const [],
      scheduledTransactions: const [],
      budgets: const [],
      goals: const [],
      funds: [
        FundRecord(
          id: 'bills',
          name: 'Bills',
          fundingAccountId: 'checking',
          status: FundStatus.active,
          targetBalanceMinor: 360000,
          targetCadence: FundTargetCadence.monthly,
          targetDayRule: targetDayRule,
          nextTargetDate: nextTargetDate ?? DateTime(2026, 9, 30),
          sync: sync,
        ),
      ],
      preferences: const UserPreferences(),
    ),
    deviceId: 'test',
  );
}

Future<void> _allocate(FinanceDataStore store, int amountMinor) =>
    store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: 'bills',
      amountMinor: amountMinor,
      date: DateTime(2026, 9, 1),
    );

Future<TransactionRecord> _expense(
  FinanceDataStore store, {
  required String id,
  required int amountMinor,
  DateTime? date,
  TransactionStatus status = TransactionStatus.cleared,
}) async {
  final transaction = TransactionRecord(
    id: id,
    type: TransactionType.expense,
    accountId: 'checking',
    categoryId: 'bills-category',
    date: date ?? DateTime(2026, 9, 4),
    payee: id,
    amountMinor: amountMinor,
    status: status,
    reservationContainerType: ReservationContainerType.fund,
    reservationContainerId: 'bills',
    sync: SyncMetadata.fresh(now: DateTime.utc(2026, 9, 4), deviceId: 'test'),
  );
  await store.saveTransaction(transaction);
  return store.transactions.singleWhere((item) => item.id == id);
}

Future<ScheduledTransactionRecord> _saveSchedule(
  FinanceDataStore store, {
  required String id,
  required DateTime occurrenceDate,
}) async {
  final schedule = ScheduledTransactionRecord(
    id: id,
    type: TransactionType.expense,
    accountId: 'checking',
    categoryId: 'bills-category',
    payee: id,
    amountMinor: 30000,
    nextDate: occurrenceDate,
    frequency: RecurrenceFrequency.monthly,
    reservationContainerType: ReservationContainerType.fund,
    reservationContainerId: 'bills',
    sync: SyncMetadata.fresh(now: DateTime.utc(2026, 9, 4), deviceId: 'test'),
  );
  await store.saveScheduledTransaction(schedule);
  return store.scheduledTransactions.singleWhere((item) => item.id == id);
}
