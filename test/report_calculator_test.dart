import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/reporting/report_calculator.dart';

void main() {
  const calculator = MoneyReportCalculator();
  final now = DateTime(2026, 7, 23);

  test('summary counts income and expenses once and excludes transfers', () {
    final snapshot = calculator.calculate(
      transactions: [
        transaction(
          id: 'income',
          type: TransactionType.income,
          date: DateTime(2026, 7, 2),
          amountMinor: 125000,
          categoryId: 'income',
        ),
        transaction(
          id: 'expense',
          type: TransactionType.expense,
          date: DateTime(2026, 7, 3),
          amountMinor: 30000,
          categoryId: 'groceries',
          splitLines: const [
            TransactionSplitLine(
              id: 'food',
              categoryId: 'groceries',
              amountMinor: 20000,
            ),
            TransactionSplitLine(
              id: 'home',
              categoryId: 'home',
              amountMinor: 10000,
            ),
          ],
        ),
        transaction(
          id: 'transfer',
          type: TransactionType.transfer,
          date: DateTime(2026, 7, 4),
          amountMinor: 90000,
        ),
        transaction(
          id: 'deleted',
          type: TransactionType.expense,
          date: DateTime(2026, 7, 5),
          amountMinor: 9900,
          categoryId: 'groceries',
          deleted: true,
        ),
        transaction(
          id: 'outside',
          type: TransactionType.expense,
          date: DateTime(2026, 6, 30),
          amountMinor: 8000,
          categoryId: 'groceries',
        ),
      ],
      categories: [
        category('income', 'Income', CategoryKind.income),
        category('groceries', 'Groceries', CategoryKind.expense),
        category('home', 'Home', CategoryKind.expense),
      ],
      range: ReportDateRange.thisMonth,
      now: now,
    );

    expect(snapshot.incomeMinor, 125000);
    expect(snapshot.expensesMinor, 30000);
    expect(snapshot.netCashFlowMinor, 95000);
    expect(
      snapshot.categoryTotals.fold<int>(
        0,
        (sum, category) => sum + category.amountMinor,
      ),
      30000,
    );
  });

  test('category report uses split allocations and safe category names', () {
    final archived = category(
      'archived',
      'Old Dining',
      CategoryKind.expense,
      archived: true,
    );
    final snapshot = calculator.calculate(
      transactions: [
        transaction(
          id: 'split',
          type: TransactionType.expense,
          date: DateTime(2026, 7, 10),
          amountMinor: 10000,
          categoryId: 'groceries',
          splitLines: const [
            TransactionSplitLine(
              id: 'one',
              categoryId: 'groceries',
              amountMinor: 6000,
            ),
            TransactionSplitLine(
              id: 'two',
              categoryId: 'archived',
              amountMinor: 4000,
            ),
          ],
        ),
        transaction(
          id: 'missing',
          type: TransactionType.expense,
          date: DateTime(2026, 7, 11),
          amountMinor: 2500,
          categoryId: 'missing-category',
        ),
      ],
      categories: [
        category('groceries', 'Groceries', CategoryKind.expense),
        archived,
      ],
      range: ReportDateRange.thisMonth,
      now: now,
    );

    expect(
      snapshot.categoryTotals
          .firstWhere((total) => total.name == 'Groceries')
          .amountMinor,
      6000,
    );
    expect(
      snapshot.categoryTotals
          .firstWhere((total) => total.name == 'Old Dining')
          .amountMinor,
      4000,
    );
    expect(
      snapshot.categoryTotals
          .firstWhere((total) => total.name == 'Uncategorized')
          .amountMinor,
      2500,
    );
  });

  test(
    'category report keeps top five and combines the remainder as Other',
    () {
      final categories = [
        for (var index = 1; index <= 7; index += 1)
          category('category-$index', 'Category $index', CategoryKind.expense),
      ];
      final transactions = [
        for (var index = 1; index <= 7; index += 1)
          transaction(
            id: 'expense-$index',
            type: TransactionType.expense,
            date: DateTime(2026, 7, index),
            amountMinor: (8 - index) * 1000,
            categoryId: 'category-$index',
          ),
      ];

      final snapshot = calculator.calculate(
        transactions: transactions,
        categories: categories,
        range: ReportDateRange.thisMonth,
        now: now,
      );

      expect(snapshot.categoryTotals, hasLength(6));
      expect(snapshot.categoryTotals.last.name, 'Other');
      expect(snapshot.categoryTotals.last.amountMinor, 3000);
      expect(
        snapshot.categoryTotals.fold<double>(
          0,
          (sum, category) => sum + category.percentage,
        ),
        closeTo(1, 0.000001),
      );
    },
  );

  test('date ranges and monthly trend group actual transaction dates', () {
    final snapshot = calculator.calculate(
      transactions: [
        transaction(
          id: 'april-income',
          type: TransactionType.income,
          date: DateTime(2026, 4, 2),
          amountMinor: 10000,
          categoryId: 'income',
        ),
        transaction(
          id: 'may-expense',
          type: TransactionType.expense,
          date: DateTime(2026, 5, 3),
          amountMinor: 2000,
          categoryId: 'expense',
        ),
        transaction(
          id: 'june-income',
          type: TransactionType.income,
          date: DateTime(2026, 6, 4),
          amountMinor: 12000,
          categoryId: 'income',
        ),
        transaction(
          id: 'july-expense',
          type: TransactionType.expense,
          date: DateTime(2026, 7, 5),
          amountMinor: 3000,
          categoryId: 'expense',
        ),
      ],
      categories: [
        category('income', 'Income', CategoryKind.income),
        category('expense', 'Expense', CategoryKind.expense),
      ],
      range: ReportDateRange.lastThreeMonths,
      now: now,
    );

    expect(snapshot.incomeMinor, 22000);
    expect(snapshot.expensesMinor, 2000);
    expect(snapshot.monthlyTotals.map((month) => month.month.month), [4, 5, 6]);
    expect(snapshot.monthlyTotals[0].incomeMinor, 10000);
    expect(snapshot.monthlyTotals[1].expensesMinor, 2000);
    expect(snapshot.monthlyTotals[2].incomeMinor, 12000);
  });

  test('empty report exposes category and trend empty states', () {
    final snapshot = calculator.calculate(
      transactions: const [],
      categories: const [],
      range: ReportDateRange.thisMonth,
      now: now,
    );

    expect(snapshot.incomeMinor, 0);
    expect(snapshot.expensesMinor, 0);
    expect(snapshot.categoryTotals, isEmpty);
    expect(snapshot.hasExpenses, isFalse);
    expect(snapshot.hasTrendData, isFalse);
  });
}

TransactionRecord transaction({
  required String id,
  required TransactionType type,
  required DateTime date,
  required int amountMinor,
  String? categoryId,
  List<TransactionSplitLine> splitLines = const [],
  bool deleted = false,
}) {
  final sync = SyncMetadata.fresh(now: DateTime(2026, 1, 1));
  return TransactionRecord(
    id: id,
    type: type,
    accountId: 'checking',
    transferAccountId: type == TransactionType.transfer ? 'savings' : null,
    categoryId: categoryId,
    date: date,
    payee: id,
    amountMinor: amountMinor,
    splitLines: splitLines,
    sync: deleted ? sync.deleted(now: DateTime(2026, 7, 20)) : sync,
  );
}

CategoryRecord category(
  String id,
  String name,
  CategoryKind kind, {
  bool archived = false,
}) {
  return CategoryRecord(
    id: id,
    name: name,
    kind: kind,
    isArchived: archived,
    sync: SyncMetadata.fresh(now: DateTime(2026, 1, 1)),
  );
}
