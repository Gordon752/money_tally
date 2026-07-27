import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/management/management_ledger_index.dart';

void main() {
  final now = DateTime(2026, 7, 26, 18);
  final categories = [
    category('parent', 'Dining'),
    category('child', 'Restaurants', parentId: 'parent'),
    category(
      'archived-child',
      'Old Dining',
      parentId: 'parent',
      archived: true,
    ),
    category('income', 'Salary', kind: CategoryKind.income),
  ];

  test('rolling range is inclusive through today and leap-day safe', () {
    final range = RollingLedgerRange.endingToday(DateTime(2025, 2, 28, 20));
    expect(range.start, DateTime(2024, 2, 28));
    expect(range.includes(DateTime(2024, 2, 27, 23, 59)), isFalse);
    expect(range.includes(DateTime(2024, 2, 28)), isTrue);
    expect(range.includes(DateTime(2025, 2, 28, 23, 59)), isTrue);
    expect(range.includes(DateTime(2025, 3, 1)), isFalse);

    final leapRange = RollingLedgerRange.endingToday(DateTime(2024, 2, 29));
    expect(leapRange.start, DateTime(2023, 2, 28));
  });

  test(
    'category counts include descendants and deduplicate split categories',
    () {
      final index = ManagementLedgerIndex.build(
        now: now,
        categories: categories,
        transactions: [
          transaction(
            id: 'direct-parent',
            categoryId: 'parent',
            date: DateTime(2026, 7, 1),
          ),
          transaction(
            id: 'child-split',
            categoryId: 'parent',
            date: DateTime(2026, 7, 2),
            splitLines: const [
              TransactionSplitLine(
                id: 'one',
                categoryId: 'child',
                amountMinor: 500,
              ),
              TransactionSplitLine(
                id: 'duplicate',
                categoryId: 'child',
                amountMinor: 500,
              ),
            ],
          ),
          transaction(
            id: 'archived-child-history',
            categoryId: 'archived-child',
            date: DateTime(2026, 7, 3),
          ),
        ],
      );

      expect(index.categoryCount('parent'), 3);
      expect(index.categoryCount('child'), 1);
      expect(index.categoryCount('archived-child'), 1);
      expect(
        index.transactionIdsFor(
          const ManagementLedgerFilter.category(
            categoryId: 'parent',
            label: 'Dining',
          ),
        ),
        {'direct-parent', 'child-split', 'archived-child-history'},
      );
    },
  );

  test('payee index counts actual income and expenses once only', () {
    final sync = SyncMetadata.fresh(now: DateTime(2026, 1, 1));
    final index = ManagementLedgerIndex.build(
      now: now,
      categories: categories,
      transactions: [
        transaction(
          id: 'expense',
          categoryId: 'parent',
          payee: ' Love’s ',
          amountMinor: 2500,
          date: DateTime(2026, 7, 2),
        ),
        transaction(
          id: 'income',
          categoryId: 'income',
          payee: 'LOVE’S',
          amountMinor: 8000,
          type: TransactionType.income,
          date: DateTime(2026, 7, 4),
        ),
        TransactionRecord(
          id: 'transfer',
          type: TransactionType.transfer,
          accountId: 'checking',
          transferAccountId: 'savings',
          date: DateTime(2026, 7, 5),
          payee: 'Love’s',
          amountMinor: 10000,
          sync: sync,
        ),
        TransactionRecord(
          id: 'adjustment',
          type: TransactionType.adjustment,
          accountId: 'checking',
          date: DateTime(2026, 7, 5),
          payee: 'Balance adjustment',
          amountMinor: 10000,
          sync: sync,
        ),
        transaction(
          id: 'outside',
          categoryId: 'parent',
          payee: 'Love’s',
          date: DateTime(2025, 7, 25),
        ),
        transaction(
          id: 'deleted',
          categoryId: 'parent',
          payee: 'Love’s',
          date: DateTime(2026, 7, 6),
          deleted: true,
        ),
      ],
    );

    final summary = index.payeeSummary('love’s');
    expect(summary.count, 2);
    expect(summary.expenseMinor, 2500);
    expect(summary.incomeMinor, 8000);
    expect(summary.mostRecentDate, DateTime(2026, 7, 4));
    expect(index.payeeSummary('Balance adjustment').count, 0);
  });
}

TransactionRecord transaction({
  required String id,
  required String categoryId,
  required DateTime date,
  String payee = 'Market',
  int amountMinor = 1000,
  TransactionType type = TransactionType.expense,
  List<TransactionSplitLine> splitLines = const [],
  bool deleted = false,
}) {
  final sync = SyncMetadata.fresh(now: DateTime(2026, 1, 1));
  return TransactionRecord(
    id: id,
    type: type,
    accountId: 'checking',
    categoryId: categoryId,
    date: date,
    payee: payee,
    amountMinor: amountMinor,
    splitLines: splitLines,
    sync: deleted ? sync.deleted(now: DateTime(2026, 7, 10)) : sync,
  );
}

CategoryRecord category(
  String id,
  String name, {
  String? parentId,
  CategoryKind kind = CategoryKind.expense,
  bool archived = false,
}) {
  return CategoryRecord(
    id: id,
    name: name,
    kind: kind,
    parentCategoryId: parentId,
    isArchived: archived,
    sync: SyncMetadata.fresh(now: DateTime(2026, 1, 1)),
  );
}
