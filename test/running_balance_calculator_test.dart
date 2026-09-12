import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/ledger/running_balance_calculator.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';

void main() {
  group('account running balances', () {
    test('applies expenses and income chronologically', () {
      final result = _calculate(
        account: _account('checking', opening: 50000),
        transactions: [
          _transaction('income', TransactionType.income, 10000, day: 3),
          _transaction('expense-2', TransactionType.expense, 2500, day: 2),
          _transaction('expense-1', TransactionType.expense, 5000, day: 1),
        ],
      );

      expect(result.afterTransaction['expense-1'], 45000);
      expect(result.afterTransaction['expense-2'], 42500);
      expect(result.afterTransaction['income'], 52500);
    });

    test('applies a transfer once to each side', () {
      final transfer = _transaction(
        'transfer',
        TransactionType.transfer,
        30000,
        transferAccountId: 'wallet',
      );

      expect(
        _calculate(
          account: _account('checking', opening: 100000),
          transactions: [transfer],
        ).afterTransaction['transfer'],
        70000,
      );
      expect(
        _calculate(
          account: _account('wallet', opening: 5000),
          transactions: [transfer],
        ).afterTransaction['transfer'],
        35000,
      );
    });

    test('uses credit-card sign semantics and balance adjustments', () {
      final result = _calculate(
        account: _account(
          'card',
          opening: -10000,
          type: AccountType.creditCard,
        ),
        transactions: [
          _transaction(
            'purchase',
            TransactionType.expense,
            5000,
            accountId: 'card',
            day: 1,
          ),
          _transaction(
            'payment',
            TransactionType.transfer,
            4000,
            accountId: 'checking',
            transferAccountId: 'card',
            day: 2,
          ),
          _transaction(
            'adjustment',
            TransactionType.adjustment,
            1000,
            accountId: 'card',
            day: 3,
          ),
        ],
      );

      expect(result.afterTransaction['purchase'], -15000);
      expect(result.afterTransaction['payment'], -11000);
      expect(result.afterTransaction['adjustment'], -10000);
    });

    test(
      'split parent affects the account once and tombstones are ignored',
      () {
        final split = _transaction(
          'split',
          TransactionType.expense,
          10000,
          splitLines: const [
            TransactionSplitLine(
              id: 'a',
              categoryId: 'fuel',
              amountMinor: 7000,
            ),
            TransactionSplitLine(
              id: 'b',
              categoryId: 'food',
              amountMinor: 3000,
            ),
          ],
        );
        final deleted = _transaction(
          'deleted',
          TransactionType.expense,
          9000,
          deleted: true,
          day: 2,
        );
        final result = _calculate(
          account: _account('checking', opening: 50000),
          transactions: [split, deleted],
        );

        expect(result.afterTransaction['split'], 40000);
        expect(result.afterTransaction, isNot(contains('deleted')));
      },
    );

    test('equal timestamps use createdAt then stable ID', () {
      final sameDate = DateTime(2026, 8, 11, 10);
      final sameCreatedAt = DateTime(2026, 8, 11, 9);
      final result = calculateAccountRunningBalances(
        account: _account('checking', opening: 10000),
        transactions: [
          _transaction(
            'b',
            TransactionType.income,
            2000,
            date: sameDate,
            createdAt: sameCreatedAt,
          ),
          _transaction(
            'a',
            TransactionType.expense,
            1000,
            date: sameDate,
            createdAt: sameCreatedAt,
          ),
        ],
      );

      expect(result.afterTransaction['a'], 9000);
      expect(result.afterTransaction['b'], 11000);
    });

    test('legacy Goal funding remains in authoritative account history', () {
      final event = GoalFundingEventRecord(
        id: 'goal-event',
        sourceAccountId: 'checking',
        totalAmountMinor: 3000,
        date: DateTime(2026, 8, 11),
        allocations: const [],
        sync: SyncMetadata.fresh(now: DateTime(2026, 8, 11)),
      );
      final result = calculateAccountRunningBalances(
        account: _account('checking', opening: 10000),
        transactions: const [],
        goalFundingEvents: [event],
      );

      expect(result.afterGoalFundingEvent['goal-event'], 7000);
    });
  });

  test('Ledger display preferences use defaults and survive backup', () {
    const defaults = UserPreferences();
    expect(defaults.showLedgerIcons, isFalse);
    expect(defaults.showLedgerTimestamps, isTrue);
    expect(defaults.showLedgerSplitIndicator, isTrue);
    expect(defaults.showRunningBalance, isFalse);
    const preferences = UserPreferences(
      showLedgerIcons: false,
      showLedgerTimestamps: false,
      showLedgerSplitIndicator: false,
      showRunningBalance: true,
    );
    final dataSet = FinanceDataSet(
      accounts: [_account('checking')],
      categories: const [],
      transactions: const [],
      scheduledTransactions: const [],
      budgets: const [],
      preferences: preferences,
    );

    final restored = const BackupCodec().decodeJson(
      const BackupCodec().encodeJson(dataSet),
    );
    expect(restored.preferences.showLedgerIcons, isFalse);
    expect(restored.preferences.showLedgerTimestamps, isFalse);
    expect(restored.preferences.showLedgerSplitIndicator, isFalse);
    expect(restored.preferences.showRunningBalance, isTrue);

    final restoredEnabled = UserPreferences.fromJson(
      const UserPreferences(showLedgerIcons: true).toJson(),
    );
    expect(restoredEnabled.showLedgerIcons, isTrue);

    // Preference records created before this setting existed keep the former
    // icons-on behavior during an update.
    expect(UserPreferences.fromJson(const {}).showLedgerIcons, isTrue);
  });
}

AccountRunningBalances _calculate({
  required AccountRecord account,
  required List<TransactionRecord> transactions,
}) {
  return calculateAccountRunningBalances(
    account: account,
    transactions: transactions,
  );
}

AccountRecord _account(
  String id, {
  int opening = 0,
  AccountType type = AccountType.checking,
}) {
  return AccountRecord(
    id: id,
    name: id,
    type: type,
    openingBalanceMinor: opening,
    sync: SyncMetadata.fresh(now: DateTime(2026, 8, 1)),
  );
}

TransactionRecord _transaction(
  String id,
  TransactionType type,
  int amountMinor, {
  String accountId = 'checking',
  String? transferAccountId,
  int day = 1,
  DateTime? date,
  DateTime? createdAt,
  bool deleted = false,
  List<TransactionSplitLine> splitLines = const [],
}) {
  final created = createdAt ?? DateTime(2026, 8, day, 9);
  return TransactionRecord(
    id: id,
    type: type,
    accountId: accountId,
    transferAccountId: transferAccountId,
    date: date ?? DateTime(2026, 8, day, 10),
    payee: id,
    amountMinor: amountMinor,
    splitLines: splitLines,
    sync: SyncMetadata(
      createdAt: created,
      updatedAt: created,
      deletedAt: deleted ? created : null,
      deviceId: 'test',
      version: 1,
    ),
  );
}
