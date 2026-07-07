import 'json_helpers.dart';
import 'sync_metadata.dart';

enum TransactionType { expense, income, transfer, adjustment }

enum TransactionStatus { pending, cleared, reconciled }

class TransactionSplitLine {
  const TransactionSplitLine({
    required this.id,
    required this.categoryId,
    required this.amountMinor,
    this.note = '',
  });

  final String id;
  final String categoryId;
  final int amountMinor;
  final String note;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'categoryId': categoryId,
      'amountMinor': amountMinor,
      'note': note,
    };
  }

  factory TransactionSplitLine.fromJson(Map<String, Object?> json) {
    return TransactionSplitLine(
      id: json['id'] as String,
      categoryId: json['categoryId'] as String,
      amountMinor: json['amountMinor'] as int? ?? 0,
      note: json['note'] as String? ?? '',
    );
  }
}

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.type,
    required this.accountId,
    required this.date,
    required this.payee,
    required this.amountMinor,
    required this.sync,
    this.transferAccountId,
    this.categoryId,
    this.note = '',
    this.status = TransactionStatus.cleared,
    this.splitLines = const [],
    this.scheduledTransactionId,
  });

  final String id;
  final TransactionType type;
  final String accountId;
  final String? transferAccountId;
  final String? categoryId;
  final DateTime date;
  final String payee;
  final int amountMinor;
  final String note;
  final TransactionStatus status;
  final List<TransactionSplitLine> splitLines;
  final String? scheduledTransactionId;
  final SyncMetadata sync;

  bool get isDeleted => sync.isDeleted;
  bool get isSplit => splitLines.isNotEmpty;
  bool get isTransfer => type == TransactionType.transfer;

  int get splitTotalMinor {
    return splitLines.fold(0, (total, line) => total + line.amountMinor);
  }

  bool get hasValidSplitTotal {
    return !isSplit || splitTotalMinor == amountMinor.abs();
  }

  int deltaForAccount(String targetAccountId) {
    return switch (type) {
      TransactionType.expense =>
        targetAccountId == accountId ? -amountMinor.abs() : 0,
      TransactionType.income =>
        targetAccountId == accountId ? amountMinor.abs() : 0,
      TransactionType.adjustment =>
        targetAccountId == accountId ? amountMinor : 0,
      TransactionType.transfer =>
        targetAccountId == accountId
            ? -amountMinor.abs()
            : targetAccountId == transferAccountId
            ? amountMinor.abs()
            : 0,
    };
  }

  TransactionRecord copyWith({
    TransactionType? type,
    String? accountId,
    String? transferAccountId,
    String? categoryId,
    DateTime? date,
    String? payee,
    int? amountMinor,
    String? note,
    TransactionStatus? status,
    List<TransactionSplitLine>? splitLines,
    String? scheduledTransactionId,
    SyncMetadata? sync,
    bool clearTransferAccount = false,
    bool clearCategory = false,
    bool clearScheduledTransaction = false,
  }) {
    return TransactionRecord(
      id: id,
      type: type ?? this.type,
      accountId: accountId ?? this.accountId,
      transferAccountId: clearTransferAccount
          ? null
          : transferAccountId ?? this.transferAccountId,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      date: date ?? this.date,
      payee: payee ?? this.payee,
      amountMinor: amountMinor ?? this.amountMinor,
      note: note ?? this.note,
      status: status ?? this.status,
      splitLines: splitLines ?? this.splitLines,
      scheduledTransactionId: clearScheduledTransaction
          ? null
          : scheduledTransactionId ?? this.scheduledTransactionId,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.name,
      'accountId': accountId,
      'transferAccountId': transferAccountId,
      'categoryId': categoryId,
      'date': date.toIso8601String(),
      'payee': payee,
      'amountMinor': amountMinor,
      'note': note,
      'status': status.name,
      'splitLines': splitLines.map((line) => line.toJson()).toList(),
      'scheduledTransactionId': scheduledTransactionId,
      'sync': sync.toJson(),
    };
  }

  factory TransactionRecord.fromJson(Map<String, Object?> json) {
    return TransactionRecord(
      id: json['id'] as String,
      type: enumByName(
        TransactionType.values,
        json['type'],
        TransactionType.expense,
      ),
      accountId: json['accountId'] as String,
      transferAccountId: json['transferAccountId'] as String?,
      categoryId: json['categoryId'] as String?,
      date: dateTimeFromJson(json['date']),
      payee: json['payee'] as String? ?? '',
      amountMinor: json['amountMinor'] as int? ?? 0,
      note: json['note'] as String? ?? '',
      status: enumByName(
        TransactionStatus.values,
        json['status'],
        TransactionStatus.cleared,
      ),
      splitLines: stringMapList(
        json['splitLines'],
      ).map(TransactionSplitLine.fromJson).toList(),
      scheduledTransactionId: json['scheduledTransactionId'] as String?,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
