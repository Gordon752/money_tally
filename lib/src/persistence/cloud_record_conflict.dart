import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/fund.dart';
import '../domain/goal.dart';
import '../domain/goal_funding.dart';
import '../domain/transaction.dart';
import '../domain/sync_metadata.dart';

/// Only ordinary mutable records use this protocol. Scheduled authority and
/// immutable reservation operations have their own transactional protocols.
const ordinaryCloudCollections = {
  'accounts',
  'categories',
  'transactions',
  'budgets',
  'goals',
  'goalContributions',
  'goalFundingEvents',
  'funds',
};

bool equalRecordJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && equalRecordJson(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => i,
        ).every((i) => equalRecordJson(a[i], b[i]));
  }
  return a == b;
}

Map<String, Object?> canonicalCloudRecord(
  String collection,
  Map<String, Object?> json,
) => switch (collection) {
  'accounts' => AccountRecord.fromJson(json).toJson(),
  'categories' => CategoryRecord.fromJson(json).toJson(),
  'transactions' => TransactionRecord.fromJson(json).toJson(),
  'budgets' => BudgetRecord.fromJson(json).toJson(),
  'goals' => GoalRecord.fromJson(json).toJson(),
  'goalContributions' => GoalContributionRecord.fromJson(json).toJson(),
  'goalFundingEvents' => GoalFundingEventRecord.fromJson(json).toJson(),
  'funds' => FundRecord.fromJson(json).toJson(),
  _ => throw ArgumentError('Not an ordinary cloud collection: $collection'),
};

class CloudRecordConflict {
  const CloudRecordConflict({
    required this.collection,
    required this.proposed,
    required this.authoritative,
    this.documentPath,
  });
  final String collection;
  final Map<String, Object?> proposed;
  final Map<String, Object?>? authoritative;
  final String? documentPath;
}

abstract interface class CloudRecordConflictRepository {
  void acknowledgeCloudRecordConflicts(
    CloudRecordWriteConflict error,
    FinanceDataSet installed,
  );
}

class CloudRecordWriteConflict implements Exception {
  const CloudRecordWriteConflict(this.conflicts);
  final List<CloudRecordConflict> conflicts;
  @override
  String toString() =>
      'Cloud records changed on another device. The cloud versions were kept; sync again to reconcile.';
}

/// A rejected tombstone must not repeatedly win the ordinary tombstone merge.
/// Install only the server response to the exact rejected local payload; an
/// edit made while the request was in flight is never replaced here.
FinanceDataSet reconcileCloudRecordConflicts(
  FinanceDataSet current,
  CloudRecordWriteConflict error,
) {
  var result = current;
  for (final conflict in error.conflicts) {
    final cloud = conflict.authoritative;
    if (cloud == null) continue;
    final cloudSync = SyncMetadata.fromJson(
      Map<String, Object?>.from(cloud['sync'] as Map),
    );
    final proposedSync = SyncMetadata.fromJson(
      Map<String, Object?>.from(conflict.proposed['sync'] as Map),
    );
    // A failed precondition is not evidence that a genuinely newer offline
    // edit should be discarded. Keep it for a fresh read/merge/retry. A cloud
    // tombstone is terminal, and newer live cloud records beat stale deletes.
    final adoptCloud =
        (cloudSync.isDeleted && !proposedSync.isDeleted) ||
        cloudSync.version >= proposedSync.version;
    if (!adoptCloud) continue;
    List<T> reconcile<T>(
      List<T> records,
      Map<String, Object?> Function(T) jsonOf,
      T Function(Map<String, Object?>) fromJson,
    ) {
      return [
        for (final record in records)
          if (!equalRecordJson(jsonOf(record), conflict.proposed))
            record
          else if (conflict.authoritative != null)
            fromJson(conflict.authoritative!),
      ];
    }

    result = switch (conflict.collection) {
      'accounts' => result.copyWith(
        accounts: reconcile(
          result.accounts,
          (r) => r.toJson(),
          AccountRecord.fromJson,
        ),
      ),
      'categories' => result.copyWith(
        categories: reconcile(
          result.categories,
          (r) => r.toJson(),
          CategoryRecord.fromJson,
        ),
      ),
      'transactions' => result.copyWith(
        transactions: reconcile(
          result.transactions,
          (r) => r.toJson(),
          TransactionRecord.fromJson,
        ),
      ),
      'budgets' => result.copyWith(
        budgets: reconcile(
          result.budgets,
          (r) => r.toJson(),
          BudgetRecord.fromJson,
        ),
      ),
      'goals' => result.copyWith(
        goals: reconcile(result.goals, (r) => r.toJson(), GoalRecord.fromJson),
      ),
      'goalContributions' => result.copyWith(
        goalContributions: reconcile(
          result.goalContributions,
          (r) => r.toJson(),
          GoalContributionRecord.fromJson,
        ),
      ),
      'goalFundingEvents' => result.copyWith(
        goalFundingEvents: reconcile(
          result.goalFundingEvents,
          (r) => r.toJson(),
          GoalFundingEventRecord.fromJson,
        ),
      ),
      'funds' => result.copyWith(
        funds: reconcile(result.funds, (r) => r.toJson(), FundRecord.fromJson),
      ),
      _ => result,
    };
  }
  return equalRecordJson(current.toJson(), result.toJson()) ? current : result;
}
