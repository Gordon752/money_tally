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
    this.weekStartDay = DateTime.sunday,
    this.rolloverEnabled = false,
    this.includeSubcategories = true,
  });

  final String id;
  final DateTime effectiveDate;
  final BudgetPeriod period;
  final int amountMinor;
  final List<String> categoryIds;
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
    this.anchorDate,
    this.weekStartDay = DateTime.sunday,
    this.rolloverEnabled = false,
    this.includeSubcategories = true,
    this.note = '',
    this.configurationRevisions = const [],
    this.isArchived = false,
  });

  final String id;
  final String name;
  final BudgetPeriod period;
  final int amountMinor;
  final List<String> categoryIds;
  final DateTime? anchorDate;
  final int weekStartDay;
  final bool rolloverEnabled;
  final bool includeSubcategories;
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
    DateTime? anchorDate,
    int? weekStartDay,
    bool? rolloverEnabled,
    bool? includeSubcategories,
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
      anchorDate: anchorDate ?? this.anchorDate,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      rolloverEnabled: rolloverEnabled ?? this.rolloverEnabled,
      includeSubcategories: includeSubcategories ?? this.includeSubcategories,
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
      'anchorDate': anchorDate?.toIso8601String(),
      'weekStartDay': weekStartDay,
      'rolloverEnabled': rolloverEnabled,
      'includeSubcategories': includeSubcategories,
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
      anchorDate: json['anchorDate'] == null
          ? null
          : dateTimeFromJson(json['anchorDate']),
      weekStartDay: json['weekStartDay'] as int? ?? DateTime.sunday,
      rolloverEnabled: json['rolloverEnabled'] as bool? ?? false,
      includeSubcategories: json['includeSubcategories'] as bool? ?? true,
      note: json['note'] as String? ?? '',
      configurationRevisions: stringMapList(
        json['configurationRevisions'],
      ).map(BudgetConfigurationRevision.fromJson).toList(),
      isArchived: json['isArchived'] as bool? ?? false,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
