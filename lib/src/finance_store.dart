part of '../main.dart';

class FinanceStore extends ChangeNotifier {
  FinanceStore({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.scheduled,
    required this.budgets,
    this.repository,
  });

  factory FinanceStore.empty({LocalFinanceRepository? repository}) {
    return FinanceStore(
      repository: repository,
      accounts: [],
      categories: [],
      transactions: [],
      scheduled: [],
      budgets: [],
    );
  }

  factory FinanceStore.seeded({LocalFinanceRepository? repository}) {
    final now = DateTime.now();
    return FinanceStore(
      repository: repository,
      accounts: [
        Account(
          id: 'checking',
          name: 'Checking',
          type: AccountType.checking,
          balanceCents: 185240,
          sync: SyncMetadata.fresh(now: now),
        ),
        Account(
          id: 'cash',
          name: 'Cash',
          type: AccountType.cash,
          balanceCents: 24700,
          sync: SyncMetadata.fresh(now: now),
        ),
        Account(
          id: 'card',
          name: 'Credit Card',
          type: AccountType.creditCard,
          balanceCents: -43822,
          sync: SyncMetadata.fresh(now: now),
        ),
      ],
      categories: [
        LedgerCategory(
          id: 'dining',
          name: 'Dining',
          kind: CategoryKind.expense,
          color: AppTheme.rose,
          sync: SyncMetadata.fresh(now: now),
        ),
        LedgerCategory(
          id: 'walmart',
          name: 'Walmart',
          kind: CategoryKind.expense,
          color: AppTheme.accent,
          sync: SyncMetadata.fresh(now: now),
        ),
        LedgerCategory(
          id: 'tobacco',
          name: 'Tobacco',
          kind: CategoryKind.expense,
          color: Color(0xFF775AA8),
          sync: SyncMetadata.fresh(now: now),
        ),
        LedgerCategory(
          id: 'snacks',
          name: 'Snacks',
          kind: CategoryKind.expense,
          color: AppTheme.gold,
          sync: SyncMetadata.fresh(now: now),
        ),
        LedgerCategory(
          id: 'movies',
          name: 'Movies',
          kind: CategoryKind.expense,
          color: AppTheme.blue,
          sync: SyncMetadata.fresh(now: now),
        ),
        LedgerCategory(
          id: 'transportation',
          name: 'Transportation',
          kind: CategoryKind.expense,
          color: Color(0xFFB96744),
          sync: SyncMetadata.fresh(now: now),
        ),
        LedgerCategory(
          id: 'income',
          name: 'Income',
          kind: CategoryKind.income,
          color: Color(0xFF4F8F5F),
          sync: SyncMetadata.fresh(now: now),
        ),
      ],
      transactions: [
        LedgerTransaction(
          id: 't1',
          accountId: 'checking',
          categoryId: 'walmart',
          date: DateTime.now().subtract(const Duration(days: 1)),
          payee: 'Walmart',
          amountCents: -6428,
          sync: SyncMetadata.fresh(now: now),
        ),
        LedgerTransaction(
          id: 't2',
          accountId: 'card',
          categoryId: 'dining',
          date: DateTime.now().subtract(const Duration(days: 2)),
          payee: 'Diner',
          amountCents: -1850,
          sync: SyncMetadata.fresh(now: now),
        ),
        LedgerTransaction(
          id: 't3',
          accountId: 'checking',
          categoryId: 'income',
          date: DateTime.now().subtract(const Duration(days: 4)),
          payee: 'Settlement',
          amountCents: 126400,
          sync: SyncMetadata.fresh(now: now),
        ),
      ],
      scheduled: [
        ScheduledTransaction(
          id: 's1',
          accountId: 'checking',
          categoryId: 'transportation',
          payee: 'Insurance',
          amountCents: -21700,
          nextDate: DateTime.now().add(const Duration(days: 5)),
          frequency: RecurrenceFrequency.monthly,
          sync: SyncMetadata.fresh(now: now),
        ),
      ],
      budgets: [
        Budget(
          id: 'b1',
          categoryId: 'dining',
          monthlyLimitCents: 25000,
          sync: SyncMetadata.fresh(now: now),
        ),
        Budget(
          id: 'b2',
          categoryId: 'walmart',
          monthlyLimitCents: 45000,
          sync: SyncMetadata.fresh(now: now),
        ),
        Budget(
          id: 'b3',
          categoryId: 'snacks',
          monthlyLimitCents: 9000,
          sync: SyncMetadata.fresh(now: now),
        ),
      ],
    );
  }

  List<Account> accounts;
  List<LedgerCategory> categories;
  List<LedgerTransaction> transactions;
  List<ScheduledTransaction> scheduled;
  List<Budget> budgets;
  final LocalFinanceRepository? repository;

  static Future<FinanceStore> load({
    LocalFinanceRepository repository = const LocalFinanceRepository(),
  }) async {
    final snapshot = await repository.load();
    if (snapshot == null) return FinanceStore.empty(repository: repository);
    return FinanceStore(
      accounts: snapshot.accounts,
      categories: snapshot.categories,
      transactions: snapshot.transactions,
      scheduled: snapshot.scheduled,
      budgets: snapshot.budgets,
      repository: repository,
    );
  }

