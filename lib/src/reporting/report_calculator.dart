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
  });

  final String id;
  final String name;
  final int amountMinor;
  final double percentage;
  final String? iconName;
  final int? colorValue;
  final bool isOther;
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
    required this.monthlyTotals,
  });

  final ReportDateRange range;
  final ReportPeriod period;
  final int incomeMinor;
  final int expensesMinor;
  final List<CategoryReportTotal> categoryTotals;
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
    final categoriesById = {
      for (final category in categories) category.id: category,
    };

    for (final transaction in selectedTransactions) {
      final amountMinor = transaction.amountMinor.abs();
      if (transaction.type == TransactionType.income) {
        incomeMinor += amountMinor;
        continue;
      }

      expensesMinor += amountMinor;
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
      monthlyTotals: _monthlyTotals(reportable, trendMonthsFor(range, anchor)),
    );
  }

  void _addExpenseCategories(
    Map<String, int> totals,
    TransactionRecord transaction,
    Map<String, CategoryRecord> categoriesById,
  ) {
    if (transaction.isSplit && transaction.hasValidSplitTotal) {
      for (final line in transaction.splitLines) {
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

    final visible = ranked.take(5).toList(growable: true);
    if (ranked.length > 5) {
      visible.add(
        MapEntry(
          _otherId,
          ranked.skip(5).fold(0, (sum, entry) => sum + entry.value),
        ),
      );
    }

    return [
      for (final entry in visible)
        CategoryReportTotal(
          id: entry.key,
          name: _categoryName(entry.key, categoriesById),
          amountMinor: entry.value,
          percentage: entry.value / expensesMinor,
          iconName: categoriesById[entry.key]?.iconName,
          colorValue: categoriesById[entry.key]?.colorValue,
          isOther: entry.key == _otherId,
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
  if (id == _otherId) return 'Other';
  if (id == _uncategorizedId) return 'Uncategorized';
  final name = categoriesById[id]?.name.trim();
  return name == null || name.isEmpty ? 'Uncategorized' : name;
}

String _monthKey(DateTime date) => '${date.year}-${date.month}';

const _uncategorizedId = '__uncategorized__';
const _otherId = '__other__';
