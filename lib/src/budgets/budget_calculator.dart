import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/transaction.dart';

DateTime budgetDateKey(DateTime date) =>
    DateTime(date.toLocal().year, date.toLocal().month, date.toLocal().day);

class BudgetPeriodWindow {
  const BudgetPeriodWindow({required this.start, required this.endExclusive});

  final DateTime start;
  final DateTime endExclusive;

  int get dayCount => endExclusive.difference(start).inDays;

  bool contains(DateTime date) {
    final key = budgetDateKey(date);
    return !key.isBefore(start) && key.isBefore(endExclusive);
  }
}

class BudgetIncludedTransaction {
  const BudgetIncludedTransaction({
    required this.transaction,
    required this.amountMinor,
  });

  final TransactionRecord transaction;
  final int amountMinor;
}

class BudgetPeriodResult {
  const BudgetPeriodResult({
    required this.window,
    required this.configuration,
    required this.baseAmountMinor,
    required this.rolloverInMinor,
    required this.availableMinor,
    required this.spentMinor,
    required this.remainingMinor,
    required this.rolloverOutMinor,
    required this.includedTransactions,
  });

  final BudgetPeriodWindow window;
  final BudgetConfigurationRevision configuration;
  final int baseAmountMinor;
  final int rolloverInMinor;
  final int availableMinor;
  final int spentMinor;
  final int remainingMinor;
  final int rolloverOutMinor;
  final List<BudgetIncludedTransaction> includedTransactions;

  bool get isOverBudget => remainingMinor < 0;
  double get progress {
    if (availableMinor <= 0) return spentMinor > 0 ? 1 : 0;
    return spentMinor / availableMinor;
  }
}

/// Deterministic, source-data-only Budget period and rollover calculations.
class BudgetCalculator {
  const BudgetCalculator();

  BudgetPeriodResult calculate({
    required BudgetRecord budget,
    required Iterable<TransactionRecord> transactions,
    required Iterable<CategoryRecord> categories,
    required DateTime date,
  }) {
    return historyThrough(
      budget: budget,
      transactions: transactions,
      categories: categories,
      date: date,
    ).last;
  }

  List<BudgetPeriodResult> historyThrough({
    required BudgetRecord budget,
    required Iterable<TransactionRecord> transactions,
    required Iterable<CategoryRecord> categories,
    required DateTime date,
  }) {
    final targetDate = budgetDateKey(date);
    final revisions = _normalizedRevisions(budget);
    final firstConfig = revisions.first;
    var cursor = periodWindowContaining(
      firstConfig,
      firstConfig.effectiveDate,
    ).start;
    final results = <BudgetPeriodResult>[];
    BudgetPeriodResult? prior;
    BudgetConfigurationRevision? priorConfiguration;

    for (var iteration = 0; iteration < 2400; iteration++) {
      final configuration = _configurationAt(revisions, cursor);
      final nominalEnd = _nextPeriodStart(configuration, cursor);
      final nextRevisionDate = _nextRevisionDateAfter(revisions, cursor);
      final window = BudgetPeriodWindow(
        start: cursor,
        endExclusive:
            nextRevisionDate != null && nextRevisionDate.isBefore(nominalEnd)
            ? nextRevisionDate
            : nominalEnd,
      );
      final included = _includedTransactions(
        configuration: configuration,
        window: window,
        transactions: transactions,
        categories: categories,
      );
      final spent = included.fold<int>(
        0,
        (total, item) => total + item.amountMinor,
      );
      final rolloverIn =
          configuration.rolloverEnabled &&
              priorConfiguration?.rolloverEnabled == true
          ? prior?.rolloverOutMinor ?? 0
          : 0;
      final available = configuration.amountMinor + rolloverIn;
      final remaining = available - spent;
      final result = BudgetPeriodResult(
        window: window,
        configuration: configuration,
        baseAmountMinor: configuration.amountMinor,
        rolloverInMinor: rolloverIn,
        availableMinor: available,
        spentMinor: spent,
        remainingMinor: remaining,
        rolloverOutMinor: configuration.rolloverEnabled ? remaining : 0,
        includedTransactions: included,
      );
      results.add(result);

      if (window.contains(targetDate) || targetDate.isBefore(window.start)) {
        return results;
      }
      prior = result;
      priorConfiguration = configuration;
      cursor = window.endExclusive;
    }
    throw StateError(
      'Budget period history exceeded its safe calculation range.',
    );
  }

  BudgetPeriodWindow periodWindowFor({
    required BudgetRecord budget,
    required DateTime date,
  }) {
    final revisions = _normalizedRevisions(budget);
    return periodWindowContaining(_configurationAt(revisions, date), date);
  }

