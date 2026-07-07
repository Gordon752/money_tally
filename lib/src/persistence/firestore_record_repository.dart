import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/scheduled_transaction.dart';
import '../domain/transaction.dart';
import '../domain/user_preferences.dart';
import 'finance_record_repository.dart';

class FirestoreRecordRepository implements FinanceRecordRepository {
  FirestoreRecordRepository({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;

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

  @override
  Stream<FinanceDataSet> watchDataSet(String userId) async* {
    // Initial scaffold: emit full loads when callers subscribe. This keeps the
    // public contract stable while we decide whether to compose live collection
    // streams here or in a store layer.
    yield await loadDataSet(userId);
  }

  @override
  Future<FinanceDataSet> loadDataSet(String userId) async {
    final results = await Future.wait([
      _collection(userId, 'accounts').get(),
      _collection(userId, 'categories').get(),
      _collection(userId, 'transactions').get(),
      _collection(userId, 'scheduledTransactions').get(),
      _collection(userId, 'budgets').get(),
      _preferencesDoc(userId).get(),
    ]);

    final accountsSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final categoriesSnapshot =
        results[1] as QuerySnapshot<Map<String, dynamic>>;
    final transactionsSnapshot =
        results[2] as QuerySnapshot<Map<String, dynamic>>;
    final scheduledSnapshot = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final budgetsSnapshot = results[4] as QuerySnapshot<Map<String, dynamic>>;
    final preferencesSnapshot =
        results[5] as DocumentSnapshot<Map<String, dynamic>>;

    return FinanceDataSet(
      accounts: accountsSnapshot.docs
          .map((doc) => AccountRecord.fromJson(doc.data()))
          .where((item) => !item.sync.isDeleted)
          .toList(),
      categories: categoriesSnapshot.docs
          .map((doc) => CategoryRecord.fromJson(doc.data()))
          .where((item) => !item.sync.isDeleted)
          .toList(),
      transactions: transactionsSnapshot.docs
          .map((doc) => TransactionRecord.fromJson(doc.data()))
          .where((item) => !item.sync.isDeleted)
          .toList(),
      scheduledTransactions: scheduledSnapshot.docs
          .map((doc) => ScheduledTransactionRecord.fromJson(doc.data()))
          .where((item) => !item.sync.isDeleted)
          .toList(),
      budgets: budgetsSnapshot.docs
          .map((doc) => BudgetRecord.fromJson(doc.data()))
          .where((item) => !item.sync.isDeleted)
          .toList(),
      preferences: preferencesSnapshot.data() == null
          ? const UserPreferences()
          : UserPreferences.fromJson(preferencesSnapshot.data()!),
    );
  }

  @override
  Future<void> saveAccount({
    required String userId,
    required AccountRecord account,
  }) {
    return _collection(
      userId,
      'accounts',
    ).doc(account.id).set(account.toJson(), SetOptions(merge: true));
  }

  @override
  Future<void> saveCategory({
    required String userId,
    required CategoryRecord category,
  }) {
    return _collection(
      userId,
      'categories',
    ).doc(category.id).set(category.toJson(), SetOptions(merge: true));
  }

  @override
  Future<void> saveTransaction({
    required String userId,
    required TransactionRecord transaction,
  }) {
    return _collection(
      userId,
      'transactions',
    ).doc(transaction.id).set(transaction.toJson(), SetOptions(merge: true));
  }

  @override
  Future<void> saveScheduledTransaction({
    required String userId,
    required ScheduledTransactionRecord scheduledTransaction,
  }) {
    return _collection(userId, 'scheduledTransactions')
        .doc(scheduledTransaction.id)
        .set(scheduledTransaction.toJson(), SetOptions(merge: true));
  }

  @override
  Future<void> saveBudget({
    required String userId,
    required BudgetRecord budget,
  }) {
    return _collection(
      userId,
      'budgets',
    ).doc(budget.id).set(budget.toJson(), SetOptions(merge: true));
  }

  @override
  Future<void> savePreferences({
    required String userId,
    required UserPreferences preferences,
  }) {
    return _preferencesDoc(
      userId,
    ).set(preferences.toJson(), SetOptions(merge: true));
  }
}
