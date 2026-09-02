import '../domain/account.dart' as v2_account;
import '../domain/budget.dart' as v2_budget;
import '../domain/category.dart' as v2_category;
import '../domain/finance_data_set.dart';
import '../domain/scheduled_transaction.dart' as v2_scheduled;
import '../domain/sync_metadata.dart' as v2_sync;
import '../domain/transaction.dart' as v2_transaction;
import '../domain/user_preferences.dart';

class V1SnapshotMigrator {
  const V1SnapshotMigrator();

  FinanceDataSet migrate(Map<String, Object?> snapshotJson) {
    final accounts = _jsonList(snapshotJson['accounts']);
    final categories = _jsonList(snapshotJson['categories']);
    final transactions = _jsonList(
      snapshotJson['transactions'],
    ).map(_transactionFromV1).toList(growable: false);
    final balanceDeltas = <String, int>{};
    for (final transaction in transactions) {
      for (final account in accounts) {
        final accountId = account['id'] as String;
        final delta = transaction.deltaForAccount(accountId);
        if (delta != 0) {
          balanceDeltas[accountId] = (balanceDeltas[accountId] ?? 0) + delta;
        }
      }
    }

    final categoriesById = {
      for (final category in categories) category['id'] as String: category,
    };

    return FinanceDataSet(
      accounts: accounts
          .map(
            (account) => _accountFromV1(
              account,
              openingBalanceMinor:
                  (account['balanceCents'] as int? ?? 0) -
                  (balanceDeltas[account['id'] as String] ?? 0),
            ),
          )
          .toList(growable: false),
      categories: categories.map(_categoryFromV1).toList(growable: false),
      transactions: transactions,
      scheduledTransactions: _jsonList(snapshotJson['scheduled'])
          .map((item) => _scheduledFromV1(item, categoriesById))
          .toList(growable: false),
      budgets: _jsonList(snapshotJson['budgets'])
          .map((budget) => _budgetFromV1(budget, categoriesById))
          .toList(growable: false),
      // Legacy users previously always saw Ledger icons. Preserve that
      // experience when importing v1 data while new installs use the current
      // first-launch default.
      preferences: const UserPreferences(showLedgerIcons: true),
    );
  }

  v2_account.AccountRecord _accountFromV1(
    Map<String, Object?> account, {
    required int openingBalanceMinor,
  }) {
    final accountType = _accountTypeFromV1(account['type'] as String?);
    return v2_account.AccountRecord(
      id: account['id'] as String,
      name: account['name'] as String? ?? '',
      type: accountType,
      openingBalanceMinor: openingBalanceMinor,
      originalLoanAmountMinor: accountType == v2_account.AccountType.loan
          ? openingBalanceMinor.abs()
          : null,
      isArchived: account['isArchived'] as bool? ?? false,
      sync: _syncFromV1(_jsonMap(account['sync'])),
    );
  }

  v2_category.CategoryRecord _categoryFromV1(Map<String, Object?> category) {
    return v2_category.CategoryRecord(
      id: category['id'] as String,
      name: category['name'] as String? ?? '',
      kind: _categoryKindFromV1(category['kind'] as String?),
      colorValue: category['color'] as int?,
      isArchived: category['isArchived'] as bool? ?? false,
      sync: _syncFromV1(_jsonMap(category['sync'])),
    );
  }

  v2_transaction.TransactionRecord _transactionFromV1(
    Map<String, Object?> transaction,
  ) {
    final isTransfer = transaction['isTransfer'] as bool? ?? false;
    final amountCents = transaction['amountCents'] as int? ?? 0;
    final type = _transactionTypeFromV1(
      amountCents: amountCents,
      isTransfer: isTransfer,
    );
    final note = transaction['note'] as String? ?? '';

    return v2_transaction.TransactionRecord(
      id: transaction['id'] as String,
      type: type,
      accountId: transaction['accountId'] as String,
      categoryId:
          type == v2_transaction.TransactionType.expense ||
              type == v2_transaction.TransactionType.income
          ? transaction['categoryId'] as String?
          : null,
      date: _dateTimeFromJson(transaction['date']),
      payee: transaction['payee'] as String? ?? '',
      amountMinor: type == v2_transaction.TransactionType.adjustment
          ? amountCents
          : amountCents.abs(),
      note: isTransfer ? _appendMigrationNote(note) : note,
      status: _transactionStatusFromV1(transaction['status'] as String?),
      sync: _syncFromV1(_jsonMap(transaction['sync'])),
    );
  }

