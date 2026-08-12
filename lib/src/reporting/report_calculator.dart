import '../domain/account.dart';
import '../domain/category.dart';
import '../domain/transaction.dart';

enum ReportDateRange {
  thisMonth('This Month'),
  lastMonth('Last Month'),
  lastThreeMonths('Last 3 Months'),
  thisYear('This Year');

  const ReportDateRange(this.label);

  final String label;
}

class ReportPeriod {
  const ReportPeriod({
    required this.start,
    required this.end,
    required this.label,
  });

  final DateTime start;
  final DateTime end;
  final String label;

  bool contains(DateTime date) {
    return !date.isBefore(start) && date.isBefore(end);
  }
}

class CategoryReportTotal {
  const CategoryReportTotal({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.percentage,
    this.iconName,
    this.colorValue,
    this.isOther = false,
    this.isUncategorized = false,
  });

  final String id;
  final String name;
  final int amountMinor;
  final double percentage;
  final String? iconName;
  final int? colorValue;
  final bool isOther;
  final bool isUncategorized;
}

class AccountReportTotal {
  const AccountReportTotal({
    required this.accountId,
    required this.name,
    required this.amountMinor,
    required this.percentage,
    required this.type,
    this.iconId,
    this.accentId,
  });

  final String accountId;
  final String name;
  final int amountMinor;
  final double percentage;
  final AccountType type;
  final String? iconId;
  final String? accentId;
}

class IncomeSourceReportTotal {
  const IncomeSourceReportTotal({
    required this.source,
    required this.amountMinor,
    required this.percentage,
  });

  final String source;
  final int amountMinor;
  final double percentage;
}

class MonthlyReportTotal {
  const MonthlyReportTotal({
    required this.month,
    required this.incomeMinor,
    required this.expensesMinor,
  });

  final DateTime month;
  final int incomeMinor;
  final int expensesMinor;

  int get netCashFlowMinor => incomeMinor - expensesMinor;
  bool get hasActivity => incomeMinor != 0 || expensesMinor != 0;
}

class ReportSnapshot {
  const ReportSnapshot({
    required this.range,
    required this.period,
    required this.incomeMinor,
    required this.expensesMinor,
    required this.categoryTotals,
    required this.accountTotals,
    required this.incomeSourceTotals,
    required this.monthlyTotals,
  });

  final ReportDateRange range;
  final ReportPeriod period;
  final int incomeMinor;
  final int expensesMinor;
  final List<CategoryReportTotal> categoryTotals;
  final List<AccountReportTotal> accountTotals;
  final List<IncomeSourceReportTotal> incomeSourceTotals;
  final List<MonthlyReportTotal> monthlyTotals;

  int get netCashFlowMinor => incomeMinor - expensesMinor;
  bool get hasExpenses => expensesMinor > 0;
  bool get hasTrendData => monthlyTotals.any((month) => month.hasActivity);
}

class MoneyReportCalculator {
  const MoneyReportCalculator();