  BudgetConfigurationRevision configurationAt(
    BudgetRecord budget,
    DateTime date,
  ) => _configurationAt(_normalizedRevisions(budget), date);

  List<BudgetConfigurationRevision> normalizedRevisions(BudgetRecord budget) =>
      _normalizedRevisions(budget);

  BudgetPeriodWindow periodWindowContaining(
    BudgetConfigurationRevision configuration,
    DateTime date,
  ) {
    final key = budgetDateKey(date);
    final startDate = configuration.startDate;
    if (startDate != null) {
      return _anchoredPeriodWindow(
        period: configuration.period,
        startDate: budgetDateKey(startDate),
        date: key,
      );
    }

    // Budgets created before Start Date retain their established calendar or
    // week-start behavior. This avoids changing existing period totals merely
    // because the app was upgraded.
    final anchor = budgetDateKey(configuration.anchorDate);
    return switch (configuration.period) {
      BudgetPeriod.weekly => () {
        final daysSinceStart =
            (key.weekday - configuration.weekStartDay + 7) % 7;
        final start = key.subtract(Duration(days: daysSinceStart));
        return BudgetPeriodWindow(
          start: start,
          endExclusive: start.add(const Duration(days: 7)),
        );
      }(),
      BudgetPeriod.biweekly => () {
        final deltaDays = key.difference(anchor).inDays;
        final periodIndex = _floorDivide(deltaDays, 14);
        final start = anchor.add(Duration(days: periodIndex * 14));
        return BudgetPeriodWindow(
          start: start,
          endExclusive: start.add(const Duration(days: 14)),
        );
      }(),
      BudgetPeriod.monthly => BudgetPeriodWindow(
        start: DateTime(key.year, key.month),
        endExclusive: DateTime(key.year, key.month + 1),
      ),
      BudgetPeriod.quarterly => () {
        final firstMonth = ((key.month - 1) ~/ 3) * 3 + 1;
        return BudgetPeriodWindow(
          start: DateTime(key.year, firstMonth),
          endExclusive: DateTime(key.year, firstMonth + 3),
        );
      }(),
      BudgetPeriod.yearly => BudgetPeriodWindow(
        start: DateTime(key.year),
        endExclusive: DateTime(key.year + 1),
      ),
    };
  }

  /// A safe display/default anchor for a legacy configuration. It preserves
  /// the period boundary the user already has today; the value is persisted
  /// only when that Budget is next saved.
  DateTime inferredStartDate(
    BudgetConfigurationRevision configuration, {
    required DateTime date,
  }) =>
      configuration.startDate ??
      periodWindowContaining(configuration, date).start;

  DateTime firstPeriodStartOnOrAfter(
    BudgetConfigurationRevision configuration,
    DateTime date,
  ) {
    final window = periodWindowContaining(configuration, date);
    return window.start.isBefore(budgetDateKey(date))
        ? window.endExclusive
        : window.start;
  }

  BudgetPeriodWindow _anchoredPeriodWindow({
    required BudgetPeriod period,
    required DateTime startDate,
    required DateTime date,
  }) {
    switch (period) {
      case BudgetPeriod.weekly:
        return _dayIntervalWindow(startDate, date, 7);
      case BudgetPeriod.biweekly:
        return _dayIntervalWindow(startDate, date, 14);
      case BudgetPeriod.monthly:
        return _monthIntervalWindow(startDate, date, 1);
      case BudgetPeriod.quarterly:
        return _monthIntervalWindow(startDate, date, 3);
      case BudgetPeriod.yearly:
        return _monthIntervalWindow(startDate, date, 12);
    }
  }

  BudgetPeriodWindow _dayIntervalWindow(
    DateTime startDate,
    DateTime date,
    int intervalDays,
  ) {
    final deltaDays = date.difference(startDate).inDays;
    final periodIndex = _floorDivide(deltaDays, intervalDays);
    final start = startDate.add(Duration(days: periodIndex * intervalDays));
    return BudgetPeriodWindow(
      start: start,
      endExclusive: start.add(Duration(days: intervalDays)),
    );
  }

  BudgetPeriodWindow _monthIntervalWindow(
    DateTime startDate,
    DateTime date,
    int intervalMonths,
  ) {
    final monthDifference =
        (date.year - startDate.year) * 12 + date.month - startDate.month;
    var periodIndex = _floorDivide(monthDifference, intervalMonths);
    var start = _addMonthsClamped(startDate, periodIndex * intervalMonths);
    if (start.isAfter(date)) {
      periodIndex--;
      start = _addMonthsClamped(startDate, periodIndex * intervalMonths);
    }
    return BudgetPeriodWindow(
      start: start,
      endExclusive: _addMonthsClamped(
        startDate,
        (periodIndex + 1) * intervalMonths,
      ),
    );
  }

