import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/fund.dart';
import '../domain/goal.dart';
import '../domain/goal_funding.dart';
import '../domain/reservation.dart';
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

enum CloudSyncLoadMode { unknown, fullBootstrap, incremental }

/// Per-attempt Firestore activity observed by a cloud repository.
///
/// Counts are deliberately described as estimates: Firestore may retry a
/// transaction internally and empty queries have minimum billing behavior.
/// The values are still precise enough to identify repeated full bootstraps or
/// unexpectedly busy upload paths on a physical device.
class CloudSyncRepositoryMetrics {
  const CloudSyncRepositoryMetrics({
    this.loadMode = CloudSyncLoadMode.unknown,
    this.fullBootstrapReason,
    this.documentsDownloaded = 0,
    this.documentsUploaded = 0,
    this.estimatedReads = 0,
    this.estimatedWrites = 0,
    this.queryCount = 0,
    this.cacheBytes,
    this.uploadedByCollection = const {},
    this.changedFieldsByCollection = const {},
  });

  final CloudSyncLoadMode loadMode;
  final String? fullBootstrapReason;
  final int documentsDownloaded;
  final int documentsUploaded;
  final int estimatedReads;
  final int estimatedWrites;
  final int queryCount;
  final int? cacheBytes;
  final Map<String, int> uploadedByCollection;
  final Map<String, Map<String, int>> changedFieldsByCollection;

  Map<String, Object?> toJson() => {
    'loadMode': loadMode.name,
    'fullBootstrapReason': fullBootstrapReason,
    'documentsDownloaded': documentsDownloaded,
    'documentsUploaded': documentsUploaded,
    'estimatedReads': estimatedReads,
    'estimatedWrites': estimatedWrites,
    'queryCount': queryCount,
    'cacheBytes': cacheBytes,
    'uploadedByCollection': uploadedByCollection,
    'changedFieldsByCollection': changedFieldsByCollection,
  };

  factory CloudSyncRepositoryMetrics.fromJson(Map<String, Object?> json) {
    return CloudSyncRepositoryMetrics(
      loadMode: CloudSyncLoadMode.values.firstWhere(
        (value) => value.name == json['loadMode'],
        orElse: () => CloudSyncLoadMode.unknown,
      ),
      fullBootstrapReason: json['fullBootstrapReason'] as String?,
      documentsDownloaded: json['documentsDownloaded'] as int? ?? 0,
      documentsUploaded: json['documentsUploaded'] as int? ?? 0,
      estimatedReads: json['estimatedReads'] as int? ?? 0,
      estimatedWrites: json['estimatedWrites'] as int? ?? 0,
      queryCount: json['queryCount'] as int? ?? 0,
      cacheBytes: json['cacheBytes'] as int?,
      uploadedByCollection: {
        for (final entry
            in (json['uploadedByCollection'] as Map? ?? const {}).entries)
          entry.key.toString(): (entry.value as num).toInt(),
      },
      changedFieldsByCollection: {
        for (final collectionEntry
            in (json['changedFieldsByCollection'] as Map? ?? const {}).entries)
          collectionEntry.key.toString(): {
            for (final fieldEntry
                in (collectionEntry.value as Map? ?? const {}).entries)
              fieldEntry.key.toString(): (fieldEntry.value as num).toInt(),
          },
      },
    );
  }
}

/// Optional instrumentation exposed by production cloud repositories.
abstract interface class CloudSyncMetricsProvider {
  void beginSyncMetrics();

  CloudSyncRepositoryMetrics get currentSyncMetrics;
}

/// A generation-aware cloud load reconstructed from either a full bootstrap
/// or changes applied to the last locally acknowledged cloud baseline.
class IncrementalFinanceSyncLoad {
  const IncrementalFinanceSyncLoad({
    required this.dataSet,
    required this.generation,
    required this.through,
    required this.wasFullBootstrap,
    this.fullBootstrapAt,
  });

  final FinanceDataSet dataSet;
  final String? generation;
  final DateTime through;
  final bool wasFullBootstrap;
  final DateTime? fullBootstrapAt;
}