  ReportSnapshot calculate({
    required Iterable<TransactionRecord> transactions,
    required Iterable<CategoryRecord> categories,
    Iterable<AccountRecord> accounts = const [],
    required ReportDateRange range,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final period = reportPeriodFor(range, anchor);
    final reportable = transactions
        .where(
          (transaction) =>
              !transaction.isDeleted &&
              (transaction.type == TransactionType.income ||
                  transaction.type == TransactionType.expense),
        )
        .toList(growable: false);
    final selectedTransactions = reportable
        .where((transaction) => period.contains(transaction.date))
        .toList(growable: false);

    var incomeMinor = 0;
    var expensesMinor = 0;
    final categoryAmounts = <String, int>{};
    final accountAmounts = <String, int>{};
    final incomeSourceAmounts = <String, int>{};
    final incomeSourceNames = <String, String>{};
    final categoriesById = {
      for (final category in categories) category.id: category,
    };
    final accountsById = {for (final account in accounts) account.id: account};

    for (final transaction in selectedTransactions) {
      final amountMinor = transaction.amountMinor.abs();
      if (transaction.type == TransactionType.income) {
        incomeMinor += amountMinor;
        final source = transaction.payee.trim().isEmpty
            ? 'Unspecified income'
            : transaction.payee.trim();
        final sourceKey = source.toLowerCase();
        incomeSourceNames.putIfAbsent(sourceKey, () => source);
        incomeSourceAmounts[sourceKey] =
            (incomeSourceAmounts[sourceKey] ?? 0) + amountMinor;
        continue;
      }

      expensesMinor += amountMinor;
      accountAmounts[transaction.accountId] =
          (accountAmounts[transaction.accountId] ?? 0) + amountMinor;
      _addExpenseCategories(categoryAmounts, transaction, categoriesById);
    }

    return ReportSnapshot(
      range: range,
      period: period,
      incomeMinor: incomeMinor,
      expensesMinor: expensesMinor,
      categoryTotals: _rankedCategoryTotals(
        categoryAmounts,
        expensesMinor,
        categoriesById,
      ),
      accountTotals: _rankedAccountTotals(
        accountAmounts,
        expensesMinor,
        accountsById,
      ),
      incomeSourceTotals: _rankedIncomeSourceTotals(
        incomeSourceAmounts,
        incomeSourceNames,
        incomeMinor,
      ),
      monthlyTotals: _monthlyTotals(reportable, trendMonthsFor(range, anchor)),
    );
  }

  void _addExpenseCategories(
    Map<String, int> totals,
    TransactionRecord transaction,
    Map<String, CategoryRecord> categoriesById,
  ) {
    final allocations = transaction.effectiveCategoryAllocations;
    if (allocations.isNotEmpty) {
      for (final line in allocations) {
        final key = categoriesById.containsKey(line.categoryId)
            ? line.categoryId
            : _uncategorizedId;
        totals[key] = (totals[key] ?? 0) + line.amountMinor.abs();
      }
      return;
    }

    final categoryId = transaction.categoryId;
    final key = categoryId != null && categoriesById.containsKey(categoryId)
        ? categoryId
        : _uncategorizedId;
    totals[key] = (totals[key] ?? 0) + transaction.amountMinor.abs();
  }

  List<CategoryReportTotal> _rankedCategoryTotals(
    Map<String, int> totals,
    int expensesMinor,
    Map<String, CategoryRecord> categoriesById,
  ) {
    if (expensesMinor == 0) return const [];

    final ranked = totals.entries.toList()
      ..sort((a, b) {
        final amountComparison = b.value.compareTo(a.value);
        return amountComparison == 0
            ? _categoryName(
                a.key,
                categoriesById,
              ).compareTo(_categoryName(b.key, categoriesById))
            : amountComparison;
      });

    return [
      for (final entry in ranked)
        CategoryReportTotal(
          id: entry.key,
          name: _categoryName(entry.key, categoriesById),
          amountMinor: entry.value,
          percentage: entry.value / expensesMinor,
          iconName: categoriesById[entry.key]?.iconName,
          colorValue: categoriesById[entry.key]?.colorValue,
          isOther: false,
          isUncategorized: entry.key == _uncategorizedId,
        ),
    ];
  }

  List<AccountReportTotal> _rankedAccountTotals(
    Map<String, int> totals,
    int expensesMinor,
    Map<String, AccountRecord> accountsById,
  ) {
    if (expensesMinor == 0) return const [];
    final ranked = totals.entries.toList()
      ..sort((a, b) {
        final amountComparison = b.value.compareTo(a.value);
        if (amountComparison != 0) return amountComparison;
        return (accountsById[a.key]?.name ?? 'Unknown account').compareTo(
          accountsById[b.key]?.name ?? 'Unknown account',
        );
      });
    return [
      for (final entry in ranked)
        AccountReportTotal(
          accountId: entry.key,
          name: accountsById[entry.key]?.name ?? 'Unknown account',
          amountMinor: entry.value,
          percentage: entry.value / expensesMinor,
          type: accountsById[entry.key]?.type ?? AccountType.otherBanking,
          iconId: accountsById[entry.key]?.appearanceIconId,
          accentId: accountsById[entry.key]?.appearanceAccentId,
        ),
    ];
  }

  List<IncomeSourceReportTotal> _rankedIncomeSourceTotals(
    Map<String, int> totals,
    Map<String, String> names,
    int incomeMinor,
  ) {
    if (incomeMinor == 0) return const [];
    final ranked = totals.entries.toList()
      ..sort((a, b) {
        final amountComparison = b.value.compareTo(a.value);
        return amountComparison == 0
            ? a.key.toLowerCase().compareTo(b.key.toLowerCase())
            : amountComparison;
      });
    return [
      for (final entry in ranked)
        IncomeSourceReportTotal(
          source: names[entry.key] ?? entry.key,
          amountMinor: entry.value,
          percentage: entry.value / incomeMinor,
        ),
    ];
  }

  List<MonthlyReportTotal> _monthlyTotals(
    List<TransactionRecord> transactions,
    List<DateTime> months,
  ) {
    final totals = {
      for (final month in months) _monthKey(month): [0, 0],
    };
    for (final transaction in transactions) {
      final monthTotals = totals[_monthKey(transaction.date)];
      if (monthTotals == null) continue;
      final amountMinor = transaction.amountMinor.abs();
      if (transaction.type == TransactionType.income) {
        monthTotals[0] += amountMinor;
      } else if (transaction.type == TransactionType.expense) {
        monthTotals[1] += amountMinor;
      }
    }
    return [
      for (final month in months)
        MonthlyReportTotal(
          month: month,
          incomeMinor: totals[_monthKey(month)]![0],
          expensesMinor: totals[_monthKey(month)]![1],
        ),
    ];
  }
}

ReportPeriod reportPeriodFor(ReportDateRange range, DateTime now) {
  final currentMonth = DateTime(now.year, now.month);
  return switch (range) {
    ReportDateRange.thisMonth => ReportPeriod(
      start: currentMonth,
      end: DateTime(now.year, now.month + 1),
      label: range.label,
    ),
    ReportDateRange.lastMonth => ReportPeriod(
      start: DateTime(now.year, now.month - 1),
      end: currentMonth,
      label: range.label,
    ),
    ReportDateRange.lastThreeMonths => ReportPeriod(
      start: DateTime(now.year, now.month - 3),
      end: currentMonth,
      label: range.label,
    ),
    ReportDateRange.thisYear => ReportPeriod(
      start: DateTime(now.year),
      end: DateTime(now.year + 1),
      label: range.label,
    ),
  };
}

List<DateTime> trendMonthsFor(ReportDateRange range, DateTime now) {
  final currentMonth = DateTime(now.year, now.month);
  return switch (range) {
    ReportDateRange.thisMonth => [
      for (var offset = 5; offset >= 0; offset -= 1)
        DateTime(currentMonth.year, currentMonth.month - offset),
    ],
    ReportDateRange.lastMonth => [
      for (var offset = 6; offset >= 1; offset -= 1)
        DateTime(currentMonth.year, currentMonth.month - offset),
    ],
    ReportDateRange.lastThreeMonths => [
      for (var offset = 3; offset >= 1; offset -= 1)
        DateTime(currentMonth.year, currentMonth.month - offset),
    ],
    ReportDateRange.thisYear => [
      for (var month = 1; month <= now.month; month += 1)
        DateTime(now.year, month),
    ],
  };
}

String _categoryName(String id, Map<String, CategoryRecord> categoriesById) {
  if (id == _uncategorizedId) return 'Uncategorized';
  final name = categoriesById[id]?.name.trim();
  return name == null || name.isEmpty ? 'Uncategorized' : name;
}

String _monthKey(DateTime date) => '${date.year}-${date.month}';

const _uncategorizedId = '__uncategorized__';
