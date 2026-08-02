import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';

void main() {
  test('scheduled Goal Funding persists its allocation plan', () async {
    final store = _store();
    final schedule = _schedule();

    await store.saveScheduledTransaction(schedule);

    final restored = ScheduledTransactionRecord.fromJson(
      store.scheduledTransactions.single.toJson(),
    );
    expect(restored.type, TransactionType.goalFunding);
    expect(restored.hasValidGoalFundingAllocations, isTrue);
    expect(restored.goalFundingAllocations, hasLength(2));
    expect(store.balanceForAccount('checking'), 100000);
    expect(store.currentGoalAmountMinor('emergency'), 0);
  });

  test(
    'Fund Now creates one linked event and moves money exactly once',
    () async {
      final store = _store();
      await store.saveScheduledTransaction(_schedule());

      final first = await store.completeScheduledGoalFunding(
        scheduledTransactionId: 'scheduled-goals',
        occurrenceDate: DateTime(2026, 8, 1),
        fundingDate: DateTime(2026, 7, 27),
      );
      final retried = await store.completeScheduledGoalFunding(
        scheduledTransactionId: 'scheduled-goals',
        occurrenceDate: DateTime(2026, 8, 1),
      );

      expect(retried.id, first.id);
      expect(
        store.goalFundingEvents.where((event) => event.isActive),
        hasLength(1),
      );
      expect(store.balanceForAccount('checking'), 70000);
      expect(store.currentGoalAmountMinor('emergency'), 20000);
      expect(store.currentGoalAmountMinor('truck'), 10000);

      final occurrence = store.scheduledTransactions.single.occurrences.single;
      expect(occurrence.status, ScheduledOccurrenceStatus.paid);
      expect(occurrence.goalFundingEventId, first.id);
      expect(occurrence.actualAmountMinor, 30000);
    },
  );

  test(
    'undo scheduled Goal Funding restores its exact planned occurrence',
    () async {
      final store = _store();
      await store.saveScheduledTransaction(_schedule());
      final event = await store.completeScheduledGoalFunding(
        scheduledTransactionId: 'scheduled-goals',
        occurrenceDate: DateTime(2026, 8, 1),
        fundingDate: DateTime(2026, 7, 27),
      );

      await store.undoGoalFunding(event.id);

      expect(store.balanceForAccount('checking'), 100000);
      expect(store.currentGoalAmountMinor('emergency'), 0);
      expect(store.currentGoalAmountMinor('truck'), 0);
      expect(store.goalFundingEvents.single.isDeleted, isTrue);
      final restored = store.scheduledTransactions.single;
      expect(restored.isDeleted, isFalse);
      final occurrence = restored.occurrences.single;
      expect(occurrence.status, ScheduledOccurrenceStatus.pending);
      expect(occurrence.scheduledDate, DateTime(2026, 8, 1));
      expect(occurrence.plannedAmountMinor, 30000);
    },
  );

  test(
    'an inactive Goal leaves a migrated scheduled transfer intact',
    () async {
      final store = _store();
      await store.saveScheduledTransaction(_schedule());

      await store.archiveGoal('emergency');

      // A single-Goal legacy funding schedule migrates to the ordinary
      // transfer path, so it is no longer an active Goal-funding schedule.
      expect(store.scheduledGoalFundingNeedsAttention('emergency'), isFalse);
      expect(store.goalDeleteEligibility('emergency').canDelete, isFalse);
      expect(
        store.completeScheduledGoalFunding(
          scheduledTransactionId: 'scheduled-goals',
          occurrenceDate: DateTime(2026, 8, 1),
        ),
        throwsA(isA<FinanceDataValidationException>()),
      );
      expect(store.scheduledTransactions.single.isDeleted, isFalse);
      expect(
        store.scheduledTransactions.single.goalFundingAllocations.map(
          (allocation) => allocation.goalId,
        ),
        containsAll(['emergency', 'truck']),
      );
    },
  );
}

FinanceDataStore _store() {
  final sync = SyncMetadata.fresh(
    now: DateTime.utc(2026, 7, 1),
    deviceId: 'test-device',
  );
  return FinanceDataStore(
    deviceId: 'test-device',
    dataSet: FinanceDataSet(
      accounts: [
        AccountRecord(
          id: 'checking',
          name: 'Checking',
          type: AccountType.checking,
          openingBalanceMinor: 100000,
          sync: sync,
        ),
      ],
      categories: const <CategoryRecord>[],
      transactions: const <TransactionRecord>[],
      scheduledTransactions: const <ScheduledTransactionRecord>[],
      budgets: const <BudgetRecord>[],
      goals: [
        GoalRecord(
          id: 'emergency',
          name: 'Emergency Fund',
          targetAmountMinor: 100000,
          status: GoalStatus.active,
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
          sync: sync,
        ),
        GoalRecord(
          id: 'truck',
          name: 'Truck Maintenance',
          targetAmountMinor: 100000,
          status: GoalStatus.active,
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
          sync: sync,
        ),
      ],
      preferences: const UserPreferences(),
    ),
  );
}

ScheduledTransactionRecord _schedule() {
  return ScheduledTransactionRecord(
    id: 'scheduled-goals',
    type: TransactionType.goalFunding,
    accountId: 'checking',
    payee: 'Goal funding',
    amountMinor: 30000,
    nextDate: DateTime(2026, 8, 1),
    frequency: RecurrenceFrequency.once,
    goalFundingAllocations: const [
      ScheduledGoalFundingAllocation(
        id: 'emergency-line',
        goalId: 'emergency',
        amountMinor: 20000,
        order: 0,
      ),
      ScheduledGoalFundingAllocation(
        id: 'truck-line',
        goalId: 'truck',
        amountMinor: 10000,
        order: 1,
      ),
    ],
    sync: SyncMetadata.fresh(
      now: DateTime.utc(2026, 7, 1),
      deviceId: 'test-device',
    ),
  );
}
