import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/finance_record_repository.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  final occurrenceDate = DateTime(2026, 8, 24);

  test(
    'production store installs an atomic Paid transition exactly once',
    () async {
      final repository = _AtomicTransitionRepository();
      final store = _store(occurrenceDate, repository);

      final allocation = await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );

      expect(repository.transitionCalls, 1);
      expect(repository.operations.keys, [allocation.id]);
      expect(store.reservationOperations.map((item) => item.id), [
        allocation.id,
      ]);
      expect(store.currentFundAmountMinor('bills'), 20000);
      expect(store.availableToSpendForAccount('checking'), 480000);
      expect(store.transactions, isEmpty);
      expect(
        store
            .scheduledTransactions
            .single
            .occurrenceStates[occurrenceDayKey(occurrenceDate)]
            ?.reservationOperationId,
        allocation.id,
      );
    },
  );

  test(
    'remote competing Paid winner converges to its one linked allocation',
    () async {
      final repository = _AtomicTransitionRepository(
        resolver:
            ({
              required repository,
              required occurrenceState,
              required reservationOperation,
            }) {
              final winningState = _remotePaidWinner(
                occurrenceState,
                reservationOperation!,
              );
              final winningOperation = _remoteAllocation(
                reservationOperation,
                winningState,
              );
              repository.install(winningState, winningOperation);
              return ScheduledFundOccurrenceTransitionResult(
                occurrenceState: winningState,
                reservationOperation: winningOperation,
                incomingStateIsAuthoritative: false,
              );
            },
      );
      final store = _store(occurrenceDate, repository);

      final allocation = await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );

      expect(allocation.id, 'remote-allocation');
      expect(store.reservationOperations, hasLength(1));
      expect(store.currentFundAmountMinor('bills'), 20000);
      expect(
        store
            .scheduledTransactions
            .single
            .occurrenceStates[occurrenceDayKey(occurrenceDate)]
            ?.operationId,
        'remote-paid-winner',
      );
    },
  );

  test(
    'remote competing Skip leaves the local Fund and occurrence unchanged',
    () async {
      final repository = _AtomicTransitionRepository(
        resolver:
            ({
              required repository,
              required occurrenceState,
              required reservationOperation,
            }) {
              final skipped = _remoteSkippedWinner(occurrenceState);
              repository.install(skipped, null);
              return ScheduledFundOccurrenceTransitionResult(
                occurrenceState: skipped,
                incomingStateIsAuthoritative: false,
              );
            },
      );
      final store = _store(occurrenceDate, repository);
      final originalSchedule = store.scheduledTransactions.single;

      await expectLater(
        store.completeScheduledFundFunding(
          scheduledTransactionId: originalSchedule.id,
          occurrenceDate: occurrenceDate,
          fundingDate: occurrenceDate,
        ),
        throwsA(isA<FinanceDataValidationException>()),
      );

      expect(store.reservationOperations, isEmpty);
      expect(store.currentFundAmountMinor('bills'), 0);
      expect(store.availableToSpendForAccount('checking'), 500000);
      expect(store.scheduledTransactions.single.nextDate, occurrenceDate);
      expect(store.scheduledTransactions.single.occurrenceStates, isEmpty);
      expect(repository.savedSchedules, isEmpty);
    },
  );

  test(
    'atomic failure leaves local schedule and reservation unchanged',
    () async {
      final repository = _AtomicTransitionRepository(failTransitions: true);
      final store = _store(occurrenceDate, repository);
      final before = store.dataSet.toJson();

      await expectLater(
        store.completeScheduledFundFunding(
          scheduledTransactionId: 'scheduled-bills-funding',
          occurrenceDate: occurrenceDate,
          fundingDate: occurrenceDate,
        ),
        throwsA(isA<StateError>()),
      );

      expect(store.dataSet.toJson(), before);
      expect(repository.operations, isEmpty);
      expect(repository.savedSchedules, isEmpty);
    },
  );

  test('retry is idempotent through the actual atomic store path', () async {
    final repository = _AtomicTransitionRepository();
    final store = _store(occurrenceDate, repository);

    final first = await store.completeScheduledFundFunding(
      scheduledTransactionId: 'scheduled-bills-funding',
      occurrenceDate: occurrenceDate,
      fundingDate: occurrenceDate,
    );
    final retry = await store.completeScheduledFundFunding(
      scheduledTransactionId: 'scheduled-bills-funding',
      occurrenceDate: occurrenceDate,
      fundingDate: occurrenceDate,
    );

    expect(retry.id, first.id);
    expect(repository.transitionCalls, 2);
    expect(repository.operations, hasLength(1));
    expect(store.reservationOperations, hasLength(1));
    expect(store.currentFundAmountMinor('bills'), 20000);
  });

  test(
    'Undo atomically installs one reversal and reopens the occurrence',
    () async {
      final repository = _AtomicTransitionRepository();
      final store = _store(occurrenceDate, repository);
      final allocation = await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );

      final reversal = await store.undoScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
      );

      expect(repository.transitionCalls, 2);
      expect(repository.operations, hasLength(2));
      expect(reversal.kind, ReservationOperationKind.reversal);
      expect(reversal.reversesOperationId, allocation.id);
      expect(store.currentFundAmountMinor('bills'), 0);
      expect(store.availableToSpendForAccount('checking'), 500000);
      expect(
        store
            .scheduledTransactions
            .single
            .occurrenceStates[occurrenceDayKey(occurrenceDate)]
            ?.status,
        ScheduledOccurrenceStatus.pending,
      );
    },
  );

  test(
    'remote Paid winner defeats Undo without changing the local Paid state',
    () async {
      final repository = _AtomicTransitionRepository();
      final store = _store(occurrenceDate, repository);
      final allocation = await store.completeScheduledFundFunding(
        scheduledTransactionId: 'scheduled-bills-funding',
        occurrenceDate: occurrenceDate,
        fundingDate: occurrenceDate,
      );
      final localPaid = store
          .scheduledTransactions
          .single
          .occurrenceStates[occurrenceDayKey(occurrenceDate)]!;
      repository.resolver =
          ({
            required repository,
            required occurrenceState,
            required reservationOperation,
          }) {
            final remotePaid = ScheduledOccurrenceState(
              scheduledDate: occurrenceState.scheduledDate,
              plannedAmountMinor: occurrenceState.plannedAmountMinor,
              status: ScheduledOccurrenceStatus.paid,
              actualAmountMinor: allocation.amountMinor,
              actualPaymentDate: occurrenceDate,
              reservationOperationId: allocation.id,
              revision: occurrenceState.revision + 1,
              operationId: 'remote-paid-after-undo',
              changedAt: DateTime.utc(2026, 8, 24, 13),
              deviceId: 'remote-device',
              historyEpochRevision: occurrenceState.historyEpochRevision,
              historyEpochOperationId: occurrenceState.historyEpochOperationId,
            );
            repository.install(remotePaid, allocation);
            return ScheduledFundOccurrenceTransitionResult(
              occurrenceState: remotePaid,
              reservationOperation: allocation,
              incomingStateIsAuthoritative: false,
            );
          };

      await expectLater(
        store.undoScheduledFundFunding(
          scheduledTransactionId: 'scheduled-bills-funding',
          occurrenceDate: occurrenceDate,
        ),
        throwsA(isA<FinanceDataValidationException>()),
      );

      final after = store
          .scheduledTransactions
          .single
          .occurrenceStates[occurrenceDayKey(occurrenceDate)]!;
      expect(after.operationId, localPaid.operationId);
      expect(after.status, ScheduledOccurrenceStatus.paid);
      expect(store.reservationOperations, hasLength(1));
      expect(store.currentFundAmountMinor('bills'), 20000);
    },
  );
}

