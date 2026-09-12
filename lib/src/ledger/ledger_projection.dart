import '../domain/category.dart';
import '../domain/transaction.dart';

/// A category selection expanded to include every descendant.  It is query
/// state only: no category or transaction is changed by applying a scope.
class LedgerCategoryScope {
  const LedgerCategoryScope._({
    required this.categoryId,
    required this.categoryIds,
    required this.label,
    required this.includesDescendants,
  });

  final String categoryId;
  final Set<String> categoryIds;
  final String label;
  final bool includesDescendants;

  factory LedgerCategoryScope.fromCategory(
    Iterable<CategoryRecord> categories,
    String categoryId,
  ) {
    final byParent = <String, List<CategoryRecord>>{};
    CategoryRecord? selected;
    for (final category in categories) {
      if (category.id == categoryId) selected = category;
      final parent = category.parentCategoryId;
      if (parent != null && parent.isNotEmpty) {
        byParent.putIfAbsent(parent, () => []).add(category);
      }
    }
    final ids = <String>{categoryId};
    final pending = <String>[categoryId];
    while (pending.isNotEmpty) {
      final parent = pending.removeLast();
      for (final child in byParent[parent] ?? const <CategoryRecord>[]) {
        if (ids.add(child.id)) pending.add(child.id);
      }
    }
    return LedgerCategoryScope._(
      categoryId: categoryId,
      categoryIds: Set.unmodifiable(ids),
      label: selected?.name ?? 'Category',
      includesDescendants: ids.length > 1,
    );
  }
}

/// Presentation of one original Ledger transaction for a filtered Ledger.
/// A category-filtered split remains one activity, but its amount is the sum
/// of only the matching effective allocations.
class LedgerTransactionProjection {
  const LedgerTransactionProjection({
    required this.transaction,
    required this.displayedAmountMinor,
    required this.matchingAllocations,
    this.categoryScope,
  });

  final TransactionRecord transaction;

  /// Signed for Ledger presentation: expenses are negative, income positive.
  final int displayedAmountMinor;
  final List<TransactionSplitLine> matchingAllocations;
  final LedgerCategoryScope? categoryScope;

  bool get isCategoryProjected => categoryScope != null;
  bool get isPartOfSplit => isCategoryProjected && transaction.isCategorySplit;
  int get originalDisplayedAmountMinor => switch (transaction.type) {
    TransactionType.expense => -transaction.amountMinor.abs(),
    TransactionType.income => transaction.amountMinor.abs(),
    TransactionType.transfer => transaction.amountMinor.abs(),
    TransactionType.goalFunding => transaction.amountMinor.abs(),
    TransactionType.adjustment => transaction.amountMinor,
  };
}

/// Returns this Ledger row's contribution to an income/expense summary.
///
/// [displayedAmountMinor] is deliberately not a financial classifier: transfers
/// have a useful signed display amount in an account Ledger, but remain internal
/// movement and must not inflate income, expense, or net summaries.
int ledgerActivitySummaryAmountMinor(LedgerTransactionProjection projection) {
  return switch (projection.transaction.type) {
    TransactionType.expense => -projection.displayedAmountMinor.abs(),
    TransactionType.income => projection.displayedAmountMinor.abs(),
    TransactionType.transfer ||
    TransactionType.goalFunding ||
    TransactionType.adjustment => 0,
  };
}

/// Produces Ledger-only projections. It relies on the canonical effective
/// allocation resolver in [TransactionRecord], so legacy mirrored lines and
/// duplicate category lines cannot be double-counted.
List<LedgerTransactionProjection> projectLedgerTransactions(
  Iterable<TransactionRecord> transactions, {
  LedgerCategoryScope? categoryScope,
}) {
  final projections = <LedgerTransactionProjection>[];
  for (final transaction in transactions) {
    if (categoryScope == null) {
      projections.add(
        LedgerTransactionProjection(
          transaction: transaction,
          displayedAmountMinor: switch (transaction.type) {
            TransactionType.expense => -transaction.amountMinor.abs(),
            TransactionType.income => transaction.amountMinor.abs(),
            TransactionType.transfer => transaction.amountMinor.abs(),
            TransactionType.goalFunding => transaction.amountMinor.abs(),
            TransactionType.adjustment => transaction.amountMinor,
          },
          matchingAllocations: const [],
        ),
      );
      continue;
    }

    if (transaction.type != TransactionType.expense &&
        transaction.type != TransactionType.income) {
      continue;
    }
    final matching = transaction.effectiveCategoryAllocations
        .where((line) => categoryScope.categoryIds.contains(line.categoryId))
        .where((line) => line.amountMinor != 0)
        .toList(growable: false);
    final amountMinor = matching.fold<int>(
      0,
      (total, line) => total + line.amountMinor.abs(),
    );
    if (amountMinor == 0) continue;
    projections.add(
      LedgerTransactionProjection(
        transaction: transaction,
        displayedAmountMinor: transaction.type == TransactionType.expense
            ? -amountMinor
            : amountMinor,
        matchingAllocations: matching,
        categoryScope: categoryScope,
      ),
    );
  }
  return projections;
}
