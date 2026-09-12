import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/budgets/budget_calculator.dart';
import 'package:money_tally/src/domain/budget.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';

void main() {
  const calculator = BudgetCalculator();
  final categories = [
    _category('groceries'),
    _category('dining'),
    _category('coffee', parentId: 'dining'),
    _category('other'),
  ];

  group('budget period boundaries', () {
    test('weekly periods honor the configured week start', () {
      final sunday = _configuration(
        period: BudgetPeriod.weekly,
        weekStartDay: DateTime.sunday,
      );
      final monday = _configuration(
        period: BudgetPeriod.weekly,
        weekStartDay: DateTime.monday,
      );

      expect(
        calculator.periodWindowContaining(sunday, DateTime(2026, 7, 22)).start,
        DateTime(2026, 7, 19),
      );
      expect(
        calculator.periodWindowContaining(monday, DateTime(2026, 7, 22)).start,
        DateTime(2026, 7, 20),
      );
    });

    test('biweekly periods remain anchored in both directions', () {
      final configuration = _configuration(
        period: BudgetPeriod.biweekly,
        anchorDate: DateTime(2026, 7, 6),
      );

      expect(
        calculator
            .periodWindowContaining(configuration, DateTime(2026, 7, 25))
            .start,
        DateTime(2026, 7, 20),
      );
      expect(
        calculator
            .periodWindowContaining(configuration, DateTime(2026, 7, 5))
            .start,
        DateTime(2026, 6, 22),
      );
    });

    test('start date anchors weekly monthly and yearly periods', () {
      final weekly = _configuration(
        period: BudgetPeriod.weekly,
        startDate: DateTime(2026, 7, 15),
      );
      final monthly = _configuration(
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 7, 15),
      );
      final yearly = _configuration(
        period: BudgetPeriod.yearly,
        startDate: DateTime(2026, 7, 15),
      );

      expect(
        calculator.periodWindowContaining(weekly, DateTime(2026, 7, 22)).start,
        DateTime(2026, 7, 22),
      );
      expect(
        calculator.periodWindowContaining(monthly, DateTime(2026, 8, 14)),
        isA<BudgetPeriodWindow>()
            .having((window) => window.start, 'start', DateTime(2026, 7, 15))
            .having(
              (window) => window.endExclusive,
              'end',
              DateTime(2026, 8, 15),
            ),
      );
      expect(
        calculator.periodWindowContaining(yearly, DateTime(2027, 7, 14)).start,
        DateTime(2026, 7, 15),
      );
    });

    test('anchored monthly periods clamp shorter months safely', () {
      final configuration = _configuration(
        period: BudgetPeriod.monthly,
        startDate: DateTime(2026, 1, 31),
      );
      final window = calculator.periodWindowContaining(
        configuration,
        DateTime(2026, 2, 28),
      );

      expect(window.start, DateTime(2026, 2, 28));
      expect(window.endExclusive, DateTime(2026, 3, 31));
    });

    test('calendar monthly, quarterly, and yearly periods are stable', () {
      final monthly = calculator.periodWindowContaining(
        _configuration(period: BudgetPeriod.monthly),
        DateTime(2028, 2, 29),
      );
      final quarterly = calculator.periodWindowContaining(
        _configuration(period: BudgetPeriod.quarterly),
        DateTime(2026, 8, 31),
      );
      final yearly = calculator.periodWindowContaining(
        _configuration(period: BudgetPeriod.yearly),
        DateTime(2026, 12, 31),
      );

      expect(monthly.start, DateTime(2028, 2));
      expect(monthly.endExclusive, DateTime(2028, 3));
      expect(monthly.dayCount, 29);
      expect(quarterly.start, DateTime(2026, 7));
      expect(quarterly.endExclusive, DateTime(2026, 10));
      expect(yearly.start, DateTime(2026));
      expect(yearly.endExclusive, DateTime(2027));
    });

    test(
      'a period-type revision preserves history and reaches its next natural boundary',
      () {
        final monthly = _configuration(
          effectiveDate: DateTime(2026, 7),
          period: BudgetPeriod.monthly,
        );
        final weekly = _configuration(
          effectiveDate: DateTime(2026, 8),
          period: BudgetPeriod.weekly,
          weekStartDay: DateTime.sunday,
        ).copyWith(id: 'weekly');
        final budget = BudgetRecord(
          id: 'changing-budget',
          name: 'Changing',
          amountMinor: 60000,
          categoryIds: const ['groceries'],
          configurationRevisions: [monthly, weekly],
          sync: SyncMetadata.fresh(now: DateTime.utc(2026, 7)),
        );

        final history = calculator.historyThrough(
          budget: budget,
          transactions: const [],
          categories: categories,
          date: DateTime(2026, 8, 5),
        );

        expect(history[0].window.start, DateTime(2026, 7));
        expect(history[0].window.endExclusive, DateTime(2026, 8));
        expect(history[1].window.start, DateTime(2026, 8));
        expect(history[1].window.endExclusive, DateTime(2026, 8, 2));
        expect(history[2].window.start, DateTime(2026, 8, 2));
        expect(history[2].window.endExclusive, DateTime(2026, 8, 9));
      },
    );
  });

  group('budget spending', () {
    test('counts only eligible actual expense activity', () {
      final budget = _budget();
      final deletedSync = SyncMetadata.fresh(
        now: DateTime.utc(2026, 7, 2),
      ).deleted(now: DateTime.utc(2026, 7, 3));
      final transactions = [
        _transaction(
          'expense',
          amount: 1200,
          categoryId: 'groceries',
          date: DateTime(2026, 7, 2),
        ),
        _transaction(
          'scheduled-paid',
          amount: 800,
          categoryId: 'groceries',
          date: DateTime(2026, 7, 3),
          scheduledId: 'schedule',
        ),
        _transaction(
          'income',
          amount: 5000,
          categoryId: 'groceries',
          date: DateTime(2026, 7, 4),
          type: TransactionType.income,
        ),
        _transaction(
          'transfer',
          amount: 5000,
          categoryId: 'groceries',
          date: DateTime(2026, 7, 5),
          type: TransactionType.transfer,
        ),
        _transaction(
          'deleted',
          amount: 900,
          categoryId: 'groceries',
          date: DateTime(2026, 7, 6),
          sync: deletedSync,
        ),
      ];

      final result = calculator.calculate(
        budget: budget,
        transactions: transactions,
        categories: categories,
        date: DateTime(2026, 7, 20),
      );

      expect(result.spentMinor, 2000);
      expect(
        result.includedTransactions.map((item) => item.transaction.id),
        containsAll(<String>['expense', 'scheduled-paid']),
      );
    });

    test('uses only matching split allocations and optional descendants', () {
      final split = _transaction(
        'split',
        amount: 5000,
        categoryId: 'other',
        date: DateTime(2026, 7, 10),
        splitLines: const [
          TransactionSplitLine(
            id: 'coffee-line',
            categoryId: 'coffee',
            amountMinor: 1750,
          ),
          TransactionSplitLine(
            id: 'other-line',
            categoryId: 'other',
            amountMinor: 3250,
          ),
        ],
      );
      final withChildren = _budget(categoryIds: const ['dining']);
      final withoutChildren = _budget(
        categoryIds: const ['dining'],
        includeSubcategories: false,
      );

      expect(
        calculator
            .calculate(
              budget: withChildren,
              transactions: [split],
              categories: categories,
              date: DateTime(2026, 7, 20),
            )
            .spentMinor,
        1750,
      );
      expect(
        calculator
            .calculate(
              budget: withoutChildren,
              transactions: [split],
              categories: categories,
              date: DateTime(2026, 7, 20),
            )
            .spentMinor,
        0,
      );
    });
  });

  group('deterministic rollover', () {
    test(
      'carries positive and negative results through consecutive periods',
      () {
        final budget = _budget(
          amountMinor: 60000,
          rolloverEnabled: true,
          effectiveDate: DateTime(2026),
        );
        final transactions = [
          _transaction(
            'jan',
            amount: 50000,
            categoryId: 'groceries',
            date: DateTime(2026, 1, 10),
          ),
          _transaction(
            'feb',
            amount: 77500,
            categoryId: 'groceries',
            date: DateTime(2026, 2, 10),
          ),
          _transaction(
            'mar',
            amount: 20000,
            categoryId: 'groceries',
            date: DateTime(2026, 3, 10),
          ),
        ];

        final history = calculator.historyThrough(
          budget: budget,
          transactions: transactions,
          categories: categories,
          date: DateTime(2026, 3, 20),
        );

        expect(history[0].rolloverOutMinor, 10000);
        expect(history[1].rolloverInMinor, 10000);
        expect(history[1].availableMinor, 70000);
        expect(history[1].rolloverOutMinor, -7500);
        expect(history[2].rolloverInMinor, -7500);
        expect(history[2].availableMinor, 52500);
        expect(history[2].remainingMinor, 32500);
      },
    );

    test('is idempotent and recalculates after source data changes', () {
      final budget = _budget(
        amountMinor: 60000,
        rolloverEnabled: true,
        effectiveDate: DateTime(2026),
      );
      final january = _transaction(
        'jan',
        amount: 50000,
        categoryId: 'groceries',
        date: DateTime(2026, 1, 10),
      );

      BudgetPeriodResult calculate(List<TransactionRecord> transactions) =>
          calculator.calculate(
            budget: budget,
            transactions: transactions,
            categories: categories,
            date: DateTime(2026, 2, 20),
          );

      final first = calculate([january]);
      final repeated = calculate([january]);
      final afterDeletion = calculate([
        january.copyWith(
          sync: january.sync.deleted(now: DateTime.utc(2026, 2, 21)),
        ),
      ]);

      expect(first.rolloverInMinor, 10000);
      expect(repeated.rolloverInMinor, first.rolloverInMinor);
      expect(repeated.remainingMinor, first.remainingMinor);
      expect(afterDeletion.rolloverInMinor, 60000);
    });

    test('rollover off restores the configured base every period', () {
      final budget = _budget(amountMinor: 60000, effectiveDate: DateTime(2026));
      final result = calculator.calculate(
        budget: budget,
        transactions: [
          _transaction(
            'jan',
            amount: 50000,
            categoryId: 'groceries',
            date: DateTime(2026, 1, 10),
          ),
        ],
        categories: categories,
        date: DateTime(2026, 2, 20),
      );

      expect(result.rolloverInMinor, 0);
      expect(result.availableMinor, 60000);
    });
  });

  test('legacy budgets migrate to monthly with rollover disabled', () {
    final sync = SyncMetadata.fresh(now: DateTime.utc(2026, 7, 1));
    final budget = BudgetRecord.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'amountMinor': 50000,
      'categoryIds': ['groceries'],
      'sync': sync.toJson(),
    });

    expect(budget.period, BudgetPeriod.monthly);
    expect(budget.rolloverEnabled, isFalse);
    expect(budget.includeSubcategories, isTrue);
    expect(budget.configurationRevisions, isEmpty);
    expect(
      calculator
          .calculate(
            budget: budget,
            transactions: const [],
            categories: categories,
            date: DateTime(2026, 7, 20),
          )
          .availableMinor,
      50000,
    );
  });
}