typedef _TransitionResolver =
    ScheduledFundOccurrenceTransitionResult Function({
      required _AtomicTransitionRepository repository,
      required ScheduledOccurrenceState occurrenceState,
      required ReservationOperationRecord? reservationOperation,
    });

class _AtomicTransitionRepository
    implements
        FinanceRecordRepository,
        ScheduledFundOccurrenceTransitionRepository {
  _AtomicTransitionRepository({this.failTransitions = false, this.resolver});

  final bool failTransitions;
  _TransitionResolver? resolver;
  ScheduledOccurrenceState? remoteState;
  final operations = <String, ReservationOperationRecord>{};
  final savedSchedules = <ScheduledTransactionRecord>[];
  int transitionCalls = 0;

  void install(
    ScheduledOccurrenceState state,
    ReservationOperationRecord? operation,
  ) {
    remoteState = state;
    if (operation != null) operations[operation.id] = operation;
  }

  @override
  Future<ScheduledFundOccurrenceTransitionResult>
  saveScheduledFundOccurrenceTransition({
    required String userId,
    required String scheduledTransactionId,
    required String dayKey,
    required ScheduledOccurrenceState occurrenceState,
    ReservationOperationRecord? reservationOperation,
  }) async {
    transitionCalls += 1;
    if (failTransitions) throw StateError('Atomic transition failed');
    final custom = resolver;
    if (custom != null) {
      return custom(
        repository: this,
        occurrenceState: occurrenceState,
        reservationOperation: reservationOperation,
      );
    }

    final current = remoteState;
    final sameAuthority =
        current != null &&
        current.revision == occurrenceState.revision &&
        current.operationId == occurrenceState.operationId;
    final winner = current == null
        ? occurrenceState
        : authoritativeOccurrenceState(current, occurrenceState);
    final incomingWins =
        current == null || identical(winner, occurrenceState) || sameAuthority;
    if (incomingWins) {
      install(occurrenceState, reservationOperation);
      return ScheduledFundOccurrenceTransitionResult(
        occurrenceState: occurrenceState,
        reservationOperation: reservationOperation == null
            ? null
            : operations[reservationOperation.id],
        incomingStateIsAuthoritative: true,
      );
    }
    final linkedId = winner.reservationOperationId;
    return ScheduledFundOccurrenceTransitionResult(
      occurrenceState: winner,
      reservationOperation: linkedId == null ? null : operations[linkedId],
      incomingStateIsAuthoritative: false,
    );
  }

  @override
  Future<void> saveScheduledTransaction({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {
    savedSchedules.add(scheduledTransaction);
  }

  @override
  Future<String?> activeRestoreGeneration(String userId) async => null;

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async =>
      throw UnimplementedError();

  @override
  Stream<FinanceDataSet> watchDataSet(String userId) => const Stream.empty();

  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async => 'test-generation';

  @override
  Future<void> saveAccount({
    required String userId,
    required AccountRecord account,
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
  Future<void> saveTransaction({
    required String userId,
    required TransactionRecord transaction,
  }) async {}
}

FinanceDataStore _store(
  DateTime occurrenceDate,
  _AtomicTransitionRepository repository,
) {
  final sync = SyncMetadata.fresh(
    now: DateTime.utc(2026, 8, 1),
    deviceId: 'device-a',
  );
  return FinanceDataStore(
    deviceId: 'device-a',
    remoteRepository: repository,
    userId: 'user',
    dataSet: FinanceDataSet(
      accounts: [
        AccountRecord(
          id: 'checking',
          name: 'CTBI',
          type: AccountType.checking,
          openingBalanceMinor: 500000,
          sync: sync,
        ),
      ],
      categories: const [],
      transactions: const [],
      scheduledTransactions: [
        ScheduledTransactionRecord(
          id: 'scheduled-bills-funding',
          type: TransactionType.goalFunding,
          accountId: 'checking',
          payee: 'Bills funding',
          amountMinor: 20000,
          nextDate: occurrenceDate,
          frequency: RecurrenceFrequency.monthly,
          reservationFundingContainerType: ReservationContainerType.fund,
          reservationFundingContainerId: 'bills',
          sync: sync,
        ),
      ],
      budgets: const [],
      goals: const [],
      funds: [
        FundRecord(
          id: 'bills',
          name: 'Bills',
          fundingAccountId: 'checking',
          status: FundStatus.active,
          sync: sync,
        ),
      ],
      reservationOperations: const [],
      preferences: const UserPreferences(),
    ),
  );
}

ScheduledOccurrenceState _remotePaidWinner(
  ScheduledOccurrenceState incoming,
  ReservationOperationRecord incomingOperation,
) => ScheduledOccurrenceState(
  scheduledDate: incoming.scheduledDate,
  plannedAmountMinor: incoming.plannedAmountMinor,
  status: ScheduledOccurrenceStatus.paid,
  actualAmountMinor: incoming.actualAmountMinor,
  actualPaymentDate: incoming.actualPaymentDate,
  reservationOperationId: 'remote-allocation',
  revision: incoming.revision + 1,
  operationId: 'remote-paid-winner',
  changedAt: incoming.changedAt.add(const Duration(seconds: 1)),
  deviceId: 'remote-device',
  historyEpochRevision: incoming.historyEpochRevision,
  historyEpochOperationId: incoming.historyEpochOperationId,
);

ReservationOperationRecord _remoteAllocation(
  ReservationOperationRecord incoming,
  ScheduledOccurrenceState winningState,
) => ReservationOperationRecord(
  id: winningState.reservationOperationId!,
  containerType: incoming.containerType,
  containerId: incoming.containerId,
  fundingAccountId: incoming.fundingAccountId,
  kind: incoming.kind,
  amountMinor: incoming.amountMinor,
  effectiveDate: incoming.effectiveDate,
  revision: incoming.revision,
  baseRevision: incoming.baseRevision,
  operationId: winningState.reservationOperationId!,
  deviceId: 'remote-device',
  scheduledTransactionId: incoming.scheduledTransactionId,
  scheduledOccurrenceDate: incoming.scheduledOccurrenceDate,
  causationId: 'remote-competing-paid',
  sync: SyncMetadata.fresh(
    now: DateTime.utc(2026, 8, 24, 12),
    deviceId: 'remote-device',
  ),
);

ScheduledOccurrenceState _remoteSkippedWinner(
  ScheduledOccurrenceState incoming,
) => ScheduledOccurrenceState(
  scheduledDate: incoming.scheduledDate,
  plannedAmountMinor: incoming.plannedAmountMinor,
  status: ScheduledOccurrenceStatus.skipped,
  revision: incoming.revision + 1,
  operationId: 'remote-skip-winner',
  changedAt: incoming.changedAt.add(const Duration(seconds: 1)),
  deviceId: 'remote-device',
  historyEpochRevision: incoming.historyEpochRevision,
  historyEpochOperationId: incoming.historyEpochOperationId,
);
