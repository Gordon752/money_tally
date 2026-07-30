import 'json_helpers.dart';
import 'sync_metadata.dart';

enum BudgetPeriod { weekly, biweekly, monthly, quarterly, yearly }

extension BudgetPeriodLabel on BudgetPeriod {
  String get label => switch (this) {
    BudgetPeriod.weekly => 'Weekly',
    BudgetPeriod.biweekly => 'Every 2 weeks',
    BudgetPeriod.monthly => 'Monthly',
    BudgetPeriod.quarterly => 'Quarterly',
    BudgetPeriod.yearly => 'Yearly',
  };
}

/// A versioned Budget configuration beginning at [effectiveDate].
///
/// Revisions keep completed periods intelligible when current settings change.
/// Calculated period totals and rollover are deliberately not persisted.
class BudgetConfigurationRevision {
  const BudgetConfigurationRevision({
    required this.id,
    required this.effectiveDate,
    required this.period,
    required this.amountMinor,
    required this.categoryIds,
    required this.anchorDate,
    this.startDate,
    this.weekStartDay = DateTime.sunday,
    this.rolloverEnabled = false,
    this.includeSubcategories = true,
  });

  final String id;
  final DateTime effectiveDate;
  final BudgetPeriod period;
  final int amountMinor;
  final List<String> categoryIds;

  /// The user-selected recurring-period anchor. A null value retains the
  /// established legacy calendar/reset-rule behavior for older revisions.
  final DateTime? startDate;
  final DateTime anchorDate;
  final int weekStartDay;
  final bool rolloverEnabled;
  final bool includeSubcategories;

