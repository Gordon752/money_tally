import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/goal.dart';
import '../domain/goal_funding.dart';
import '../domain/scheduled_transaction.dart';
import '../domain/transaction.dart';
import '../domain/user_preferences.dart';

abstract interface class FinanceRecordRepository {
  Stream<FinanceDataSet> watchDataSet(String userId);

  Future<FinanceDataSet> loadDataSet(String userId);

  /// Returns the currently authoritative restore generation, if this user has
  /// completed an authoritative backup restore.
  Future<String?> activeRestoreGeneration(String userId);

  Future<void> saveAccount({
    required String userId,
    required AccountRecord account,
  });

  Future<void> saveCategory({
    required String userId,
    required CategoryRecord category,
  });

  Future<void> saveTransaction({
    required String userId,
    required TransactionRecord transaction,
  });

  Future<void> saveScheduledTransaction({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  });

  Future<void> saveBudget({
    required String userId,
    required BudgetRecord budget,
  });

  Future<void> saveGoal({required String userId, required GoalRecord goal});

  Future<void> saveGoalContribution({
    required String userId,
    required GoalContributionRecord contribution,
  });

  Future<void> saveGoalFundingEvent({
    required String userId,
    required GoalFundingEventRecord fundingEvent,
  });

  Future<void> savePreferences({
    required String userId,
    required UserPreferences preferences,
  });

  /// Stages [dataSet] as a complete cloud generation and activates it only
  /// after every record has been written successfully.
  ///
  /// This is reserved for an explicitly confirmed backup restore. Normal sync
  /// continues to use the per-record save methods above.
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  });
}

/// Optional capability for repositories that can persist a complete merged
/// data set more efficiently than issuing one request per record.
///
/// Normal record saves continue to use [FinanceRecordRepository]. This is used
/// only by the explicit full-sync path after local and remote data have already
/// been reconciled.
abstract interface class BulkFinanceRecordRepository {
  Future<void> saveDataSet({
    required String userId,
    required FinanceDataSet dataSet,
    FinanceDataSet? baseline,
  });
}