  int get netWorthCents =>
      accounts.fold(0, (total, account) => total + account.balanceCents);

  List<LedgerTransaction> get recentTransactions {
    final copy = [...transactions];
    copy.sort((a, b) => b.date.compareTo(a.date));
    return copy;
  }

  List<ScheduledTransaction> get upcomingScheduled {
    final copy = [...scheduled];
    copy.sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return copy;
  }

  Account accountById(String id) =>
      accounts.firstWhere((account) => account.id == id);

  LedgerCategory categoryById(String id) =>
      categories.firstWhere((category) => category.id == id);

  int spentThisMonth(String categoryId) {
    final now = DateTime.now();
    return transactions
        .where(
          (transaction) =>
              transaction.categoryId == categoryId &&
              transaction.amountCents < 0 &&
              transaction.date.year == now.year &&
              transaction.date.month == now.month,
        )
        .fold(0, (total, transaction) => total + transaction.amountCents.abs());
  }

  void adjustAccountBalance(String accountId, int newBalanceCents) {
    accounts = [
      for (final account in accounts)
        if (account.id == accountId)
          account.copyWith(balanceCents: newBalanceCents)
        else
          account,
    ];
    _commit();
  }

  Account addAccount({
    required String name,
    required AccountType type,
    required int balanceCents,
  }) {
    final trimmed = name.trim();
    final slug = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final account = Account(
      id: '${slug.isEmpty ? 'account' : slug}_${DateTime.now().millisecondsSinceEpoch}',
      name: trimmed.isEmpty ? 'Account' : trimmed,
      type: type,
      balanceCents: balanceCents,
      sync: SyncMetadata.fresh(),
    );
    accounts = [...accounts, account];
    _commit();
    return account;
  }

  Account editAccount({
    required String accountId,
    required String name,
    required AccountType type,
  }) {
    late Account updatedAccount;
    accounts = [
      for (final account in accounts)
        if (account.id == accountId)
          updatedAccount = account.copyWith(name: name.trim(), type: type)
        else
          account,
    ];
    _commit();
    return updatedAccount;
  }

  Account archiveAccount(String accountId) {
    late Account archivedAccount;
    accounts = [
      for (final account in accounts)
        if (account.id == accountId)
          archivedAccount = account.copyWith(isArchived: true)
        else
          account,
    ];
    _commit();
    return archivedAccount;
  }

  void addTransaction({
    required String accountId,
    required String categoryId,
    required DateTime date,
    required String payee,
    required int amountCents,
    String note = '',
  }) {
    transactions = [
      LedgerTransaction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        accountId: accountId,
        categoryId: categoryId,
        date: date,
        payee: payee,
        amountCents: amountCents,
        note: note,
        sync: SyncMetadata.fresh(),
      ),
      ...transactions,
    ];
    accounts = [
      for (final account in accounts)
        if (account.id == accountId)
          account.copyWith(balanceCents: account.balanceCents + amountCents)
        else
          account,
    ];
    _commit();
  }

  LedgerCategory? addCategory(
    String name, {
    CategoryKind kind = CategoryKind.expense,
  }) {
    final slug = name.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    if (slug.isEmpty) return null;
    final category = LedgerCategory(
      id: '${slug}_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      kind: kind,
      color: AppTheme.accent,
      sync: SyncMetadata.fresh(),
    );
    categories = [...categories, category];
    _commit();
    return category;
  }

  void renameCategory(String id, String name) {
    categories = [
      for (final category in categories)
        if (category.id == id)
          category.copyWith(name: name.trim())
        else
          category,
    ];
    _commit();
  }

  FinanceSnapshot snapshot() {
    return FinanceSnapshot(
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      scheduled: scheduled,
      budgets: budgets,
    );
  }

  Future<void> pushSnapshot({
    required FinanceRemoteRepository remoteRepository,
    required String userId,
  }) async {
    await remoteRepository.saveSnapshot(userId: userId, snapshot: snapshot());
  }

  Future<bool> pullSnapshot({
    required FinanceRemoteRepository remoteRepository,
    required String userId,
  }) async {
    final remoteSnapshot = await remoteRepository.loadSnapshot(userId: userId);
    if (remoteSnapshot == null) return false;
    accounts = remoteSnapshot.accounts;
    categories = remoteSnapshot.categories;
    transactions = remoteSnapshot.transactions;
    scheduled = remoteSnapshot.scheduled;
    budgets = remoteSnapshot.budgets;
    _commit();
    return true;
  }

  void _commit() {
    final localRepository = repository;
    if (localRepository != null) {
      final currentSnapshot = snapshot();
      unawaited(localRepository.save(currentSnapshot));
    }
    notifyListeners();
  }

}

class FinanceStoreScope extends InheritedNotifier<FinanceStore> {
  const FinanceStoreScope({
    required FinanceStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static FinanceStore watch(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<FinanceStoreScope>();
    assert(scope != null, 'No FinanceStoreScope found');
    return scope!.notifier!;
  }

  static FinanceStore read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<FinanceStoreScope>();
    final scope = element?.widget as FinanceStoreScope?;
    assert(scope != null, 'No FinanceStoreScope found');
    return scope!.notifier!;
  }
}
