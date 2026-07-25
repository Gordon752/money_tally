import 'json_helpers.dart';
import 'sync_metadata.dart';

enum GoalStatus { active, completed, archived }

enum GoalFundingMethod { accountFunded, trackingOnly }

enum GoalType { reachTarget, maintainBalance }

class GoalRecord {
  const GoalRecord({
    required this.id,
    required this.name,
    required this.targetAmountMinor,
    required this.status,
    required this.fundingMethod,
    required this.sync,
    this.goalType = GoalType.reachTarget,
    this.description = '',
    this.startingAmountMinor = 0,
    this.targetDate,
    this.defaultFundingAccountId,
    this.accentColorValue = 0xFF367BF5,
    this.reservationsReleased = false,
    this.requiresFundingMigration = false,
  });

  final String id;
  final String name;
  final String description;
  final int targetAmountMinor;
  final int startingAmountMinor;
  final DateTime? targetDate;
  final GoalStatus status;
  final GoalFundingMethod fundingMethod;
  final GoalType goalType;
  final String? defaultFundingAccountId;
  final int accentColorValue;
  final bool reservationsReleased;
  final bool requiresFundingMigration;
  final SyncMetadata sync;

  DateTime get createdDate => sync.createdAt;
  DateTime get updatedDate => sync.updatedAt;
  bool get isDeleted => sync.isDeleted;
  bool get isActive =>
      !isDeleted &&
      (status == GoalStatus.active ||
          (goalType == GoalType.maintainBalance &&
              status == GoalStatus.completed));
  bool get isCompleted =>
      !isDeleted &&
      goalType == GoalType.reachTarget &&
      status == GoalStatus.completed;
  bool get isArchived => !isDeleted && status == GoalStatus.archived;

  GoalRecord copyWith({
    String? name,
    String? description,
    int? targetAmountMinor,
    int? startingAmountMinor,
    DateTime? targetDate,
    GoalStatus? status,
    GoalFundingMethod? fundingMethod,
    GoalType? goalType,
    String? defaultFundingAccountId,
    int? accentColorValue,
    bool? reservationsReleased,
    bool? requiresFundingMigration,
    SyncMetadata? sync,
    bool clearTargetDate = false,
    bool clearDefaultFundingAccount = false,
  }) {
    return GoalRecord(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      targetAmountMinor: targetAmountMinor ?? this.targetAmountMinor,
      startingAmountMinor: startingAmountMinor ?? this.startingAmountMinor,
      targetDate: clearTargetDate ? null : targetDate ?? this.targetDate,
      status: status ?? this.status,
      fundingMethod: fundingMethod ?? this.fundingMethod,
      goalType: goalType ?? this.goalType,
      defaultFundingAccountId: clearDefaultFundingAccount
          ? null
          : defaultFundingAccountId ?? this.defaultFundingAccountId,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      reservationsReleased: reservationsReleased ?? this.reservationsReleased,
      requiresFundingMigration:
          requiresFundingMigration ?? this.requiresFundingMigration,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'targetAmountMinor': targetAmountMinor,
      'startingAmountMinor': startingAmountMinor,
      'targetDate': targetDate?.toIso8601String(),
      'status': status.name,
      'fundingMethod': fundingMethod.name,
      'goalType': goalType.name,
      'defaultFundingAccountId': defaultFundingAccountId,
      'accentColorValue': accentColorValue,
      'reservationsReleased': reservationsReleased,
      'requiresFundingMigration': requiresFundingMigration,
      'sync': sync.toJson(),
    };
  }

  factory GoalRecord.fromJson(Map<String, Object?> json) {
    return GoalRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      targetAmountMinor: json['targetAmountMinor'] as int? ?? 0,
      startingAmountMinor: json['startingAmountMinor'] as int? ?? 0,
      targetDate: json['targetDate'] == null
          ? null
          : dateTimeFromJson(json['targetDate']),
      status: enumByName(GoalStatus.values, json['status'], GoalStatus.active),
      fundingMethod: _goalFundingMethodFromJson(json['fundingMethod']),
      goalType: enumByName(
        GoalType.values,
        json['goalType'],
        GoalType.reachTarget,
      ),
      defaultFundingAccountId: json['defaultFundingAccountId'] as String?,
      accentColorValue: json['accentColorValue'] as int? ?? 0xFF367BF5,
      reservationsReleased: json['reservationsReleased'] as bool? ?? false,
      requiresFundingMigration:
          json['requiresFundingMigration'] as bool? ??
          json['fundingMethod'] == 'reserveFromAccount',
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}

class GoalContributionRecord {
  const GoalContributionRecord({
    required this.id,
    required this.goalId,
    required this.amountMinor,
    required this.date,
    required this.fundingMethod,
    required this.sync,
    this.sourceAccountId,
    this.note = '',
    this.isLegacyReservation = false,
  });

  final String id;
  final String goalId;
  final int amountMinor;
  final DateTime date;
  final String? sourceAccountId;
  final GoalFundingMethod fundingMethod;
  final String note;
  final bool isLegacyReservation;
  final SyncMetadata sync;

  DateTime get createdDate => sync.createdAt;
  DateTime get updatedDate => sync.updatedAt;
  bool get isDeleted => sync.isDeleted;
  bool get isActive => !isDeleted;

  GoalContributionRecord copyWith({
    int? amountMinor,
    DateTime? date,
    String? sourceAccountId,
    GoalFundingMethod? fundingMethod,
    String? note,
    bool? isLegacyReservation,
    SyncMetadata? sync,
    bool clearSourceAccount = false,
  }) {
    return GoalContributionRecord(
      id: id,
      goalId: goalId,
      amountMinor: amountMinor ?? this.amountMinor,
      date: date ?? this.date,
      sourceAccountId: clearSourceAccount
          ? null
          : sourceAccountId ?? this.sourceAccountId,
      fundingMethod: fundingMethod ?? this.fundingMethod,
      note: note ?? this.note,
      isLegacyReservation: isLegacyReservation ?? this.isLegacyReservation,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'goalId': goalId,
      'amountMinor': amountMinor,
      'date': date.toIso8601String(),
      'sourceAccountId': sourceAccountId,
      'fundingMethod': fundingMethod.name,
      'note': note,
      'isLegacyReservation': isLegacyReservation,
      'sync': sync.toJson(),
    };
  }

  factory GoalContributionRecord.fromJson(Map<String, Object?> json) {
    return GoalContributionRecord(
      id: json['id'] as String,
      goalId: json['goalId'] as String,
      amountMinor: json['amountMinor'] as int? ?? 0,
      date: dateTimeFromJson(json['date']),
      sourceAccountId: json['sourceAccountId'] as String?,
      fundingMethod: _goalFundingMethodFromJson(json['fundingMethod']),
      note: json['note'] as String? ?? '',
      isLegacyReservation:
          json['isLegacyReservation'] as bool? ??
          json['fundingMethod'] == 'reserveFromAccount',
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}

GoalFundingMethod _goalFundingMethodFromJson(Object? value) {
  if (value == 'reserveFromAccount' || value == 'accountFunded') {
    return GoalFundingMethod.accountFunded;
  }
  return GoalFundingMethod.trackingOnly;
}
