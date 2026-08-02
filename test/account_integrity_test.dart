import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/domain/account.dart' as v2_account;
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/sync_metadata.dart' as v2_sync;
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/migration/v1_snapshot_migrator.dart';
import 'package:money_tally/src/migration/finance_data_bootstrapper.dart';

void main() {
  test(
    'legacy account bridge preserves every field on an existing AccountRecord',
    () {
      final legacyStore = FinanceStore(
        accounts: [
          Account(
            id: 'discover',
            name: 'Discover',
            type: AccountType.creditCard,
            balanceCents: -12345,
            sync: SyncMetadata.fresh(now: DateTime.utc(2026, 8, 2)),
          ),
        ],
        categories: const [],
        transactions: const [],
        scheduled: const [],
        budgets: const [],
      );
      final incoming = const V1SnapshotMigrator().migrate(
        legacyStore.snapshot().toJson(),
      );
      final currentAccount = v2_account.AccountRecord(
        id: 'discover',
        name: 'Discover',
        type: v2_account.AccountType.creditCard,
        openingBalanceMinor: -12345,
        creditLimitMinor: 650000,
        isArchived: false,
        includeInGroupBalance: false,
        includeInNetWorth: false,
        sortOrder: 300,
        sync: v2_sync.SyncMetadata.fresh(now: DateTime.utc(2026, 8, 1)),
      );

      // The legacy record is newer but has no creditLimitMinor or the other
      // v2-only fields. That timestamp difference was the data-loss trigger.
      expect(incoming.accounts.single.creditLimitMinor, isNull);
      final merged = mergeLegacyDataSetIntoV2(
        incoming: incoming,
        current: FinanceDataSet(
          accounts: [currentAccount],
          categories: const [],
          transactions: const [],
          scheduledTransactions: const [],
          budgets: const [],
          preferences: const UserPreferences(),
        ),
      );

      expect(merged.accounts.single.toJson(), currentAccount.toJson());
    },
  );

  test('legacy-only accounts remain available for first-time migration', () {
    final incoming = FinanceDataSet(
      accounts: [
        v2_account.AccountRecord(
          id: 'new-legacy-account',
          name: 'Legacy Cash',
          type: v2_account.AccountType.cash,
          openingBalanceMinor: 5000,
          sync: v2_sync.SyncMetadata.fresh(),
        ),
      ],
      categories: const [],
      transactions: const [],
      scheduledTransactions: const [],
      budgets: const [],
      preferences: const UserPreferences(),
    );

    final merged = mergeLegacyDataSetIntoV2(
      incoming: incoming,
      current: const FinanceDataSet(
        accounts: [],
        categories: [],
        transactions: [],
        scheduledTransactions: [],
        budgets: [],
        preferences: UserPreferences(),
      ),
    );

    expect(merged.accounts.single.id, 'new-legacy-account');
  });
}
