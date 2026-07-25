import 'account.dart';
import 'budget.dart';
import 'category.dart';
import 'goal.dart';
import 'goal_funding.dart';
import 'json_helpers.dart';
import 'scheduled_transaction.dart';
import 'transaction.dart';
import 'user_preferences.dart';

class FinanceDataSet {
  const FinanceDataSet({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.scheduledTransactions,
    required this.budgets,
    required this.preferences,
    this.goals = const [],
    this.goalContributions = const [],
    this.goalFundingEvents = const [],
  });

  final List<AccountRecord> accounts;
  final List<CategoryRecord> categories;
  final List<TransactionRecord> transactions;
  final List<ScheduledTransactionRecord> scheduledTransactions;
  final List<BudgetRecord> budgets;
  final List<GoalRecord> goals;
  final List<GoalContributionRecord> goalContributions;
  final List<GoalFundingEventRecord> goalFundingEvents;
  final UserPreferences preferences;

  FinanceDataSet copyWith({
    List<AccountRecord>? accounts,
    List<CategoryRecord>? categories,
    List<TransactionRecord>? transactions,
    List<ScheduledTransactionRecord>? scheduledTransactions,
    List<BudgetRecord>? budgets,
    List<GoalRecord>? goals,
    List<GoalContributionRecord>? goalContributions,
    List<GoalFundingEventRecord>? goalFundingEvents,
    UserPreferences? preferences,
  }) {
    return FinanceDataSet(
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      scheduledTransactions:
          scheduledTransactions ?? this.scheduledTransactions,
      budgets: budgets ?? this.budgets,
      goals: goals ?? this.goals,
      goalContributions: goalContributions ?? this.goalContributions,
      goalFundingEvents: goalFundingEvents ?? this.goalFundingEvents,
      preferences: preferences ?? this.preferences,
    );
  }

  int balanceForAccount(String accountId) {
    final account = accounts.firstWhere((item) => item.id == accountId);
    final transactionBalance = transactions
        .where((transaction) => !transaction.isDeleted)
        .fold(
          account.openingBalanceMinor,
          (total, transaction) =>
              total + transaction.deltaForAccount(accountId),
        );
    final goalFundingTotal = goalFundingEvents
        .where((event) => event.isActive && event.sourceAccountId == accountId)
        .fold<int>(0, (total, event) => total + event.totalAmountMinor.abs());
    return transactionBalance - goalFundingTotal;
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 4,
      'accounts': accounts.map((item) => item.toJson()).toList(),
      'categories': categories.map((item) => item.toJson()).toList(),
      'transactions': transactions.map((item) => item.toJson()).toList(),
      'scheduledTransactions': scheduledTransactions
          .map((item) => item.toJson())
          .toList(),
      'budgets': budgets.map((item) => item.toJson()).toList(),
      'goals': goals.map((item) => item.toJson()).toList(),
      'goalContributions': goalContributions
          .map((item) => item.toJson())
          .toList(),
      'goalFundingEvents': goalFundingEvents
          .map((item) => item.toJson())
          .toList(),
      'preferences': preferences.toJson(),
    };
  }

  factory FinanceDataSet.fromJson(Map<String, Object?> json) {
    return FinanceDataSet(
      accounts: stringMapList(
        json['accounts'],
      ).map(AccountRecord.fromJson).toList(),
      categories: stringMapList(
        json['categories'],
      ).map(CategoryRecord.fromJson).toList(),
      transactions: stringMapList(
        json['transactions'],
      ).map(TransactionRecord.fromJson).toList(),
      scheduledTransactions: stringMapList(
        json['scheduledTransactions'],
      ).map(ScheduledTransactionRecord.fromJson).toList(),
      budgets: stringMapList(
        json['budgets'],
      ).map(BudgetRecord.fromJson).toList(),
      goals: stringMapList(json['goals']).map(GoalRecord.fromJson).toList(),
      goalContributions: stringMapList(
        json['goalContributions'],
      ).map(GoalContributionRecord.fromJson).toList(),
      goalFundingEvents: stringMapList(
        json['goalFundingEvents'],
      ).map(GoalFundingEventRecord.fromJson).toList(),
      preferences: UserPreferences.fromJson(stringMap(json['preferences'])),
    );
  }
}
