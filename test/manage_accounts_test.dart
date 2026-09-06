import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/account.dart' as account_domain;
import 'package:money_tally/src/domain/sync_metadata.dart' as sync_domain;
import 'package:money_tally/src/domain/transaction.dart' as transaction_domain;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/design/widgets/trackmark_switch.dart';
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

  testWidgets(
    'Account Inclusion labels and switch columns map correctly at small width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final dataStore = FinanceDataStore(dataSet: migrated);

      await tester.pumpWidget(
        FinanceDataStoreScope(
          store: dataStore,
          child: const MaterialApp(home: AccountInclusionScreen()),
        ),
      );

      expect(find.text('Group\nTotals'), findsOneWidget);
      expect(find.text('Net Worth'), findsOneWidget);
      expect(
        find.text(
          'Choose which accounts are included in group totals and net worth.',
        ),
        findsOneWidget,
      );

      final account = dataStore.activeAccountsInDisplayOrder.first;
      final row = find.byKey(ValueKey('account-inclusion-${account.id}'));
      final switches = find.descendant(
        of: row,
        matching: find.byType(TrackmarkSwitch),
      );
      expect(switches, findsNWidgets(2));
      final originalNetWorth = account.includeInNetWorth;
      await tester.tap(switches.first);
      await tester.pumpAndSettle();

      final updated = dataStore.accountById(account.id);
      expect(updated.includeInGroupBalance, !account.includeInGroupBalance);
      expect(updated.includeInNetWorth, originalNetWorth);
      expect(tester.takeException(), isNull);
    },
  );

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
                  currency: dataStore.preferences.currency,
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
    expect(find.text('This will overdraw Checking'), findsOneWidget);
    expect(
      find.text(
        'This transaction will leave Checking with a balance of -\$42.18.',
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
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
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
      expect(find.text('Balance -\$10.00'), findsOneWidget);
      expect(
        find.text('This transaction would leave Pocket Cash at -\$10.00.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining').last);
      await tester.pumpAndSettle();

      final saveButton = find.byKey(const ValueKey('transaction-save'));
      expect(
        find.byKey(const ValueKey('transaction-insufficient-funds')),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(saveButton).onPressed,
        isNotNull,
        reason: 'A valid overdrawing transaction remains saveable.',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      final save = find.text('Save').last;
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('This will overdraw Pocket Cash'), findsOneWidget);
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
      expect(dataStore.balanceForAccount(lowCash.id), -1000);
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
    expect(
      shouldWarnAssetAccountOverdraw(
        account: account_domain.AccountRecord(
          id: 'checking-warning',
          name: 'Checking',
          type: account_domain.AccountType.checking,
          openingBalanceMinor: 0,
          sync: sync,
        ),
        projectedBalanceMinor: -1,
        warningEnabled: true,
      ),
      isTrue,
    );
    expect(
      shouldWarnAssetAccountOverdraw(
        account: account_domain.AccountRecord(
          id: 'checking-no-warning',
          name: 'Checking',
          type: account_domain.AccountType.checking,
          openingBalanceMinor: 0,
          sync: sync,
        ),
        projectedBalanceMinor: -1,
        warningEnabled: false,
      ),
      isFalse,
    );
  });

  testWidgets('canceling split overdraft confirmation preserves the draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final lowCash = account_domain.AccountRecord(
      id: 'split-cash',
      name: 'Split Cash',
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
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '3000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-payee')),
      'Three way purchase',
    );
    await tester.tap(find.byKey(const ValueKey('transaction-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transaction-enable-split')));
    await tester.pumpAndSettle();

    final splitSection = find.byKey(
      const ValueKey('transaction-split-category-field'),
    );
    await tester.tap(
      find.descendant(of: splitSection, matching: find.text('Choose category')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snacks').last);
    await tester.pumpAndSettle();
    final splitFields = find.descendant(
      of: splitSection,
      matching: find.byType(TextField),
    );
    await tester.enterText(splitFields.at(1), '1000');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('transaction-add-split')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('transaction-split-category-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Walmart').last);
    await tester.pumpAndSettle();
    expect(splitFields, findsNWidgets(3));
    await tester.enterText(splitFields.at(2), '500');
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('transaction-pending-toggle')),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('transaction-pending-toggle')),
        matching: find.byType(TrackmarkSwitch),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-note')),
      'Keep every field',
    );
    final save = find.text('Save').last;
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('This will overdraw Split Cash'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Add Transaction'), findsOneWidget);
    expect(find.text('Dining'), findsWidgets);
    expect(find.text('Snacks'), findsWidgets);
    expect(find.text('Walmart'), findsWidgets);
    expect(splitFields, findsNWidgets(3));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('transaction-payee')))
          .controller
          ?.text,
      'Three way purchase',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('transaction-note')))
          .controller
          ?.text,
      'Keep every field',
    );
    expect(
      tester
          .widget<TrackmarkSwitch>(
            find.descendant(
              of: find.byKey(const ValueKey('transaction-pending-toggle')),
              matching: find.byType(TrackmarkSwitch),
            ),
          )
          .value,
      isTrue,
    );
    expect(dataStore.balanceForAccount(lowCash.id), 1000);

    await tester.tap(find.byKey(const ValueKey('transaction-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Anyway'));
    await tester.pumpAndSettle();

    final saved = dataStore.transactions.where(
      (transaction) => transaction.accountId == lowCash.id,
    );
    expect(saved, hasLength(1));
    expect(saved.single.splitLines, hasLength(3));
    expect(saved.single.splitLines.map((line) => line.amountMinor).toList(), [
      1500,
      1000,
      500,
    ]);
    expect(dataStore.balanceForAccount(lowCash.id), -2000);
  });

  testWidgets(
    'disabled overdraft warning saves without inline alarm or dialog',
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
        id: 'no-warning-cash',
        name: 'No Warning Cash',
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
            warnBeforeNegativeAssetBalance: false,
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
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '2000',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('transaction-insufficient-funds')),
        findsNothing,
      );
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dining').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('This will overdraw'), findsNothing);
      expect(dataStore.balanceForAccount(lowCash.id), -1000);
    },
  );

  testWidgets('transfer can overdraw an asset source after confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final lowCash = account_domain.AccountRecord(
      id: 'transfer-cash',
      name: 'Transfer Cash',
      type: account_domain.AccountType.cash,
      openingBalanceMinor: 1000,
      sync: sync_domain.SyncMetadata.fresh(),
    );
    final checkingBefore = migrated.balanceForAccount('checking');
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        accounts: [...migrated.accounts, lowCash],
        preferences: migrated.preferences.copyWith(
          defaultTransferSourceMode: AccountDefaultMode.specific,
          defaultTransferSourceAccountId: lowCash.id,
        ),
      ),
    );

    await tester.pumpWidget(
      MoneyTallyApp(store: legacyStore, dataStore: dataStore),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-to-transfer-cash')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checking').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transfer-amount')),
      '2000',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('transfer-insufficient-funds')),
      findsOneWidget,
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('This will overdraw Transfer Cash'), findsOneWidget);
    await tester.tap(find.text('Save Anyway'));
    await tester.pumpAndSettle();

    expect(dataStore.balanceForAccount(lowCash.id), -1000);
    expect(dataStore.balanceForAccount('checking'), checkingBefore + 2000);
  });

  testWidgets('editing an existing expense into overdraft confirms once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final category = migrated.categories.firstWhere(
      (item) => item.name == 'Dining',
    );
    final account = account_domain.AccountRecord(
      id: 'edit-cash',
      name: 'Edit Cash',
      type: account_domain.AccountType.cash,
      openingBalanceMinor: 5000,
      sync: sync_domain.SyncMetadata.fresh(),
    );
    final existing = transaction_domain.TransactionRecord(
      id: 'edit-overdraft',
      type: transaction_domain.TransactionType.expense,
      accountId: account.id,
      categoryId: category.id,
      date: DateTime(2026, 8, 20),
      payee: 'Existing purchase',
      amountMinor: 2000,
      sync: sync_domain.SyncMetadata.fresh(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(
        accounts: [...migrated.accounts, account],
        transactions: [...migrated.transactions, existing],
      ),
    );

    await tester.pumpWidget(
      FinanceDataStoreScope(
        store: dataStore,
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showTransactionDialog(
                context,
                transaction: dataStore.transactions.firstWhere(
                  (item) => item.id == existing.id,
                ),
              ),
              child: const Text('Edit test'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit test'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '6000',
    );
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('This will overdraw Edit Cash'), findsOneWidget);
    await tester.tap(find.text('Save Anyway'));
    await tester.pumpAndSettle();

    expect(dataStore.balanceForAccount(account.id), -1000);
    expect(
      dataStore.transactions.where((item) => item.id == existing.id),
      hasLength(1),
    );
    expect(
      dataStore.transactions
          .firstWhere((item) => item.id == existing.id)
          .amountMinor,
      6000,
    );
  });

  testWidgets(
    'negative balance adjustment warns, preserves draft, then saves',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final legacyStore = FinanceStore.seeded();
      final migrated = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final account = account_domain.AccountRecord(
        id: 'adjust-cash',
        name: 'Adjustment Cash',
        type: account_domain.AccountType.cash,
        openingBalanceMinor: 5000,
        sync: sync_domain.SyncMetadata.fresh(),
      );
      final dataStore = FinanceDataStore(
        dataSet: migrated.copyWith(accounts: [...migrated.accounts, account]),
      );

      await tester.pumpWidget(
        FinanceDataStoreScope(
          store: dataStore,
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAdjustBalanceDialog(context, account),
                child: const Text('Adjust test'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Adjust test'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('account-adjust-balance'));
      await tester.enterText(field, '-2500');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('adjustment-insufficient-funds')),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller?.text, r'-$25.00');
      expect(dataStore.balanceForAccount(account.id), 5000);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Anyway'));
      await tester.pumpAndSettle();
      expect(dataStore.balanceForAccount(account.id), -2500);
    },
  );

  testWidgets('credit card expense never asks for asset-overdraft approval', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final legacyStore = FinanceStore.seeded();
    final migrated = const V1SnapshotMigrator().migrate(
      legacyStore.snapshot().toJson(),
    );
    final category = migrated.categories.firstWhere(
      (item) => item.name == 'Dining',
    );
    final account = account_domain.AccountRecord(
      id: 'test-card',
      name: 'Test Card',
      type: account_domain.AccountType.creditCard,
      openingBalanceMinor: -1000,
      creditLimitMinor: 100000,
      sync: sync_domain.SyncMetadata.fresh(),
    );
    final dataStore = FinanceDataStore(
      dataSet: migrated.copyWith(accounts: [...migrated.accounts, account]),
    );

    await tester.pumpWidget(
      FinanceDataStoreScope(
        store: dataStore,
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showTransactionDialog(
                context,
                initialAccountId: account.id,
                initialIsExpense: true,
              ),
              child: const Text('Add card expense'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add card expense'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount')),
      '2500',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-payee')),
      'Card purchase',
    );
    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(category.name).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('This will overdraw'), findsNothing);
    expect(dataStore.balanceForAccount(account.id), -3500);
    expect(
      dataStore.transactions.where((item) => item.payee == 'Card purchase'),
      hasLength(1),
    );
  });
}
