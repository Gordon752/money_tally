part of '../main.dart';

abstract interface class FinanceRemoteRepository {
  Future<FinanceSnapshot?> loadSnapshot({required String userId});

  Future<void> saveSnapshot({
    required String userId,
    required FinanceSnapshot snapshot,
  });
}

class FirestoreFinanceRepository implements FinanceRemoteRepository {
  FirestoreFinanceRepository({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      firestore.collection('users');

  DocumentReference<Map<String, dynamic>> _snapshotDoc(String userId) {
    return _users.doc(userId).collection('finance').doc('snapshot');
  }

  @override
  Future<FinanceSnapshot?> loadSnapshot({required String userId}) async {
    final document = await _snapshotDoc(userId).get();
    final data = document.data();
    if (data == null) return null;
    return FinanceSnapshot.fromJson(data);
  }

  @override
  Future<void> saveSnapshot({
    required String userId,
    required FinanceSnapshot snapshot,
  }) async {
    await _snapshotDoc(userId).set({
      ...snapshot.toJson(),
      'syncedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
