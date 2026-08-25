import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/account.dart' as v2_account;
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart'
    as v2_scheduled;
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/transaction.dart' as v2_transaction;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

void main() {
  testWidgets('Fund allocation amount receives focus immediately', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Monthly Bills',
      fundingAccountId: 'checking',
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showFundAmountDialog(context, fundId: fund.id, isReturn: false),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('fund-operation-amount')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Goal funding amount receives focus immediately', (tester) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Emergency',
      targetAmountMinor: 100000,
      startingAmountMinor: 0,
      targetDate: null,
      defaultFundingAccountId: 'checking',
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showFundGoalsSheet(context, initialGoalId: goal.id),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('fund-goals-total')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.text('Available to Spend \$5,000.00'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('fund-goals-total')),
      '5000',
    );
    await tester.pump();
    expect(
      find.text('After allocation · \$4,950.00 available'),
      findsOneWidget,
    );
  });

  testWidgets('Spend from Fund previews reserved and unreserved portions', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 200000,
      date: DateTime.now(),
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showTransactionDialog(
              context,
              initialIsExpense: true,
              initialAccountId: 'checking',
              initialReservationContainerType: ReservationContainerType.fund,
              initialReservationContainerId: fund.id,
            ),
            child: const Text('Spend'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Spend'));
    await tester.pumpAndSettle();

    expect(find.text('Spend from Bills'), findsOneWidget);
    expect(find.text('Paid from'), findsOneWidget);
    expect(find.text('CTBI'), findsOneWidget);
    expect(find.text('Reserved money is held in this account'), findsOneWidget);
    expect(find.text('Using reserved money'), findsOneWidget);
    expect(find.text('Mark as Pending'), findsOneWidget);
    expect(find.text('Schedule future occurrences'), findsOneWidget);
    final reservationTop = tester
        .getTopLeft(find.text('Using reserved money'))
        .dy;
    final pendingTop = tester.getTopLeft(find.text('Mark as Pending')).dy;
    final scheduleTop = tester
        .getTopLeft(find.text('Schedule future occurrences'))
        .dy;
    expect(reservationTop, lessThan(pendingTop));
    expect(pendingTop, lessThan(scheduleTop));

    final accountRow = find.byKey(const ValueKey('transaction-account-row'));
    expect(
      find.descendant(of: accountRow, matching: find.byType(InkWell)),
      findsNothing,
    );
    await tester.tap(accountRow);
    await tester.pumpAndSettle();
    expect(find.text('Choose account'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '210000',
    );
    await tester.pump();

    _expectReservationPreview(
      payment: r'$2,100.00',
      coveredLabel: 'Covered by Bills Fund',
      covered: r'$2,000.00',
      unreserved: r'$100.00',
    );
  });

  testWidgets('Spend from Goal previews reserved and unreserved portions', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'MacBook',
      targetAmountMinor: 200000,
      startingAmountMinor: 0,
      targetDate: null,
      defaultFundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.goal,
      containerId: goal.id,
      amountMinor: 200000,
      date: DateTime.now(),
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showTransactionDialog(
              context,
              initialIsExpense: true,
              initialAccountId: 'checking',
              initialReservationContainerType: ReservationContainerType.goal,
              initialReservationContainerId: goal.id,
            ),
            child: const Text('Spend'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Spend'));
    await tester.pumpAndSettle();
    expect(find.text('Spend from MacBook'), findsOneWidget);
    expect(find.text('Paid from'), findsOneWidget);
    expect(find.text('Using reserved money'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '210000',
    );
    await tester.pump();

    _expectReservationPreview(
      payment: r'$2,100.00',
      coveredLabel: 'Covered by MacBook Goal',
      covered: r'$2,000.00',
      unreserved: r'$100.00',
    );
  });

  testWidgets('Allocate shows funding account and live available remainder', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 100000,
      date: DateTime.now(),
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showFundAmountDialog(context, fundId: fund.id, isReturn: false),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('From CTBI'), findsOneWidget);
    expect(find.text('Available to Spend \$4,000.00'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('fund-operation-amount')),
      '50000',
    );
    await tester.pump();
    expect(
      find.text('After allocation · \$3,500.00 available'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('fund-operation-amount')),
      '450000',
    );
    await tester.pump();
    expect(find.text('After allocation · -\$500.00 available'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reservation-overcommit-warning')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Allocate'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'exact-available Fund allocation stays valid while persistence is pending',
    (tester) async {
      await _setPhoneSize(tester);
      final repository = _BlockingLocalFinanceRepository();
      final store = _store(localRepository: repository);
      final fund = await store.createFund(
        name: 'Bills',
        fundingAccountId: 'checking',
      );
      await tester.pumpWidget(
        _app(
          store,
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => showFundAmountDialog(
                context,
                fundId: fund.id,
                isReturn: false,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fund-operation-amount')),
        '500000',
      );
      await tester.pump();
      expect(find.text('After allocation · \$0.00 available'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reservation-overcommit-warning')),
        findsNothing,
      );

      repository.blockNextSave();
      await tester.tap(find.widgetWithText(FilledButton, 'Allocate'));
      await tester.pump();

      expect(find.text('Allocate to Bills'), findsOneWidget);
      expect(find.text('After allocation · \$0.00 available'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reservation-overcommit-warning')),
        findsNothing,
      );

      repository.releaseSave();
      await tester.pumpAndSettle();
      expect(find.text('Allocate to Bills'), findsNothing);
      expect(store.currentFundAmountMinor(fund.id), 500000);
    },
  );

  testWidgets('Fund return shows and updates authoritative reservation', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 300000,
      date: DateTime.now(),
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showFundAmountDialog(context, fundId: fund.id, isReturn: true),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Bills Fund'), findsOneWidget);
    expect(find.text('Reserved \$3,000.00'), findsOneWidget);
    expect(find.text('Returns to CTBI'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('fund-operation-amount')),
      '50000',
    );
    await tester.pump();
    expect(find.text('After return · \$2,500.00 reserved'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('fund-operation-amount')),
      '350000',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('reservation-return-exceeds')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Return'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Return All does not flash a negative reservation while saving', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final repository = _BlockingLocalFinanceRepository();
    final store = _store(localRepository: repository);
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 300000,
      date: DateTime.now(),
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showFundAmountDialog(context, fundId: fund.id, isReturn: true),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('fund-operation-amount')),
      '300000',
    );
    await tester.pump();
    expect(find.text('After return · \$0.00 reserved'), findsOneWidget);

    repository.blockNextSave();
    await tester.tap(find.widgetWithText(FilledButton, 'Return'));
    await tester.pump();

    expect(find.text('Return Funds'), findsOneWidget);
    expect(find.text('After return · \$0.00 reserved'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reservation-return-exceeds')),
      findsNothing,
    );

    repository.releaseSave();
    await tester.pumpAndSettle();
    expect(find.text('Return Funds'), findsNothing);
    expect(store.currentFundAmountMinor(fund.id), 0);
  });

  testWidgets('Funds floating add menu offers creation and allocation', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showFloatingAddMenu(
              context,
              section: FinanceSection.plan,
              planSegment: PlanSegment.funds,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Create Fund'), findsOneWidget);
    expect(find.text('Allocate to Funds'), findsOneWidget);
    expect(find.text('Fund Goals'), findsNothing);
  });

  testWidgets('Allocate to Funds saves one exact total as a two-Fund batch', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final bills = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    final repairs = await store.createFund(
      name: 'Repairs',
      fundingAccountId: 'checking',
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showAllocateFundsSheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Allocate to Funds'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('allocate-funds-total')),
      '100000',
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('allocate-funds-fund-allocate-funds-draft-0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bills'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('allocate-funds-add-allocation')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('allocate-funds-fund-allocate-funds-draft-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repairs'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(
        const ValueKey('allocate-funds-amount-allocate-funds-draft-1'),
      ),
      '40000',
    );
    await tester.pump();

    final summary = find.byKey(const ValueKey('allocate-funds-summary'));
    expect(
      find.descendant(of: summary, matching: find.text('Total\n\$1,000.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Remaining\nBalanced')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('allocate-funds-save')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('allocate-funds-save')));
    await tester.pumpAndSettle();

    expect(find.text('Allocate to Funds'), findsNothing);
    expect(store.currentFundAmountMinor(bills.id), 60000);
    expect(store.currentFundAmountMinor(repairs.id), 40000);
    expect(store.reservedForAccount('checking'), 100000);
    expect(store.availableToSpendForAccount('checking'), 400000);
    final operations = store.reservationOperations
        .where(
          (operation) =>
              operation.containerType == ReservationContainerType.fund &&
              {bills.id, repairs.id}.contains(operation.containerId),
        )
        .toList(growable: false);
    expect(operations, hasLength(2));
    expect(
      operations
          .map(
            (operation) => operation.causationId!.split(':').take(2).join(':'),
          )
          .toSet(),
      hasLength(1),
    );
  });

  testWidgets('Goal return uses the shared reservation context', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Emergency',
      targetAmountMinor: 20000,
      startingAmountMinor: 15000,
      targetDate: null,
      defaultFundingAccountId: 'checking',
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showReservationAmountDialog(
              context,
              containerType: ReservationContainerType.goal,
              containerId: goal.id,
              containerName: goal.name,
              isReturn: true,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Return Goal Reservation'), findsOneWidget);
    expect(find.text('Emergency Goal'), findsOneWidget);
    expect(find.text('Reserved \$150.00'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('fund-operation-amount')),
      '5000',
    );
    await tester.pump();
    expect(find.text('After return · \$100.00 reserved'), findsOneWidget);
  });

  testWidgets('Mark as Paid can consume a Fund from the payment account', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Monthly Bills',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 50000,
      date: DateTime.now(),
    );
    final schedule = v2_scheduled.ScheduledTransactionRecord(
      id: 'discover-payment',
      type: v2_transaction.TransactionType.transfer,
      accountId: 'checking',
      transferAccountId: 'discover',
      payee: 'Discover',
      amountMinor: 3500,
      nextDate: DateTime.now(),
      frequency: v2_scheduled.RecurrenceFrequency.monthly,
      sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
    );
    await store.saveScheduledTransaction(schedule);
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => markScheduledTransactionPaid(context, schedule),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mark-paid-reservation')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('mark-paid-reservation')),
    );
    await tester.tap(find.byKey(const ValueKey('mark-paid-reservation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly Bills').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    final transaction = store.transactions.singleWhere(
      (item) => item.scheduledTransactionId == schedule.id,
    );
    expect(transaction.accountId, 'checking');
    expect(transaction.transferAccountId, 'discover');
    expect(transaction.reservationContainerType, ReservationContainerType.fund);
    expect(transaction.reservationContainerId, fund.id);
    expect(store.currentFundAmountMinor(fund.id), 46500);
  });

  testWidgets(
    'Mark as Paid completes locally when the occurrence cloud write fails',
    (tester) async {
      await _setPhoneSize(tester);
      final remote = _FailingOccurrenceRepository();
      final store = _store(remoteRepository: remote);
      final fund = await store.createFund(
        name: 'Bills',
        fundingAccountId: 'checking',
      );
      await store.allocateReservation(
        containerType: ReservationContainerType.fund,
        containerId: fund.id,
        amountMinor: 50000,
        date: DateTime(2026, 8, 22),
      );
      final schedule = v2_scheduled.ScheduledTransactionRecord(
        id: 'quota-failed-payment',
        type: v2_transaction.TransactionType.transfer,
        accountId: 'checking',
        transferAccountId: 'discover',
        payee: 'Discover',
        amountMinor: 3500,
        nextDate: DateTime(2026, 8, 22),
        frequency: v2_scheduled.RecurrenceFrequency.monthly,
        reservationContainerType: ReservationContainerType.fund,
        reservationContainerId: fund.id,
        sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
      );
      await store.saveScheduledTransaction(schedule);
      await tester.pumpWidget(
        _app(
          store,
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => markScheduledTransactionPaid(context, schedule),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Mark as Paid'), findsNothing);
      expect(remote.occurrenceSaveAttempts, 1);
      expect(
        store.transactions
            .where(
              (transaction) =>
                  transaction.scheduledTransactionId == schedule.id,
            )
            .length,
        1,
      );
      final updated = store.scheduledTransactions.singleWhere(
        (item) => item.id == schedule.id,
      );
      expect(updated.nextDate, DateTime(2026, 9, 22));
      expect(
        updated.occurrenceStates['20260822']?.status,
        v2_scheduled.ScheduledOccurrenceStatus.paid,
      );
      expect(store.currentFundAmountMinor(fund.id), 46500);
    },
  );

  testWidgets(
    'retry completes a partially saved scheduled payment without duplication',
    (tester) async {
      await _setPhoneSize(tester);
      final remote = _FailingOccurrenceRepository();
      final store = _store(remoteRepository: remote);
      final fund = await store.createFund(
        name: 'Bills',
        fundingAccountId: 'checking',
      );
      await store.allocateReservation(
        containerType: ReservationContainerType.fund,
        containerId: fund.id,
        amountMinor: 50000,
        date: DateTime(2026, 8, 22),
      );
      final schedule = v2_scheduled.ScheduledTransactionRecord(
        id: 'partially-saved-payment',
        type: v2_transaction.TransactionType.transfer,
        accountId: 'checking',
        transferAccountId: 'discover',
        payee: 'Discover',
        amountMinor: 3500,
        nextDate: DateTime(2026, 8, 22),
        frequency: v2_scheduled.RecurrenceFrequency.monthly,
        reservationContainerType: ReservationContainerType.fund,
        reservationContainerId: fund.id,
        sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
      );
      await store.saveScheduledTransaction(schedule);
      await store.addTransfer(
        fromAccountId: 'checking',
        toAccountId: 'discover',
        date: DateTime(2026, 8, 22),
        payee: 'Discover',
        amountMinor: 3500,
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: schedule.nextDate,
        scheduledPlannedAmountMinor: schedule.amountMinor,
        reservationContainerType: ReservationContainerType.fund,
        reservationContainerId: fund.id,
      );
      expect(store.currentFundAmountMinor(fund.id), 46500);

      await tester.pumpWidget(
        _app(
          store,
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => markScheduledTransactionPaid(context, schedule),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Mark as Paid'), findsNothing);
      expect(
        store.transactions
            .where(
              (transaction) =>
                  transaction.scheduledTransactionId == schedule.id,
            )
            .length,
        1,
      );
      expect(store.currentFundAmountMinor(fund.id), 46500);
      expect(
        store.scheduledTransactions
            .singleWhere((item) => item.id == schedule.id)
            .occurrenceStates['20260822']
            ?.status,
        v2_scheduled.ScheduledOccurrenceStatus.paid,
      );
    },
  );

  testWidgets('scheduled transfer editor offers Fund reservation linkage', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Monthly Bills',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 50000,
      date: DateTime.now(),
    );
    final schedule = v2_scheduled.ScheduledTransactionRecord(
      id: 'discover-payment-edit',
      type: v2_transaction.TransactionType.transfer,
      accountId: 'checking',
      transferAccountId: 'discover',
      payee: 'Discover',
      amountMinor: 3500,
      nextDate: DateTime.now(),
      frequency: v2_scheduled.RecurrenceFrequency.monthly,
      sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
    );
    await tester.pumpWidget(
      _app(
        store,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () =>
                showScheduledTransactionDialog(context, existing: schedule),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scheduled-reservation')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('scheduled-reservation')),
    );
    await tester.tap(find.byKey(const ValueKey('scheduled-reservation')));
    await tester.pumpAndSettle();
    expect(find.text('Monthly Bills'), findsOneWidget);
  });

  testWidgets(
    'linked empty Fund remains visible and can be removed from a schedule',
    (tester) async {
      await _setPhoneSize(tester);
      final store = _store();
      final fund = await store.createFund(
        name: 'Bills',
        fundingAccountId: 'checking',
      );
      await store.allocateReservation(
        containerType: ReservationContainerType.fund,
        containerId: fund.id,
        amountMinor: 50000,
        date: DateTime.now(),
      );
      await store.returnReservation(
        containerType: ReservationContainerType.fund,
        containerId: fund.id,
        amountMinor: 50000,
        date: DateTime.now(),
      );
      final schedule = v2_scheduled.ScheduledTransactionRecord(
        id: 'linked-empty-fund',
        type: v2_transaction.TransactionType.transfer,
        accountId: 'checking',
        transferAccountId: 'discover',
        payee: 'Discover',
        amountMinor: 3500,
        nextDate: DateTime.now(),
        frequency: v2_scheduled.RecurrenceFrequency.monthly,
        reservationContainerType: ReservationContainerType.fund,
        reservationContainerId: fund.id,
        sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
      );
      await store.saveScheduledTransaction(schedule);
      await tester.pumpWidget(
        _app(
          store,
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => showScheduledTransactionDialog(
                context,
                existing: store.scheduledTransactions.single,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final reservationRow = find.byKey(
        const ValueKey('scheduled-reservation'),
      );
      expect(reservationRow, findsOneWidget);
      await tester.ensureVisible(reservationRow);
      expect(find.text('Bills'), findsOneWidget);
      await tester.tap(reservationRow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = store.scheduledTransactions.single;
      expect(saved.reservationContainerType, isNull);
      expect(saved.reservationContainerId, isNull);
      expect(store.fundDeleteEligibility(fund.id).canDelete, isTrue);
    },
  );

  testWidgets('empty Fund can be permanently deleted without archiving first', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Temporary Fund',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 10000,
      date: DateTime.now(),
    );
    await store.returnReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 10000,
      date: DateTime.now(),
    );
    await tester.pumpWidget(_app(store, FundPlanCard(fund: fund)));

    await tester.tap(find.byKey(ValueKey('fund-card-${fund.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this Fund permanently?'), findsOneWidget);
    await tester.tap(find.text('Delete Permanently'));
    await tester.pumpAndSettle();

    expect(store.fundById(fund.id).isDeleted, isTrue);
  });

  testWidgets('long pressing a Fund opens its actions', (tester) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    await tester.pumpWidget(_app(store, FundPlanCard(fund: fund)));

    await tester.longPress(find.byKey(ValueKey('fund-card-${fund.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Allocate'), findsOneWidget);
    expect(find.text('Return Reserved Money'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets(
    'Fund actions schedule funding with its fixed account and Fund selected',
    (tester) async {
      await _setPhoneSize(tester);
      final store = _store();
      final fund = await store.createFund(
        name: 'Bills',
        fundingAccountId: 'checking',
      );
      await tester.pumpWidget(_app(store, FundPlanCard(fund: fund)));

      await tester.tap(find.byKey(ValueKey('fund-card-${fund.id}')));
      await tester.pumpAndSettle();

      expect(find.text('View Activity'), findsOneWidget);
      expect(find.text('Allocate'), findsOneWidget);
      expect(find.text('Return Reserved Money'), findsOneWidget);
      expect(find.text('Schedule Funding'), findsOneWidget);

      await tester.tap(find.text('Schedule Funding'));
      await tester.pumpAndSettle();

      expect(find.text('Schedule Funding'), findsOneWidget);
      final accountRow = find.byKey(
        const ValueKey('scheduled-fund-funding-account'),
      );
      final fundRow = find.byKey(const ValueKey('scheduled-fund-funding-fund'));
      expect(
        find.descendant(of: accountRow, matching: find.text('CTBI')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: fundRow, matching: find.text('Bills')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('scheduled-fund-funding-amount')),
        '20000',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('scheduled-fund-funding-save')),
      );
      await tester.pumpAndSettle();

      expect(store.scheduledTransactions, hasLength(1));
      final schedule = store.scheduledTransactions.single;
      expect(schedule.type, v2_transaction.TransactionType.goalFunding);
      expect(schedule.accountId, 'checking');
      expect(
        schedule.reservationFundingContainerType,
        ReservationContainerType.fund,
      );
      expect(schedule.reservationFundingContainerId, fund.id);
      expect(schedule.goalFundingAllocations, isEmpty);
    },
  );

  testWidgets(
    'Fund with scheduled funding explains why it cannot be archived',
    (tester) async {
      await _setPhoneSize(tester);
      final store = _store();
      final fund = await store.createFund(
        name: 'Bills',
        fundingAccountId: 'checking',
      );
      await store.saveScheduledTransaction(
        v2_scheduled.ScheduledTransactionRecord(
          id: 'scheduled-bills-funding',
          type: v2_transaction.TransactionType.goalFunding,
          accountId: 'checking',
          payee: 'Bills',
          amountMinor: 20000,
          nextDate: DateTime(2026, 9, 1),
          frequency: v2_scheduled.RecurrenceFrequency.monthly,
          reservationFundingContainerType: ReservationContainerType.fund,
          reservationFundingContainerId: fund.id,
          sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
        ),
      );

      await expectLater(
        store.archiveFund(fund.id),
        throwsA(
          isA<FinanceDataValidationException>().having(
            (error) => error.message,
            'message',
            contains('Remove this Fund from scheduled funding'),
          ),
        ),
      );

      await tester.pumpWidget(_app(store, FundPlanCard(fund: fund)));
      await tester.tap(find.byKey(ValueKey('fund-card-${fund.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect(find.text('Fund can\u2019t be archived yet'), findsOneWidget);
      expect(
        find.textContaining('Bills still schedules funding for this Fund'),
        findsOneWidget,
      );
      expect(store.fundById(fund.id).status, FundStatus.active);
    },
  );

  testWidgets('Goal actions use the same reservation wording as Funds', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final goal = await store.createGoal(
      name: 'Emergency',
      targetAmountMinor: 100000,
      startingAmountMinor: 0,
      targetDate: DateTime(2026, 9, 30),
      defaultFundingAccountId: 'checking',
    );
    await tester.pumpWidget(_app(store, GoalCard(goal: goal)));

    await tester.tap(find.byKey(ValueKey('goal-card-${goal.id}')));
    await tester.pumpAndSettle();

    expect(find.text('View Activity'), findsOneWidget);
    expect(find.text('Allocate'), findsOneWidget);
    expect(find.text('Return Reserved Money'), findsOneWidget);
    expect(find.text('Schedule Funding'), findsOneWidget);
  });

  testWidgets('Fund card opens actions then its read-only Activity', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    await store.allocateReservation(
      containerType: ReservationContainerType.fund,
      containerId: fund.id,
      amountMinor: 20000,
      date: DateTime(2026, 8, 23),
    );
    final operation = store.reservationOperations.single;
    await tester.pumpWidget(_app(store, FundPlanCard(fund: fund)));

    await tester.tap(find.byKey(ValueKey('fund-card-${fund.id}')));
    await tester.pumpAndSettle();
    expect(find.text('View Activity'), findsOneWidget);
    expect(find.text('Fund Details'), findsNothing);

    await tester.tap(find.text('View Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Fund Details'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.textContaining('Allocated'), findsOneWidget);
    expect(
      find.byKey(ValueKey('fund-reservation-activity-${operation.id}')),
      findsOneWidget,
    );
  });

  testWidgets('Fund deletion identifies its remaining scheduled linkage', (
    tester,
  ) async {
    await _setPhoneSize(tester);
    final store = _store();
    final fund = await store.createFund(
      name: 'Bills',
      fundingAccountId: 'checking',
    );
    await store.saveScheduledTransaction(
      v2_scheduled.ScheduledTransactionRecord(
        id: 'linked-discover-payment',
        type: v2_transaction.TransactionType.transfer,
        accountId: 'checking',
        transferAccountId: 'discover',
        payee: 'Discover payment',
        amountMinor: 3500,
        nextDate: DateTime(2026, 9, 22),
        frequency: v2_scheduled.RecurrenceFrequency.monthly,
        reservationContainerType: ReservationContainerType.fund,
        reservationContainerId: fund.id,
        sync: v2_sync.SyncMetadata.fresh(deviceId: 'test'),
      ),
    );
    await tester.pumpWidget(_app(store, FundPlanCard(fund: fund)));

    await tester.tap(find.byKey(ValueKey('fund-card-${fund.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Fund can’t be deleted yet'), findsOneWidget);
    expect(
      find.textContaining('Discover payment still uses this Fund'),
      findsOneWidget,
    );
    expect(find.textContaining('Use reserved money to None'), findsOneWidget);
  });
}

void _expectReservationPreview({
  required String payment,
  required String coveredLabel,
  required String covered,
  required String unreserved,
}) {
  final paymentRow = find.byKey(const ValueKey('reservation-payment-amount'));
  final coveredRow = find.byKey(const ValueKey('reservation-covered-amount'));
  final unreservedRow = find.byKey(
    const ValueKey('reservation-unreserved-amount'),
  );
  expect(paymentRow, findsOneWidget);
  expect(
    find.descendant(of: paymentRow, matching: find.text(payment)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: coveredRow, matching: find.text(coveredLabel)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: coveredRow, matching: find.text(covered)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: unreservedRow, matching: find.text(unreserved)),
    findsOneWidget,
  );
}

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(FinanceDataStore store, Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: FinanceDataStoreScope(
      store: store,
      child: Scaffold(body: SafeArea(child: child)),
    ),
  );
}

FinanceDataStore _store({
  FinanceRecordRepository? remoteRepository,
  LocalFinanceDataSetRepository? localRepository,
}) {
  final sync = v2_sync.SyncMetadata.fresh(
    now: DateTime.utc(2026, 8, 22),
    deviceId: 'test',
  );
  return FinanceDataStore(
    dataSet: FinanceDataSet(
      accounts: [
        v2_account.AccountRecord(
          id: 'checking',
          name: 'CTBI',
          type: v2_account.AccountType.checking,
          openingBalanceMinor: 500000,
          sync: sync,
        ),
        v2_account.AccountRecord(
          id: 'discover',
          name: 'Discover',
          type: v2_account.AccountType.creditCard,
          openingBalanceMinor: -114486,
          sync: sync,
        ),
      ],
      categories: const [],
      transactions: const [],
      scheduledTransactions: const [],
      budgets: const [],
      goals: const <GoalRecord>[],
      funds: const <FundRecord>[],
      preferences: const UserPreferences(),
    ),
    deviceId: 'test',
    localRepository: localRepository,
    remoteRepository: remoteRepository,
    userId: remoteRepository == null ? null : 'test-user',
  );
}

class _BlockingLocalFinanceRepository extends LocalFinanceDataSetRepository {
  Completer<void>? _pendingSave;

  void blockNextSave() {
    expect(_pendingSave, isNull);
    _pendingSave = Completer<void>();
  }

  void releaseSave() {
    final pending = _pendingSave;
    expect(pending, isNotNull);
    _pendingSave = null;
    pending!.complete();
  }

  @override
  Future<void> save(FinanceDataSet dataSet) async {
    final pending = _pendingSave;
    if (pending != null) await pending.future;
  }
}

class _FailingOccurrenceRepository
    implements FinanceRecordRepository, ScheduledOccurrenceStateRepository {
  int occurrenceSaveAttempts = 0;

  @override
  Future<v2_scheduled.ScheduledOccurrenceState> saveScheduledOccurrenceState({
    required String userId,
    required String scheduledTransactionId,
    required String dayKey,
    required v2_scheduled.ScheduledOccurrenceState occurrenceState,
  }) async {
    occurrenceSaveAttempts += 1;
    throw Exception('resource-exhausted');
  }

  @override
  Future<String?> activeRestoreGeneration(String userId) async => null;

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async =>
      const FinanceDataSet(
        accounts: [],
        categories: [],
        transactions: [],
        scheduledTransactions: [],
        budgets: [],
        preferences: UserPreferences(),
      );

  @override
  Stream<FinanceDataSet> watchDataSet(String userId) => const Stream.empty();

  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async => 'unused';

  @override
  Future<void> saveAccount({
    required String userId,
    required v2_account.AccountRecord account,
  }) async {}

  @override
  Future<void> saveBudget({
    required String userId,
    required BudgetRecord budget,
  }) async {}

  @override
  Future<void> saveCategory({
    required String userId,
    required CategoryRecord category,
  }) async {}

  @override
  Future<void> saveGoal({
    required String userId,
    required GoalRecord goal,
  }) async {}

  @override
  Future<void> saveGoalContribution({
    required String userId,
    required GoalContributionRecord contribution,
  }) async {}

  @override
  Future<void> saveGoalFundingEvent({
    required String userId,
    required GoalFundingEventRecord fundingEvent,
  }) async {}

  @override
  Future<void> savePreferences({
    required String userId,
    required UserPreferences preferences,
  }) async {}

  @override
  Future<void> saveScheduledTransaction({
    required String userId,
    required v2_scheduled.ScheduledTransactionRecord scheduledTransaction,
  }) async {}

  @override
  Future<void> saveTransaction({
    required String userId,
    required v2_transaction.TransactionRecord transaction,
  }) async {}
}
