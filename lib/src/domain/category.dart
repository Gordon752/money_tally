import 'json_helpers.dart';
import 'sync_metadata.dart';

enum CategoryKind { income, expense, transfer, system }

class CategoryIconOption {
  const CategoryIconOption({
    required this.id,
    required this.sfSymbolName,
    required this.label,
  });

  final String id;
  final String sfSymbolName;
  final String label;
}

const curatedCategoryIcons = [
  CategoryIconOption(id: 'dining', sfSymbolName: 'fork.knife', label: 'Dining'),
  CategoryIconOption(id: 'cart', sfSymbolName: 'cart', label: 'Shopping'),
  CategoryIconOption(id: 'car', sfSymbolName: 'car', label: 'Auto'),
  CategoryIconOption(id: 'fuel', sfSymbolName: 'fuelpump', label: 'Fuel'),
  CategoryIconOption(id: 'movie', sfSymbolName: 'film', label: 'Movies'),
  CategoryIconOption(id: 'home', sfSymbolName: 'house', label: 'Home'),
  CategoryIconOption(
    id: 'medical',
    sfSymbolName: 'cross.case',
    label: 'Medical',
  ),
  CategoryIconOption(id: 'phone', sfSymbolName: 'phone', label: 'Phone'),
  CategoryIconOption(id: 'utilities', sfSymbolName: 'bolt', label: 'Utilities'),
  CategoryIconOption(
    id: 'insurance',
    sfSymbolName: 'shield',
    label: 'Insurance',
  ),
  CategoryIconOption(
    id: 'maintenance',
    sfSymbolName: 'wrench.adjustable',
    label: 'Maintenance',
  ),
  CategoryIconOption(id: 'tag', sfSymbolName: 'tag', label: 'General'),
];

class CategoryRecord {
  const CategoryRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.sync,
    this.parentCategoryId,
    this.iconName,
    this.colorValue,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final CategoryKind kind;
  final String? parentCategoryId;
  final String? iconName;
  final int? colorValue;
  final bool isArchived;
  final SyncMetadata sync;

  bool get hasIcon => iconName != null && iconName!.trim().isNotEmpty;
  bool get isDeleted => sync.isDeleted;
  bool get isVisible => !isArchived && !isDeleted;

  CategoryRecord copyWith({
    String? name,
    CategoryKind? kind,
    String? parentCategoryId,
    String? iconName,
    int? colorValue,
    bool? isArchived,
    SyncMetadata? sync,
    bool clearParentCategory = false,
    bool clearIcon = false,
    bool clearColor = false,
  }) {
    return CategoryRecord(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      parentCategoryId: clearParentCategory
          ? null
          : parentCategoryId ?? this.parentCategoryId,
      iconName: clearIcon ? null : iconName ?? this.iconName,
      colorValue: clearColor ? null : colorValue ?? this.colorValue,
      isArchived: isArchived ?? this.isArchived,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind.name,
      'parentCategoryId': parentCategoryId,
      'iconName': iconName,
      'colorValue': colorValue,
      'isArchived': isArchived,
      'sync': sync.toJson(),
    };
  }

  factory CategoryRecord.fromJson(Map<String, Object?> json) {
    return CategoryRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      kind: enumByName(CategoryKind.values, json['kind'], CategoryKind.expense),
      parentCategoryId: json['parentCategoryId'] as String?,
      iconName: json['iconName'] as String?,
      colorValue: json['colorValue'] as int?,
      isArchived: json['isArchived'] as bool? ?? false,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
