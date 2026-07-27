import 'package:flutter/material.dart';

import '../../domain/category.dart';
import '../app_icons.dart';
import '../category_icon_catalog.dart';
import '../design_tokens.dart';

enum CategoryIconBadgeSize { compact, row, form, hero }

extension on CategoryIconBadgeSize {
  double get containerSize => switch (this) {
    CategoryIconBadgeSize.compact => 28,
    CategoryIconBadgeSize.row => 34,
    CategoryIconBadgeSize.form => 40,
    CategoryIconBadgeSize.hero => 48,
  };

  double get glyphSize => switch (this) {
    CategoryIconBadgeSize.compact => 14,
    CategoryIconBadgeSize.row => 17,
    CategoryIconBadgeSize.form => 20,
    CategoryIconBadgeSize.hero => 23,
  };
}

/// Consistent, color-aware presentation for a persisted Category icon.
///
/// Category colors communicate identity only. Accounting meaning continues to
/// come from amount and status colors elsewhere in the app.
class CategoryIconBadge extends StatelessWidget {
  const CategoryIconBadge({
    required this.iconName,
    required this.kind,
    this.colorValue,
    this.semanticLabel,
    this.size = CategoryIconBadgeSize.row,
    this.selected = false,
    this.disabled = false,
    this.archived = false,
    this.showContainer = true,
    super.key,
  });

  factory CategoryIconBadge.category(
    CategoryRecord category, {
    CategoryIconBadgeSize size = CategoryIconBadgeSize.row,
    bool selected = false,
    bool disabled = false,
    bool showContainer = true,
    Key? key,
  }) {
    return CategoryIconBadge(
      key: key,
      iconName: category.iconName,
      kind: category.kind,
      colorValue: category.colorValue,
      semanticLabel: '${category.name} category',
      size: size,
      selected: selected,
      disabled: disabled,
      archived: category.isArchived,
      showContainer: showContainer,
    );
  }

  final String? iconName;
  final CategoryKind kind;
  final int? colorValue;
  final String? semanticLabel;
  final CategoryIconBadgeSize size;
  final bool selected;
  final bool disabled;
  final bool archived;
  final bool showContainer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final identityColor = colorValue == null
        ? AppColors.accent
        : Color(colorValue!);
    final emphasis = disabled
        ? 0.42
        : archived
        ? 0.58
        : 1.0;
    final icon = CategoryIconCatalog.find(iconName)?.icon ?? _fallbackIcon;
    final glyph = Icon(
      icon,
      size: size.glyphSize,
      color: identityColor.withValues(alpha: 0.92 * emphasis),
    );

    final content = showContainer
        ? Container(
            width: size.containerSize,
            height: size.containerSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: identityColor.withValues(
                alpha: (isDark ? 0.19 : 0.105) * emphasis,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: identityColor.withValues(
                  alpha: selected
                      ? 0.72 * emphasis
                      : (isDark ? 0.25 : 0.16) * emphasis,
                ),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: glyph,
          )
        : SizedBox.square(dimension: size.glyphSize, child: glyph);

    if (semanticLabel == null) return content;
    return Semantics(image: true, label: semanticLabel, child: content);
  }

  IconData get _fallbackIcon => switch (kind) {
    CategoryKind.income => AppIcon.income,
    CategoryKind.expense => AppIcon.expense,
    CategoryKind.transfer => AppIcon.transfer,
    CategoryKind.system => AppIcon.category,
  };
}