  BudgetConfigurationRevision copyWith({
    String? id,
    DateTime? effectiveDate,
    BudgetPeriod? period,
    int? amountMinor,
    List<String>? categoryIds,
    DateTime? startDate,
    DateTime? anchorDate,
    int? weekStartDay,
    bool? rolloverEnabled,
    bool? includeSubcategories,
  }) {
    return BudgetConfigurationRevision(
      id: id ?? this.id,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      period: period ?? this.period,
      amountMinor: amountMinor ?? this.amountMinor,
      categoryIds: categoryIds ?? this.categoryIds,
      startDate: startDate ?? this.startDate,
      anchorDate: anchorDate ?? this.anchorDate,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      rolloverEnabled: rolloverEnabled ?? this.rolloverEnabled,
      includeSubcategories: includeSubcategories ?? this.includeSubcategories,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'effectiveDate': effectiveDate.toIso8601String(),
    'period': period.name,
    'amountMinor': amountMinor,
    'categoryIds': categoryIds,
    'startDate': startDate?.toIso8601String(),
    'anchorDate': anchorDate.toIso8601String(),
    'weekStartDay': weekStartDay,
    'rolloverEnabled': rolloverEnabled,
    'includeSubcategories': includeSubcategories,
  };

  factory BudgetConfigurationRevision.fromJson(Map<String, Object?> json) {
    final effectiveDate = dateTimeFromJson(json['effectiveDate']);
    return BudgetConfigurationRevision(
      id: json['id'] as String? ?? 'budget_revision_legacy',
      effectiveDate: effectiveDate,
      period: enumByName(
        BudgetPeriod.values,
        json['period'],
        BudgetPeriod.monthly,
      ),
      amountMinor: json['amountMinor'] as int? ?? 0,
      categoryIds: (json['categoryIds'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(),
      startDate: json['startDate'] == null
          ? null
          : dateTimeFromJson(json['startDate']),
      anchorDate: json['anchorDate'] == null
          ? effectiveDate
          : dateTimeFromJson(json['anchorDate']),
      weekStartDay: json['weekStartDay'] as int? ?? DateTime.sunday,
      rolloverEnabled: json['rolloverEnabled'] as bool? ?? false,
      includeSubcategories: json['includeSubcategories'] as bool? ?? true,
    );
  }
}

class BudgetRecord {
  const BudgetRecord({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.categoryIds,
    required this.sync,
    this.period = BudgetPeriod.monthly,
    this.startDate,
    this.anchorDate,
    this.weekStartDay = DateTime.sunday,
    this.rolloverEnabled = false,
    this.includeSubcategories = true,
    this.lowBudgetAlertEnabled = true,
    this.lowBudgetAlertThresholdBasisPoints = 500,
    this.note = '',
    this.configurationRevisions = const [],
    this.isArchived = false,
  });

  final String id;
  final String name;
  final BudgetPeriod period;
  final int amountMinor;
  final List<String> categoryIds;

  /// The current user-selected recurring-period anchor. Older records remain
  /// valid with null and are interpreted through their existing period rules.
  final DateTime? startDate;
  final DateTime? anchorDate;
  final int weekStartDay;
  final bool rolloverEnabled;
  final bool includeSubcategories;

  /// Stored as basis points so future custom thresholds remain compatible.
  final bool lowBudgetAlertEnabled;
  final int lowBudgetAlertThresholdBasisPoints;
  final String note;
  final List<BudgetConfigurationRevision> configurationRevisions;
  final bool isArchived;
  final SyncMetadata sync;

  bool get isDeleted => sync.isDeleted;
  bool get isVisible => !isArchived && !isDeleted;

  BudgetConfigurationRevision legacyConfiguration(DateTime effectiveDate) {
    return BudgetConfigurationRevision(
      id: '${id}_legacy',
      effectiveDate: effectiveDate,
      period: period,
      amountMinor: amountMinor,
      categoryIds: categoryIds,
      startDate: startDate,
      anchorDate: anchorDate ?? effectiveDate,
      weekStartDay: weekStartDay,
      rolloverEnabled: rolloverEnabled,
      includeSubcategories: includeSubcategories,
    );
  }

  BudgetRecord copyWith({
    String? name,
    BudgetPeriod? period,
    int? amountMinor,
    List<String>? categoryIds,
    DateTime? startDate,
    DateTime? anchorDate,
    int? weekStartDay,
    bool? rolloverEnabled,
    bool? includeSubcategories,
    bool? lowBudgetAlertEnabled,
    int? lowBudgetAlertThresholdBasisPoints,
    String? note,
    List<BudgetConfigurationRevision>? configurationRevisions,
    bool? isArchived,
    SyncMetadata? sync,
  }) {
    return BudgetRecord(
      id: id,
      name: name ?? this.name,
      period: period ?? this.period,
      amountMinor: amountMinor ?? this.amountMinor,
      categoryIds: categoryIds ?? this.categoryIds,
      startDate: startDate ?? this.startDate,
      anchorDate: anchorDate ?? this.anchorDate,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      rolloverEnabled: rolloverEnabled ?? this.rolloverEnabled,
      includeSubcategories: includeSubcategories ?? this.includeSubcategories,
      lowBudgetAlertEnabled:
          lowBudgetAlertEnabled ?? this.lowBudgetAlertEnabled,
      lowBudgetAlertThresholdBasisPoints:
          lowBudgetAlertThresholdBasisPoints ??
          this.lowBudgetAlertThresholdBasisPoints,
      note: note ?? this.note,
      configurationRevisions:
          configurationRevisions ?? this.configurationRevisions,
      isArchived: isArchived ?? this.isArchived,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'period': period.name,
      'amountMinor': amountMinor,
      'categoryIds': categoryIds,
      'startDate': startDate?.toIso8601String(),
      'anchorDate': anchorDate?.toIso8601String(),
      'weekStartDay': weekStartDay,
      'rolloverEnabled': rolloverEnabled,
      'includeSubcategories': includeSubcategories,
      'lowBudgetAlertEnabled': lowBudgetAlertEnabled,
      'lowBudgetAlertThresholdBasisPoints': lowBudgetAlertThresholdBasisPoints,
      'note': note,
      'configurationRevisions': configurationRevisions
          .map((revision) => revision.toJson())
          .toList(),
      'isArchived': isArchived,
      'sync': sync.toJson(),
    };
  }

  factory BudgetRecord.fromJson(Map<String, Object?> json) {
    return BudgetRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      period: enumByName(
        BudgetPeriod.values,
        json['period'],
        BudgetPeriod.monthly,
      ),
      amountMinor: json['amountMinor'] as int? ?? 0,
      categoryIds: (json['categoryIds'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(),
      startDate: json['startDate'] == null
          ? null
          : dateTimeFromJson(json['startDate']),
      anchorDate: json['anchorDate'] == null
          ? null
          : dateTimeFromJson(json['anchorDate']),
      weekStartDay: json['weekStartDay'] as int? ?? DateTime.sunday,
      rolloverEnabled: json['rolloverEnabled'] as bool? ?? false,
      includeSubcategories: json['includeSubcategories'] as bool? ?? true,
      lowBudgetAlertEnabled: json['lowBudgetAlertEnabled'] as bool? ?? true,
      lowBudgetAlertThresholdBasisPoints:
          json['lowBudgetAlertThresholdBasisPoints'] as int? ?? 500,
      note: json['note'] as String? ?? '',
      configurationRevisions: stringMapList(
        json['configurationRevisions'],
      ).map(BudgetConfigurationRevision.fromJson).toList(),
      isArchived: json['isArchived'] as bool? ?? false,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
