import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/goal.dart';
import '../domain/goal_funding.dart';
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

class FirestoreRecordRepository
    implements
        FinanceRecordRepository,
        BulkFinanceRecordRepository,
        ScheduledOccurrenceStateRepository {
  FirestoreRecordRepository({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;
  final Map<String, String?> _activeGenerations = {};

  static const _batchWriteLimit = 400;
  static const _normalSyncWriteConcurrency = 8;

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
    final results = await Future.wait([
      _loadCollection(userId, 'accounts', generation),
      _loadCollection(userId, 'categories', generation),
      _loadCollection(userId, 'transactions', generation),
      _loadCollection(userId, 'scheduledTransactions', generation),
      _loadCollection(userId, 'budgets', generation),
      _loadCollection(userId, 'goals', generation),
      _loadCollection(userId, 'goalContributions', generation),
      _loadCollection(userId, 'goalFundingEvents', generation),
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
    final preferencesSnapshot =
        results[8] as DocumentSnapshot<Map<String, dynamic>>;

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
      preferences: preferencesSnapshot.data() == null
          ? const UserPreferences()
          : UserPreferences.fromJson(preferencesSnapshot.data()!),
    );
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
    return firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw StateError(
          'The scheduled transaction is unavailable for occurrence update.',
        );
      }
      final rawStates = snapshot.data()?['occurrenceStates'];
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
        transaction.update(reference, {
          'occurrenceStates.$dayKey': occurrenceState.toJson(),
        });
      }
      return winner;
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
  Future<void> savePreferences({
    required String userId,
    required UserPreferences preferences,
  }) async {
    final generation = await _activeGeneration(userId);
    final document = generation == null
        ? _preferencesDoc(userId)
        : _generationPreferencesDoc(userId, generation);
    await document.set(preferences.toJson(), SetOptions(merge: true));
  }

  @override
  Future<void> saveDataSet({
    required String userId,
    required FinanceDataSet dataSet,
    FinanceDataSet? baseline,
  }) async {
    final generation = await _activeGeneration(userId);
    final writes = <_GenerationWrite>[];

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
        final reference = generation == null
            ? _collection(userId, collection).doc(id)
            : _generationCollection(
                userId,
                generation,
                collection,
              ).doc(_encodedDocumentId(id));
        writes.add(_GenerationWrite(reference: reference, data: data));
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
    addRecords(
      'scheduledTransactions',
      dataSet.scheduledTransactions,
      baseline?.scheduledTransactions ?? const <ScheduledTransactionRecord>[],
      (item) => item.id,
      (item) => _scheduledDefinitionJson(item),
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
    final preferencesJson = dataSet.preferences.toJson();
    if (baseline == null ||
        jsonEncode(baseline.preferences.toJson()) !=
            jsonEncode(preferencesJson)) {
      writes.add(
        _GenerationWrite(
          reference: generation == null
              ? _preferencesDoc(userId)
              : _generationPreferencesDoc(userId, generation),
          data: preferencesJson,
        ),
      );
    }

    debugPrint('Cloud sync upload: ${writes.length} documents');
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
      for (final entry in occurrenceAuthorityFor(schedule).entries) {
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
            reference: _generationCollection(
              userId,
              generation,
              collection,
            ).doc(_encodedDocumentId(idOf(record))),
            data: jsonOf(record),
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
    writes.add(
      _GenerationWrite(
        reference: _generationPreferencesDoc(userId, generation),
        data: dataSet.preferences.toJson(),
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

  Future<String?> _loadActiveGeneration(String userId) async {
    await firestore.enableNetwork();
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
    await reference.doc(documentId).set(json, SetOptions(merge: true));
  }

  String _encodedDocumentId(String recordId) {
    final encodedId = base64Url
        .encode(utf8.encode(recordId))
        .replaceAll('=', '');
    return encodedId;
  }
}

class _GenerationWrite {
  const _GenerationWrite({required this.reference, required this.data});

  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, Object?> data;
}
