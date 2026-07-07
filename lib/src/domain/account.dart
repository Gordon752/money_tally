import 'json_helpers.dart';
import 'sync_metadata.dart';

enum AccountGroup { banking, cash, creditCards, loans }

enum AccountType { checking, savings, cash, creditCard, loan, otherBanking }

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
    this.isArchived = false,
    this.includeInGroupBalance = true,
    this.includeInNetWorth = true,
  });

  final String id;
  final String name;
  final AccountType type;
  final int openingBalanceMinor;
  final bool isArchived;
  final bool includeInGroupBalance;
  final bool includeInNetWorth;
  final SyncMetadata sync;

  AccountGroup get group => type.group;

  AccountRecord copyWith({
    String? name,
    AccountType? type,
    int? openingBalanceMinor,
    bool? isArchived,
    bool? includeInGroupBalance,
    bool? includeInNetWorth,
    SyncMetadata? sync,
  }) {
    return AccountRecord(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
      isArchived: isArchived ?? this.isArchived,
      includeInGroupBalance:
          includeInGroupBalance ?? this.includeInGroupBalance,
      includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
      sync: sync ?? this.sync.touched(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'openingBalanceMinor': openingBalanceMinor,
      'isArchived': isArchived,
      'includeInGroupBalance': includeInGroupBalance,
      'includeInNetWorth': includeInNetWorth,
      'sync': sync.toJson(),
    };
  }

  factory AccountRecord.fromJson(Map<String, Object?> json) {
    return AccountRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      type: enumByName(AccountType.values, json['type'], AccountType.checking),
      openingBalanceMinor: json['openingBalanceMinor'] as int? ?? 0,
      isArchived: json['isArchived'] as bool? ?? false,
      includeInGroupBalance: json['includeInGroupBalance'] as bool? ?? true,
      includeInNetWorth: json['includeInNetWorth'] as bool? ?? true,
      sync: SyncMetadata.fromJson(stringMap(json['sync'])),
    );
  }
}
