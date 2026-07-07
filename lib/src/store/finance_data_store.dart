import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/account.dart';
import '../domain/budget.dart';
import '../domain/category.dart';
import '../domain/finance_data_set.dart';
import '../domain/scheduled_transaction.dart';
import '../domain/sync_metadata.dart';
import '../domain/transaction.dart';
import '../domain/user_preferences.dart';
import '../persistence/finance_record_repository.dart';
import '../persistence/local_finance_data_set_repository.dart';

class FinanceDataValidationException implements Exception {
  const FinanceDataValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FinanceDataStore extends ChangeNotifier {
  factory FinanceDataStore({
    required FinanceDataSet dataSet,
    LocalFinanceDataSetRepository? localRepository,
    FinanceRecordRepository? remoteRepository,
    String? userId,
    String deviceId = 'local',
  }) {
    return FinanceDataStore._(
      dataSet,
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      userId: userId,
      deviceId: deviceId,
    );
  }

  FinanceDataStore._(
    this._dataSet, {
    this.localRepository,
    this.remoteRepository,
    this.userId,
    this.deviceId = 'local',
  });

  factory FinanceDataStore.empty({
    LocalFinanceDataSetRepository? localRepository,
    FinanceRecordRepository? remoteRepository,
    String? userId,
    String deviceId = 'local',
  }) {
    return FinanceDataStore(
      dataSet: const FinanceDataSet(
        accounts: [],
        categories: [],
        transactions: [],
        scheduledTransactions: [],
        budgets: [],
        preferences: UserPreferences(),
      ),
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      userId: userId,
      deviceId: deviceId,
    );
  }

  static Future<FinanceDataStore> load({
    LocalFinanceDataSetRepository localRepository =
        const LocalFinanceDataSetRepository(),
    FinanceRecordRepository? remoteRepository,
    String? userId,
    String deviceId = 'local',
  }) async {
    final localData = await localRepository.load();
    return FinanceDataStore(
      dataSet:
          localData ??
          const FinanceDataSet(
            accounts: [],
            categories: [],
            transactions: [],
            scheduledTransactions: [],
            budgets: [],
            preferences: UserPreferences(),
          ),
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      userId: userId,
      deviceId: deviceId,
    );
  }

  FinanceDataSet _dataSet;
  final LocalFinanceDataSetRepository? localRepository;
  final FinanceRecordRepository? remoteRepository;
  final String? userId;
  final String deviceId;

  FinanceDataSet get dataSet => _dataSet;
  List<AccountRecord> get accounts => _dataSet.accounts;
  List<CategoryRecord> get categories => _dataSet.categories;
  List<TransactionRecord> get transactions => _dataSet.transactions;
  List<ScheduledTransactionRecord> get scheduledTransactions =>
      _dataSet.scheduledTransactions;
  List<BudgetRecord> get budgets => _dataSet.budgets;
  UserPreferences get preferences => _dataSet.preferences;

  List<AccountRecord> get activeAccountsInDisplayOrder {
    return accounts
        .where((account) => !account.isArchived)
        .toList(growable: false)
      ..sort(compareAccountDisplayOrder);
  }

  int balanceForAccount(String accountId) {
    return _dataSet.balanceForAccount(accountId);
  }

  int get totalAssetsMinor {
    return accounts
        .where((account) => account.includeInNetWorth)
        .map((account) => balanceForAccount(account.id))
        .where((balance) => balance > 0)
        .fold(0, (total, balance) => total + balance);
  }

  int get totalLiabilitiesMinor {
    return accounts
        .where((account) => account.includeInNetWorth)
        .map((account) => balanceForAccount(account.id))
        .where((balance) => balance < 0)
        .fold(0, (total, balance) => total + balance);
  }

  int get netWorthMinor => totalAssetsMinor + totalLiabilitiesMinor;

  int get availableCashMinor {
    return accounts
        .where(
          (account) =>
              account.includeInGroupBalance &&
              (account.group == AccountGroup.banking ||
                  account.group == AccountGroup.cash),
        )
        .map((account) => balanceForAccount(account.id))
        .fold(0, (total, balance) => total + balance);
  }

  int incomeThisMonthMinor({DateTime? now}) {
    return _totalThisMonth(type: TransactionType.income, now: now);
  }

  int expensesThisMonthMinor({DateTime? now}) {
    return _totalThisMonth(type: TransactionType.expense, now: now);
  }

  int _totalThisMonth({required TransactionType type, DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final periodStart = DateTime(anchor.year, anchor.month);
    final periodEnd = DateTime(anchor.year, anchor.month + 1);
    return transactions
        .where((transaction) {
          return transaction.type == type &&
              !transaction.date.isBefore(periodStart) &&
              transaction.date.isBefore(periodEnd);
        })
        .fold(0, (total, transaction) => total + transaction.amountMinor.abs());
  }

  int spentThisMonthForBudget(BudgetRecord budget, {DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final periodStart = DateTime(anchor.year, anchor.month);
    final periodEnd = DateTime(anchor.year, anchor.month + 1);
    final categoryIds = budget.categoryIds.toSet();

    return transactions
        .where((transaction) {
          return transaction.type == TransactionType.expense &&
              !transaction.date.isBefore(periodStart) &&
              transaction.date.isBefore(periodEnd);
        })
        .fold(0, (total, transaction) {
          if (transaction.isSplit) {
            final splitSpent = transaction.splitLines
                .where((line) => categoryIds.contains(line.categoryId))
                .fold(
                  0,
                  (splitTotal, line) => splitTotal + line.amountMinor.abs(),
                );
            return total + splitSpent;
          }
          return categoryIds.contains(transaction.categoryId)
              ? total + transaction.amountMinor.abs()
              : total;
        });
  }

  AccountRecord accountById(String id) {
    return accounts.firstWhere((account) => account.id == id);
  }

  CategoryRecord categoryById(String id) {
    return categories.firstWhere((category) => category.id == id);
  }

  Future<void> replaceDataSet(
    FinanceDataSet dataSet, {
    bool persistLocal = true,
  }) async {
    _dataSet = dataSet;
    if (persistLocal) {
      await localRepository?.save(_dataSet);
    }
    notifyListeners();
  }

  Future<void> saveAccount(AccountRecord account) async {
    final updated = _upsert(accounts, account, (item) => item.id);
    _dataSet = _dataSet.copyWith(accounts: updated);
    await _commit(accounts: [account]);
  }

  Future<void> archiveAccount(String accountId) async {
    final account = accountById(accountId).copyWith(isArchived: true);
    await saveAccount(account);
  }

  Future<void> moveAccountWithinGroup({
    required String accountId,
    required int direction,
  }) async {
    if (direction == 0) return;
    final account = accountById(accountId);
    final groupAccounts =
        accounts
            .where((item) => !item.isArchived && item.group == account.group)
            .toList(growable: false)
          ..sort(compareAccountDisplayOrder);
    final fromIndex = groupAccounts.indexWhere((item) => item.id == accountId);
    final toIndex = fromIndex + direction.sign;
    if (fromIndex < 0 || toIndex < 0 || toIndex >= groupAccounts.length) {
      return;
    }

    final reordered = [...groupAccounts];
    final moving = reordered.removeAt(fromIndex);
    reordered.insert(toIndex, moving);

    final changedAccounts = <AccountRecord>[];
    for (var index = 0; index < reordered.length; index += 1) {
      final normalizedSortOrder = index * 100;
      final item = reordered[index];
      if (item.sortOrder != normalizedSortOrder) {
        changedAccounts.add(item.copyWith(sortOrder: normalizedSortOrder));
      }
    }
    if (changedAccounts.isEmpty) return;

    final changedById = {for (final item in changedAccounts) item.id: item};
    final updated = [for (final item in accounts) changedById[item.id] ?? item];
    _dataSet = _dataSet.copyWith(accounts: updated);
    await _commit(accounts: changedAccounts);
  }

  Future<void> saveCategory(CategoryRecord category) async {
    final updated = _upsert(categories, category, (item) => item.id);
    _dataSet = _dataSet.copyWith(categories: updated);
    await _commit(category: category);
  }

  Future<void> saveBudget(BudgetRecord budget) async {
    final updated = _upsert(budgets, budget, (item) => item.id);
    _dataSet = _dataSet.copyWith(budgets: updated);
    await _commit(budget: budget);
  }

  Future<void> saveScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    final updated = _upsert(
      scheduledTransactions,
      scheduledTransaction,
      (item) => item.id,
    );
    _dataSet = _dataSet.copyWith(scheduledTransactions: updated);
    await _commit(scheduledTransaction: scheduledTransaction);
  }

  Future<void> savePreferences(UserPreferences preferences) async {
    _dataSet = _dataSet.copyWith(preferences: preferences);
    await _commit(preferences: preferences);
  }

  Future<void> saveTransaction(TransactionRecord transaction) async {
    _validateTransaction(transaction);
    final updated = _upsert(transactions, transaction, (item) => item.id);
    _dataSet = _dataSet.copyWith(transactions: updated);
    await _commit(transaction: transaction);
  }

  Future<TransactionRecord> addExpense({
    required String accountId,
    required String categoryId,
    required DateTime date,
    required String payee,
    required int amountMinor,
    String note = '',
    List<TransactionSplitLine> splitLines = const [],
  }) async {
    final transaction = TransactionRecord(
      id: _newId('txn'),
      type: TransactionType.expense,
      accountId: accountId,
      categoryId: categoryId,
      date: date,
      payee: payee,
      amountMinor: amountMinor.abs(),
      note: note,
      splitLines: splitLines,
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    await saveTransaction(transaction);
    return transaction;
  }

  Future<TransactionRecord> addIncome({
    required String accountId,
    required String categoryId,
    required DateTime date,
    required String payee,
    required int amountMinor,
    String note = '',
  }) async {
    final transaction = TransactionRecord(
      id: _newId('txn'),
      type: TransactionType.income,
      accountId: accountId,
      categoryId: categoryId,
      date: date,
      payee: payee,
      amountMinor: amountMinor.abs(),
      note: note,
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    await saveTransaction(transaction);
    return transaction;
  }

  Future<TransactionRecord> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required DateTime date,
    required String payee,
    required int amountMinor,
    String note = '',
  }) async {
    final transaction = TransactionRecord(
      id: _newId('txn'),
      type: TransactionType.transfer,
      accountId: fromAccountId,
      transferAccountId: toAccountId,
      date: date,
      payee: payee,
      amountMinor: amountMinor.abs(),
      note: note,
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    await saveTransaction(transaction);
    return transaction;
  }

  Future<TransactionRecord> adjustAccountBalance({
    required String accountId,
    required int targetBalanceMinor,
    required DateTime date,
    String payee = 'Balance adjustment',
    String note = '',
  }) async {
    final currentBalance = balanceForAccount(accountId);
    final delta = targetBalanceMinor - currentBalance;
    final transaction = TransactionRecord(
      id: _newId('adj'),
      type: TransactionType.adjustment,
      accountId: accountId,
      date: date,
      payee: payee,
      amountMinor: delta,
      note: note,
      sync: SyncMetadata.fresh(deviceId: deviceId),
    );
    await saveTransaction(transaction);
    return transaction;
  }

  void _validateTransaction(TransactionRecord transaction) {
    final accountExists = accounts.any(
      (account) => account.id == transaction.accountId,
    );
    if (!accountExists) {
      throw FinanceDataValidationException(
        'Transaction account does not exist: ${transaction.accountId}',
      );
    }

    if (transaction.type == TransactionType.transfer) {
      final transferAccountId = transaction.transferAccountId;
      if (transferAccountId == null || transferAccountId.isEmpty) {
        throw const FinanceDataValidationException(
          'Transfer requires a destination account.',
        );
      }
      if (transferAccountId == transaction.accountId) {
        throw const FinanceDataValidationException(
          'Transfer source and destination accounts must be different.',
        );
      }
      final destinationExists = accounts.any(
        (account) => account.id == transferAccountId,
      );
      if (!destinationExists) {
        throw FinanceDataValidationException(
          'Transfer destination account does not exist: $transferAccountId',
        );
      }
    }

    if (transaction.type != TransactionType.transfer &&
        transaction.type != TransactionType.adjustment) {
      final categoryId = transaction.categoryId;
      if (categoryId == null || categoryId.isEmpty) {
        throw const FinanceDataValidationException(
          'Income and expense transactions require a category.',
        );
      }
      final categoryExists = categories.any(
        (category) => category.id == categoryId,
      );
      if (!categoryExists) {
        throw FinanceDataValidationException(
          'Transaction category does not exist: $categoryId',
        );
      }
    }

    if (!transaction.hasValidSplitTotal) {
      throw FinanceDataValidationException(
        'Split total ${transaction.splitTotalMinor} does not match transaction amount ${transaction.amountMinor.abs()}.',
      );
    }
  }

  Future<void> _commit({
    List<AccountRecord> accounts = const [],
    CategoryRecord? category,
    TransactionRecord? transaction,
    ScheduledTransactionRecord? scheduledTransaction,
    BudgetRecord? budget,
    UserPreferences? preferences,
  }) async {
    await localRepository?.save(_dataSet);
    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote != null && currentUserId != null) {
      for (final account in accounts) {
        await remote.saveAccount(userId: currentUserId, account: account);
      }
      if (category != null) {
        await remote.saveCategory(userId: currentUserId, category: category);
      }
      if (transaction != null) {
        await remote.saveTransaction(
          userId: currentUserId,
          transaction: transaction,
        );
      }
      if (scheduledTransaction != null) {
        await remote.saveScheduledTransaction(
          userId: currentUserId,
          scheduledTransaction: scheduledTransaction,
        );
      }
      if (budget != null) {
        await remote.saveBudget(userId: currentUserId, budget: budget);
      }
      if (preferences != null) {
        await remote.savePreferences(
          userId: currentUserId,
          preferences: preferences,
        );
      }
    }
    notifyListeners();
  }

  List<T> _upsert<T>(List<T> items, T value, String Function(T) idOf) {
    final id = idOf(value);
    var found = false;
    final updated = <T>[];
    for (final item in items) {
      if (idOf(item) == id) {
        updated.add(value);
        found = true;
      } else {
        updated.add(item);
      }
    }
    if (!found) updated.add(value);
    return updated;
  }

  String _newId(String prefix) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }
}

int compareAccountDisplayOrder(AccountRecord a, AccountRecord b) {
  final groupComparison = a.group.index.compareTo(b.group.index);
  if (groupComparison != 0) return groupComparison;
  final sortComparison = a.sortOrder.compareTo(b.sortOrder);
  if (sortComparison != 0) return sortComparison;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
