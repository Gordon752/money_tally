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
    this.originalLoanAmountMinor,
    this.isArchived = false,
    this.includeInGroupBalance = true,
    this.includeInNetWorth = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final AccountType type;
  final int openingBalanceMinor;
  final int? creditLimitMinor;
  final int? originalLoanAmountMinor;
  final bool isArchived;
  final bool includeInGroupBalance;
  final bool includeInNetWorth;
  final int sortOrder;
  final SyncMetadata sync;

  AccountGroup get group => type.group;

  AccountRecord copyWith({
    String? name,
    AccountType? type,
    int? openingBalanceMinor,
    int? creditLimitMinor,
    int? originalLoanAmountMinor,
    bool? isArchived,
    bool? includeInGroupBalance,
    bool? includeInNetWorth,
    int? sortOrder,
    SyncMetadata? sync,
    bool clearCreditLimit = false,
    bool clearOriginalLoanAmount = false,
  }) {
    return AccountRecord(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
      creditLimitMinor: clearCreditLimit
          ? null
          : creditLimitMinor ?? this.creditLimitMinor,
      originalLoanAmountMinor: clearOriginalLoanAmount
          ? null
          : originalLoanAmountMinor ?? this.originalLoanAmountMinor,
      isArchived: isArchived ?? this.isArchived,
      includeInGroupBalance:
          includeInGroupBalance ?? this.includeInGroupBalance,
      includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
      sortOrder: sortOrder ?? this.sortOrder,
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
      'originalLoanAmountMinor': originalLoanAmountMinor,
      'isArchived': isArchived,
      'includeInGroupBalance': includeInGroupBalance,
      'includeInNetWorth': includeInNetWorth,
      'sortOrder': sortOrder,
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
      originalLoanAmountMinor: json['originalLoanAmountMinor'] as int?,
      isArchived: json['isArchived'] as bool? ?? false,
      includeInGroupBalance: json['includeInGroupBalance'] as bool? ?? true,
      includeInNetWorth: json['includeInNetWorth'] as bool? ?? true,
      sortOrder: json['sortOrder'] as int? ?? 0,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
