part of '../main.dart';

class FinanceSnapshot {
  const FinanceSnapshot({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.scheduled,
    required this.budgets,
  });

  final List<Account> accounts;
  final List<LedgerCategory> categories;
  final List<LedgerTransaction> transactions;
  final List<ScheduledTransaction> scheduled;
  final List<Budget> budgets;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 1,
      'accounts': accounts.map((account) => account.toJson()).toList(),
      'categories': categories.map((category) => category.toJson()).toList(),
      'transactions': transactions
          .map((transaction) => transaction.toJson())
          .toList(),
      'scheduled': scheduled.map((item) => item.toJson()).toList(),
      'budgets': budgets.map((budget) => budget.toJson()).toList(),
    };
  }

  factory FinanceSnapshot.fromJson(Map<String, Object?> json) {
    return FinanceSnapshot(
      accounts: jsonList(
        json['accounts'],
      ).map((item) => Account.fromJson(item)).toList(),
      categories: jsonList(
        json['categories'],
      ).map((item) => LedgerCategory.fromJson(item)).toList(),
      transactions: jsonList(
        json['transactions'],
      ).map((item) => LedgerTransaction.fromJson(item)).toList(),
      scheduled: jsonList(
        json['scheduled'],
      ).map((item) => ScheduledTransaction.fromJson(item)).toList(),
      budgets: jsonList(
        json['budgets'],
      ).map((item) => Budget.fromJson(item)).toList(),
    );
  }
}

class LocalFinanceRepository {
  static const _storageKey = 'money_tally_finance_snapshot_v1';

  const LocalFinanceRepository();

  Future<FinanceSnapshot?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    return FinanceSnapshot.fromJson(decoded);
  }

  Future<void> save(FinanceSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(snapshot.toJson()));
  }
}