/// Optional capability for repositories that can avoid downloading every
/// cloud record on each synchronization.
///
/// Implementations must not advance their durable cursor until
/// [acknowledgeIncrementalSync] is called after the merged data set has been
/// installed and uploaded successfully. A restore-generation change must
/// force a full bootstrap before incremental loading resumes.
abstract interface class IncrementalFinanceRecordRepository {
  Future<IncrementalFinanceSyncLoad> loadDataSetForSync(String userId);

  Future<void> acknowledgeIncrementalSync({
    required String userId,
    required IncrementalFinanceSyncLoad load,
    required FinanceDataSet resultingDataSet,
  });
}

/// Removes device-local cloud-sync state that belongs to a deleted account.
/// The user's authoritative cloud records are deleted by the trusted backend;
/// this capability prevents a later local-only session from retaining an
/// incremental copy of those records on the device.
abstract interface class DeletedAccountLocalStateCleaner {
  Future<void> clearDeletedAccountLocalState(String userId);
}

/// Optional capability for causally ordered, field-scoped schedule occurrence
/// writes. Implementations must compare occurrence authority remotely rather
/// than replacing an enclosing schedule snapshot.
abstract interface class ScheduledOccurrenceStateRepository {
  Future<ScheduledOccurrenceState> saveScheduledOccurrenceState({
    required String userId,
    required String scheduledTransactionId,
    required String dayKey,
    required ScheduledOccurrenceState occurrenceState,
  });
}

/// Optional capability for a causal, field-scoped scheduled-history reset.
///
/// Implementations must compare [ScheduledTransactionRecord.occurrenceHistoryEpoch]
/// remotely. A stale schedule definition must never overwrite a newer reset.
abstract interface class ScheduledHistoryResetRepository {
  Future<void> saveScheduledHistoryReset({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  });
}

/// Optional capability for repositories that understand the unified
/// Goal/Fund reservation model. Keeping this separate allows older/local test
/// repositories to remain valid while reservation-aware cloud repositories
/// persist the new records explicitly.
abstract interface class ReservationRecordRepository {
  Future<void> saveFund({required String userId, required FundRecord fund});

  Future<void> saveReservationOperation({
    required String userId,
    required ReservationOperationRecord operation,
  });
}

/// Optional capability for an idempotent reservation operation whose stable
/// identity is owned by a Scheduled occurrence.
///
/// Unlike an ordinary user-created reservation operation, two devices may
/// independently recover the same Paid occurrence after one device saved the
/// occurrence authority but did not finish installing the linked allocation
/// locally. Implementations return the existing immutable operation when its
/// financial/linkage identity matches [operation].
abstract interface class ScheduledReservationOperationRepository {
  Future<ReservationOperationRecord> saveScheduledReservationOperation({
    required String userId,
    required ReservationOperationRecord operation,
  });
}

/// Result of atomically resolving one Scheduled Fund occurrence together with
/// the immutable reservation operation linked by that occurrence.
///
/// [incomingStateIsAuthoritative] is also true for an idempotent retry of an
/// already-installed occurrence operation. In that case a repository may have
/// repaired a missing linked reservation operation without rewriting the
/// occurrence state.
class ScheduledFundOccurrenceTransitionResult {
  const ScheduledFundOccurrenceTransitionResult({
    required this.occurrenceState,
    required this.incomingStateIsAuthoritative,
    this.reservationOperation,
  });

  final ScheduledOccurrenceState occurrenceState;
  final ReservationOperationRecord? reservationOperation;
  final bool incomingStateIsAuthoritative;
}

/// Optional capability for an atomic Scheduled Fund occurrence transition.
///
/// Implementations must remotely resolve occurrence authority before writing.
/// When [occurrenceState] wins (or is an idempotent retry of the installed
/// winner), its linked allocation/reversal [reservationOperation] must be
/// created or validated in the same atomic transaction. When a different
/// remote occurrence wins, no incoming operation is written and the remote
/// winner plus its linked operation, when available, are returned.
abstract interface class ScheduledFundOccurrenceTransitionRepository {
  Future<ScheduledFundOccurrenceTransitionResult>
  saveScheduledFundOccurrenceTransition({
    required String userId,
    required String scheduledTransactionId,
    required String dayKey,
    required ScheduledOccurrenceState occurrenceState,
    ReservationOperationRecord? reservationOperation,
  });
}