BudgetConfigurationRevision _configuration({
  BudgetPeriod period = BudgetPeriod.monthly,
  DateTime? effectiveDate,
  DateTime? anchorDate,
  DateTime? startDate,
  int amountMinor = 60000,
  List<String> categoryIds = const ['groceries'],
  int weekStartDay = DateTime.sunday,
  bool rolloverEnabled = false,
  bool includeSubcategories = true,
}) {
  final effective = effectiveDate ?? DateTime(2026, 7, 1);
  return BudgetConfigurationRevision(
    id: 'configuration',
    effectiveDate: effective,
    period: period,
    amountMinor: amountMinor,
    categoryIds: categoryIds,
    startDate: startDate,
    anchorDate: anchorDate ?? effective,
    weekStartDay: weekStartDay,
    rolloverEnabled: rolloverEnabled,
    includeSubcategories: includeSubcategories,
  );
}

BudgetRecord _budget({
  int amountMinor = 60000,
  List<String> categoryIds = const ['groceries'],
  bool rolloverEnabled = false,
  bool includeSubcategories = true,
  DateTime? effectiveDate,
}) {
  final effective = effectiveDate ?? DateTime(2026, 7, 1);
  final configuration = _configuration(
    effectiveDate: effective,
    amountMinor: amountMinor,
    categoryIds: categoryIds,
    rolloverEnabled: rolloverEnabled,
    includeSubcategories: includeSubcategories,
  );
  return BudgetRecord(
    id: 'budget',
    name: 'Groceries',
    amountMinor: amountMinor,
    categoryIds: categoryIds,
    rolloverEnabled: rolloverEnabled,
    includeSubcategories: includeSubcategories,
    configurationRevisions: [configuration],
    sync: SyncMetadata.fresh(now: effective.toUtc()),
  );
}

CategoryRecord _category(String id, {String? parentId}) {
  return CategoryRecord(
    id: id,
    name: id,
    kind: CategoryKind.expense,
    parentCategoryId: parentId,
    sync: SyncMetadata.fresh(now: DateTime.utc(2026, 1, 1)),
  );
}

TransactionRecord _transaction(
  String id, {
  required int amount,
  required String categoryId,
  required DateTime date,
  TransactionType type = TransactionType.expense,
  List<TransactionSplitLine> splitLines = const [],
  String? scheduledId,
  SyncMetadata? sync,
}) {
  return TransactionRecord(
    id: id,
    type: type,
    accountId: 'checking',
    transferAccountId: type == TransactionType.transfer ? 'savings' : null,
    categoryId: categoryId,
    date: date,
    payee: id,
    amountMinor: amount,
    splitLines: splitLines,
    scheduledTransactionId: scheduledId,
    scheduledOccurrenceDate: scheduledId == null ? null : date,
    scheduledPlannedAmountMinor: scheduledId == null ? null : amount,
    sync: sync ?? SyncMetadata.fresh(now: date.toUtc()),
  );
}
