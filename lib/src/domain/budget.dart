import 'json_helpers.dart';
import 'sync_metadata.dart';

enum BudgetPeriod { monthly }

class BudgetRecord {
  const BudgetRecord({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.categoryIds,
    required this.sync,
    this.period = BudgetPeriod.monthly,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final BudgetPeriod period;
  final int amountMinor;
  final List<String> categoryIds;
  final bool isArchived;
  final SyncMetadata sync;

  int remainingMinor(int spentMinor) => amountMinor - spentMinor;
  bool isOverBudget(int spentMinor) => spentMinor > amountMinor;
  bool get isDeleted => sync.isDeleted;
  bool get isVisible => !isArchived && !isDeleted;

  BudgetRecord copyWith({
    String? name,
    BudgetPeriod? period,
    int? amountMinor,
    List<String>? categoryIds,
    bool? isArchived,
    SyncMetadata? sync,
  }) {
    return BudgetRecord(
      id: id,
      name: name ?? this.name,
      period: period ?? this.period,
      amountMinor: amountMinor ?? this.amountMinor,
      categoryIds: categoryIds ?? this.categoryIds,
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
      isArchived: json['isArchived'] as bool? ?? false,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
