import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as v1;
import 'package:money_tally/src/domain/transaction.dart' as v2_transaction;
import 'package:money_tally/src/migration/finance_data_bootstrapper.dart';
import 'package:money_tally/src/migration/v1_snapshot_migrator.dart';
import 'package:money_tally/src/persistence/local_finance_data_set_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('v1 migration preserves visible account balances', () {
    final snapshot = v1.FinanceStore.seeded().snapshot();
    final migrated = const V1SnapshotMigrator().migrate(snapshot.toJson());

    for (final account in snapshot.accounts) {
      expect(migrated.balanceForAccount(account.id), account.balanceCents);
    }

    expect(migrated.accounts.first.id, snapshot.accounts.first.id);
    expect(
      migrated.transactions.first.type,
      v2_transaction.TransactionType.expense,
    );
    expect(migrated.transactions.first.amountMinor, 6428);
    expect(
      migrated.transactions.last.type,
      v2_transaction.TransactionType.income,
    );
    expect(migrated.transactions.last.amountMinor, 126400);
    expect(migrated.budgets.first.categoryIds, ['dining']);
  });

  test('v1 transfer without destination migrates as an adjustment', () {
    final sync = v1.SyncMetadata.fresh(now: DateTime(2026, 7, 6));
    final snapshot = v1.FinanceSnapshot(
      accounts: [
        v1.Account(
          id: 'checking',
          name: 'Checking',
          type: v1.AccountType.checking,
          balanceCents: 10000,
          sync: sync,
        ),
      ],
      categories: [
        v1.LedgerCategory(
          id: 'transfer',
          name: 'Transfer',
          kind: v1.CategoryKind.transfer,
          color: const Color(0xFF00796B),
          sync: sync,
        ),
      ],
      transactions: [
        v1.LedgerTransaction(
          id: 'legacy-transfer',
          accountId: 'checking',
          categoryId: 'transfer',
          date: DateTime(2026, 7, 6),
          payee: 'Legacy transfer',
          amountCents: -2500,
          isTransfer: true,
          sync: sync,
        ),
      ],
      scheduled: const [],
      budgets: const [],
    );

    final migrated = const V1SnapshotMigrator().migrate(snapshot.toJson());
    final transaction = migrated.transactions.single;

    expect(transaction.type, v2_transaction.TransactionType.adjustment);
    expect(transaction.categoryId, isNull);
    expect(transaction.amountMinor, -2500);
    expect(transaction.note, contains('Migrated transfer without destination'));
    expect(migrated.accounts.single.openingBalanceMinor, 12500);
    expect(migrated.balanceForAccount('checking'), 10000);
  });

  test(
    'bootstrapper prefers v2 data and migrates v1 local data when needed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final v1Repository = const v1.LocalFinanceRepository();
      final v2Repository = const LocalFinanceDataSetRepository(
        storageKey: 'test_money_tally_v2',
      );
      final snapshot = v1.FinanceStore.seeded().snapshot();
      await v1Repository.save(snapshot);

      final bootstrapper = FinanceDataBootstrapper(
        localRepository: v2Repository,
      );

      final migrated = await bootstrapper.loadDataSet();
      final savedV2 = await v2Repository.load();

      expect(savedV2, isNotNull);
      expect(migrated.accounts.length, snapshot.accounts.length);
      expect(migrated.balanceForAccount('checking'), 185240);
    },
  );
}
