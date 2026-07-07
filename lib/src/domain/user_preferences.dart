import 'json_helpers.dart';
import 'money.dart';
import 'transaction.dart';

enum LaunchScreen { dashboard, ledger, accounts, budgets, scheduled, reports }

enum AppearanceMode { system, light, dark }

enum FloatingAddButtonPosition { left, right }

enum DefaultTransactionType { expense, income, transfer, lastUsed }

const defaultAccountGroupOrderNames = [
  'banking',
  'cash',
  'creditCards',
  'loans',
];

class UserPreferences {
  const UserPreferences({
    this.launchScreen = LaunchScreen.dashboard,
    this.appearanceMode = AppearanceMode.system,
    this.floatingAddButtonPosition = FloatingAddButtonPosition.right,
    this.currency = const CurrencyFormatSettings(),
    this.defaultTransactionType = DefaultTransactionType.lastUsed,
    this.lastUsedTransactionType = TransactionType.expense,
    this.notificationsEnabled = false,
    this.collapsedAccountGroupNames = const {},
    this.accountGroupOrderNames = defaultAccountGroupOrderNames,
    this.accountGroupLabelOverrides = const {},
  });

  final LaunchScreen launchScreen;
  final AppearanceMode appearanceMode;
  final FloatingAddButtonPosition floatingAddButtonPosition;
  final CurrencyFormatSettings currency;
  final DefaultTransactionType defaultTransactionType;
  final TransactionType lastUsedTransactionType;
  final bool notificationsEnabled;
  final Set<String> collapsedAccountGroupNames;
  final List<String> accountGroupOrderNames;
  final Map<String, String> accountGroupLabelOverrides;

  UserPreferences copyWith({
    LaunchScreen? launchScreen,
    AppearanceMode? appearanceMode,
    FloatingAddButtonPosition? floatingAddButtonPosition,
    CurrencyFormatSettings? currency,
    DefaultTransactionType? defaultTransactionType,
    TransactionType? lastUsedTransactionType,
    bool? notificationsEnabled,
    Set<String>? collapsedAccountGroupNames,
    List<String>? accountGroupOrderNames,
    Map<String, String>? accountGroupLabelOverrides,
  }) {
    return UserPreferences(
      launchScreen: launchScreen ?? this.launchScreen,
      appearanceMode: appearanceMode ?? this.appearanceMode,
      floatingAddButtonPosition:
          floatingAddButtonPosition ?? this.floatingAddButtonPosition,
      currency: currency ?? this.currency,
      defaultTransactionType:
          defaultTransactionType ?? this.defaultTransactionType,
      lastUsedTransactionType:
          lastUsedTransactionType ?? this.lastUsedTransactionType,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      collapsedAccountGroupNames:
          collapsedAccountGroupNames ?? this.collapsedAccountGroupNames,
      accountGroupOrderNames:
          accountGroupOrderNames ?? this.accountGroupOrderNames,
      accountGroupLabelOverrides:
          accountGroupLabelOverrides ?? this.accountGroupLabelOverrides,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'launchScreen': launchScreen.name,
      'appearanceMode': appearanceMode.name,
      'floatingAddButtonPosition': floatingAddButtonPosition.name,
      'currency': currency.toJson(),
      'defaultTransactionType': defaultTransactionType.name,
      'lastUsedTransactionType': lastUsedTransactionType.name,
      'notificationsEnabled': notificationsEnabled,
      'collapsedAccountGroupNames': collapsedAccountGroupNames.toList()..sort(),
      'accountGroupOrderNames': accountGroupOrderNames,
      'accountGroupLabelOverrides': accountGroupLabelOverrides,
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
      collapsedAccountGroupNames:
          (json['collapsedAccountGroupNames'] as List<Object?>?)
              ?.whereType<String>()
              .toSet() ??
          const {},
      accountGroupOrderNames:
          (json['accountGroupOrderNames'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          defaultAccountGroupOrderNames,
      accountGroupLabelOverrides:
          stringMap(json['accountGroupLabelOverrides']).map(
            (key, value) => MapEntry(key, value is String ? value : ''),
          )..removeWhere((key, value) => value.trim().isEmpty),
    );
  }
}
