import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'accent_color_catalog.dart';

class CreditCardIconOption {
  const CreditCardIconOption({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

/// Stable, app-owned appearance identifiers for credit-card accounts.
///
/// User data stores these IDs rather than package code points so icon-font
/// updates cannot invalidate a saved account appearance.
abstract final class CreditCardAppearanceCatalog {
  static const defaultIconId = 'creditcard';
  static const defaultAccentId = 'teal';

  static const icons = <CreditCardIconOption>[
    CreditCardIconOption(
      id: 'creditcard',
      label: 'Card',
      icon: CupertinoIcons.creditcard,
    ),
    CreditCardIconOption(
      id: 'creditcardFill',
      label: 'Filled Card',
      icon: CupertinoIcons.creditcard_fill,
    ),
    CreditCardIconOption(
      id: 'rectangleStack',
      label: 'Card Stack',
      icon: CupertinoIcons.rectangle_stack,
    ),
    CreditCardIconOption(
      id: 'rectangleStackFill',
      label: 'Filled Card Stack',
      icon: CupertinoIcons.rectangle_stack_fill,
    ),
  ];

  static const accents = TrackmarkAccentCatalog.options;

  static CreditCardIconOption iconFor(String? id) =>
      icons.firstWhere((option) => option.id == id, orElse: () => icons.first);

  static TrackmarkAccentOption? accentFor(String? id) =>
      TrackmarkAccentCatalog.findById(id);
}

/// The fixed-size identity treatment used on credit-card account cards and in
/// the small live form preview.
class CreditCardAppearanceBadge extends StatelessWidget {
  const CreditCardAppearanceBadge({
    required this.iconId,
    required this.accentId,
    this.size = 46,
    super.key,
  });

  final String? iconId;
  final String? accentId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = CreditCardAppearanceCatalog.iconFor(iconId).icon;
    final accent = CreditCardAppearanceCatalog.accentFor(accentId)?.color;
    final foreground = accent ?? theme.colorScheme.onSurfaceVariant;
    final background = accent == null
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : foreground.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.20 : 0.11,
          );
    final border = accent == null
        ? theme.colorScheme.outlineVariant.withValues(alpha: 0.62)
        : foreground.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.46 : 0.23,
          );
    return Semantics(
      label:
          'Credit card icon, ${CreditCardAppearanceCatalog.iconFor(iconId).label}',
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(size * 0.26),
          border: Border.all(color: border),
        ),
        child: Icon(icon, color: foreground, size: size * 0.50),
      ),
    );
  }
}