  v2_scheduled.ScheduledTransactionRecord _scheduledFromV1(
    Map<String, Object?> item,
    Map<String, Map<String, Object?>> categoriesById,
  ) {
    final amountCents = item['amountCents'] as int? ?? 0;
    final category = categoriesById[item['categoryId'] as String?];
    final type = category?['kind'] == 'transfer'
        ? v2_transaction.TransactionType.adjustment
        : amountCents < 0
        ? v2_transaction.TransactionType.expense
        : v2_transaction.TransactionType.income;

    return v2_scheduled.ScheduledTransactionRecord(
      id: item['id'] as String,
      type: type,
      accountId: item['accountId'] as String,
      categoryId:
          type == v2_transaction.TransactionType.expense ||
              type == v2_transaction.TransactionType.income
          ? item['categoryId'] as String?
          : null,
      payee: item['payee'] as String? ?? '',
      amountMinor: type == v2_transaction.TransactionType.adjustment
          ? amountCents
          : amountCents.abs(),
      nextDate: _dateTimeFromJson(item['nextDate']),
      frequency: _recurrenceFromV1(item['frequency'] as String?),
      alertPreference: item['alertEnabled'] as bool? ?? true
          ? v2_scheduled.AlertPreference.sameDay
          : v2_scheduled.AlertPreference.none,
      sync: _syncFromV1(_jsonMap(item['sync'])),
    );
  }

  v2_budget.BudgetRecord _budgetFromV1(
    Map<String, Object?> budget,
    Map<String, Map<String, Object?>> categoriesById,
  ) {
    final categoryId = budget['categoryId'] as String;
    final categoryName =
        categoriesById[categoryId]?['name'] as String? ?? 'Budget';
    return v2_budget.BudgetRecord(
      id: budget['id'] as String,
      name: categoryName,
      amountMinor: budget['monthlyLimitCents'] as int? ?? 0,
      categoryIds: [categoryId],
      sync: _syncFromV1(_jsonMap(budget['sync'])),
    );
  }

  v2_account.AccountType _accountTypeFromV1(String? type) {
    return switch (type) {
      'cash' => v2_account.AccountType.cash,
      'checking' => v2_account.AccountType.checking,
      'savings' => v2_account.AccountType.savings,
      'creditCard' => v2_account.AccountType.creditCard,
      'loan' => v2_account.AccountType.loan,
      _ => v2_account.AccountType.otherBanking,
    };
  }

  v2_category.CategoryKind _categoryKindFromV1(String? kind) {
    return switch (kind) {
      'income' => v2_category.CategoryKind.income,
      'transfer' => v2_category.CategoryKind.transfer,
      _ => v2_category.CategoryKind.expense,
    };
  }

  v2_transaction.TransactionType _transactionTypeFromV1({
    required int amountCents,
    required bool isTransfer,
  }) {
    if (isTransfer) {
      return v2_transaction.TransactionType.adjustment;
    }
    return amountCents < 0
        ? v2_transaction.TransactionType.expense
        : v2_transaction.TransactionType.income;
  }

  v2_transaction.TransactionStatus _transactionStatusFromV1(String? status) {
    return switch (status) {
      'pending' => v2_transaction.TransactionStatus.pending,
      'reconciled' => v2_transaction.TransactionStatus.reconciled,
      _ => v2_transaction.TransactionStatus.cleared,
    };
  }

  v2_scheduled.RecurrenceFrequency _recurrenceFromV1(String? frequency) {
    return switch (frequency) {
      'once' => v2_scheduled.RecurrenceFrequency.once,
      'weekly' => v2_scheduled.RecurrenceFrequency.weekly,
      'biweekly' => v2_scheduled.RecurrenceFrequency.biweekly,
      'yearly' => v2_scheduled.RecurrenceFrequency.yearly,
      _ => v2_scheduled.RecurrenceFrequency.monthly,
    };
  }

  v2_sync.SyncMetadata _syncFromV1(Map<String, Object?> sync) {
    return v2_sync.SyncMetadata(
      createdAt: _dateTimeFromJson(sync['createdAt']),
      updatedAt: _dateTimeFromJson(sync['updatedAt']),
      deletedAt: sync['deletedAt'] == null
          ? null
          : _dateTimeFromJson(sync['deletedAt']),
      deviceId: sync['deviceId'] as String? ?? 'local',
      version: sync['version'] as int? ?? 1,
    );
  }

  String _appendMigrationNote(String note) {
    const message = 'Migrated transfer without destination account.';
    if (note.trim().isEmpty) return message;
    return '$note\n$message';
  }

  DateTime _dateTimeFromJson(Object? value) {
    if (value is String) return DateTime.parse(value);
    return DateTime.now().toUtc();
  }

  Map<String, Object?> _jsonMap(Object? value) {
    if (value == null) return const {};
    return (value as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  List<Map<String, Object?>> _jsonList(Object? value) {
    return (value as List<Object?>? ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }
}
