import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/ledger/ledger_projection.dart';

void main() {
  final sync = SyncMetadata.fresh(now: DateTime(2026, 7, 28), deviceId: 'test');
  final categories = [
    CategoryRecord(
      id: 'dining',
      name: 'Dining',
      kind: CategoryKind.expense,
      sync: sync,
    ),
    CategoryRecord(
      id: 'snacks',
      name: 'Snacks',
      kind: CategoryKind.expense,
      parentCategoryId: 'dining',
      sync: sync,
    ),
    CategoryRecord(
      id: 'tips',
      name: 'Tips',
      kind: CategoryKind.expense,
      parentCategoryId: 'dining',
      sync: sync,
    ),
    CategoryRecord(
      id: 'fuel',
      name: 'Fuel',
      kind: CategoryKind.expense,
      sync: sync,
    ),
  ];

  TransactionRecord record({
    String id = 'split',
    TransactionType type = TransactionType.expense,
    String? categoryId = 'fuel',
    int amountMinor = 7973,
    List<TransactionSplitLine> lines = const [],
  }) => TransactionRecord(
    id: id,
    type: type,
    accountId: 'wallet',
    categoryId: categoryId,
    date: DateTime(2026, 8, 11, 12),
    payee: 'Pilot',
    amountMinor: amountMinor,
    splitLines: lines,
    sync: sync,
  );

  test('subcategory projection renders only its matching split allocation', () {
    final transaction = record(
      lines: const [
        TransactionSplitLine(
          id: 'tobacco',
          categoryId: 'fuel',
          amountMinor: 7000,
        ),
        TransactionSplitLine(
          id: 'snacks',
          categoryId: 'snacks',
          amountMinor: 973,
        ),
      ],
    );
    final projections = projectLedgerTransactions([
      transaction,
    ], categoryScope: LedgerCategoryScope.fromCategory(categories, 'snacks'));

    expect(projections, hasLength(1));
    expect(projections.single.displayedAmountMinor, -973);
    expect(projections.single.isPartOfSplit, isTrue);
    expect(projections.single.matchingAllocations.single.categoryId, 'snacks');
  });

  test(
    'parent scope combines matching descendants once per original transaction',
    () {
      final transaction = record(
        lines: const [
          TransactionSplitLine(
            id: 'snacks',
            categoryId: 'snacks',
            amountMinor: 500,
          ),
          TransactionSplitLine(
            id: 'tips',
            categoryId: 'tips',
            amountMinor: 200,
          ),
          TransactionSplitLine(
            id: 'fuel',
            categoryId: 'fuel',
            amountMinor: 300,
          ),
        ],
        amountMinor: 1000,
      );
      final projections = projectLedgerTransactions([
        transaction,
      ], categoryScope: LedgerCategoryScope.fromCategory(categories, 'dining'));

      expect(projections, hasLength(1));
      expect(projections.single.displayedAmountMinor, -700);
      expect(projections.single.matchingAllocations, hasLength(2));
    },
  );

  test(
    'single category and legacy mirrored records retain their full amount',
    () {
      final primary = record(categoryId: 'snacks', amountMinor: 1250);
      final mirrored = record(
        id: 'mirrored',
        categoryId: 'snacks',
        amountMinor: 1250,
        lines: const [
          TransactionSplitLine(
            id: 'mirror',
            categoryId: 'snacks',
            amountMinor: 1250,
          ),
        ],
      );
      final scope = LedgerCategoryScope.fromCategory(categories, 'snacks');

      final projections = projectLedgerTransactions([
        primary,
        mirrored,
      ], categoryScope: scope);
      expect(
        projections.map((item) => item.displayedAmountMinor),
        everyElement(equals(-1250)),
      );
      expect(projections.every((item) => !item.isPartOfSplit), isTrue);
    },
  );

  test(
    'zero and non-category transactions do not enter category projections',
    () {
      final zero = record(
        lines: const [
          TransactionSplitLine(
            id: 'zero',
            categoryId: 'snacks',
            amountMinor: 0,
          ),
        ],
      );
      final transfer = record(
        id: 'transfer',
        type: TransactionType.transfer,
        categoryId: null,
      );
      final projections = projectLedgerTransactions([
        zero,
        transfer,
      ], categoryScope: LedgerCategoryScope.fromCategory(categories, 'snacks'));
      expect(projections, isEmpty);
    },
  );
}
