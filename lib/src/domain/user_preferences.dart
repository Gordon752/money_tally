import 'json_helpers.dart';
import 'money.dart';
import 'transaction.dart';

enum LaunchScreen { dashboard, ledger, accounts, budgets, scheduled, reports }

enum AppearanceMode { system, light, dark }

enum FloatingAddButtonPosition { left, right }

enum DefaultTransactionType { expense, income, transfer, lastUsed }

class UserPreferences {
  const UserPreferences({
    this.launchScreen = LaunchScreen.dashboard,
    this.appearanceMode = AppearanceMode.system,
    this.floatingAddButtonPosition = FloatingAddButtonPosition.right,
    this.currency = const CurrencyFormatSettings(),
    this.defaultTransactionType = DefaultTransactionType.lastUsed,
    this.lastUsedTransactionType = TransactionType.expense,
    this.notificationsEnabled = false,
  });

  final LaunchScreen launchScreen;
  final AppearanceMode appearanceMode;
  final FloatingAddButtonPosition floatingAddButtonPosition;
  final CurrencyFormatSettings currency;
  final DefaultTransactionType defaultTransactionType;
  final TransactionType lastUsedTransactionType;
  final bool notificationsEnabled;

  Map<String, Object?> toJson() {
    return {
      'launchScreen': launchScreen.name,
      'appearanceMode': appearanceMode.name,
      'floatingAddButtonPosition': floatingAddButtonPosition.name,
      'currency': currency.toJson(),
      'defaultTransactionType': defaultTransactionType.name,
      'lastUsedTransactionType': lastUsedTransactionType.name,
      'notificationsEnabled': notificationsEnabled,
    };
  }

  factory UserPreferences.fromJson(Map<String, Object?> json) {
    return UserPreferences(
      launchScreen: enumByName(
        LaunchScreen.values,
        json['launchScreen'],
        LaunchScreen.dashboard,
      ),
      appearanceMode: enumByName(
        AppearanceMode.values,
        json['appearanceMode'],
        AppearanceMode.system,
      ),
      floatingAddButtonPosition: enumByName(
        FloatingAddButtonPosition.values,
        json['floatingAddButtonPosition'],
        FloatingAddButtonPosition.right,
      ),
      currency: CurrencyFormatSettings.fromJson(stringMap(json['currency'])),
      defaultTransactionType: enumByName(
        DefaultTransactionType.values,
        json['defaultTransactionType'],
        DefaultTransactionType.lastUsed,
      ),
      lastUsedTransactionType: enumByName(
        TransactionType.values,
        json['lastUsedTransactionType'],
        TransactionType.expense,
      ),
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? false,
    );
  }
}
