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

enum PlanSegment { budgets, funds, goals }

enum AppearanceMode { system, light, dark }

enum FloatingAddButtonPosition { left, center, right }

enum DefaultTransactionType { expense, income, transfer, lastUsed }

enum AccountDefaultMode { lastUsed, none, specific, useTransactionDefault }

enum AutomaticBackupFrequency { daily, weekly }

enum AutomaticBackupLocation { local, iCloud }

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
    this.automaticBackupsEnabled = false,
    this.automaticBackupFrequency = AutomaticBackupFrequency.weekly,
    this.preferredAutomaticBackupMinutes = 23 * 60,
    this.automaticBackupLocation = AutomaticBackupLocation.local,
    this.showLedgerIcons = true,
    this.showLedgerTimestamps = true,
    this.showLedgerSplitIndicator = true,
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
  final bool automaticBackupsEnabled;
  final AutomaticBackupFrequency automaticBackupFrequency;

  /// Minutes after local midnight. Background execution remains best-effort.
  final int preferredAutomaticBackupMinutes;
  final AutomaticBackupLocation automaticBackupLocation;
  final bool showLedgerIcons;
  final bool showLedgerTimestamps;
  final bool showLedgerSplitIndicator;
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
    bool clearDefaultTransactionAccountId = false,
    AccountDefaultMode? defaultTransferSourceMode,
    String? defaultTransferSourceAccountId,
    bool clearDefaultTransferSourceAccountId = false,
    String? lastUsedTransactionAccountId,
    bool clearLastUsedTransactionAccountId = false,
    String? lastUsedTransferSourceAccountId,
    bool clearLastUsedTransferSourceAccountId = false,
    bool? newAccountIncludeInGroupBalance,
    bool? newAccountIncludeInNetWorth,
    bool? warnBeforeNegativeAssetBalance,
    bool? notificationsEnabled,
    bool? automaticSyncEnabled,
    int? preferredDailySyncMinutes,
    bool? automaticBackupsEnabled,
    AutomaticBackupFrequency? automaticBackupFrequency,
    int? preferredAutomaticBackupMinutes,
    AutomaticBackupLocation? automaticBackupLocation,
    bool? showLedgerIcons,
    bool? showLedgerTimestamps,
    bool? showLedgerSplitIndicator,
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
      defaultTransactionAccountId: clearDefaultTransactionAccountId
          ? null
          : defaultTransactionAccountId ?? this.defaultTransactionAccountId,
      defaultTransferSourceMode:
          defaultTransferSourceMode ?? this.defaultTransferSourceMode,
      defaultTransferSourceAccountId: clearDefaultTransferSourceAccountId
          ? null
          : defaultTransferSourceAccountId ??
                this.defaultTransferSourceAccountId,
      lastUsedTransactionAccountId: clearLastUsedTransactionAccountId
          ? null
          : lastUsedTransactionAccountId ?? this.lastUsedTransactionAccountId,
      lastUsedTransferSourceAccountId: clearLastUsedTransferSourceAccountId
          ? null
          : lastUsedTransferSourceAccountId ??
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
      automaticBackupsEnabled:
          automaticBackupsEnabled ?? this.automaticBackupsEnabled,
      automaticBackupFrequency:
          automaticBackupFrequency ?? this.automaticBackupFrequency,
      preferredAutomaticBackupMinutes:
          preferredAutomaticBackupMinutes ??
          this.preferredAutomaticBackupMinutes,
      automaticBackupLocation:
          automaticBackupLocation ?? this.automaticBackupLocation,
      showLedgerIcons: showLedgerIcons ?? this.showLedgerIcons,
      showLedgerTimestamps: showLedgerTimestamps ?? this.showLedgerTimestamps,
      showLedgerSplitIndicator:
          showLedgerSplitIndicator ?? this.showLedgerSplitIndicator,
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
      'automaticBackupsEnabled': automaticBackupsEnabled,
      'automaticBackupFrequency': automaticBackupFrequency.name,
      'preferredAutomaticBackupMinutes': preferredAutomaticBackupMinutes,
      'automaticBackupLocation': automaticBackupLocation.name,
      'showLedgerIcons': showLedgerIcons,
      'showLedgerTimestamps': showLedgerTimestamps,
      'showLedgerSplitIndicator': showLedgerSplitIndicator,
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
      automaticBackupsEnabled:
          json['automaticBackupsEnabled'] as bool? ?? false,
      automaticBackupFrequency: enumByName(
        AutomaticBackupFrequency.values,
        json['automaticBackupFrequency'],
        AutomaticBackupFrequency.weekly,
      ),
      preferredAutomaticBackupMinutes: _validPreferredMinutes(
        json['preferredAutomaticBackupMinutes'],
        fallback: 23 * 60,
      ),
      automaticBackupLocation: enumByName(
        AutomaticBackupLocation.values,
        json['automaticBackupLocation'],
        AutomaticBackupLocation.local,
      ),
      showLedgerIcons: json['showLedgerIcons'] as bool? ?? true,
      showLedgerTimestamps: json['showLedgerTimestamps'] as bool? ?? true,
      showLedgerSplitIndicator:
          json['showLedgerSplitIndicator'] as bool? ?? true,
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
  return _validPreferredMinutes(value, fallback: 22 * 60);
}

int _validPreferredMinutes(Object? value, {required int fallback}) {
  final minutes = value is int ? value : fallback;
  return minutes.clamp(0, (24 * 60) - 1);
}
