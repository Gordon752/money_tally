import 'json_helpers.dart';
import 'money.dart';
import 'transaction.dart';

enum LaunchScreen {
  dashboard,
  ledger,
  accounts,
  budgets,
  planBudgets,
  planGoals,
  scheduled,
  reports,
}

enum PlanSegment { budgets, goals }

enum AppearanceMode { system, light, dark }

enum FloatingAddButtonPosition { left, center, right }

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
    this.preferredPlanSegment = PlanSegment.budgets,
    this.appearanceMode = AppearanceMode.system,
    this.floatingAddButtonPosition = FloatingAddButtonPosition.right,
    this.currency = const CurrencyFormatSettings(),
    this.defaultTransactionType = DefaultTransactionType.lastUsed,
    this.lastUsedTransactionType = TransactionType.expense,
    this.notificationsEnabled = false,
    this.collapsedAccountGroupNames = const {},
    this.accountGroupOrderNames = defaultAccountGroupOrderNames,
    this.accountGroupLabelOverrides = const {},
    this.savedPayeeNames = const [],
    this.archivedPayeeNames = const {},
    this.deletedPayeeNames = const {},
  });

  final LaunchScreen launchScreen;
  final PlanSegment preferredPlanSegment;
  final AppearanceMode appearanceMode;
  final FloatingAddButtonPosition floatingAddButtonPosition;
  final CurrencyFormatSettings currency;
  final DefaultTransactionType defaultTransactionType;
  final TransactionType lastUsedTransactionType;
  final bool notificationsEnabled;
  final Set<String> collapsedAccountGroupNames;
  final List<String> accountGroupOrderNames;
  final Map<String, String> accountGroupLabelOverrides;
  final List<String> savedPayeeNames;
  final Set<String> archivedPayeeNames;
  final Set<String> deletedPayeeNames;

  UserPreferences copyWith({
    LaunchScreen? launchScreen,
    PlanSegment? preferredPlanSegment,
    AppearanceMode? appearanceMode,
    FloatingAddButtonPosition? floatingAddButtonPosition,
    CurrencyFormatSettings? currency,
    DefaultTransactionType? defaultTransactionType,
    TransactionType? lastUsedTransactionType,
    bool? notificationsEnabled,
    Set<String>? collapsedAccountGroupNames,
    List<String>? accountGroupOrderNames,
    Map<String, String>? accountGroupLabelOverrides,
    List<String>? savedPayeeNames,
    Set<String>? archivedPayeeNames,
    Set<String>? deletedPayeeNames,
  }) {
    return UserPreferences(
      launchScreen: launchScreen ?? this.launchScreen,
      preferredPlanSegment: preferredPlanSegment ?? this.preferredPlanSegment,
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
      savedPayeeNames: savedPayeeNames ?? this.savedPayeeNames,
      archivedPayeeNames: archivedPayeeNames ?? this.archivedPayeeNames,
      deletedPayeeNames: deletedPayeeNames ?? this.deletedPayeeNames,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'launchScreen': launchScreen.name,
      'preferredPlanSegment': preferredPlanSegment.name,
      'appearanceMode': appearanceMode.name,
      'floatingAddButtonPosition': floatingAddButtonPosition.name,
      'currency': currency.toJson(),
      'defaultTransactionType': defaultTransactionType.name,
      'lastUsedTransactionType': lastUsedTransactionType.name,
      'notificationsEnabled': notificationsEnabled,
      'collapsedAccountGroupNames': collapsedAccountGroupNames.toList()..sort(),
      'accountGroupOrderNames': accountGroupOrderNames,
      'accountGroupLabelOverrides': accountGroupLabelOverrides,
      'savedPayeeNames': savedPayeeNames,
      'archivedPayeeNames': archivedPayeeNames.toList()..sort(),
      'deletedPayeeNames': deletedPayeeNames.toList()..sort(),
    };
  }

  factory UserPreferences.fromJson(Map<String, Object?> json) {
    return UserPreferences(
      launchScreen: enumByName(
        LaunchScreen.values,
        json['launchScreen'],
        LaunchScreen.dashboard,
      ),
      preferredPlanSegment: enumByName(
        PlanSegment.values,
        json['preferredPlanSegment'],
        json['launchScreen'] == 'planGoals'
            ? PlanSegment.goals
            : PlanSegment.budgets,
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
      savedPayeeNames:
          (json['savedPayeeNames'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      archivedPayeeNames:
          (json['archivedPayeeNames'] as List<Object?>?)
              ?.whereType<String>()
              .map((value) => value.toLowerCase())
              .toSet() ??
          const {},
      deletedPayeeNames:
          (json['deletedPayeeNames'] as List<Object?>?)
              ?.whereType<String>()
              .map((value) => value.toLowerCase())
              .toSet() ??
          const {},
    );
  }
}
