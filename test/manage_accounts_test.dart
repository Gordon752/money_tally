import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/account.dart' as account_domain;
import 'package:money_tally/src/domain/sync_metadata.dart' as sync_domain;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/migration/v1_snapshot_migrator.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

void main() {
  test('manage-account preferences round trip with safe legacy defaults', () {
    const preferences = UserPreferences(
      defaultTransactionAccountMode: AccountDefaultMode.specific,
      defaultTransactionAccountId: 'checking',
      defaultTransferSourceMode: AccountDefaultMode.useTransactionDefault,
      lastUsedTransactionAccountId: 'cash',
      lastUsedTransferSourceAccountId: 'checking',
      newAccountIncludeInGroupBalance: false,
      newAccountIncludeInNetWorth: false,
      warnBeforeNegativeAssetBalance: false,
      automaticSyncEnabled: true,
      preferredDailySyncMinutes: 21 * 60 + 45,
      automaticBackupsEnabled: true,
      automaticBackupFrequency: AutomaticBackupFrequency.daily,
      preferredAutomaticBackupMinutes: 23 * 60 + 20,
    );

    final restored = UserPreferences.fromJson(preferences.toJson());
    expect(restored.defaultTransactionAccountMode, AccountDefaultMode.specific);
    expect(restored.defaultTransactionAccountId, 'checking');
    expect(
      restored.defaultTransferSourceMode,
      AccountDefaultMode.useTransactionDefault,
    );
    expect(restored.lastUsedTransactionAccountId, 'cash');
    expect(restored.lastUsedTransferSourceAccountId, 'checking');
    expect(restored.newAccountIncludeInGroupBalance, isFalse);
    expect(restored.newAccountIncludeInNetWorth, isFalse);
    expect(restored.warnBeforeNegativeAssetBalance, isFalse);
    expect(restored.automaticSyncEnabled, isTrue);
    expect(restored.preferredDailySyncMinutes, 21 * 60 + 45);
    expect(restored.automaticBackupsEnabled, isTrue);
    expect(restored.automaticBackupFrequency, AutomaticBackupFrequency.daily);
    expect(restored.preferredAutomaticBackupMinutes, 23 * 60 + 20);

    final legacy = UserPreferences.fromJson(const {});
    expect(legacy.defaultTransactionAccountMode, AccountDefaultMode.lastUsed);
    expect(legacy.defaultTransferSourceMode, AccountDefaultMode.lastUsed);
    expect(legacy.newAccountIncludeInGroupBalance, isTrue);
    expect(legacy.newAccountIncludeInNetWorth, isTrue);
    expect(legacy.warnBeforeNegativeAssetBalance, isTrue);
    expect(legacy.automaticSyncEnabled, isFalse);
    expect(legacy.preferredDailySyncMinutes, 22 * 60);
    expect(legacy.automaticBackupsEnabled, isFalse);
    expect(legacy.automaticBackupFrequency, AutomaticBackupFrequency.weekly);
    expect(legacy.preferredAutomaticBackupMinutes, 23 * 60);
  });

  test('invalid configured defaults fall back without retaining an orphan', () {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        preferences: migrated.preferences.copyWith(
          defaultTransactionAccountMode: AccountDefaultMode.specific,
          defaultTransactionAccountId: 'missing-account',
          lastUsedTransactionAccountId: 'checking',
          defaultTransferSourceMode: AccountDefaultMode.specific,
          defaultTransferSourceAccountId: 'missing-account',
          lastUsedTransferSourceAccountId: 'cash',
        ),
      ),
    );

    expect(resolvedDefaultTransactionAccountId(dataStore), 'checking');
    expect(resolvedDefaultTransferSourceAccountId(dataStore), 'cash');
    expect(accountDefaultLabel(dataStore, transfer: false), 'Checking');
    expect(accountDefaultLabel(dataStore, transfer: true), 'Cash');
  });

  test('account order is constrained to a complete active group', () async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final secondBanking = account_domain.AccountRecord(
      id: 'savings-test',
      name: 'Savings Test',
      type: account_domain.AccountType.savings,
      openingBalanceMinor: 50000,
      sortOrder: 100,
      sync: sync_domain.SyncMetadata.fresh(),
    );
    final dataSet = migrated.copyWith(
      accounts: [...migrated.accounts, secondBanking],
    );
    final banking = dataSet.accounts
        .where(
          (account) => account.group == account_domain.AccountGroup.banking,
        )
        .toList();
    expect(banking.length, greaterThanOrEqualTo(2));
    final dataStore = FinanceDataStore(dataSet: dataSet);
    final reversedIds = banking.reversed.map((account) => account.id).toList();

    await dataStore.reorderAccountsWithinGroup(
      group: account_domain.AccountGroup.banking,
      orderedAccountIds: reversedIds,
    );

    expect(
      dataStore.activeAccountsInDisplayOrder
          .where(
            (account) => account.group == account_domain.AccountGroup.banking,
          )
          .map((account) => account.id),
      reversedIds,
    );
    expect(
      () => dataStore.reorderAccountsWithinGroup(
        group: account_domain.AccountGroup.banking,
        orderedAccountIds: [reversedIds.first],
      ),
      throwsA(isA<FinanceDataValidationException>()),
    );
  });

  test(
    'restoring an account preserves flags and places it at group end',
    () async {
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final original = migrated.accounts.firstWhere(
        (account) => account.group == account_domain.AccountGroup.banking,
      );
      final archived = original.copyWith(
        isArchived: true,
        includeInGroupBalance: false,
        includeInNetWorth: false,
        sortOrder: -100,
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          accounts: [
            for (final account in migrated.accounts)
              if (account.id == original.id) archived else account,
          ],
        ),
      );

      await dataStore.restoreAccount(original.id);

      final restored = dataStore.accountById(original.id);
      expect(restored.isArchived, isFalse);
      expect(restored.includeInGroupBalance, isFalse);
      expect(restored.includeInNetWorth, isFalse);
      final groupAccounts = dataStore.activeAccountsInDisplayOrder
          .where(
            (account) => account.group == account_domain.AccountGroup.banking,
          )
          .toList();
      expect(groupAccounts.last.id, original.id);
    },
  );

  testWidgets('Manage Accounts exposes dedicated settings and pickers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: migrated);

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final manageAccounts = find.widgetWithText(ListTile, 'Manage accounts');
    await tester.ensureVisible(manageAccounts);
    await tester.pumpAndSettle();
    await tester.tap(manageAccounts);
    await tester.pumpAndSettle();

    expect(find.text('Manage Accounts'), findsOneWidget);
    expect(find.text('Default transaction account'), findsOneWidget);
    expect(find.text('Default transfer source'), findsOneWidget);
    expect(find.text('Account inclusion'), findsOneWidget);
    expect(find.text('Account order'), findsOneWidget);
    expect(
      find.text('Warn before an account goes below \$0.00'),
      findsOneWidget,
    );

    await tester.tap(find.text('Default transaction account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checking').last);
    await tester.pumpAndSettle();

    expect(
      dataStore.preferences.defaultTransactionAccountMode,
      AccountDefaultMode.specific,
    );
    expect(dataStore.preferences.defaultTransactionAccountId, 'checking');
    expect(find.text('Checking'), findsOneWidget);
  });

  testWidgets('overdraw confirmation is explicit and cancelable', (
    tester,
  ) async {
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final dataStore = FinanceDataStore(dataSet: migrated);
    final account = dataStore.accountById('checking');
    bool? result;

    await tester.pumpWidget(
      FinanceDataStoreScope(
        store: dataStore,
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await confirmAssetAccountOverdraw(
                  context,
                  account: account,
                  projectedBalanceMinor: -4218,
                );
              },
              child: const Text('Test warning'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Test warning'));
    await tester.pumpAndSettle();
    expect(find.text('Overdraw this account?'), findsOneWidget);
    expect(
      find.text(
        'Saving this transaction will leave Checking with a balance of -\$42.18.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('Test warning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Anyway'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets(
    'global default account preselects and asset overdraft requires confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final lowCash = account_domain.AccountRecord(
        id: 'low-cash',
        name: 'Pocket Cash',
        type: account_domain.AccountType.cash,
        openingBalanceMinor: 1000,
        sync: sync_domain.SyncMetadata.fresh(),
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(
          accounts: [...migrated.accounts, lowCash],
          preferences: migrated.preferences.copyWith(
            defaultTransactionAccountMode: AccountDefaultMode.specific,
            defaultTransactionAccountId: lowCash.id,
          ),
        ),
      );

      await tester.pumpWidget(
        MoneyTallyApp(store: legacyStore, dataStore: dataStore),
      );
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense').last);
      await tester.pumpAndSettle();

      expect(find.text('Pocket Cash'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '2000',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('transaction-insufficient-funds')),
        findsOneWidget,
      );
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining').last);
      await tester.pumpAndSettle();

      final save = find.text('Save').last;
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Overdraw this account?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Add Transaction'), findsOneWidget);

      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Anyway'));
      await tester.pumpAndSettle();
      expect(
        dataStore.transactions.where(
          (transaction) => transaction.accountId == lowCash.id,
        ),
        hasLength(1),
      );
    },
  );

  test('liability accounts are excluded from asset overdraft warnings', () {
    final sync = sync_domain.SyncMetadata.fresh();
    expect(
      accountIsAsset(
        account_domain.AccountRecord(
          id: 'checking',
          name: 'Checking',
          type: account_domain.AccountType.checking,
          openingBalanceMinor: 0,
          sync: sync,
        ),
      ),
      isTrue,
    );
    expect(
      accountIsAsset(
        account_domain.AccountRecord(
          id: 'card',
          name: 'Card',
          type: account_domain.AccountType.creditCard,
          openingBalanceMinor: 0,
          sync: sync,
        ),
      ),
      isFalse,
    );
    expect(
      accountIsAsset(
        account_domain.AccountRecord(
          id: 'loan',
          name: 'Loan',
          type: account_domain.AccountType.loan,
          openingBalanceMinor: 0,
          sync: sync,
        ),
      ),
      isFalse,
    );
  });
}
