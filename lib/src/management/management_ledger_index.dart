import '../domain/category.dart';
import '../domain/transaction.dart';

enum ManagementLedgerFilterKind { category, payee }

class ManagementLedgerFilter {
  const ManagementLedgerFilter.category({
    required String categoryId,
    required this.label,
  }) : kind = ManagementLedgerFilterKind.category,
       value = categoryId;

  const ManagementLedgerFilter.payee({required String payee})
    : kind = ManagementLedgerFilterKind.payee,
      value = payee,
      label = payee;

  final ManagementLedgerFilterKind kind;
  final String value;
  final String label;
}

class RollingLedgerRange {
  const RollingLedgerRange({required this.start, required this.endExclusive});

  factory RollingLedgerRange.endingToday(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final priorYear = today.year - 1;
    final lastDayInPriorMonth = DateTime(priorYear, today.month + 1, 0).day;
    final safeDay = today.day.clamp(1, lastDayInPriorMonth);
    return RollingLedgerRange(
      start: DateTime(priorYear, today.month, safeDay),
      endExclusive: today.add(const Duration(days: 1)),
    );
  }

  final DateTime start;
  final DateTime endExclusive;

  bool includes(DateTime value) {
    final local = value.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    return !day.isBefore(start) && day.isBefore(endExclusive);
  }
}

class PayeeLedgerSummary {
  const PayeeLedgerSummary({
    required this.transactionIds,
    required this.expenseMinor,
    required this.incomeMinor,
    this.mostRecentDate,
  });

  static const empty = PayeeLedgerSummary(
    transactionIds: <String>{},
    expenseMinor: 0,
    incomeMinor: 0,
  );

  final Set<String> transactionIds;
  final int expenseMinor;
  final int incomeMinor;
  final DateTime? mostRecentDate;

  int get count => transactionIds.length;
}

class ManagementLedgerIndex {
  ManagementLedgerIndex._({
    required this.range,
    required this.categoryTransactionIds,
    required this.payeeSummaries,
  });

  factory ManagementLedgerIndex.build({
    required Iterable<TransactionRecord> transactions,
    required Iterable<CategoryRecord> categories,
    required DateTime now,
  }) {
    final range = RollingLedgerRange.endingToday(now);
    final categoriesById = {
      for (final category in categories) category.id: category,
    };
    final categoryTransactions = <String, Set<String>>{};
    final mutablePayees = <String, _MutablePayeeSummary>{};

    for (final transaction in transactions) {
      if (!_isEligibleActualTransaction(transaction, range)) continue;

      final directCategoryIds = transaction.splitLines.isNotEmpty
          ? transaction.splitLines
                .map((line) => line.categoryId)
                .where((id) => id.isNotEmpty)
                .toSet()
          : {?transaction.categoryId};
      final creditedCategories = <String>{};
      for (final categoryId in directCategoryIds) {
        var currentId = categoryId;
        final visited = <String>{};
        while (visited.add(currentId)) {
          creditedCategories.add(currentId);
          final parentId = categoriesById[currentId]?.parentCategoryId;
          if (parentId == null || parentId.isEmpty) break;
          currentId = parentId;
        }
      }
      for (final categoryId in creditedCategories) {
        categoryTransactions
            .putIfAbsent(categoryId, () => <String>{})
            .add(transaction.id);
      }

      final normalizedPayee = normalizeManagedPayee(transaction.payee);
      if (normalizedPayee.isEmpty) continue;
      final payee = mutablePayees.putIfAbsent(
        normalizedPayee,
        _MutablePayeeSummary.new,
      );
      if (!payee.transactionIds.add(transaction.id)) continue;
      switch (transaction.type) {
        case TransactionType.expense:
          payee.expenseMinor += transaction.amountMinor.abs();
        case TransactionType.income:
          payee.incomeMinor += transaction.amountMinor.abs();
        case TransactionType.transfer:
        case TransactionType.adjustment:
          break;
      }
      if (payee.mostRecentDate == null ||
          transaction.date.isAfter(payee.mostRecentDate!)) {
        payee.mostRecentDate = transaction.date;
      }
    }

    return ManagementLedgerIndex._(
      range: range,
      categoryTransactionIds: {
        for (final entry in categoryTransactions.entries)
          entry.key: Set<String>.unmodifiable(entry.value),
      },
      payeeSummaries: {
        for (final entry in mutablePayees.entries)
          entry.key: PayeeLedgerSummary(
            transactionIds: Set<String>.unmodifiable(
              entry.value.transactionIds,
            ),
            expenseMinor: entry.value.expenseMinor,
            incomeMinor: entry.value.incomeMinor,
            mostRecentDate: entry.value.mostRecentDate,
          ),
      },
    );
  }

  final RollingLedgerRange range;
  final Map<String, Set<String>> categoryTransactionIds;
  final Map<String, PayeeLedgerSummary> payeeSummaries;

  int categoryCount(String categoryId) =>
      categoryTransactionIds[categoryId]?.length ?? 0;

  PayeeLedgerSummary payeeSummary(String payee) =>
      payeeSummaries[normalizeManagedPayee(payee)] ?? PayeeLedgerSummary.empty;

  Set<String> transactionIdsFor(ManagementLedgerFilter filter) {
    return switch (filter.kind) {
      ManagementLedgerFilterKind.category =>
        categoryTransactionIds[filter.value] ?? const <String>{},
      ManagementLedgerFilterKind.payee => payeeSummary(
        filter.value,
      ).transactionIds,
    };
  }
}

bool _isEligibleActualTransaction(
  TransactionRecord transaction,
  RollingLedgerRange range,
) {
  return !transaction.isDeleted &&
      range.includes(transaction.date) &&
      (transaction.type == TransactionType.expense ||
          transaction.type == TransactionType.income);
}

String normalizeManagedPayee(String value) => value.trim().toLowerCase();

class _MutablePayeeSummary {
  final transactionIds = <String>{};
  var expenseMinor = 0;
  var incomeMinor = 0;
  DateTime? mostRecentDate;
}