  DateTime _addMonthsClamped(DateTime date, int months) {
    final monthIndex = date.month - 1 + months;
    final year = date.year + (monthIndex ~/ 12);
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, date.day > lastDay ? lastDay : date.day);
  }

  List<BudgetConfigurationRevision> _normalizedRevisions(BudgetRecord budget) {
    final revisions = [...budget.configurationRevisions];
    if (revisions.isEmpty) {
      final created = budgetDateKey(budget.sync.createdAt);
      final provisional = budget.legacyConfiguration(created);
      final effective = periodWindowContaining(provisional, created).start;
      revisions.add(
        provisional.copyWith(effectiveDate: effective, anchorDate: effective),
      );
    }
    revisions.sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
    return revisions;
  }

  BudgetConfigurationRevision _configurationAt(
    List<BudgetConfigurationRevision> revisions,
    DateTime date,
  ) {
    final key = budgetDateKey(date);
    var selected = revisions.first;
    for (final revision in revisions) {
      if (budgetDateKey(revision.effectiveDate).isAfter(key)) break;
      selected = revision;
    }
    return selected;
  }

  DateTime? _nextRevisionDateAfter(
    List<BudgetConfigurationRevision> revisions,
    DateTime date,
  ) {
    final key = budgetDateKey(date);
    for (final revision in revisions) {
      final effective = budgetDateKey(revision.effectiveDate);
      if (effective.isAfter(key)) return effective;
    }
    return null;
  }

  DateTime _nextPeriodStart(
    BudgetConfigurationRevision configuration,
    DateTime periodStart,
  ) {
    final naturalWindow = periodWindowContaining(configuration, periodStart);
    if (naturalWindow.start.isBefore(periodStart)) {
      return naturalWindow.endExclusive;
    }
    if (configuration.startDate != null) {
      return naturalWindow.endExclusive;
    }
    return switch (configuration.period) {
      BudgetPeriod.weekly => periodStart.add(const Duration(days: 7)),
      BudgetPeriod.biweekly => periodStart.add(const Duration(days: 14)),
      BudgetPeriod.monthly => DateTime(periodStart.year, periodStart.month + 1),
      BudgetPeriod.quarterly => DateTime(
        periodStart.year,
        periodStart.month + 3,
      ),
      BudgetPeriod.yearly => DateTime(periodStart.year + 1),
    };
  }

  List<BudgetIncludedTransaction> _includedTransactions({
    required BudgetConfigurationRevision configuration,
    required BudgetPeriodWindow window,
    required Iterable<TransactionRecord> transactions,
    required Iterable<CategoryRecord> categories,
  }) {
    final categoryIds = configuration.includeSubcategories
        ? _categoryAndDescendantIds(configuration.categoryIds, categories)
        : configuration.categoryIds.toSet();
    final included = <BudgetIncludedTransaction>[];

    for (final transaction in transactions) {
      if (transaction.isDeleted ||
          transaction.type != TransactionType.expense ||
          !window.contains(transaction.date)) {
        continue;
      }
      final allocations = transaction.effectiveCategoryAllocations;
      if (allocations.isNotEmpty) {
        final amount = allocations
            .where((line) => categoryIds.contains(line.categoryId))
            .fold<int>(0, (total, line) => total + line.amountMinor.abs());
        if (amount > 0) {
          included.add(
            BudgetIncludedTransaction(
              transaction: transaction,
              amountMinor: amount,
            ),
          );
        }
      } else if (categoryIds.contains(transaction.categoryId)) {
        included.add(
          BudgetIncludedTransaction(
            transaction: transaction,
            amountMinor: transaction.amountMinor.abs(),
          ),
        );
      }
    }
    included.sort((a, b) => b.transaction.date.compareTo(a.transaction.date));
    return included;
  }

  Set<String> _categoryAndDescendantIds(
    Iterable<String> roots,
    Iterable<CategoryRecord> categories,
  ) {
    final ids = roots.toSet();
    var changed = true;
    while (changed) {
      changed = false;
      for (final category in categories) {
        if (category.isDeleted) continue;
        final parentId = category.parentCategoryId;
        if (parentId != null &&
            ids.contains(parentId) &&
            ids.add(category.id)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  int _floorDivide(int value, int divisor) {
    final quotient = value ~/ divisor;
    final remainder = value % divisor;
    return remainder == 0 || value >= 0 ? quotient : quotient - 1;
  }
}
