import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/fund.dart';
import '../domain/goal.dart';
import '../domain/goal_funding.dart';
import '../domain/reservation.dart';
import '../domain/scheduled_transaction.dart';
import '../domain/scheduled_occurrence_authority.dart';
import '../domain/transaction.dart';
import '../domain/user_preferences.dart';
import 'finance_record_repository.dart';

Map<String, Object?> _scheduledDefinitionJson(
  ScheduledTransactionRecord scheduledTransaction,
) {
  final json = _scheduledCloudJson(scheduledTransaction);
  json.remove('occurrenceStates');
  json.remove('occurrenceHistoryEpoch');
  return json;
}

Map<String, Object?> _scheduledCloudJson(
  ScheduledTransactionRecord scheduledTransaction,
) {
  final json = scheduledTransaction.toJson();
  json.remove('scheduledNotificationIds');
  json.remove('lastReminderScheduledAt');
  return json;
}

@visibleForTesting
Map<String, Object?> scheduledCloudJsonForSync({
  required ScheduledTransactionRecord scheduledTransaction,
  required bool existsInRemoteBaseline,
}) => existsInRemoteBaseline
    ? _scheduledDefinitionJson(scheduledTransaction)
    : _scheduledCloudJson(scheduledTransaction);

@visibleForTesting
bool shouldAdvanceScheduledHistoryEpoch({
  required ScheduledTransactionRecord scheduledTransaction,
  required ScheduledTransactionRecord remoteBaseline,
}) {
  final incomingEpoch = occurrenceHistoryEpochFor(scheduledTransaction);
  final baselineEpoch = occurrenceHistoryEpochFor(remoteBaseline);
  if (sameOccurrenceHistoryEpoch(incomingEpoch, baselineEpoch)) return false;
  final winner = authoritativeOccurrenceHistoryEpoch(
    incomingEpoch,
    baselineEpoch,
  );
  return sameOccurrenceHistoryEpoch(winner, incomingEpoch);
}

