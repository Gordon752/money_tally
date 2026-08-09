import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'accent_color_catalog.dart';
import '../domain/account.dart';

class AccountIconOption {
  const AccountIconOption({
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
abstract final class AccountAppearanceCatalog {
  static const defaultIconId = 'creditcard';
  static const defaultAccentId = 'teal';

  static const creditCardIcons = <AccountIconOption>[
    AccountIconOption(
      id: 'creditcard',
      label: 'Card',
      icon: CupertinoIcons.creditcard,
    ),
    AccountIconOption(
      id: 'creditcardFill',
      label: 'Filled Card',
      icon: CupertinoIcons.creditcard_fill,
    ),
    AccountIconOption(
      id: 'rectangleStack',
      label: 'Card Stack',
      icon: CupertinoIcons.rectangle_stack,
    ),
    AccountIconOption(
      id: 'rectangleStackFill',
      label: 'Filled Card Stack',
      icon: CupertinoIcons.rectangle_stack_fill,
    ),
  ];

  static const bankingIcons = <AccountIconOption>[
    AccountIconOption(
      id: 'bank',
      label: 'Bank',
      icon: CupertinoIcons.building_2_fill,
    ),
    AccountIconOption(
      id: 'checking',
      label: 'Checking',
      icon: CupertinoIcons.creditcard,
    ),
    AccountIconOption(
      id: 'savings',
      label: 'Savings',
      icon: CupertinoIcons.money_dollar_circle,
    ),
    AccountIconOption(
      id: 'portfolio',
      label: 'Portfolio',
      icon: CupertinoIcons.briefcase,
    ),
  ];

  static const cashIcons = <AccountIconOption>[
    AccountIconOption(
      id: 'cash',
      label: 'Cash',
      icon: CupertinoIcons.money_dollar,
    ),
    AccountIconOption(
      id: 'cashCircle',
      label: 'Cash Circle',
      icon: CupertinoIcons.money_dollar_circle,
    ),
    AccountIconOption(
      id: 'cashCircleFill',
      label: 'Filled Cash Circle',
      icon: CupertinoIcons.money_dollar_circle_fill,
    ),
    AccountIconOption(
      id: 'cashWallet',
      label: 'Wallet',
      icon: CupertinoIcons.creditcard,
    ),
  ];

  static const loanIcons = <AccountIconOption>[
    AccountIconOption(
      id: 'loanDocument',
      label: 'Loan Document',
      icon: CupertinoIcons.doc_text,
    ),
    AccountIconOption(
      id: 'mortgage',
      label: 'Mortgage',
      icon: CupertinoIcons.house,
    ),
    AccountIconOption(
      id: 'vehicleLoan',
      label: 'Vehicle Loan',
      icon: CupertinoIcons.car,
    ),
    AccountIconOption(
      id: 'loanFinance',
      label: 'Finance',
      icon: CupertinoIcons.money_dollar_circle,
    ),
  ];

  static const accents = TrackmarkAccentCatalog.options;

  static List<AccountIconOption> iconsFor(AccountType type) => switch (type) {
    AccountType.creditCard => creditCardIcons,
    AccountType.cash => cashIcons,
    AccountType.loan => loanIcons,
    AccountType.checking ||
    AccountType.savings ||
    AccountType.otherBanking => bankingIcons,
  };

  static String defaultIconIdFor(AccountType type) => switch (type) {
    AccountType.creditCard => defaultIconId,
    AccountType.cash => 'cash',
    AccountType.loan => 'loanDocument',
    AccountType.checking || AccountType.otherBanking => 'bank',
    AccountType.savings => 'savings',
  };

  static AccountIconOption iconFor(AccountType type, String? id) {
    final icons = iconsFor(type);
    final defaultId = defaultIconIdFor(type);
    return icons.firstWhere(
      (option) => option.id == id,
      orElse: () => icons.firstWhere(
        (option) => option.id == defaultId,
        orElse: () => icons.first,
      ),
    );
  }

  static bool supportsIcon(AccountType type, String? id) =>
      iconsFor(type).any((option) => option.id == id);

  static TrackmarkAccentOption? accentFor(String? id) =>
      TrackmarkAccentCatalog.findById(id);
}

/// Compatibility facade for the existing credit-card implementation and its
/// stable stored IDs. New account types use [AccountAppearanceCatalog]
/// directly, while credit cards keep their established API and behavior.
abstract final class CreditCardAppearanceCatalog {
  static const defaultIconId = AccountAppearanceCatalog.defaultIconId;
  static const defaultAccentId = AccountAppearanceCatalog.defaultAccentId;
  static const icons = AccountAppearanceCatalog.creditCardIcons;
  static const accents = AccountAppearanceCatalog.accents;

  static AccountIconOption iconFor(String? id) =>
      AccountAppearanceCatalog.iconFor(AccountType.creditCard, id);

  static TrackmarkAccentOption? accentFor(String? id) =>
      AccountAppearanceCatalog.accentFor(id);
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
    return AccountAppearanceBadge(
      accountType: AccountType.creditCard,
      iconId: iconId,
      accentId: accentId,
      size: size,
    );
  }
}

/// Fixed-size identity treatment shared by every individual account type.
class AccountAppearanceBadge extends StatelessWidget {
  const AccountAppearanceBadge({
    required this.accountType,
    required this.iconId,
    required this.accentId,
    this.size = 46,
    super.key,
  });

  final AccountType accountType;
  final String? iconId;
  final String? accentId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final option = AccountAppearanceCatalog.iconFor(accountType, iconId);
    final icon = option.icon;
    final accent = AccountAppearanceCatalog.accentFor(accentId)?.color;
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
      label: '${accountType.group.defaultLabel} account icon, ${option.label}',
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
