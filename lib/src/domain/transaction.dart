import 'json_helpers.dart';
import 'sync_metadata.dart';

/// [goalFunding] is intentionally a scheduled-only kind. It is never offered
/// by the immediate transaction segmented control and does not create a
/// [TransactionRecord]; completed Goal funding is represented by a
/// [GoalFundingEventRecord].
enum TransactionType { expense, income, transfer, goalFunding, adjustment }

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

/// Resolves the category allocation shape used by every financial consumer.
///
/// Older records and the former category-first form can contain a single split
/// line that simply mirrors [categoryId]. That is still a valid *single*
/// category allocation, not a category split. Empty and zero-value lines are
/// ignored, and duplicate category lines are consolidated so callers never
/// double-count a transaction.
List<TransactionSplitLine> resolveEffectiveCategoryAllocations({
  required TransactionType type,
  required String? categoryId,
  required int amountMinor,
  required Iterable<TransactionSplitLine> splitLines,
}) {
  if (type != TransactionType.expense && type != TransactionType.income) {
    return const [];
  }

  final resolved = <String, TransactionSplitLine>{};
  for (final line in splitLines) {
    final normalizedCategoryId = line.categoryId.trim();
    final normalizedAmount = line.amountMinor.abs();
    if (normalizedCategoryId.isEmpty || normalizedAmount == 0) continue;

    final existing = resolved[normalizedCategoryId];
    resolved[normalizedCategoryId] = TransactionSplitLine(
      id: existing?.id ?? line.id,
      categoryId: normalizedCategoryId,
      amountMinor: (existing?.amountMinor ?? 0) + normalizedAmount,
      note: existing?.note ?? line.note,
    );
  }

  if (resolved.isNotEmpty) return resolved.values.toList(growable: false);

  final normalizedPrimaryCategoryId = categoryId?.trim() ?? '';
  if (normalizedPrimaryCategoryId.isEmpty || amountMinor.abs() == 0) {
    return const [];
  }
  return [
    TransactionSplitLine(
      id: '',
      categoryId: normalizedPrimaryCategoryId,
      amountMinor: amountMinor.abs(),
    ),
  ];
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
    this.scheduledOccurrenceDate,
    this.scheduledPlannedAmountMinor,
    this.goalFundingEventId,
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
  final DateTime? scheduledOccurrenceDate;
  final int? scheduledPlannedAmountMinor;
  final String? goalFundingEventId;
  final SyncMetadata sync;

  bool get isDeleted => sync.isDeleted;
  List<TransactionSplitLine> get effectiveCategoryAllocations {
    return resolveEffectiveCategoryAllocations(
      type: type,
      categoryId: categoryId,
      amountMinor: amountMinor,
      splitLines: splitLines,
    );
  }

  /// True only when this transaction allocates value to multiple effective
  /// categories. This deliberately does not describe raw persistence shape.
  bool get isCategorySplit => effectiveCategoryAllocations.length > 1;

  /// Backward-compatible name for presentation code. New consumers should
  /// prefer [isCategorySplit] when clarity matters.
  bool get isSplit => isCategorySplit;
  bool get isTransfer => type == TransactionType.transfer;

  int get splitTotalMinor {
    return effectiveCategoryAllocations.fold(
      0,
      (total, line) => total + line.amountMinor,
    );
  }

  bool get hasStoredCategoryAllocationPayload {
    return splitLines.any(
      (line) => line.categoryId.trim().isNotEmpty && line.amountMinor != 0,
    );
  }

  bool get hasValidSplitTotal {
    return !hasStoredCategoryAllocationPayload ||
        splitTotalMinor == amountMinor.abs();
  }

  int deltaForAccount(String targetAccountId) {
    return switch (type) {
      TransactionType.expense =>
        targetAccountId == accountId ? -amountMinor.abs() : 0,
      TransactionType.income =>
        targetAccountId == accountId ? amountMinor.abs() : 0,
      TransactionType.adjustment =>
        targetAccountId == accountId ? amountMinor : 0,
      TransactionType.goalFunding => 0,
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
    DateTime? scheduledOccurrenceDate,
    int? scheduledPlannedAmountMinor,
    String? goalFundingEventId,
    SyncMetadata? sync,
    bool clearTransferAccount = false,
    bool clearCategory = false,
    bool clearScheduledTransaction = false,
    bool clearGoalFundingEvent = false,
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
      scheduledOccurrenceDate: clearScheduledTransaction
          ? null
          : scheduledOccurrenceDate ?? this.scheduledOccurrenceDate,
      scheduledPlannedAmountMinor: clearScheduledTransaction
          ? null
          : scheduledPlannedAmountMinor ?? this.scheduledPlannedAmountMinor,
      goalFundingEventId: clearGoalFundingEvent
          ? null
          : goalFundingEventId ?? this.goalFundingEventId,
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
      'scheduledOccurrenceDate': scheduledOccurrenceDate?.toIso8601String(),
      'scheduledPlannedAmountMinor': scheduledPlannedAmountMinor,
      'goalFundingEventId': goalFundingEventId,
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
      scheduledOccurrenceDate: json['scheduledOccurrenceDate'] == null
          ? null
          : dateTimeFromJson(json['scheduledOccurrenceDate']),
      scheduledPlannedAmountMinor: json['scheduledPlannedAmountMinor'] as int?,
      goalFundingEventId: json['goalFundingEventId'] as String?,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