class FirestoreRecordRepository
    implements
        FinanceRecordRepository,
        BulkFinanceRecordRepository,
        IncrementalFinanceRecordRepository,
        CloudSyncMetricsProvider,
        ReservationRecordRepository,
        ScheduledOccurrenceStateRepository,
        ScheduledHistoryResetRepository {
  FirestoreRecordRepository({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;
  final Map<String, String?> _activeGenerations = {};
  CloudSyncRepositoryMetrics _syncMetrics = const CloudSyncRepositoryMetrics();

  static const _batchWriteLimit = 400;
  static const _normalSyncWriteConcurrency = 8;
  static const _cloudUpdatedAtField = '_trackmarkCloudUpdatedAt';
  static const _incrementalCachePrefix =
      'trackmark_firestore_incremental_sync_cache_';
  static const _syncCollections = <String>[
    'accounts',
    'categories',
    'transactions',
    'scheduledTransactions',
    'budgets',
    'goals',
    'goalContributions',
    'goalFundingEvents',
    'funds',
    'reservationOperations',
  ];

  @override
  CloudSyncRepositoryMetrics get currentSyncMetrics => _syncMetrics;

  @override
  void beginSyncMetrics() {
    _syncMetrics = const CloudSyncRepositoryMetrics();
  }

  void _updateSyncMetrics({
    CloudSyncLoadMode? loadMode,
    String? fullBootstrapReason,
    int downloadedDelta = 0,
    int uploadedDelta = 0,
    int readDelta = 0,
    int writeDelta = 0,
    int queryDelta = 0,
    int? cacheBytes,
    Map<String, int> uploadedByCollectionDelta = const {},
    Map<String, Map<String, int>> changedFieldsByCollectionDelta = const {},
  }) {
    final current = _syncMetrics;
    final uploadedByCollection = <String, int>{...current.uploadedByCollection};
    for (final entry in uploadedByCollectionDelta.entries) {
      uploadedByCollection.update(
        entry.key,
        (value) => value + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    final changedFieldsByCollection = <String, Map<String, int>>{
      for (final entry in current.changedFieldsByCollection.entries)
        entry.key: {...entry.value},
    };
    for (final collectionEntry in changedFieldsByCollectionDelta.entries) {
      final fields = changedFieldsByCollection.putIfAbsent(
        collectionEntry.key,
        () => <String, int>{},
      );
      for (final fieldEntry in collectionEntry.value.entries) {
        fields.update(
          fieldEntry.key,
          (value) => value + fieldEntry.value,
          ifAbsent: () => fieldEntry.value,
        );
      }
    }
    _syncMetrics = CloudSyncRepositoryMetrics(
      loadMode: loadMode ?? current.loadMode,
      fullBootstrapReason: fullBootstrapReason ?? current.fullBootstrapReason,
      documentsDownloaded: current.documentsDownloaded + downloadedDelta,
      documentsUploaded: current.documentsUploaded + uploadedDelta,
      estimatedReads: current.estimatedReads + readDelta,
      estimatedWrites: current.estimatedWrites + writeDelta,
      queryCount: current.queryCount + queryDelta,
      cacheBytes: cacheBytes ?? current.cacheBytes,
      uploadedByCollection: uploadedByCollection,
      changedFieldsByCollection: changedFieldsByCollection,
    );
  }

  CollectionReference<Map<String, dynamic>> get _users {
    return firestore.collection('users');
  }

  CollectionReference<Map<String, dynamic>> _collection(
    String userId,
    String collectionPath,
  ) {
    return _users.doc(userId).collection(collectionPath);
  }

  DocumentReference<Map<String, dynamic>> _preferencesDoc(String userId) {
    return _users.doc(userId).collection('preferences').doc('main');
  }

  DocumentReference<Map<String, dynamic>> _authorityDoc(String userId) {
    return _users.doc(userId).collection('metadata').doc('restoreAuthority');
  }

  DocumentReference<Map<String, dynamic>> _syncClockDoc(String userId) {
    return _users.doc(userId).collection('metadata').doc('syncClock');
  }

  DocumentReference<Map<String, dynamic>> _generationPreferencesDoc(
    String userId,
    String generation,
  ) {
    return _generationCollection(userId, generation, 'preferences').doc('main');
  }

  CollectionReference<Map<String, dynamic>> _generationCollection(
    String userId,
    String generation,
    String collectionPath,
  ) {
    return _users
        .doc(userId)
        .collection('restoreGenerations')
        .doc(generation)
        .collection(collectionPath);
  }

  @override
  Stream<FinanceDataSet> watchDataSet(String userId) async* {
    // Initial scaffold: emit full loads when callers subscribe. This keeps the
    // public contract stable while we decide whether to compose live collection
    // streams here or in a store layer.
    yield await loadDataSet(userId);
  }

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async {
    await firestore.enableNetwork();
    final generation = await _loadActiveGeneration(userId);
    return _loadDataSetForGeneration(userId, generation);
  }

  Future<FinanceDataSet> _loadDataSetForGeneration(
    String userId,
    String? generation,
  ) async {
    final results = await Future.wait([
      _loadCollection(userId, 'accounts', generation),
      _loadCollection(userId, 'categories', generation),
      _loadCollection(userId, 'transactions', generation),
      _loadCollection(userId, 'scheduledTransactions', generation),
      _loadCollection(userId, 'budgets', generation),
      _loadCollection(userId, 'goals', generation),
      _loadCollection(userId, 'goalContributions', generation),
      _loadCollection(userId, 'goalFundingEvents', generation),
      _loadCollection(userId, 'funds', generation),
      _loadCollection(userId, 'reservationOperations', generation),
      generation == null
          ? _preferencesDoc(userId).get(const GetOptions(source: Source.server))
          : _generationPreferencesDoc(
              userId,
              generation,
            ).get(const GetOptions(source: Source.server)),
    ]);

    final accountsSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final categoriesSnapshot =
        results[1] as QuerySnapshot<Map<String, dynamic>>;
    final transactionsSnapshot =
        results[2] as QuerySnapshot<Map<String, dynamic>>;
    final scheduledSnapshot = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final budgetsSnapshot = results[4] as QuerySnapshot<Map<String, dynamic>>;
    final goalsSnapshot = results[5] as QuerySnapshot<Map<String, dynamic>>;
    final contributionsSnapshot =
        results[6] as QuerySnapshot<Map<String, dynamic>>;
    final fundingEventsSnapshot =
        results[7] as QuerySnapshot<Map<String, dynamic>>;
    final fundsSnapshot = results[8] as QuerySnapshot<Map<String, dynamic>>;
    final reservationOperationsSnapshot =
        results[9] as QuerySnapshot<Map<String, dynamic>>;
    final preferencesSnapshot =
        results[10] as DocumentSnapshot<Map<String, dynamic>>;

    _recordSnapshotReads(results);

    return FinanceDataSet(
      accounts: accountsSnapshot.docs
          .map((doc) => AccountRecord.fromJson(doc.data()))
          .toList(),
      categories: categoriesSnapshot.docs
          .map((doc) => CategoryRecord.fromJson(doc.data()))
          .toList(),
      transactions: transactionsSnapshot.docs
          .map((doc) => TransactionRecord.fromJson(doc.data()))
          .toList(),
      scheduledTransactions: scheduledSnapshot.docs
          .map((doc) => ScheduledTransactionRecord.fromJson(doc.data()))
          .toList(),
      budgets: budgetsSnapshot.docs
          .map((doc) => BudgetRecord.fromJson(doc.data()))
          .toList(),
      goals: goalsSnapshot.docs
          .map((doc) => GoalRecord.fromJson(doc.data()))
          .toList(),
      goalContributions: contributionsSnapshot.docs
          .map((doc) => GoalContributionRecord.fromJson(doc.data()))
          .toList(),
      goalFundingEvents: fundingEventsSnapshot.docs
          .map((doc) => GoalFundingEventRecord.fromJson(doc.data()))
          .toList(),
      funds: fundsSnapshot.docs
          .map((doc) => FundRecord.fromJson(doc.data()))
          .toList(),
      reservationOperations: reservationOperationsSnapshot.docs
          .map((doc) => ReservationOperationRecord.fromJson(doc.data()))
          .toList(),
      preferences: preferencesSnapshot.data() == null
          ? const UserPreferences()
          : UserPreferences.fromJson(preferencesSnapshot.data()!),
    );
  }

  @override
  Future<IncrementalFinanceSyncLoad> loadDataSetForSync(String userId) async {
    await firestore.enableNetwork();
    final generation = await _loadActiveGeneration(userId);
    final through = await _createServerCheckpoint(userId);
    final cacheResult = await _loadIncrementalCache(userId);
    final cached = cacheResult.cache;
    final fullBootstrapExpired =
        cached != null &&
        through.difference(cached.fullBootstrapAt).abs() >=
            const Duration(days: 7);
    if (cached == null ||
        cached.generation != generation ||
        fullBootstrapExpired) {
      final reason = cached == null
          ? cacheResult.missReason ?? 'incremental cache unavailable'
          : cached.generation != generation
          ? 'restore generation changed'
          : 'seven-day safety refresh';
      _updateSyncMetrics(
        loadMode: CloudSyncLoadMode.fullBootstrap,
        fullBootstrapReason: reason,
      );
      return IncrementalFinanceSyncLoad(
        dataSet: await _loadDataSetForGeneration(userId, generation),
        generation: generation,
        through: through,
        wasFullBootstrap: true,
        fullBootstrapAt: through,
      );
    }

    _updateSyncMetrics(loadMode: CloudSyncLoadMode.incremental);

    final snapshots = await Future.wait([
      for (final collection in _syncCollections)
        _loadChangedCollection(
          userId,
          collection,
          generation,
          after: cached.through,
          through: through,
        ),
      generation == null
          ? _preferencesDoc(userId).get(const GetOptions(source: Source.server))
          : _generationPreferencesDoc(
              userId,
              generation,
            ).get(const GetOptions(source: Source.server)),
    ]);
    _recordSnapshotReads(snapshots);
    final delta = _dataSetFromSnapshots(snapshots);
    return IncrementalFinanceSyncLoad(
      dataSet: applyRemoteDataSetDelta(cached.dataSet, delta),
      generation: generation,
      through: through,
      wasFullBootstrap: false,
      fullBootstrapAt: cached.fullBootstrapAt,
    );
  }

  @override
  Future<void> acknowledgeIncrementalSync({
    required String userId,
    required IncrementalFinanceSyncLoad load,
    required FinanceDataSet resultingDataSet,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      'generation': load.generation,
      'through': load.through.toUtc().toIso8601String(),
      'fullBootstrapAt': (load.fullBootstrapAt ?? load.through)
          .toUtc()
          .toIso8601String(),
      'dataSet': resultingDataSet.toJson(),
    });
    final saved = await preferences.setString(
      '$_incrementalCachePrefix$userId',
      encoded,
    );
    if (!saved) {
      throw StateError('Cloud sync cache could not be saved locally.');
    }
    _updateSyncMetrics(cacheBytes: utf8.encode(encoded).length);
  }

  void _recordSnapshotReads(List<Object> snapshots) {
    var documents = 0;
    var reads = 0;
    var queries = 0;
    for (final snapshot in snapshots) {
      if (snapshot is QuerySnapshot<Map<String, dynamic>>) {
        final count = snapshot.docs.length;
        documents += count;
        reads += count == 0 ? 1 : count;
        queries += 1;
      } else if (snapshot is DocumentSnapshot<Map<String, dynamic>>) {
        documents += snapshot.exists ? 1 : 0;
        reads += 1;
      }
    }
    _updateSyncMetrics(
      downloadedDelta: documents,
      readDelta: reads,
      queryDelta: queries,
    );
  }

  FinanceDataSet _dataSetFromSnapshots(List<Object> results) {
    final accounts = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final categories = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final transactions = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final scheduled = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final budgets = results[4] as QuerySnapshot<Map<String, dynamic>>;
    final goals = results[5] as QuerySnapshot<Map<String, dynamic>>;
    final contributions = results[6] as QuerySnapshot<Map<String, dynamic>>;
    final fundingEvents = results[7] as QuerySnapshot<Map<String, dynamic>>;
    final funds = results[8] as QuerySnapshot<Map<String, dynamic>>;
    final operations = results[9] as QuerySnapshot<Map<String, dynamic>>;
    final preference = results[10] as DocumentSnapshot<Map<String, dynamic>>;
    return FinanceDataSet(
      accounts: accounts.docs
          .map((doc) => AccountRecord.fromJson(doc.data()))
          .toList(),
      categories: categories.docs
          .map((doc) => CategoryRecord.fromJson(doc.data()))
          .toList(),
      transactions: transactions.docs
          .map((doc) => TransactionRecord.fromJson(doc.data()))
          .toList(),
      scheduledTransactions: scheduled.docs
          .map((doc) => ScheduledTransactionRecord.fromJson(doc.data()))
          .toList(),
      budgets: budgets.docs
          .map((doc) => BudgetRecord.fromJson(doc.data()))
          .toList(),
      goals: goals.docs.map((doc) => GoalRecord.fromJson(doc.data())).toList(),
      goalContributions: contributions.docs
          .map((doc) => GoalContributionRecord.fromJson(doc.data()))
          .toList(),
      goalFundingEvents: fundingEvents.docs
          .map((doc) => GoalFundingEventRecord.fromJson(doc.data()))
          .toList(),
      funds: funds.docs.map((doc) => FundRecord.fromJson(doc.data())).toList(),
      reservationOperations: operations.docs
          .map((doc) => ReservationOperationRecord.fromJson(doc.data()))
          .toList(),
      preferences: preference.data() == null
          ? const UserPreferences()
          : UserPreferences.fromJson(preference.data()!),
    );
  }

  Future<DateTime> _createServerCheckpoint(String userId) async {
    final reference = _syncClockDoc(userId);
    _updateSyncMetrics(writeDelta: 1);
    await reference.set({
      'checkpointAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _updateSyncMetrics(readDelta: 1);
    final snapshot = await reference.get(
      const GetOptions(source: Source.server),
    );
    final value = snapshot.data()?['checkpointAt'];
    if (value is! Timestamp) {
      throw StateError('Cloud sync checkpoint is unavailable.');
    }
    return value.toDate().toUtc();
  }

  Future<_IncrementalCacheLoadResult> _loadIncrementalCache(
    String userId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final encoded = preferences.getString('$_incrementalCachePrefix$userId');
    if (encoded == null) {
      return const _IncrementalCacheLoadResult(
        missReason: 'no acknowledged incremental cache',
      );
    }
    try {
      final json = Map<String, Object?>.from(jsonDecode(encoded) as Map);
      final through = DateTime.parse(json['through']! as String).toUtc();
      final fullBootstrapAt = DateTime.parse(
        (json['fullBootstrapAt'] ?? json['through'])! as String,
      ).toUtc();
      return _IncrementalCacheLoadResult(
        cache: _IncrementalSyncCache(
          generation: json['generation'] as String?,
          through: through,
          fullBootstrapAt: fullBootstrapAt,
          dataSet: FinanceDataSet.fromJson(
            Map<String, Object?>.from(json['dataSet']! as Map),
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('Discarding unreadable cloud sync cache: $error');
      await preferences.remove('$_incrementalCachePrefix$userId');
      return _IncrementalCacheLoadResult(
        missReason: 'incremental cache was unreadable: ${error.runtimeType}',
      );
    }
  }

  @override
  Future<String?> activeRestoreGeneration(String userId) {
    return _loadActiveGeneration(userId);
  }

  @override
  Future<void> saveAccount({
    required String userId,
    required AccountRecord account,
  }) async {
    await _saveRecord(userId, 'accounts', account.id, account.toJson());
  }

  @override
  Future<void> saveCategory({
    required String userId,
    required CategoryRecord category,
  }) async {
    await _saveRecord(userId, 'categories', category.id, category.toJson());
  }

  @override
  Future<void> saveTransaction({
    required String userId,
    required TransactionRecord transaction,
  }) async {
    await _saveRecord(
      userId,
      'transactions',
      transaction.id,
      transaction.toJson(),
    );
  }

  @override
  Future<void> saveScheduledTransaction({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {
    await _saveRecord(
      userId,
      'scheduledTransactions',
      scheduledTransaction.id,
      _scheduledDefinitionJson(scheduledTransaction),
    );
  }

  @override
  Future<ScheduledOccurrenceState> saveScheduledOccurrenceState({
    required String userId,
    required String scheduledTransactionId,
    required String dayKey,
    required ScheduledOccurrenceState occurrenceState,
  }) async {
    final generation = await _activeGeneration(userId);
    final reference = generation == null
        ? _collection(
            userId,
            'scheduledTransactions',
          ).doc(scheduledTransactionId)
        : _generationCollection(
            userId,
            generation,
            'scheduledTransactions',
          ).doc(_encodedDocumentId(scheduledTransactionId));
    _updateSyncMetrics(readDelta: 1);
    return firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw StateError(
          'The scheduled transaction is unavailable for occurrence update.',
        );
      }
      final rawStates = snapshot.data()?['occurrenceStates'];
      final remoteEpoch = snapshot.data()?['occurrenceHistoryEpoch'] is Map
          ? ScheduledOccurrenceHistoryEpoch.fromJson(
              Map<String, Object?>.from(
                snapshot.data()!['occurrenceHistoryEpoch'] as Map,
              ),
            )
          : ScheduledOccurrenceHistoryEpoch.legacy;
      if (occurrenceState.historyEpochRevision != remoteEpoch.revision ||
          occurrenceState.historyEpochOperationId != remoteEpoch.operationId) {
        throw StateError(
          'Scheduled history changed on another device. Sync and try again.',
        );
      }
      ScheduledOccurrenceState? remoteState;
      if (rawStates is Map && rawStates[dayKey] is Map) {
        remoteState = ScheduledOccurrenceState.fromJson(
          Map<String, Object?>.from(rawStates[dayKey] as Map),
        );
      }
      final winner = remoteState == null
          ? occurrenceState
          : authoritativeOccurrenceState(remoteState, occurrenceState);
      if (identical(winner, occurrenceState)) {
        _updateSyncMetrics(uploadedDelta: 1, writeDelta: 1);
        transaction.update(reference, {
          'occurrenceStates.$dayKey': occurrenceState.toJson(),
          _cloudUpdatedAtField: FieldValue.serverTimestamp(),
        });
      }
      return winner;
    });
  }

  @override
  Future<void> saveScheduledHistoryReset({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {
    final incomingEpoch = scheduledTransaction.occurrenceHistoryEpoch;
    if (incomingEpoch == null) {
      throw ArgumentError('A scheduled-history reset requires an epoch.');
    }
    final generation = await _activeGeneration(userId);
    final reference = generation == null
        ? _collection(
            userId,
            'scheduledTransactions',
          ).doc(scheduledTransaction.id)
        : _generationCollection(
            userId,
            generation,
            'scheduledTransactions',
          ).doc(_encodedDocumentId(scheduledTransaction.id));
    _updateSyncMetrics(readDelta: 1);
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw StateError(
          'The scheduled transaction is unavailable for history reset.',
        );
      }
      final remoteEpoch = snapshot.data()?['occurrenceHistoryEpoch'] is Map
          ? ScheduledOccurrenceHistoryEpoch.fromJson(
              Map<String, Object?>.from(
                snapshot.data()!['occurrenceHistoryEpoch'] as Map,
              ),
            )
          : ScheduledOccurrenceHistoryEpoch.legacy;
      final winner = authoritativeOccurrenceHistoryEpoch(
        remoteEpoch,
        incomingEpoch,
      );
      if (!sameOccurrenceHistoryEpoch(winner, incomingEpoch)) {
        throw StateError(
          'Scheduled history changed on another device. Sync and try again.',
        );
      }
      if (sameOccurrenceHistoryEpoch(remoteEpoch, incomingEpoch)) return;

      final data = _scheduledDefinitionJson(scheduledTransaction)
        ..['occurrenceHistoryEpoch'] = incomingEpoch.toJson()
        ..['occurrenceStates'] = {
          for (final entry in scheduledTransaction.occurrenceStates.entries)
            entry.key: entry.value.toJson(),
        }
        ..['occurrences'] = scheduledTransaction.occurrences
            .map((occurrence) => occurrence.toJson())
            .toList()
        ..[_cloudUpdatedAtField] = FieldValue.serverTimestamp();
      _updateSyncMetrics(uploadedDelta: 1, writeDelta: 1);
      transaction.update(reference, data);
    });
  }

  @override
  Future<void> saveBudget({
    required String userId,
    required BudgetRecord budget,
  }) async {
    await _saveRecord(userId, 'budgets', budget.id, budget.toJson());
  }

  @override
  Future<void> saveGoal({
    required String userId,
    required GoalRecord goal,
  }) async {
    await _saveRecord(userId, 'goals', goal.id, goal.toJson());
  }

  @override
  Future<void> saveGoalContribution({
    required String userId,
    required GoalContributionRecord contribution,
  }) async {
    await _saveRecord(
      userId,
      'goalContributions',
      contribution.id,
      contribution.toJson(),
    );
  }

  @override
  Future<void> saveGoalFundingEvent({
    required String userId,
    required GoalFundingEventRecord fundingEvent,
  }) async {
    await _saveRecord(
      userId,
      'goalFundingEvents',
      fundingEvent.id,
      fundingEvent.toJson(),
    );
  }

  @override
  Future<void> saveFund({
    required String userId,
    required FundRecord fund,
  }) async {
    await _saveRecord(userId, 'funds', fund.id, fund.toJson());
  }

  @override
  Future<void> saveReservationOperation({
    required String userId,
    required ReservationOperationRecord operation,
  }) async {
    final generation = await _activeGeneration(userId);
    final reference = generation == null
        ? _collection(userId, 'reservationOperations')
        : _generationCollection(userId, generation, 'reservationOperations');
    final documentId = generation == null
        ? operation.id
        : _encodedDocumentId(operation.id);
    final document = reference.doc(documentId);
    await firestore.runTransaction((transaction) async {
      final existingSnapshot = await transaction.get(document);
      if (existingSnapshot.exists) {
        final existing = ReservationOperationRecord.fromJson(
          Map<String, Object?>.from(existingSnapshot.data()!),
        );
        if (!_sameImmutableReservationOperation(existing, operation)) {
          throw StateError(
            'Reservation operation ${operation.id} is immutable and already exists with different content.',
          );
        }
        return;
      }
      transaction.set(document, _cloudWriteJson(operation.toJson()));
    });
  }

  @override
  Future<void> savePreferences({
    required String userId,
    required UserPreferences preferences,
  }) async {
    final generation = await _activeGeneration(userId);
    final document = generation == null
        ? _preferencesDoc(userId)
        : _generationPreferencesDoc(userId, generation);
    await document.set(
      _cloudWriteJson(preferences.toJson()),
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> saveDataSet({
    required String userId,
    required FinanceDataSet dataSet,
    FinanceDataSet? baseline,
  }) async {
    final generation = await _activeGeneration(userId);
    final writes = <_GenerationWrite>[];
    final changedFieldsByCollection = <String, Map<String, int>>{};

    void recordChangedFields(
      String collection,
      Map<String, Object?>? baseline,
      Map<String, Object?> current,
    ) {
      final fields = changedFieldsByCollection.putIfAbsent(
        collection,
        () => <String, int>{},
      );
      final keys = <String>{...?baseline?.keys, ...current.keys};
      for (final key in keys) {
        final before = baseline?[key];
        final after = current[key];
        if (jsonEncode(before) == jsonEncode(after)) continue;
        fields.update(key, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    void addRecords<T>(
      String collection,
      Iterable<T> records,
      Iterable<T> baselineRecords,
      String Function(T record) idOf,
      Map<String, Object?> Function(T record) jsonOf,
    ) {
      final baselineJsonById = {
        for (final record in baselineRecords) idOf(record): jsonOf(record),
      };
      for (final record in records) {
        final id = idOf(record);
        final data = jsonOf(record);
        final baselineData = baselineJsonById[id];
        if (baselineData != null &&
            jsonEncode(baselineData) == jsonEncode(data)) {
          continue;
        }
        recordChangedFields(collection, baselineData, data);
        final reference = generation == null
            ? _collection(userId, collection).doc(id)
            : _generationCollection(
                userId,
                generation,
                collection,
              ).doc(_encodedDocumentId(id));
        writes.add(
          _GenerationWrite(
            collection: collection,
            reference: reference,
            data: _cloudWriteJson(data),
          ),
        );
      }
    }

    addRecords(
      'accounts',
      dataSet.accounts,
      baseline?.accounts ?? const <AccountRecord>[],
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'categories',
      dataSet.categories,
      baseline?.categories ?? const <CategoryRecord>[],
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'transactions',
      dataSet.transactions,
      baseline?.transactions ?? const <TransactionRecord>[],
      (item) => item.id,
      (item) => item.toJson(),
    );
    final baselineSchedulesById = {
      for (final schedule
          in baseline?.scheduledTransactions ??
              const <ScheduledTransactionRecord>[])
        schedule.id: schedule,
    };
    addRecords(
      'scheduledTransactions',
      dataSet.scheduledTransactions,
      baseline?.scheduledTransactions ?? const <ScheduledTransactionRecord>[],
      (item) => item.id,
      // Definition-only writes intentionally cannot overwrite occurrence
      // authority on an existing cloud schedule. A schedule that is absent
      // from the remote baseline, however, must be created with its epoch and
      // occurrence state atomically; otherwise the follow-up field-scoped
      // occurrence write sees a legacy epoch and correctly rejects it.
      (item) => scheduledCloudJsonForSync(
        scheduledTransaction: item,
        existsInRemoteBaseline: baselineSchedulesById.containsKey(item.id),
      ),
    );
    addRecords(
      'budgets',
      dataSet.budgets,
      baseline?.budgets ?? const <BudgetRecord>[],
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'goals',
      dataSet.goals,
      baseline?.goals ?? const <GoalRecord>[],
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'goalContributions',
      dataSet.goalContributions,
      baseline?.goalContributions ?? const <GoalContributionRecord>[],
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'goalFundingEvents',
      dataSet.goalFundingEvents,
      baseline?.goalFundingEvents ?? const <GoalFundingEventRecord>[],
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'funds',
      dataSet.funds,
      baseline?.funds ?? const <FundRecord>[],
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'reservationOperations',
      dataSet.reservationOperations,
      baseline?.reservationOperations ?? const <ReservationOperationRecord>[],
      (item) => item.id,
      (item) => item.toJson(),
    );
    // Preferences are intentionally device-local during normal data-set
    // merges (see mergeFinanceDataSetsPreferCurrent). Explicit user changes
    // are published by savePreferences, while authoritative restore writes
    // use replaceDataSetAuthoritatively. Including a device's retained local
    // preferences in routine bulk reconciliation makes devices overwrite one
    // another at every launch.

    debugPrint('Cloud sync upload: ${writes.length} documents');
    final uploadedByCollection = <String, int>{};
    for (final write in writes) {
      uploadedByCollection.update(
        write.collection,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    debugPrint('Cloud sync upload breakdown: $uploadedByCollection');
    _updateSyncMetrics(
      uploadedDelta: writes.length,
      writeDelta: writes.length,
      uploadedByCollectionDelta: uploadedByCollection,
      changedFieldsByCollectionDelta: changedFieldsByCollection,
    );
    for (
      var offset = 0;
      offset < writes.length;
      offset += _normalSyncWriteConcurrency
    ) {
      final end = (offset + _normalSyncWriteConcurrency).clamp(
        0,
        writes.length,
      );
      debugPrint('Cloud sync upload: saving documents $offset–${end - 1}');
      await Future.wait(
        writes
            .sublist(offset, end)
            .map(
              (write) =>
                  write.reference.set(write.data, SetOptions(merge: true)),
            ),
      );
      debugPrint('Cloud sync upload: saved documents $offset–${end - 1}');
    }
    for (final schedule in dataSet.scheduledTransactions) {
      final baselineSchedule = baselineSchedulesById[schedule.id];
      if (baselineSchedule == null) continue;
      if (!shouldAdvanceScheduledHistoryEpoch(
        scheduledTransaction: schedule,
        remoteBaseline: baselineSchedule,
      )) {
        continue;
      }
      // A normal definition write must never overwrite occurrence authority.
      // When the merged data set carries a newer history epoch, advance it
      // through the dedicated transactional reset before writing states that
      // belong to that epoch.
      await saveScheduledHistoryReset(
        userId: userId,
        scheduledTransaction: schedule,
      );
    }
    for (final schedule in dataSet.scheduledTransactions) {
      final baselineSchedule = baselineSchedulesById[schedule.id];
      // New schedules carry their occurrence state in the atomic create above.
      if (baselineSchedule == null) continue;
      final baselineAuthority = occurrenceAuthorityFor(baselineSchedule);
      for (final entry in occurrenceAuthorityFor(schedule).entries) {
        final previous = baselineAuthority[entry.key];
        if (previous != null &&
            jsonEncode(previous.toJson()) == jsonEncode(entry.value.toJson())) {
          continue;
        }
        await saveScheduledOccurrenceState(
          userId: userId,
          scheduledTransactionId: schedule.id,
          dayKey: entry.key,
          occurrenceState: entry.value,
        );
      }
    }
  }

  @override
  Future<String> replaceDataSetAuthoritatively({
    required String userId,
    required FinanceDataSet dataSet,
  }) async {
    final generation =
        'restore_${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}';
    final writes = <_GenerationWrite>[];

    void addRecords<T>(
      String collection,
      Iterable<T> records,
      String Function(T record) idOf,
      Map<String, Object?> Function(T record) jsonOf,
    ) {
      for (final record in records) {
        writes.add(
          _GenerationWrite(
            collection: collection,
            reference: _generationCollection(
              userId,
              generation,
              collection,
            ).doc(_encodedDocumentId(idOf(record))),
            data: _cloudWriteJson(jsonOf(record)),
          ),
        );
      }
    }

    addRecords(
      'accounts',
      dataSet.accounts,
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'categories',
      dataSet.categories,
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'transactions',
      dataSet.transactions,
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'scheduledTransactions',
      dataSet.scheduledTransactions,
      (item) => item.id,
      (item) => _scheduledCloudJson(item),
    );
    addRecords(
      'budgets',
      dataSet.budgets,
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'goals',
      dataSet.goals,
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'goalContributions',
      dataSet.goalContributions,
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'goalFundingEvents',
      dataSet.goalFundingEvents,
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'funds',
      dataSet.funds,
      (item) => item.id,
      (item) => item.toJson(),
    );
    addRecords(
      'reservationOperations',
      dataSet.reservationOperations,
      (item) => item.id,
      (item) => item.toJson(),
    );
    writes.add(
      _GenerationWrite(
        collection: 'preferences',
        reference: _generationPreferencesDoc(userId, generation),
        data: _cloudWriteJson(dataSet.preferences.toJson()),
      ),
    );

    for (var offset = 0; offset < writes.length; offset += _batchWriteLimit) {
      final batch = firestore.batch();
      final end = (offset + _batchWriteLimit).clamp(0, writes.length);
      for (final write in writes.sublist(offset, end)) {
        batch.set(write.reference, write.data);
      }
      await batch.commit();
    }

    // This single marker write is the authority boundary. Staged records are
    // invisible to normal loads until every preceding batch has succeeded.
    await _authorityDoc(userId).set({
      'activeGeneration': generation,
      'activatedAt': FieldValue.serverTimestamp(),
    });
    _activeGenerations[userId] = generation;
    return generation;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadCollection(
    String userId,
    String collection,
    String? generation,
  ) {
    final reference = _collection(userId, collection);
    return generation == null
        ? reference.get(const GetOptions(source: Source.server))
        : _generationCollection(
            userId,
            generation,
            collection,
          ).get(const GetOptions(source: Source.server));
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadChangedCollection(
    String userId,
    String collection,
    String? generation, {
    required DateTime after,
    required DateTime through,
  }) {
    final reference = generation == null
        ? _collection(userId, collection)
        : _generationCollection(userId, generation, collection);
    return reference
        .where(_cloudUpdatedAtField, isGreaterThan: Timestamp.fromDate(after))
        .where(
          _cloudUpdatedAtField,
          isLessThanOrEqualTo: Timestamp.fromDate(through),
        )
        .get(const GetOptions(source: Source.server));
  }

  Future<String?> _loadActiveGeneration(String userId) async {
    await firestore.enableNetwork();
    _updateSyncMetrics(readDelta: 1);
    final snapshot = await _authorityDoc(
      userId,
    ).get(const GetOptions(source: Source.server));
    final value = snapshot.data()?['activeGeneration'];
    if (value != null && (value is! String || value.trim().isEmpty)) {
      throw StateError('Invalid Trackmark cloud restore authority marker');
    }
    final generation = value as String?;
    _activeGenerations[userId] = generation;
    return generation;
  }

  Future<String?> _activeGeneration(String userId) async {
    if (_activeGenerations.containsKey(userId)) {
      return _activeGenerations[userId];
    }
    return _loadActiveGeneration(userId);
  }

  Future<void> _saveRecord(
    String userId,
    String collection,
    String id,
    Map<String, Object?> json,
  ) async {
    final generation = await _activeGeneration(userId);
    final reference = generation == null
        ? _collection(userId, collection)
        : _generationCollection(userId, generation, collection);
    final documentId = generation == null ? id : _encodedDocumentId(id);
    await reference
        .doc(documentId)
        .set(_cloudWriteJson(json), SetOptions(merge: true));
  }

  Map<String, Object?> _cloudWriteJson(Map<String, Object?> json) {
    return Map<String, Object?>.from(json)
      ..[_cloudUpdatedAtField] = FieldValue.serverTimestamp();
  }

  String _encodedDocumentId(String recordId) {
    final encodedId = base64Url
        .encode(utf8.encode(recordId))
        .replaceAll('=', '');
    return encodedId;
  }
}

bool _sameImmutableReservationOperation(
  ReservationOperationRecord left,
  ReservationOperationRecord right,
) {
  return left.id == right.id &&
      left.containerType == right.containerType &&
      left.containerId == right.containerId &&
      left.fundingAccountId == right.fundingAccountId &&
      left.kind == right.kind &&
      left.amountMinor == right.amountMinor &&
      left.effectiveDate.toUtc() == right.effectiveDate.toUtc() &&
      left.revision == right.revision &&
      left.baseRevision == right.baseRevision &&
      left.operationId == right.operationId &&
      left.deviceId == right.deviceId &&
      left.transactionId == right.transactionId &&
      left.scheduledTransactionId == right.scheduledTransactionId &&
      left.scheduledOccurrenceDate?.toUtc() ==
          right.scheduledOccurrenceDate?.toUtc() &&
      left.reversesOperationId == right.reversesOperationId &&
      left.causationId == right.causationId &&
      left.note == right.note;
}

class _IncrementalSyncCache {
  const _IncrementalSyncCache({
    required this.generation,
    required this.through,
    required this.dataSet,
    required this.fullBootstrapAt,
  });

  final String? generation;
  final DateTime through;
  final FinanceDataSet dataSet;
  final DateTime fullBootstrapAt;
}

class _IncrementalCacheLoadResult {
  const _IncrementalCacheLoadResult({this.cache, this.missReason});

  final _IncrementalSyncCache? cache;
  final String? missReason;
}

@visibleForTesting
FinanceDataSet applyRemoteDataSetDelta(
  FinanceDataSet baseline,
  FinanceDataSet delta,
) {
  List<T> merge<T>(
    List<T> current,
    List<T> changed,
    String Function(T item) idOf,
  ) {
    final byId = <String, T>{for (final item in current) idOf(item): item};
    for (final item in changed) {
      byId[idOf(item)] = item;
    }
    return byId.values.toList(growable: false);
  }

  return FinanceDataSet(
    accounts: merge(baseline.accounts, delta.accounts, (item) => item.id),
    categories: merge(baseline.categories, delta.categories, (item) => item.id),
    transactions: merge(
      baseline.transactions,
      delta.transactions,
      (item) => item.id,
    ),
    scheduledTransactions: merge(
      baseline.scheduledTransactions,
      delta.scheduledTransactions,
      (item) => item.id,
    ),
    budgets: merge(baseline.budgets, delta.budgets, (item) => item.id),
    goals: merge(baseline.goals, delta.goals, (item) => item.id),
    funds: merge(baseline.funds, delta.funds, (item) => item.id),
    reservationOperations: merge(
      baseline.reservationOperations,
      delta.reservationOperations,
      (item) => item.id,
    ),
    goalContributions: merge(
      baseline.goalContributions,
      delta.goalContributions,
      (item) => item.id,
    ),
    goalFundingEvents: merge(
      baseline.goalFundingEvents,
      delta.goalFundingEvents,
      (item) => item.id,
    ),
    preferences: delta.preferences,
  );
}

class _GenerationWrite {
  const _GenerationWrite({
    required this.collection,
    required this.reference,
    required this.data,
  });

  final String collection;
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, Object?> data;
}
