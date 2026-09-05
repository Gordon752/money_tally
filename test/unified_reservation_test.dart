import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  final today = DateTime(2026, 8, 22);
  final sync = SyncMetadata.fresh(now: today, deviceId: 'device-a');

  test('cleared, pending, future, reserved, and available are independent', () {
    final dataSet = _baseDataSet(sync: sync).copyWith(
      transactions: [
        _expense(
          id: 'cleared-expense',
          amountMinor: 50000,
          date: today,
          status: TransactionStatus.cleared,
          sync: sync,
        ),
        _expense(
          id: 'pending-expense',
          amountMinor: 25000,
          date: today,
          status: TransactionStatus.pending,
          sync: sync,
        ),
        _expense(
          id: 'future-expense',
          amountMinor: 30000,
          date: today.add(const Duration(days: 7)),
          status: TransactionStatus.cleared,
          sync: sync,
        ),
      ],
      reservationOperations: [
        _operation(
          id: 'allocate-bills',
          kind: ReservationOperationKind.allocate,
          amountMinor: 200000,
          revision: 1,
          sync: sync,
        ),
      ],
    );

    expect(dataSet.clearedBalanceForAccount('checking', asOf: today), 450000);
    expect(dataSet.pendingEffectForAccount('checking', asOf: today), -25000);
    expect(dataSet.futureEffectForAccount('checking', asOf: today), -30000);
    expect(dataSet.reservedForAccount('checking', asOf: today), 200000);
    expect(dataSet.availableToSpendForAccount('checking', asOf: today), 225000);
  });

  test('Pending to Cleared does not change available to spend', () {
    final allocation = _operation(
      id: 'allocate-bills',
      kind: ReservationOperationKind.allocate,
      amountMinor: 200000,
      revision: 1,
      sync: sync,
    );
    final pending =
        _expense(
          id: 'bill-payment',
          amountMinor: 70000,
          date: today,
          status: TransactionStatus.pending,
          sync: sync,
        ).copyWith(
          reservationContainerType: ReservationContainerType.fund,
          reservationContainerId: 'bills',
        );
    final consume = _operation(
      id: 'consume-bills',
      kind: ReservationOperationKind.consume,
      amountMinor: 70000,
      revision: 2,
      transactionId: pending.id,
      sync: sync,
    );
    final before = _baseDataSet(sync: sync).copyWith(
      transactions: [pending],
      reservationOperations: [allocation, consume],
    );
    final after = before.copyWith(
      transactions: [pending.copyWith(status: TransactionStatus.cleared)],
    );

    expect(before.clearedBalanceForAccount('checking', asOf: today), 500000);
    expect(before.pendingEffectForAccount('checking', asOf: today), -70000);
    expect(before.reservedForAccount('checking', asOf: today), 130000);
    expect(before.availableToSpendForAccount('checking', asOf: today), 300000);

    expect(after.clearedBalanceForAccount('checking', asOf: today), 430000);
    expect(after.pendingEffectForAccount('checking', asOf: today), 0);
    expect(after.reservedForAccount('checking', asOf: today), 130000);
    expect(after.availableToSpendForAccount('checking', asOf: today), 300000);
  });

  test(
    'Goal and Fund reservations share accounting without changing balance',
    () {
      final dataSet = _baseDataSet(sync: sync).copyWith(
        reservationOperations: [
          _operation(
            id: 'fund-allocation',
            kind: ReservationOperationKind.allocate,
            amountMinor: 120000,
            revision: 1,
            sync: sync,
          ),
          _operation(
            id: 'goal-allocation',
            containerType: ReservationContainerType.goal,
            containerId: 'vacation',
            kind: ReservationOperationKind.allocate,
            amountMinor: 80000,
            revision: 1,
            sync: sync,
          ),
        ],
      );

      expect(dataSet.clearedBalanceForAccount('checking', asOf: today), 500000);
      expect(dataSet.reservedForAccount('checking', asOf: today), 200000);
      expect(
        dataSet.availableToSpendForAccount('checking', asOf: today),
        300000,
      );
    },
  );

  test('concurrent over-consumption converges deterministically', () {
    final allocate = _operation(
      id: 'allocate',
      kind: ReservationOperationKind.allocate,
      amountMinor: 10000,
      revision: 1,
      sync: sync,
    );
    final consumeA = _operation(
      id: 'consume-a',
      operationId: 'device-a:consume',
      kind: ReservationOperationKind.consume,
      amountMinor: 8000,
      revision: 2,
      sync: sync,
    );
    final consumeB = _operation(
      id: 'consume-b',
      operationId: 'device-b:consume',
      kind: ReservationOperationKind.consume,
      amountMinor: 8000,
      revision: 2,
      sync: sync,
    );

    final first = calculateReservationLedger(
      operations: [consumeB, allocate, consumeA],
      asOf: today,
    );
    final second = calculateReservationLedger(
      operations: [consumeA, consumeB, allocate],
      asOf: today,
    );

    expect(first.reservedMinor, 2000);
    expect(second.reservedMinor, first.reservedMinor);
    expect(first.acceptedOperationIds, second.acceptedOperationIds);
    expect(first.conflictedOperationIds, {'consume-b'});
  });

  test('immutable reservation operation sync is an idempotent union', () {
    final remoteAllocate = _operation(
      id: 'remote-allocate',
      operationId: 'device-a:allocate',
      kind: ReservationOperationKind.allocate,
      amountMinor: 10000,
      revision: 1,
      sync: sync,
    );
    final localConsume = _operation(
      id: 'local-consume',
      operationId: 'device-b:consume',
      kind: ReservationOperationKind.consume,
      amountMinor: 3000,
      revision: 2,
      sync: SyncMetadata.fresh(now: today, deviceId: 'device-b'),
    );

    final merged = mergeFinanceDataSetsPreferCurrent(
      incoming: _baseDataSet(
        sync: sync,
      ).copyWith(reservationOperations: [remoteAllocate]),
      current: _baseDataSet(
        sync: sync,
      ).copyWith(reservationOperations: [localConsume]),
    );
    final repeated = mergeFinanceDataSetsPreferCurrent(
      incoming: merged,
      current: merged,
    );

    expect(merged.reservationOperations.map((operation) => operation.id), [
      'remote-allocate',
      'local-consume',
    ]);
    expect(repeated.reservationOperations, hasLength(2));
    expect(
      calculateReservationLedger(
        operations: repeated.reservationOperations,
        asOf: today,
      ).reservedMinor,
      7000,
    );
  });

  test('published immutable operation wins an impossible same-ID conflict', () {
    final published = _operation(
      id: 'shared-id',
      operationId: 'published-operation',
      kind: ReservationOperationKind.allocate,
      amountMinor: 10000,
      revision: 1,
      sync: sync,
    );
    final corruptLocalCopy = _operation(
      id: 'shared-id',
      operationId: 'local-operation',
      kind: ReservationOperationKind.allocate,
      amountMinor: 99999,
      revision: 1,
      sync: SyncMetadata.fresh(now: today, deviceId: 'device-b'),
    );

    final merged = mergeImmutableReservationOperations(
      incoming: [published],
      current: [corruptLocalCopy],
    );

    expect(merged, hasLength(1));
    expect(merged.single.operationId, 'published-operation');
    expect(merged.single.amountMinor, 10000);
  });

  test('concurrent transaction edits consume the winning transaction once', () {
    final winningTransaction =
        _expense(
          id: 'shared-transaction',
          amountMinor: 6000,
          date: today,
          status: TransactionStatus.cleared,
          sync: sync,
        ).copyWith(
          reservationContainerType: ReservationContainerType.fund,
          reservationContainerId: 'bills',
        );
    final operations = [
      _operation(
        id: 'allocate',
        operationId: 'allocate',
        kind: ReservationOperationKind.allocate,
        amountMinor: 10000,
        revision: 1,
        sync: sync,
      ),
      _operation(
        id: 'device-a-edit',
        operationId: 'device-a-edit',
        kind: ReservationOperationKind.consume,
        amountMinor: 7000,
        revision: 2,
        transactionId: winningTransaction.id,
        sync: sync,
      ),
      _operation(
        id: 'device-b-edit',
        operationId: 'device-b-edit',
        kind: ReservationOperationKind.consume,
        amountMinor: 6000,
        revision: 2,
        transactionId: winningTransaction.id,
        sync: sync,
      ),
      _operation(
        id: 'device-b-duplicate',
        operationId: 'device-b-duplicate',
        kind: ReservationOperationKind.consume,
        amountMinor: 6000,
        revision: 2,
        transactionId: winningTransaction.id,
        sync: sync,
      ),
    ];
    final dataSet = _baseDataSet(sync: sync).copyWith(
      transactions: [winningTransaction],
      reservationOperations: operations,
    );

    expect(dataSet.reservedForAccount('checking', asOf: today), 4000);
    expect(
      calculateReservationLedger(
        operations: effectiveReservationOperationsForContainer(
          operations: operations.reversed,
          transactions: [winningTransaction],
          containerType: ReservationContainerType.fund,
          containerId: 'bills',
        ),
        asOf: today,
      ).reservedMinor,
      4000,
    );
  });

  test('schema 6 backup round trip preserves definitions and operations', () {
    final original = _baseDataSet(sync: sync).copyWith(
      reservationOperations: [
        _operation(
          id: 'allocate-bills',
          kind: ReservationOperationKind.allocate,
          amountMinor: 12345,
          revision: 1,
          sync: sync,
        ),
      ],
    );

    final decoded = const BackupCodec().decodeJson(
      const BackupCodec().encodeJson(original, exportedAt: today),
    );

    expect(decoded.toJson()['schemaVersion'], 6);
    expect(decoded.funds.single.id, 'bills');
    expect(decoded.goals.single.reservationModelVersion, 1);
    expect(decoded.reservationOperations.single.amountMinor, 12345);
    expect(decoded.reservedForAccount('checking', asOf: today), 12345);
  });

  test('monthly Fund target rolls forward without resetting its balance', () {
    final fund = FundRecord(
      id: 'month-end',
      name: 'Bills',
      fundingAccountId: 'checking',
      status: FundStatus.active,
      targetBalanceMinor: 200000,
      targetCadence: FundTargetCadence.monthly,
      nextTargetDate: DateTime(2027, 1, 31),
      sync: sync,
    );

    expect(
      effectiveFundTargetDate(fund, asOf: DateTime(2027, 2, 1)),
      DateTime(2027, 2, 28),
    );
    expect(
      effectiveFundTargetDate(fund, asOf: DateTime(2027, 3, 1)),
      DateTime(2027, 3, 31),
    );
    expect(
      effectiveFundTargetDate(fund, asOf: DateTime(2028, 2, 1)),
      DateTime(2028, 2, 29),
    );
  });

  test('real Fund-backed expense consumes reservation exactly once', () async {
    final store = FinanceDataStore(
      dataSet: _baseDataSet(sync: sync).copyWith(
        reservationOperations: [
          _operation(
            id: 'allocate-bills',
            kind: ReservationOperationKind.allocate,
            amountMinor: 200000,
            revision: 1,
            sync: sync,
          ),
        ],
      ),
      deviceId: 'device-a',
    );

    final transaction = await store.addExpense(
      accountId: 'checking',
      categoryId: 'expense',
      date: today,
      payee: 'Discover',
      amountMinor: 70000,
      reservationContainerType: ReservationContainerType.fund,
      reservationContainerId: 'bills',
    );

    expect(store.balanceForAccount('checking'), 430000);
    expect(store.currentFundAmountMinor('bills', asOf: today), 130000);
    expect(store.reservationOperations, hasLength(2));
    expect(store.reservationOperations.last.transactionId, transaction.id);

    await store.setTransactionStatus(transaction.id, TransactionStatus.pending);
    expect(store.currentFundAmountMinor('bills', asOf: today), 130000);
    expect(store.reservationOperations, hasLength(2));
  });

  test('Fund covers its reserved portion of a larger real expense', () async {
    final store = FinanceDataStore(
      dataSet: _baseDataSet(sync: sync).copyWith(
        reservationOperations: [
          _operation(
            id: 'allocate-partial-bills',
            kind: ReservationOperationKind.allocate,
            amountMinor: 200000,
            revision: 1,
            sync: sync,
          ),
        ],
      ),
      deviceId: 'device-a',
    );

    final transaction = await store.addExpense(
      accountId: 'checking',
      categoryId: 'expense',
      date: today,
      payee: 'Apple Store',
      amountMinor: 210000,
      reservationContainerType: ReservationContainerType.fund,
      reservationContainerId: 'bills',
    );
    final consumption = store.reservationOperations.singleWhere(
      (operation) =>
          operation.transactionId == transaction.id &&
          operation.kind == ReservationOperationKind.consume,
    );

    expect(consumption.amountMinor, 200000);
    expect(store.balanceForAccount('checking'), 290000);
    expect(store.currentFundAmountMinor('bills', asOf: today), 0);
    expect(store.availableToSpendForAccount('checking', asOf: today), 290000);
    expect(store.expensesThisMonthMinor(now: today), 210000);

    await store.saveTransaction(
      transaction.copyWith(
        sync: transaction.sync.deleted(deviceId: store.deviceId),
      ),
    );
    expect(store.currentFundAmountMinor('bills', asOf: today), 200000);
    expect(store.balanceForAccount('checking'), 500000);
    expect(store.availableToSpendForAccount('checking', asOf: today), 300000);
  });

  test('editing and deleting Fund-backed expense reverses causally', () async {
    final store = FinanceDataStore(
      dataSet: _baseDataSet(sync: sync).copyWith(
        reservationOperations: [
          _operation(
            id: 'allocate-bills',
            kind: ReservationOperationKind.allocate,
            amountMinor: 200000,
            revision: 1,
            sync: sync,
          ),
        ],
      ),
      deviceId: 'device-a',
    );
    final transaction = await store.addExpense(
      accountId: 'checking',
      categoryId: 'expense',
      date: today,
      payee: 'Bill',
      amountMinor: 70000,
      reservationContainerType: ReservationContainerType.fund,
      reservationContainerId: 'bills',
    );

    await store.saveTransaction(
      transaction.copyWith(
        amountMinor: 50000,
        sync: transaction.sync.touched(deviceId: 'device-a'),
      ),
    );
    expect(store.currentFundAmountMinor('bills', asOf: today), 150000);

    final edited = store.transactions.single;
    await store.saveTransaction(
      edited.copyWith(sync: edited.sync.deleted(deviceId: 'device-a')),
    );
    expect(store.currentFundAmountMinor('bills', asOf: today), 200000);
    expect(store.balanceForAccount('checking'), 500000);
  });

  test(
    'Scheduled Paid consumes and Undo Payment restores reservation',
    () async {
      final schedule = ScheduledTransactionRecord(
        id: 'schedule-bill',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'expense',
        payee: 'Discover',
        amountMinor: 70000,
        nextDate: today,
        frequency: RecurrenceFrequency.monthly,
        reservationContainerType: ReservationContainerType.fund,
        reservationContainerId: 'bills',
        sync: sync,
      );
      final store = FinanceDataStore(
        dataSet: _baseDataSet(sync: sync).copyWith(
          scheduledTransactions: [schedule],
          reservationOperations: [
            _operation(
              id: 'allocate-bills',
              kind: ReservationOperationKind.allocate,
              amountMinor: 200000,
              revision: 1,
              sync: sync,
            ),
          ],
        ),
        deviceId: 'device-a',
      );
      final transaction = await store.addExpense(
        accountId: 'checking',
        categoryId: 'expense',
        date: today,
        payee: 'Discover',
        amountMinor: 70000,
        scheduledTransactionId: schedule.id,
        scheduledOccurrenceDate: today,
        scheduledPlannedAmountMinor: 70000,
        reservationContainerType: ReservationContainerType.fund,
        reservationContainerId: 'bills',
      );
      await store.saveScheduledOccurrence(
        scheduledTransaction: schedule.copyWith(
          nextDate: DateTime(2026, 9, 22),
        ),
        occurrence: ScheduledOccurrenceRecord(
          scheduledDate: today,
          plannedAmountMinor: 70000,
          status: ScheduledOccurrenceStatus.paid,
          actualAmountMinor: 70000,
          actualPaymentDate: today,
          transactionId: transaction.id,
        ),
      );

      expect(store.currentFundAmountMinor('bills', asOf: today), 130000);
      await store.undoScheduledPayment(transaction.id, now: today);
      expect(store.currentFundAmountMinor('bills', asOf: today), 200000);
      expect(store.balanceForAccount('checking'), 500000);
      expect(
        store.scheduledTransactions.single.occurrenceStates['20260822']?.status,
        ScheduledOccurrenceStatus.pending,
      );
    },
  );

  test(
    'Scheduled Goal funding allocates reservation without hidden transfer',
    () async {
      final allocation = ScheduledGoalFundingAllocation(
        id: 'allocation-vacation',
        goalId: 'vacation',
        amountMinor: 80000,
        order: 0,
      );
      final schedule = ScheduledTransactionRecord(
        id: 'schedule-goal',
        type: TransactionType.goalFunding,
        accountId: 'checking',
        payee: 'Vacation funding',
        amountMinor: 80000,
        nextDate: today,
        frequency: RecurrenceFrequency.monthly,
        goalFundingAllocations: [allocation],
        sync: sync,
      );
      final store = FinanceDataStore(
        dataSet: _baseDataSet(
          sync: sync,
        ).copyWith(scheduledTransactions: [schedule]),
        deviceId: 'device-a',
      );

      final event = await store.completeScheduledGoalFunding(
        scheduledTransactionId: schedule.id,
        occurrenceDate: today,
        fundingDate: today,
      );
      expect(store.currentGoalAmountMinor('vacation'), 80000);
      expect(store.balanceForAccount('checking'), 500000);
      expect(store.transactions, isEmpty);

      await store.undoGoalFunding(event.id);
      expect(store.currentGoalAmountMinor('vacation'), 0);
      expect(store.balanceForAccount('checking'), 500000);
    },
  );
}

