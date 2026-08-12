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

enum AccountDefaultMode { lastUsed, none, specific, useTransactionDefault }

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
    this.defaultTransactionAccountMode = AccountDefaultMode.lastUsed,
    this.defaultTransactionAccountId,
    this.defaultTransferSourceMode = AccountDefaultMode.lastUsed,
    this.defaultTransferSourceAccountId,
    this.lastUsedTransactionAccountId,
    this.lastUsedTransferSourceAccountId,
    this.newAccountIncludeInGroupBalance = true,
    this.newAccountIncludeInNetWorth = true,
    this.warnBeforeNegativeAssetBalance = true,
    this.notificationsEnabled = false,
    this.automaticSyncEnabled = false,
    this.preferredDailySyncMinutes = 22 * 60,
    this.showRunningBalance = false,
    this.collapsedAccountGroupNames = const {},
    this.accountGroupOrderNames = defaultAccountGroupOrderNames,
    this.accountGroupLabelOverrides = const {},
    this.savedPayeeNames = const [],
    this.archivedPayeeNames = const {},
    this.deletedPayeeNames = const {},
    this.legacyV1MigrationCompleted = false,
  });

  final LaunchScreen launchScreen;
  final PlanSegment preferredPlanSegment;
  final AppearanceMode appearanceMode;
  final FloatingAddButtonPosition floatingAddButtonPosition;
  final CurrencyFormatSettings currency;
  final DefaultTransactionType defaultTransactionType;
  final TransactionType lastUsedTransactionType;
  final AccountDefaultMode defaultTransactionAccountMode;
  final String? defaultTransactionAccountId;
  final AccountDefaultMode defaultTransferSourceMode;
  final String? defaultTransferSourceAccountId;
  final String? lastUsedTransactionAccountId;
  final String? lastUsedTransferSourceAccountId;
  final bool newAccountIncludeInGroupBalance;
  final bool newAccountIncludeInNetWorth;
  final bool warnBeforeNegativeAssetBalance;
  final bool notificationsEnabled;
  final bool automaticSyncEnabled;

  /// Minutes after local midnight. This is a best-effort scheduling preference,
  /// not a promise that iOS will launch the app at an exact clock time.
  final int preferredDailySyncMinutes;
  final bool showRunningBalance;
  final Set<String> collapsedAccountGroupNames;
  final List<String> accountGroupOrderNames;
  final Map<String, String> accountGroupLabelOverrides;
  final List<String> savedPayeeNames;
  final Set<String> archivedPayeeNames;
  final Set<String> deletedPayeeNames;

  /// Marks the one-time import from the retired v1 snapshot as complete.
  /// This lives with the v2 data set so local persistence, backups, and sync
  /// all retain the same migration boundary.
  final bool legacyV1MigrationCompleted;

  UserPreferences copyWith({
    LaunchScreen? launchScreen,
    PlanSegment? preferredPlanSegment,
    AppearanceMode? appearanceMode,
    FloatingAddButtonPosition? floatingAddButtonPosition,
    CurrencyFormatSettings? currency,
    DefaultTransactionType? defaultTransactionType,
    TransactionType? lastUsedTransactionType,
    AccountDefaultMode? defaultTransactionAccountMode,
    String? defaultTransactionAccountId,
    AccountDefaultMode? defaultTransferSourceMode,
    String? defaultTransferSourceAccountId,
    String? lastUsedTransactionAccountId,
    String? lastUsedTransferSourceAccountId,
    bool? newAccountIncludeInGroupBalance,
    bool? newAccountIncludeInNetWorth,
    bool? warnBeforeNegativeAssetBalance,
    bool? notificationsEnabled,
    bool? automaticSyncEnabled,
    int? preferredDailySyncMinutes,
    bool? showRunningBalance,
    Set<String>? collapsedAccountGroupNames,
    List<String>? accountGroupOrderNames,
    Map<String, String>? accountGroupLabelOverrides,
    List<String>? savedPayeeNames,
    Set<String>? archivedPayeeNames,
    Set<String>? deletedPayeeNames,
    bool? legacyV1MigrationCompleted,
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
      defaultTransactionAccountMode:
          defaultTransactionAccountMode ?? this.defaultTransactionAccountMode,
      defaultTransactionAccountId:
          defaultTransactionAccountId ?? this.defaultTransactionAccountId,
      defaultTransferSourceMode:
          defaultTransferSourceMode ?? this.defaultTransferSourceMode,
      defaultTransferSourceAccountId:
          defaultTransferSourceAccountId ?? this.defaultTransferSourceAccountId,
      lastUsedTransactionAccountId:
          lastUsedTransactionAccountId ?? this.lastUsedTransactionAccountId,
      lastUsedTransferSourceAccountId:
          lastUsedTransferSourceAccountId ??
          this.lastUsedTransferSourceAccountId,
      newAccountIncludeInGroupBalance:
          newAccountIncludeInGroupBalance ??
          this.newAccountIncludeInGroupBalance,
      newAccountIncludeInNetWorth:
          newAccountIncludeInNetWorth ?? this.newAccountIncludeInNetWorth,
      warnBeforeNegativeAssetBalance:
          warnBeforeNegativeAssetBalance ?? this.warnBeforeNegativeAssetBalance,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      automaticSyncEnabled: automaticSyncEnabled ?? this.automaticSyncEnabled,
      preferredDailySyncMinutes:
          preferredDailySyncMinutes ?? this.preferredDailySyncMinutes,
      showRunningBalance: showRunningBalance ?? this.showRunningBalance,
      collapsedAccountGroupNames:
          collapsedAccountGroupNames ?? this.collapsedAccountGroupNames,
      accountGroupOrderNames:
          accountGroupOrderNames ?? this.accountGroupOrderNames,
      accountGroupLabelOverrides:
          accountGroupLabelOverrides ?? this.accountGroupLabelOverrides,
      savedPayeeNames: savedPayeeNames ?? this.savedPayeeNames,
      archivedPayeeNames: archivedPayeeNames ?? this.archivedPayeeNames,
      deletedPayeeNames: deletedPayeeNames ?? this.deletedPayeeNames,
      legacyV1MigrationCompleted:
          legacyV1MigrationCompleted ?? this.legacyV1MigrationCompleted,
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
      'defaultTransactionAccountMode': defaultTransactionAccountMode.name,
      'defaultTransactionAccountId': defaultTransactionAccountId,
      'defaultTransferSourceMode': defaultTransferSourceMode.name,
      'defaultTransferSourceAccountId': defaultTransferSourceAccountId,
      'lastUsedTransactionAccountId': lastUsedTransactionAccountId,
      'lastUsedTransferSourceAccountId': lastUsedTransferSourceAccountId,
      'newAccountIncludeInGroupBalance': newAccountIncludeInGroupBalance,
      'newAccountIncludeInNetWorth': newAccountIncludeInNetWorth,
      'warnBeforeNegativeAssetBalance': warnBeforeNegativeAssetBalance,
      'notificationsEnabled': notificationsEnabled,
      'automaticSyncEnabled': automaticSyncEnabled,
      'preferredDailySyncMinutes': preferredDailySyncMinutes,
      'showRunningBalance': showRunningBalance,
      'collapsedAccountGroupNames': collapsedAccountGroupNames.toList()..sort(),
      'accountGroupOrderNames': accountGroupOrderNames,
      'accountGroupLabelOverrides': accountGroupLabelOverrides,
      'savedPayeeNames': savedPayeeNames,
      'archivedPayeeNames': archivedPayeeNames.toList()..sort(),
      'deletedPayeeNames': deletedPayeeNames.toList()..sort(),
      'legacyV1MigrationCompleted': legacyV1MigrationCompleted,
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
      defaultTransactionAccountMode: enumByName(
        AccountDefaultMode.values,
        json['defaultTransactionAccountMode'],
        AccountDefaultMode.lastUsed,
      ),
      defaultTransactionAccountId:
          json['defaultTransactionAccountId'] as String?,
      defaultTransferSourceMode: enumByName(
        AccountDefaultMode.values,
        json['defaultTransferSourceMode'],
        AccountDefaultMode.lastUsed,
      ),
      defaultTransferSourceAccountId:
          json['defaultTransferSourceAccountId'] as String?,
      lastUsedTransactionAccountId:
          json['lastUsedTransactionAccountId'] as String?,
      lastUsedTransferSourceAccountId:
          json['lastUsedTransferSourceAccountId'] as String?,
      newAccountIncludeInGroupBalance:
          json['newAccountIncludeInGroupBalance'] as bool? ?? true,
      newAccountIncludeInNetWorth:
          json['newAccountIncludeInNetWorth'] as bool? ?? true,
      warnBeforeNegativeAssetBalance:
          json['warnBeforeNegativeAssetBalance'] as bool? ?? true,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? false,
      automaticSyncEnabled: json['automaticSyncEnabled'] as bool? ?? false,
      preferredDailySyncMinutes: _validPreferredSyncMinutes(
        json['preferredDailySyncMinutes'],
      ),
      showRunningBalance: json['showRunningBalance'] as bool? ?? false,
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
      legacyV1MigrationCompleted:
          json['legacyV1MigrationCompleted'] as bool? ?? false,
    );
  }
}

int _validPreferredSyncMinutes(Object? value) {
  final minutes = value is int ? value : 22 * 60;
  return minutes.clamp(0, (24 * 60) - 1);
}
