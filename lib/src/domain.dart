part of '../main.dart';

enum AccountType { cash, checking, savings, creditCard, loan }

enum CategoryKind { income, expense, transfer }

enum TransactionStatus { pending, cleared, reconciled }

enum RecurrenceFrequency { once, weekly, biweekly, monthly, yearly }

class SyncMetadata {
  const SyncMetadata({
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
    this.deletedAt,
    this.version = 1,
  });

  factory SyncMetadata.fresh({DateTime? now, String deviceId = 'local'}) {
    final timestamp = now ?? DateTime.now();
    return SyncMetadata(
      createdAt: timestamp,
      updatedAt: timestamp,
      deviceId: deviceId,
    );
  }

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final int version;

  bool get isDeleted => deletedAt != null;

  SyncMetadata touched({DateTime? now, String? deviceId}) {
    return SyncMetadata(
      createdAt: createdAt,
      updatedAt: now ?? DateTime.now(),
      deletedAt: deletedAt,
      deviceId: deviceId ?? this.deviceId,
      version: version + 1,
    );
  }

  SyncMetadata deleted({DateTime? now, String? deviceId}) {
    final timestamp = now ?? DateTime.now();
    return SyncMetadata(
      createdAt: createdAt,
      updatedAt: timestamp,
      deletedAt: timestamp,
      deviceId: deviceId ?? this.deviceId,
      version: version + 1,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'deviceId': deviceId,
      'version': version,
    };
  }

  factory SyncMetadata.fromJson(Map<String, Object?>? json) {
    if (json == null) return SyncMetadata.fresh();
    return SyncMetadata(
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
      deviceId: json['deviceId'] as String? ?? 'local',
      version: json['version'] as int? ?? 1,
    );
  }
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.balanceCents,
    required this.sync,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final AccountType type;
  final int balanceCents;
  final bool isArchived;
  final SyncMetadata sync;

  Account copyWith({int? balanceCents, bool? isArchived}) {
    return Account(
      id: id,
      name: name,
      type: type,
      balanceCents: balanceCents ?? this.balanceCents,
      isArchived: isArchived ?? this.isArchived,
      sync: sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'balanceCents': balanceCents,
      'isArchived': isArchived,
      'sync': sync.toJson(),
    };
  }

  factory Account.fromJson(Map<String, Object?> json) {
    return Account(
      id: json['id'] as String,
      name: json['name'] as String,
      type: enumFromName(AccountType.values, json['type'] as String),
      balanceCents: json['balanceCents'] as int,
      isArchived: json['isArchived'] as bool? ?? false,
      sync: SyncMetadata.fromJson(jsonMapOrNull(json['sync'])),
    );
  }
}

class LedgerCategory {
  const LedgerCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.color,
    required this.sync,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final CategoryKind kind;
  final Color color;
  final bool isArchived;
  final SyncMetadata sync;

  LedgerCategory copyWith({String? name, bool? isArchived}) {
    return LedgerCategory(
      id: id,
      name: name ?? this.name,
      kind: kind,
      color: color,
      isArchived: isArchived ?? this.isArchived,
      sync: sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind.name,
      'color': color.toARGB32(),
      'isArchived': isArchived,
      'sync': sync.toJson(),
    };
  }

  factory LedgerCategory.fromJson(Map<String, Object?> json) {
    return LedgerCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: enumFromName(CategoryKind.values, json['kind'] as String),
      color: Color(json['color'] as int),
      isArchived: json['isArchived'] as bool? ?? false,
      sync: SyncMetadata.fromJson(jsonMapOrNull(json['sync'])),
    );
  }
}

class LedgerTransaction {
  const LedgerTransaction({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.date,
    required this.payee,
    required this.amountCents,
    required this.sync,
    this.note = '',
    this.status = TransactionStatus.cleared,
    this.isTransfer = false,
  });

  final String id;
  final String accountId;
  final String categoryId;
  final DateTime date;
  final String payee;
  final int amountCents;
  final String note;
  final TransactionStatus status;
  final bool isTransfer;
  final SyncMetadata sync;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'accountId': accountId,
      'categoryId': categoryId,
      'date': date.toIso8601String(),
      'payee': payee,
      'amountCents': amountCents,
      'note': note,
      'status': status.name,
      'isTransfer': isTransfer,
      'sync': sync.toJson(),
    };
  }

  factory LedgerTransaction.fromJson(Map<String, Object?> json) {
    return LedgerTransaction(
      id: json['id'] as String,
      accountId: json['accountId'] as String,
      categoryId: json['categoryId'] as String,
      date: DateTime.parse(json['date'] as String),
      payee: json['payee'] as String,
      amountCents: json['amountCents'] as int,
      note: json['note'] as String? ?? '',
      status: enumFromName(
        TransactionStatus.values,
        json['status'] as String? ?? TransactionStatus.cleared.name,
      ),
      isTransfer: json['isTransfer'] as bool? ?? false,
      sync: SyncMetadata.fromJson(jsonMapOrNull(json['sync'])),
    );
  }
}

class ScheduledTransaction {
  const ScheduledTransaction({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.payee,
    required this.amountCents,
    required this.nextDate,
    required this.frequency,
    required this.sync,
    this.alertEnabled = true,
    this.autoPost = false,
  });

  final String id;
  final String accountId;
  final String categoryId;
  final String payee;
  final int amountCents;
  final DateTime nextDate;
  final RecurrenceFrequency frequency;
  final bool alertEnabled;
  final bool autoPost;
  final SyncMetadata sync;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'accountId': accountId,
      'categoryId': categoryId,
      'payee': payee,
      'amountCents': amountCents,
      'nextDate': nextDate.toIso8601String(),
      'frequency': frequency.name,
      'alertEnabled': alertEnabled,
      'autoPost': autoPost,
      'sync': sync.toJson(),
    };
  }

  factory ScheduledTransaction.fromJson(Map<String, Object?> json) {
    return ScheduledTransaction(
      id: json['id'] as String,
      accountId: json['accountId'] as String,
      categoryId: json['categoryId'] as String,
      payee: json['payee'] as String,
      amountCents: json['amountCents'] as int,
      nextDate: DateTime.parse(json['nextDate'] as String),
      frequency: enumFromName(
        RecurrenceFrequency.values,
        json['frequency'] as String,
      ),
      alertEnabled: json['alertEnabled'] as bool? ?? true,
      autoPost: json['autoPost'] as bool? ?? false,
      sync: SyncMetadata.fromJson(jsonMapOrNull(json['sync'])),
    );
  }
}

class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.monthlyLimitCents,
    required this.sync,
  });

  final String id;
  final String categoryId;
  final int monthlyLimitCents;
  final SyncMetadata sync;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'categoryId': categoryId,
      'monthlyLimitCents': monthlyLimitCents,
      'sync': sync.toJson(),
    };
  }

  factory Budget.fromJson(Map<String, Object?> json) {
    return Budget(
      id: json['id'] as String,
      categoryId: json['categoryId'] as String,
      monthlyLimitCents: json['monthlyLimitCents'] as int,
      sync: SyncMetadata.fromJson(jsonMapOrNull(json['sync'])),
    );
  }
}

T enumFromName<T extends Enum>(List<T> values, String name) {
  return values.firstWhere((value) => value.name == name);
}

List<Map<String, Object?>> jsonList(Object? value) {
  return (value as List<Object?>? ?? const [])
      .cast<Map<Object?, Object?>>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList();
}

Map<String, Object?>? jsonMapOrNull(Object? value) {
  if (value == null) return null;
  return (value as Map<Object?, Object?>).map(
    (key, value) => MapEntry(key.toString(), value),
  );
}