FinanceDataSet _baseDataSet({required SyncMetadata sync}) {
  return FinanceDataSet(
    accounts: [
      AccountRecord(
        id: 'checking',
        name: 'CTBI',
        type: AccountType.checking,
        openingBalanceMinor: 500000,
        sync: sync,
      ),
    ],
    categories: [
      CategoryRecord(
        id: 'expense',
        name: 'Expense',
        kind: CategoryKind.expense,
        sync: sync,
      ),
    ],
    transactions: const [],
    scheduledTransactions: const [],
    budgets: const [],
    goals: [
      GoalRecord(
        id: 'vacation',
        name: 'Vacation',
        targetAmountMinor: 300000,
        status: GoalStatus.active,
        fundingMethod: GoalFundingMethod.accountFunded,
        defaultFundingAccountId: 'checking',
        reservationModelVersion: 1,
        sync: sync,
      ),
    ],
    funds: [
      FundRecord(
        id: 'bills',
        name: 'Bills',
        fundingAccountId: 'checking',
        status: FundStatus.active,
        targetBalanceMinor: 200000,
        targetCadence: FundTargetCadence.monthly,
        sync: sync,
      ),
    ],
    preferences: const UserPreferences(),
  );
}

TransactionRecord _expense({
  required String id,
  required int amountMinor,
  required DateTime date,
  required TransactionStatus status,
  required SyncMetadata sync,
}) {
  return TransactionRecord(
    id: id,
    type: TransactionType.expense,
    accountId: 'checking',
    categoryId: 'expense',
    date: date,
    payee: 'Expense',
    amountMinor: amountMinor,
    status: status,
    sync: sync,
  );
}

ReservationOperationRecord _operation({
  required String id,
  required ReservationOperationKind kind,
  required int amountMinor,
  required int revision,
  required SyncMetadata sync,
  ReservationContainerType containerType = ReservationContainerType.fund,
  String containerId = 'bills',
  String? operationId,
  String? transactionId,
}) {
  return ReservationOperationRecord(
    id: id,
    containerType: containerType,
    containerId: containerId,
    fundingAccountId: 'checking',
    kind: kind,
    amountMinor: amountMinor,
    effectiveDate: DateTime(2026, 8, 22),
    revision: revision,
    baseRevision: revision - 1,
    operationId: operationId ?? 'device-a:$id',
    deviceId: 'device-a',
    transactionId: transactionId,
    sync: sync,
  );
}
