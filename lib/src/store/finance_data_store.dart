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
import '../notifications/notification_scheduler.dart';
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
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler(),
    String? userId,
    String deviceId = 'local',
  }) {
    return FinanceDataStore._(
      dataSet,
      localRepository: localRepository,
      remoteRepository: remoteRepository,
      notificationScheduler: notificationScheduler,
      userId: userId,
      deviceId: deviceId,
    );
  }

  FinanceDataStore._(
    this._dataSet, {
    this.localRepository,
    this.remoteRepository,
    this.notificationScheduler = const NoopNotificationScheduler(),
    this.userId,
    this.deviceId = 'local',
  });

  factory FinanceDataStore.empty({
    LocalFinanceDataSetRepository? localRepository,
    FinanceRecordRepository? remoteRepository,
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler(),
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
      notificationScheduler: notificationScheduler,
      userId: userId,
      deviceId: deviceId,
    );
  }

  static Future<FinanceDataStore> load({
    LocalFinanceDataSetRepository localRepository =
        const LocalFinanceDataSetRepository(),
    FinanceRecordRepository? remoteRepository,
    NotificationScheduler notificationScheduler =
        const NoopNotificationScheduler(),
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
      notificationScheduler: notificationScheduler,
      userId: userId,
      deviceId: deviceId,
    );
  }

  FinanceDataSet _dataSet;
  final LocalFinanceDataSetRepository? localRepository;
  FinanceRecordRepository? remoteRepository;
  final NotificationScheduler notificationScheduler;
  String? userId;
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
    final groupOrder = accountGroupDisplayOrderIndexes;
    return accounts
        .where((account) => account.isVisible)
        .toList(growable: false)
      ..sort(
        (a, b) => compareAccountDisplayOrder(a, b, groupOrder: groupOrder),
      );
  }

  List<AccountGroup> get accountGroupsInDisplayOrder {
    final remaining = {
      for (final group in AccountGroup.values) group.name: group,
    };
    final ordered = <AccountGroup>[];
    for (final groupName in preferences.accountGroupOrderNames) {
      final group = remaining.remove(groupName);
      if (group != null) ordered.add(group);
    }
    ordered.addAll(
      remaining.values.toList()..sort((a, b) => a.index.compareTo(b.index)),
    );
    return ordered;
  }

  Map<AccountGroup, int> get accountGroupDisplayOrderIndexes {
    final groups = accountGroupsInDisplayOrder;
    return {
      for (var index = 0; index < groups.length; index += 1)
        groups[index]: index,
    };
  }

  String accountGroupLabel(AccountGroup group) {
    final override = preferences.accountGroupLabelOverrides[group.name]?.trim();
    if (override != null && override.isNotEmpty) return override;
    return group.defaultLabel;
  }

  int balanceForAccount(String accountId) {
    return _dataSet.balanceForAccount(accountId);
  }

  int creditUsedMinorForAccount(String accountId) {
    final account = accountById(accountId);
    if (account.type != AccountType.creditCard) return 0;
    return balanceForAccount(accountId).isNegative
        ? balanceForAccount(accountId).abs()
        : 0;
  }

  int? creditAvailableMinorForAccount(String accountId) {
    final account = accountById(accountId);
    final creditLimit = account.creditLimitMinor;
    if (account.type != AccountType.creditCard || creditLimit == null) {
      return null;
    }
    return creditLimit - creditUsedMinorForAccount(accountId);
  }

  int creditLimitMinorForGroup(AccountGroup group) {
    if (group != AccountGroup.creditCards) return 0;
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              account.type == AccountType.creditCard,
        )
        .fold(0, (total, account) => total + (account.creditLimitMinor ?? 0));
  }

  int creditUsedMinorForGroup(AccountGroup group) {
    if (group != AccountGroup.creditCards) return 0;
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              account.type == AccountType.creditCard,
        )
        .fold(0, (total, account) {
          return total + creditUsedMinorForAccount(account.id);
        });
  }

  int remainingLoanMinorForAccount(String accountId) {
    final account = accountById(accountId);
    if (account.type != AccountType.loan) return 0;
    return balanceForAccount(accountId).abs();
  }

  int? loanPaidDownMinorForAccount(String accountId) {
    final account = accountById(accountId);
    final originalAmount = account.originalLoanAmountMinor;
    if (account.type != AccountType.loan || originalAmount == null) {
      return null;
    }
    final remaining = remainingLoanMinorForAccount(accountId);
    final paidDown = originalAmount - remaining;
    if (paidDown < 0) return 0;
    if (paidDown > originalAmount) return originalAmount;
    return paidDown;
  }

  int originalLoanAmountMinorForGroup(AccountGroup group) {
    if (group != AccountGroup.loans) return 0;
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              account.type == AccountType.loan,
        )
        .fold(
          0,
          (total, account) => total + (account.originalLoanAmountMinor ?? 0),
        );
  }

  int remainingLoanMinorForGroup(AccountGroup group) {
    if (group != AccountGroup.loans) return 0;
    return accounts
        .where(
          (account) =>
              account.isVisible &&
              account.includeInGroupBalance &&
              account.type == AccountType.loan &&
              account.originalLoanAmountMinor != null,
        )
        .fold(0, (total, account) {
          return total + remainingLoanMinorForAccount(account.id);
        });
  }

  int get totalAssetsMinor {
    return accounts
        .where((account) => account.isVisible && account.includeInNetWorth)
        .map((account) => balanceForAccount(account.id))
        .where((balance) => balance > 0)
        .fold(0, (total, balance) => total + balance);
  }

  int get totalLiabilitiesMinor {
    return accounts
        .where((account) => account.isVisible && account.includeInNetWorth)
        .map((account) => balanceForAccount(account.id))
        .where((balance) => balance < 0)
        .fold(0, (total, balance) => total + balance);
  }

  int get netWorthMinor => totalAssetsMinor + totalLiabilitiesMinor;

  int get openingNetWorthMinor {
    return accounts
        .where((account) => account.isVisible && account.includeInNetWorth)
        .fold(0, (total, account) => total + account.openingBalanceMinor);
  }

  int get netWorthLedgerChangeMinor => netWorthMinor - openingNetWorthMinor;

  int get availableCashMinor {
    return accounts
        .where(
          (account) =>
              account.isVisible &&
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

  int scheduledDueOrOverdueCount({DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final today = DateTime(anchor.year, anchor.month, anchor.day);
    return scheduledTransactions
        .where((item) => isScheduledDueOrOverdue(item, today))
        .length;
  }

  bool hasActionableScheduledAccounts(
    ScheduledTransactionRecord scheduledTransaction,
  ) {
    final sourceExists = accounts.any(
      (account) =>
          account.id == scheduledTransaction.accountId && account.isVisible,
    );
    if (!sourceExists) return false;
    if (scheduledTransaction.type != TransactionType.transfer) return true;
    final destinationId = scheduledTransaction.transferAccountId;
    return destinationId != null &&
        destinationId != scheduledTransaction.accountId &&
        accounts.any(
          (account) => account.id == destinationId && account.isVisible,
        );
  }

  DateTime? nextActionableScheduledDate(
    ScheduledTransactionRecord scheduledTransaction, {
    DateTime? now,
  }) {
    if (scheduledTransaction.isDeleted ||
        scheduledTransaction.lastAction != ScheduledAction.none ||
        !hasActionableScheduledAccounts(scheduledTransaction)) {
      return null;
    }
    return firstUnresolvedScheduledDate(
      scheduledTransaction,
      today: now ?? DateTime.now(),
    );
  }

  List<ScheduledTransactionRecord> actionableScheduledTransactions({
    DateTime? now,
  }) {
    final result = <ScheduledTransactionRecord>[];
    for (final scheduledTransaction in scheduledTransactions) {
      final actionableDate = nextActionableScheduledDate(
        scheduledTransaction,
        now: now,
      );
      if (actionableDate == null) continue;
      result.add(
        isSameScheduledDay(actionableDate, scheduledTransaction.nextDate)
            ? scheduledTransaction
            : scheduledTransaction.copyWith(
                nextDate: actionableDate,
                sync: scheduledTransaction.sync,
              ),
      );
    }
    result.sort((left, right) => left.nextDate.compareTo(right.nextDate));
    return result;
  }

  Future<void> resetScheduledHistory({DateTime? now}) async {
    final anchor = now ?? DateTime.now();
    final updatedSchedules = <ScheduledTransactionRecord>[];
    for (final scheduledTransaction in scheduledTransactions) {
      var nextDate = scheduledTransaction.nextDate;
      var lastAction = scheduledTransaction.lastAction;
      if (!scheduledTransaction.isDeleted &&
          scheduledTransaction.frequency != RecurrenceFrequency.once) {
        nextDate =
            firstUnresolvedScheduledDate(scheduledTransaction, today: anchor) ??
            nextDate;
        lastAction = ScheduledAction.none;
      }
      final resetSync = _touchAfterCurrent(scheduledTransaction.sync);
      var reset = scheduledTransaction.copyWith(
        nextDate: nextDate,
        lastAction: lastAction,
        occurrences: const [],
        scheduledNotificationIds: const [],
        sync: resetSync,
        clearLastReminderScheduledAt: true,
      );
      reset = await _applyScheduledNotificationState(reset);
      reset = reset.copyWith(sync: resetSync);
      updatedSchedules.add(reset);
    }

    final updatedTransactions = <TransactionRecord>[];
    final linkageClearedTransactions = <TransactionRecord>[];
    for (final transaction in transactions) {
      if (transaction.scheduledTransactionId == null &&
          transaction.scheduledOccurrenceDate == null &&
          transaction.scheduledPlannedAmountMinor == null) {
        updatedTransactions.add(transaction);
        continue;
      }
      final reset = transaction.copyWith(
        clearScheduledTransaction: true,
        sync: _touchAfterCurrent(transaction.sync),
      );
      updatedTransactions.add(reset);
      linkageClearedTransactions.add(reset);
    }

    _dataSet = _dataSet.copyWith(
      scheduledTransactions: updatedSchedules,
      transactions: updatedTransactions,
    );
    notifyListeners();
    await localRepository?.save(_dataSet);

    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote != null && currentUserId != null) {
      try {
        for (final scheduledTransaction in updatedSchedules) {
          await remote.saveScheduledTransaction(
            userId: currentUserId,
            scheduledTransaction: scheduledTransaction,
          );
        }
        for (final transaction in linkageClearedTransactions) {
          await remote.saveTransaction(
            userId: currentUserId,
            transaction: transaction,
          );
        }
      } on Exception catch (error) {
        debugPrint(
          'Remote scheduled-history reset failed; local reset retained: $error',
        );
      }
    }
    await refreshScheduledNotificationBadge(now: anchor);
  }

  SyncMetadata _touchAfterCurrent(SyncMetadata sync) {
    final currentTime = DateTime.now().toUtc();
    final timestamp = currentTime.isAfter(sync.updatedAt)
        ? currentTime
        : sync.updatedAt.add(const Duration(microseconds: 1));
    return sync.touched(now: timestamp, deviceId: deviceId);
  }

  int _totalThisMonth({required TransactionType type, DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final periodStart = DateTime(anchor.year, anchor.month);
    final periodEnd = DateTime(anchor.year, anchor.month + 1);
    return transactions
        .where((transaction) {
          return !transaction.isDeleted &&
              transaction.type == type &&
              !transaction.date.isBefore(periodStart) &&
              transaction.date.isBefore(periodEnd);
        })
        .fold(0, (total, transaction) => total + transaction.amountMinor.abs());
  }

  int spentThisMonthForBudget(BudgetRecord budget, {DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final periodStart = DateTime(anchor.year, anchor.month);
    final periodEnd = DateTime(anchor.year, anchor.month + 1);
    final categoryIds = _categoryAndDescendantIds(budget.categoryIds);

    return transactions
        .where((transaction) {
          return !transaction.isDeleted &&
              transaction.type == TransactionType.expense &&
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

  Set<String> _categoryAndDescendantIds(Iterable<String> rootCategoryIds) {
    final categoryIds = rootCategoryIds.toSet();
    var changed = true;
    while (changed) {
      changed = false;
      for (final category in categories) {
        final parentId = category.parentCategoryId;
        if (parentId != null &&
            categoryIds.contains(parentId) &&
            categoryIds.add(category.id)) {
          changed = true;
        }
      }
    }
    return categoryIds;
  }

  AccountRecord accountById(String id) {
    return accounts.firstWhere((account) => account.id == id);
  }

  CategoryRecord categoryById(String id) {
    return categories.firstWhere((category) => category.id == id);
  }

  BudgetRecord budgetById(String id) {
    return budgets.firstWhere((budget) => budget.id == id);
  }

  Future<void> replaceDataSet(
    FinanceDataSet dataSet, {
    bool persistLocal = true,
  }) async {
    _dataSet = dataSet;
    if (persistLocal) {
      await localRepository?.save(_dataSet);
    }
    await refreshScheduledNotificationBadge();
    notifyListeners();
  }

  Future<void> attachRemoteSync({
    required FinanceRecordRepository remoteRepository,
    required String userId,
  }) async {
    this.remoteRepository = remoteRepository;
    this.userId = userId;

    final remoteDataSet = await remoteRepository.loadDataSet(userId);
    if (financeDataSetHasRecords(remoteDataSet)) {
      final merged = mergeFinanceDataSetsPreferCurrent(
        incoming: remoteDataSet,
        current: _dataSet,
      );
      await replaceDataSet(merged);
      await pushAllRecordsToRemote();
      return;
    }

    await pushAllRecordsToRemote();
  }

  void detachRemoteSync() {
    remoteRepository = null;
    userId = null;
  }

  Future<void> pushAllRecordsToRemote() async {
    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote == null || currentUserId == null) return;

    for (final account in accounts) {
      await remote.saveAccount(userId: currentUserId, account: account);
    }
    for (final category in categories) {
      await remote.saveCategory(userId: currentUserId, category: category);
    }
    for (final transaction in transactions) {
      await remote.saveTransaction(
        userId: currentUserId,
        transaction: transaction,
      );
    }
    for (final scheduledTransaction in scheduledTransactions) {
      await remote.saveScheduledTransaction(
        userId: currentUserId,
        scheduledTransaction: scheduledTransaction,
      );
    }
    for (final budget in budgets) {
      await remote.saveBudget(userId: currentUserId, budget: budget);
    }
    await remote.savePreferences(
      userId: currentUserId,
      preferences: preferences,
    );
  }

  Future<void> saveAccount(AccountRecord account) async {
    final updated = _upsert(accounts, account, (item) => item.id);
    _dataSet = _dataSet.copyWith(accounts: updated);
    await _commit(accounts: [account]);
  }

  Future<void> archiveAccount(String accountId) async {
    final account = accountById(accountId).copyWith(isArchived: true);
    await saveAccount(account);
    await refreshScheduledNotifications();
  }

  Future<void> deleteAccount(String accountId) async {
    final existing = accountById(accountId);
    final account = existing.copyWith(
      isArchived: true,
      sync: existing.sync.deleted(deviceId: deviceId),
    );
    await saveAccount(account);
    await refreshScheduledNotifications();
  }

  Future<void> moveAccountWithinGroup({
    required String accountId,
    required int direction,
  }) async {
    if (direction == 0) return;
    final account = accountById(accountId);
    final groupAccounts =
        accounts
            .where((item) => item.isVisible && item.group == account.group)
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

  Future<void> saveCategoryLocalFirst(CategoryRecord category) async {
    final previousDataSet = _dataSet;
    final updated = _upsert(categories, category, (item) => item.id);
    _dataSet = _dataSet.copyWith(categories: updated);
    notifyListeners();
    try {
      await localRepository?.save(_dataSet);
    } catch (_) {
      _dataSet = previousDataSet;
      notifyListeners();
      rethrow;
    }

    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote == null || currentUserId == null) return;
    unawaited(
      remote.saveCategory(userId: currentUserId, category: category).catchError(
        (Object error) {
          debugPrint(
            'Remote category save failed; local change retained: $error',
          );
        },
      ),
    );
  }

  Future<void> archiveCategory(String categoryId) async {
    final category = categoryById(categoryId).copyWith(isArchived: true);
    await saveCategory(category);
  }

  Future<void> deleteCategory(String categoryId) async {
    final existing = categoryById(categoryId);
    final category = existing.copyWith(
      isArchived: true,
      sync: existing.sync.deleted(deviceId: deviceId),
    );
    await saveCategory(category);
  }

  Future<void> saveBudget(BudgetRecord budget) async {
    final updated = _upsert(budgets, budget, (item) => item.id);
    _dataSet = _dataSet.copyWith(budgets: updated);
    await _commit(budget: budget);
  }

  Future<void> archiveBudget(String budgetId) async {
    final budget = budgetById(budgetId).copyWith(isArchived: true);
    await saveBudget(budget);
  }

  Future<void> deleteBudget(String budgetId) async {
    final existing = budgetById(budgetId);
    final budget = existing.copyWith(
      isArchived: true,
      sync: existing.sync.deleted(deviceId: deviceId),
    );
    await saveBudget(budget);
  }

  Future<void> saveScheduledTransaction(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    final notificationAdjusted = await _applyScheduledNotificationState(
      scheduledTransaction,
    );
    final updated = _upsert(
      scheduledTransactions,
      notificationAdjusted,
      (item) => item.id,
    );
    _dataSet = _dataSet.copyWith(scheduledTransactions: updated);
    await _commit(scheduledTransaction: notificationAdjusted);
    await refreshScheduledNotificationBadge();
  }

  Future<void> saveTransactionAndSchedule({
    required TransactionRecord transaction,
    required ScheduledTransactionRecord scheduledTransaction,
  }) async {
    _validateTransaction(transaction);
    final previousDataSet = _dataSet;
    ScheduledTransactionRecord? notificationAdjusted;
    try {
      notificationAdjusted = await _applyScheduledNotificationState(
        scheduledTransaction,
      );
      _dataSet = _dataSet.copyWith(
        transactions: _upsert(transactions, transaction, (item) => item.id),
        scheduledTransactions: _upsert(
          scheduledTransactions,
          notificationAdjusted,
          (item) => item.id,
        ),
      );
      await _commit(
        transaction: transaction,
        scheduledTransaction: notificationAdjusted,
      );
      await refreshScheduledNotificationBadge();
    } catch (_) {
      _dataSet = previousDataSet;
      if (notificationAdjusted != null &&
          notificationAdjusted.scheduledNotificationIds.isNotEmpty) {
        await notificationScheduler.cancelScheduledTransaction(
          notificationAdjusted,
        );
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> savePreferences(UserPreferences preferences) async {
    final notificationsChanged =
        _dataSet.preferences.notificationsEnabled !=
        preferences.notificationsEnabled;
    _dataSet = _dataSet.copyWith(preferences: preferences);
    await _commit(preferences: preferences);
    if (notificationsChanged) {
      await refreshScheduledNotifications();
    }
  }

  Future<void> refreshScheduledNotifications() async {
    var changed = false;
    final updated = <ScheduledTransactionRecord>[];
    for (final scheduledTransaction in scheduledTransactions) {
      final adjusted = await _applyScheduledNotificationState(
        scheduledTransaction,
      );
      updated.add(adjusted);
      changed = changed || !identical(adjusted, scheduledTransaction);
    }
    if (!changed) {
      await refreshScheduledNotificationBadge();
      return;
    }

    _dataSet = _dataSet.copyWith(scheduledTransactions: updated);
    await _commit();
    await refreshScheduledNotificationBadge();
  }

  Future<void> refreshScheduledNotificationBadge({DateTime? now}) async {
    final count = preferences.notificationsEnabled
        ? scheduledDueOrOverdueCount(now: now)
        : 0;
    await notificationScheduler.updateBadgeCount(count);
  }

  Future<ScheduledTransactionRecord> _applyScheduledNotificationState(
    ScheduledTransactionRecord scheduledTransaction,
  ) async {
    final existing = _existingScheduledTransaction(scheduledTransaction.id);
    if (existing != null && existing.scheduledNotificationIds.isNotEmpty) {
      await notificationScheduler.cancelScheduledTransaction(existing);
    }

    final shouldSchedule =
        preferences.notificationsEnabled &&
        !scheduledTransaction.isDeleted &&
        hasActionableScheduledAccounts(scheduledTransaction) &&
        scheduledTransaction.hasAlert &&
        scheduledTransaction.lastAction == ScheduledAction.none;
    if (!shouldSchedule) {
      if (scheduledTransaction.scheduledNotificationIds.isEmpty &&
          scheduledTransaction.lastReminderScheduledAt == null) {
        return scheduledTransaction;
      }
      return scheduledTransaction.copyWith(
        scheduledNotificationIds: const [],
        clearLastReminderScheduledAt: true,
      );
    }

    final hasPermission = await notificationScheduler
        .requestPermissionIfNeeded();
    if (!hasPermission) {
      return scheduledTransaction.copyWith(
        scheduledNotificationIds: const [],
        clearLastReminderScheduledAt: true,
      );
    }

    final notificationIds = await notificationScheduler
        .scheduleScheduledTransaction(scheduledTransaction);
    return scheduledTransaction.copyWith(
      scheduledNotificationIds: notificationIds,
      lastReminderScheduledAt: DateTime.now(),
    );
  }

  ScheduledTransactionRecord? _existingScheduledTransaction(String id) {
    for (final scheduledTransaction in scheduledTransactions) {
      if (scheduledTransaction.id == id) return scheduledTransaction;
    }
    return null;
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
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    int? scheduledPlannedAmountMinor,
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
      scheduledTransactionId: scheduledTransactionId,
      scheduledOccurrenceDate: scheduledOccurrenceDate,
      scheduledPlannedAmountMinor: scheduledPlannedAmountMinor,
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
    List<TransactionSplitLine> splitLines = const [],
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    int? scheduledPlannedAmountMinor,
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
      splitLines: splitLines,
      scheduledTransactionId: scheduledTransactionId,
      scheduledOccurrenceDate: scheduledOccurrenceDate,
      scheduledPlannedAmountMinor: scheduledPlannedAmountMinor,
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
    String? scheduledTransactionId,
    DateTime? scheduledOccurrenceDate,
    int? scheduledPlannedAmountMinor,
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
      scheduledTransactionId: scheduledTransactionId,
      scheduledOccurrenceDate: scheduledOccurrenceDate,
      scheduledPlannedAmountMinor: scheduledPlannedAmountMinor,
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
    notifyListeners();
    await localRepository?.save(_dataSet);
    final remote = remoteRepository;
    final currentUserId = userId;
    if (remote != null && currentUserId != null) {
      try {
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
      } on Exception catch (error) {
        debugPrint('Remote finance save failed; local change retained: $error');
      }
    }
  }

  Future<void> moveAccountGroup({
    required AccountGroup group,
    required int direction,
  }) async {
    final groups = accountGroupsInDisplayOrder;
    final fromIndex = groups.indexOf(group);
    final toIndex = fromIndex + direction;
    if (fromIndex < 0 || toIndex < 0 || toIndex >= groups.length) return;

    final reordered = [...groups];
    final moving = reordered.removeAt(fromIndex);
    reordered.insert(toIndex, moving);
    await savePreferences(
      preferences.copyWith(
        accountGroupOrderNames: [
          for (final reorderedGroup in reordered) reorderedGroup.name,
        ],
      ),
    );
  }

  Future<void> renameAccountGroup({
    required AccountGroup group,
    required String label,
  }) async {
    final trimmed = label.trim();
    final overrides = {...preferences.accountGroupLabelOverrides};
    if (trimmed.isEmpty || trimmed == group.defaultLabel) {
      overrides.remove(group.name);
    } else {
      overrides[group.name] = trimmed;
    }
    await savePreferences(
      preferences.copyWith(accountGroupLabelOverrides: overrides),
    );
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

int compareAccountDisplayOrder(
  AccountRecord a,
  AccountRecord b, {
  Map<AccountGroup, int> groupOrder = const {},
}) {
  final groupComparison = (groupOrder[a.group] ?? a.group.index).compareTo(
    groupOrder[b.group] ?? b.group.index,
  );
  if (groupComparison != 0) return groupComparison;
  final sortComparison = a.sortOrder.compareTo(b.sortOrder);
  if (sortComparison != 0) return sortComparison;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

DateTime? firstUnresolvedScheduledDate(
  ScheduledTransactionRecord scheduledTransaction, {
  required DateTime today,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final resolvedDates = scheduledTransaction.occurrences
      .map((occurrence) => scheduledDayKey(occurrence.scheduledDate))
      .toSet();
  var candidate = DateTime(
    scheduledTransaction.nextDate.year,
    scheduledTransaction.nextDate.month,
    scheduledTransaction.nextDate.day,
  );

  // The cap is defensive for malformed legacy records. Monthly records can
  // still advance for centuries without locking the UI.
  for (var iteration = 0; iteration < 12000; iteration += 1) {
    final endDate = scheduledTransaction.endDate;
    if (endDate != null && candidate.isAfter(endDate)) return null;
    if (!candidate.isBefore(day) &&
        !resolvedDates.contains(scheduledDayKey(candidate))) {
      return candidate;
    }
    final next = nextScheduledRecurrenceDate(
      candidate,
      scheduledTransaction.frequency,
    );
    if (next == null || !next.isAfter(candidate)) return null;
    candidate = next;
  }
  return null;
}

DateTime? nextScheduledRecurrenceDate(
  DateTime date,
  RecurrenceFrequency frequency,
) {
  return switch (frequency) {
    RecurrenceFrequency.once => null,
    RecurrenceFrequency.weekly => date.add(const Duration(days: 7)),
    RecurrenceFrequency.biweekly => date.add(const Duration(days: 14)),
    RecurrenceFrequency.monthly => DateTime(
      date.year,
      date.month + 1,
      date.day,
    ),
    RecurrenceFrequency.yearly => DateTime(date.year + 1, date.month, date.day),
  };
}

bool isSameScheduledDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String scheduledDayKey(DateTime date) =>
    '${date.year}-${date.month}-${date.day}';

bool isScheduledDueOrOverdue(
  ScheduledTransactionRecord scheduledTransaction,
  DateTime now,
) {
  if (scheduledTransaction.isDeleted ||
      scheduledTransaction.lastAction != ScheduledAction.none) {
    return false;
  }
  final today = DateTime(now.year, now.month, now.day);
  final dueDate = DateTime(
    scheduledTransaction.nextDate.year,
    scheduledTransaction.nextDate.month,
    scheduledTransaction.nextDate.day,
  );
  return !dueDate.isAfter(today);
}

FinanceDataSet mergeFinanceDataSetsPreferCurrent({
  required FinanceDataSet incoming,
  required FinanceDataSet current,
}) {
  return incoming.copyWith(
    accounts: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.accounts,
      current: current.accounts,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    categories: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.categories,
      current: current.categories,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    transactions: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.transactions,
      current: current.transactions,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    scheduledTransactions: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.scheduledTransactions,
      current: current.scheduledTransactions,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    budgets: mergeFinanceRecordsPreferCurrent(
      incoming: incoming.budgets,
      current: current.budgets,
      idOf: (item) => item.id,
      syncOf: (item) => item.sync,
    ),
    preferences: current.preferences,
  );
}

List<T> mergeFinanceRecordsPreferCurrent<T>({
  required List<T> incoming,
  required List<T> current,
  required String Function(T item) idOf,
  required SyncMetadata Function(T item) syncOf,
}) {
  final currentById = {for (final item in current) idOf(item): item};
  final incomingIds = incoming.map(idOf).toSet();
  return [
    for (final item in incoming)
      if (currentById[idOf(item)] case final currentItem?)
        preferCurrentFinanceRecord(
          incoming: item,
          current: currentItem,
          syncOf: syncOf,
        )
      else
        item,
    for (final item in current)
      if (!incomingIds.contains(idOf(item))) item,
  ];
}

T preferCurrentFinanceRecord<T>({
  required T incoming,
  required T current,
  required SyncMetadata Function(T item) syncOf,
}) {
  final currentSync = syncOf(current);
  final incomingSync = syncOf(incoming);
  if (currentSync.isDeleted) return current;
  if (incomingSync.isDeleted) return incoming;
  return currentSync.updatedAt.isAfter(incomingSync.updatedAt) ||
          currentSync.updatedAt.isAtSameMomentAs(incomingSync.updatedAt)
      ? current
      : incoming;
}

bool financeDataSetHasRecords(FinanceDataSet dataSet) {
  return dataSet.accounts.isNotEmpty ||
      dataSet.categories.isNotEmpty ||
      dataSet.transactions.isNotEmpty ||
      dataSet.scheduledTransactions.isNotEmpty ||
      dataSet.budgets.isNotEmpty;
}
