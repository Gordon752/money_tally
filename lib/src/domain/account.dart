import 'json_helpers.dart';
import 'sync_metadata.dart';

enum AccountGroup { banking, cash, creditCards, loans }

enum AccountType { checking, savings, cash, creditCard, loan, otherBanking }

extension AccountGroupDefaults on AccountGroup {
  String get defaultLabel {
    return switch (this) {
      AccountGroup.banking => 'Banking',
      AccountGroup.cash => 'Cash',
      AccountGroup.creditCards => 'Credit Cards',
      AccountGroup.loans => 'Loans',
    };
  }
}

extension AccountTypeGroup on AccountType {
  AccountGroup get group {
    return switch (this) {
      AccountType.checking ||
      AccountType.savings ||
      AccountType.otherBanking => AccountGroup.banking,
      AccountType.cash => AccountGroup.cash,
      AccountType.creditCard => AccountGroup.creditCards,
      AccountType.loan => AccountGroup.loans,
    };
  }
}

class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalanceMinor,
    required this.sync,
    this.creditLimitMinor,
    this.interestEstimationEnabled = false,
    this.annualPercentageRate,
    this.statementClosingDay,
    this.paymentDueDay,
    this.creditCardIconId,
    this.creditCardAccentId,
    this.originalLoanAmountMinor,
    this.isArchived = false,
    this.includeInGroupBalance = true,
    this.includeInNetWorth = true,
    this.sortOrder = 0,
    this.goalId,
    this.isDetachedGoalAccount = false,
  });

  final String id;
  final String name;
  final AccountType type;
  final int openingBalanceMinor;
  final int? creditLimitMinor;

  /// Optional credit-card metadata for the future Credit Insights estimate.
  /// These values are intentionally descriptive only in this phase; no
  /// balance, transaction, or interest calculations depend on them.
  final bool interestEstimationEnabled;
  final double? annualPercentageRate;
  final int? statementClosingDay;
  final int? paymentDueDay;
  final String? creditCardIconId;
  final String? creditCardAccentId;
  final int? originalLoanAmountMinor;
  final bool isArchived;
  final bool includeInGroupBalance;
  final bool includeInNetWorth;
  final int sortOrder;

  /// A non-null value makes this an internal savings account owned by a Goal.
  /// It deliberately remains an ordinary asset [type] so the proven account
  /// and transaction machinery can calculate its balance without a parallel
  /// Goal ledger.
  final String? goalId;

  /// Retains a zero-balance historical Goal account after its Goal presentation
  /// has been permanently deleted.  Ledger history remains resolvable, while
  /// the account never becomes an ordinary Accounts-page card.
  final bool isDetachedGoalAccount;
  final SyncMetadata sync;

  AccountGroup get group => type.group;
  bool get isDeleted => sync.isDeleted;
  bool get isVisible => !isArchived && !isDeleted;
  bool get isGoalAccount => goalId != null && goalId!.isNotEmpty;
  bool get isInternalGoalAccount => isGoalAccount || isDetachedGoalAccount;

  AccountRecord copyWith({
    String? name,
    AccountType? type,
    int? openingBalanceMinor,
    int? creditLimitMinor,
    bool? interestEstimationEnabled,
    double? annualPercentageRate,
    int? statementClosingDay,
    int? paymentDueDay,
    String? creditCardIconId,
    String? creditCardAccentId,
    int? originalLoanAmountMinor,
    bool? isArchived,
    bool? includeInGroupBalance,
    bool? includeInNetWorth,
    int? sortOrder,
    String? goalId,
    bool? isDetachedGoalAccount,
    SyncMetadata? sync,
    bool clearCreditLimit = false,
    bool clearCreditInsights = false,
    bool clearCreditCardAppearance = false,
    bool clearCreditCardAccent = false,
    bool clearOriginalLoanAmount = false,
    bool clearGoalId = false,
  }) {
    return AccountRecord(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
      creditLimitMinor: clearCreditLimit
          ? null
          : creditLimitMinor ?? this.creditLimitMinor,
      interestEstimationEnabled: clearCreditInsights
          ? false
          : interestEstimationEnabled ?? this.interestEstimationEnabled,
      annualPercentageRate: clearCreditInsights
          ? null
          : annualPercentageRate ?? this.annualPercentageRate,
      statementClosingDay: clearCreditInsights
          ? null
          : statementClosingDay ?? this.statementClosingDay,
      paymentDueDay: clearCreditInsights
          ? null
          : paymentDueDay ?? this.paymentDueDay,
      creditCardIconId: clearCreditCardAppearance
          ? null
          : creditCardIconId ?? this.creditCardIconId,
      creditCardAccentId: clearCreditCardAppearance || clearCreditCardAccent
          ? null
          : creditCardAccentId ?? this.creditCardAccentId,
      originalLoanAmountMinor: clearOriginalLoanAmount
          ? null
          : originalLoanAmountMinor ?? this.originalLoanAmountMinor,
      isArchived: isArchived ?? this.isArchived,
      includeInGroupBalance:
          includeInGroupBalance ?? this.includeInGroupBalance,
      includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
      sortOrder: sortOrder ?? this.sortOrder,
      goalId: clearGoalId ? null : goalId ?? this.goalId,
      isDetachedGoalAccount:
          isDetachedGoalAccount ?? this.isDetachedGoalAccount,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'openingBalanceMinor': openingBalanceMinor,
      'creditLimitMinor': creditLimitMinor,
      'interestEstimationEnabled': interestEstimationEnabled,
      'annualPercentageRate': annualPercentageRate,
      'statementClosingDay': statementClosingDay,
      'paymentDueDay': paymentDueDay,
      'creditCardIconId': creditCardIconId,
      'creditCardAccentId': creditCardAccentId,
      'originalLoanAmountMinor': originalLoanAmountMinor,
      'isArchived': isArchived,
      'includeInGroupBalance': includeInGroupBalance,
      'includeInNetWorth': includeInNetWorth,
      'sortOrder': sortOrder,
      'goalId': goalId,
      'isDetachedGoalAccount': isDetachedGoalAccount,
      'sync': sync.toJson(),
    };
  }

  factory AccountRecord.fromJson(Map<String, Object?> json) {
    return AccountRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      type: enumByName(AccountType.values, json['type'], AccountType.checking),
      openingBalanceMinor: json['openingBalanceMinor'] as int? ?? 0,
      creditLimitMinor: json['creditLimitMinor'] as int?,
      interestEstimationEnabled:
          json['interestEstimationEnabled'] as bool? ?? false,
      annualPercentageRate: (json['annualPercentageRate'] as num?)?.toDouble(),
      statementClosingDay: json['statementClosingDay'] as int?,
      paymentDueDay: json['paymentDueDay'] as int?,
      creditCardIconId: json['creditCardIconId'] as String?,
      creditCardAccentId: json['creditCardAccentId'] as String?,
      originalLoanAmountMinor: json['originalLoanAmountMinor'] as int?,
      isArchived: json['isArchived'] as bool? ?? false,
      includeInGroupBalance: json['includeInGroupBalance'] as bool? ?? true,
      includeInNetWorth: json['includeInNetWorth'] as bool? ?? true,
      sortOrder: json['sortOrder'] as int? ?? 0,
      goalId: json['goalId'] as String?,
      isDetachedGoalAccount: json['isDetachedGoalAccount'] as bool? ?? false,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
