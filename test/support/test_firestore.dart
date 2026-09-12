import 'package:cloud_firestore/cloud_firestore.dart';

class TestFirestore implements FirebaseFirestore {
  final records = <String, Map<String, dynamic>>{};
  int committedWrites = 0;
  bool failNextTransaction = false;
  final committedPayloads = <Map<String, dynamic>>[];
  int retries = 0;
  void Function()? beforeCommit;
  Future<void> Function()? beforeRead;
  @override
  Future<void> enableNetwork() async {}
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    if (failNextTransaction) {
      failNextTransaction = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    final transaction = _Transaction(this);
    final result = await transactionHandler(transaction);
    final change = beforeCommit;
    if (change != null) {
      beforeCommit = null;
      change();
      retries++;
      return runTransaction(
        transactionHandler,
        timeout: timeout,
        maxAttempts: maxAttempts - 1,
      );
    }
    records.addAll(transaction.writes);
    committedPayloads.addAll(transaction.payloads);
    committedWrites += transaction.writes.length;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Minimal deterministic test double; production uses the SDK transaction.
// ignore: subtype_of_sealed_class
class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.cloud, this.path, {this.onlyChanged = false});
  final TestFirestore cloud;
  final bool onlyChanged;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(cloud, '${this.path}/$path');
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _QuerySnapshot([
    if (!onlyChanged)
      for (final entry in cloud.records.entries)
        if (entry.key.startsWith('$path/') &&
            !entry.key.substring(path.length + 1).contains('/'))
          _QueryDocument(entry.value),
  ]);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return _Collection(cloud, path, onlyChanged: true);
    }
    return super.noSuchMethod(invocation);
  }
}

// ignore: subtype_of_sealed_class
class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.cloud, this.path);
  final TestFirestore cloud;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(cloud, '$path/$collectionPath');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Snapshot(cloud.records[path]);
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    cloud.records[path] = {...?cloud.records[path], ...data};
    if (data.containsKey('checkpointAt')) {
      cloud.records[path]!['checkpointAt'] = Timestamp.fromDate(
        DateTime.utc(2026, 9, 7),
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Snapshot<T> implements DocumentSnapshot<T> {
  _Snapshot(this.value);
  final T? value;
  @override
  bool get exists => value != null;
  @override
  T? data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transaction implements Transaction {
  _Transaction(this.cloud);
  final TestFirestore cloud;
  final writes = <String, Map<String, dynamic>>{};
  final payloads = <Map<String, dynamic>>[];
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    await cloud.beforeRead?.call();
    return _Snapshot<T>(cloud.records[documentReference.path] as T?);
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    payloads.add(Map<String, dynamic>.from(data as Map));
    writes[documentReference.path] = {
      ...?cloud.records[documentReference.path],
      ...data as Map<String, dynamic>,
    };
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _QuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _QueryDocument extends _Snapshot<Map<String, dynamic>>
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(Map<String, dynamic> super.value);
  @override
  Map<String, dynamic> data() => value!;
}
