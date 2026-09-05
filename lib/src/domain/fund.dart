import 'json_helpers.dart';
import 'sync_metadata.dart';

enum FundStatus { active, archived }

enum FundTargetCadence { none, monthly }

enum FundTargetDayRule { fixedDay, endOfMonth }

/// One non-persisted line in a batch Fund allocation request.
///
/// The resulting reservation operations remain the authoritative persisted
/// records; this value only carries input from the allocation workflow into
/// the store.
class FundAllocation {
  const FundAllocation({required this.fundId, required this.amountMinor});

  final String fundId;
  final int amountMinor;
}

class FundRecord {
  const FundRecord({
    required this.id,
    required this.name,
    required this.fundingAccountId,
    required this.status,
    required this.sync,
    this.description = '',
    this.targetBalanceMinor = 0,
    this.targetCadence = FundTargetCadence.none,
    this.targetDayRule = FundTargetDayRule.fixedDay,
    this.nextTargetDate,
    this.linkedAccountId,
    this.accentColorValue = 0xFF247C75,
    this.iconId,
  });

  final String id;
  final String name;
  final String description;
  final String fundingAccountId;
  final FundStatus status;
  final int targetBalanceMinor;
  final FundTargetCadence targetCadence;
  final FundTargetDayRule targetDayRule;
  final DateTime? nextTargetDate;

  /// Optional context such as the card or loan this Fund is intended to pay.
  /// It is never the source of reserved cash.
  final String? linkedAccountId;
  final int accentColorValue;
  final String? iconId;
  final SyncMetadata sync;

  bool get isDeleted => sync.isDeleted;
  bool get isActive => !isDeleted && status == FundStatus.active;
  bool get isArchived => !isDeleted && status == FundStatus.archived;

  FundRecord copyWith({
    String? name,
    String? description,
    String? fundingAccountId,
    FundStatus? status,
    int? targetBalanceMinor,
    FundTargetCadence? targetCadence,
    FundTargetDayRule? targetDayRule,
    DateTime? nextTargetDate,
    String? linkedAccountId,
    int? accentColorValue,
    String? iconId,
    SyncMetadata? sync,
    bool clearNextTargetDate = false,
    bool clearLinkedAccount = false,
    bool clearIcon = false,
  }) {
    return FundRecord(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      fundingAccountId: fundingAccountId ?? this.fundingAccountId,
      status: status ?? this.status,
      targetBalanceMinor: targetBalanceMinor ?? this.targetBalanceMinor,
      targetCadence: targetCadence ?? this.targetCadence,
      targetDayRule: targetDayRule ?? this.targetDayRule,
      nextTargetDate: clearNextTargetDate
          ? null
          : nextTargetDate ?? this.nextTargetDate,
      linkedAccountId: clearLinkedAccount
          ? null
          : linkedAccountId ?? this.linkedAccountId,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      iconId: clearIcon ? null : iconId ?? this.iconId,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'fundingAccountId': fundingAccountId,
    'status': status.name,
    'targetBalanceMinor': targetBalanceMinor,
    'targetCadence': targetCadence.name,
    'targetDayRule': targetDayRule.name,
    'nextTargetDate': nextTargetDate?.toIso8601String(),
    'linkedAccountId': linkedAccountId,
    'accentColorValue': accentColorValue,
    'iconId': iconId,
    'sync': sync.toJson(),
  };

  factory FundRecord.fromJson(Map<String, Object?> json) => FundRecord(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    fundingAccountId: json['fundingAccountId'] as String? ?? '',
    status: enumByName(FundStatus.values, json['status'], FundStatus.active),
    targetBalanceMinor: json['targetBalanceMinor'] as int? ?? 0,
    targetCadence: enumByName(
      FundTargetCadence.values,
      json['targetCadence'],
      FundTargetCadence.none,
    ),
    // Older records store a numeric anchor only. Never infer month-end intent.
    targetDayRule: enumByName(
      FundTargetDayRule.values,
      json['targetDayRule'],
      FundTargetDayRule.fixedDay,
    ),
    nextTargetDate: json['nextTargetDate'] == null
        ? null
        : dateTimeFromJson(json['nextTargetDate']),
    linkedAccountId: json['linkedAccountId'] as String?,
    accentColorValue: json['accentColorValue'] as int? ?? 0xFF247C75,
    iconId: json['iconId'] as String?,
    sync: SyncMetadata.fromJson(stringMap(json['sync'])),
  );
}

/// The single local-calendar boundary rule for recurring Fund presentation and
/// consumption attribution. Months outside 1..12 are normalized by DateTime.
/// Dates before the first target are also supported for the preceding funding
/// deadline; this does not advance or mutate the persisted recurrence anchor.
DateTime? fundTargetBoundary(
  FundRecord fund, {
  required int year,
  required int month,
}) {
  final anchor = fund.nextTargetDate;
  if (fund.targetCadence != FundTargetCadence.monthly || anchor == null) {
    return null;
  }
  final monthStart = DateTime(year, month, 1);
  final lastDay = DateTime(monthStart.year, monthStart.month + 1, 0).day;
  final day = fund.targetDayRule == FundTargetDayRule.endOfMonth
      ? lastDay
      : anchor.day.clamp(1, lastDay);
  return DateTime(monthStart.year, monthStart.month, day);
}

/// Resolves the next target checkpoint without changing or resetting money.
/// Fixed days always use the original anchor, restoring the 31st after February.
DateTime? effectiveFundTargetDate(FundRecord fund, {DateTime? asOf}) {
  final anchor = fund.nextTargetDate;
  if (fund.targetCadence == FundTargetCadence.none || anchor == null) {
    return null;
  }
  final todayValue = asOf ?? DateTime.now();
  final today = DateTime(todayValue.year, todayValue.month, todayValue.day);
  var monthOffset = 0;
  while (monthOffset < 1200) {
    final candidate = fundTargetBoundary(
      fund,
      year: anchor.year,
      month: anchor.month + monthOffset,
    )!;
    if (!candidate.isBefore(today)) return candidate;
    monthOffset += 1;
  }
  return null;
}
