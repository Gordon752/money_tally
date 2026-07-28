import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/design/widgets/transaction_row.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/scheduled_transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/persistence/backup_codec.dart';

void main() {
  final metadata = SyncMetadata.fresh(
    now: DateTime(2026, 7, 27),
    deviceId: 'test-device',
  );

  TransactionRecord transaction({
    String id = 'transaction',
    TransactionType type = TransactionType.expense,
    String? categoryId = 'food',
    int amountMinor = 10000,
    List<TransactionSplitLine> splitLines = const [],
  }) {
    return TransactionRecord(
      id: id,
      type: type,
      accountId: 'checking',
      categoryId: categoryId,
      date: DateTime(2026, 7, 27, 12),
      payee: 'Test',
      amountMinor: amountMinor,
      splitLines: splitLines,
      sync: metadata,
    );
  }

  test(
    'primary category resolves to one effective allocation without splitting',
    () {
      final record = transaction();

      expect(record.effectiveCategoryAllocations, hasLength(1));
      expect(record.effectiveCategoryAllocations.single.categoryId, 'food');
      expect(record.effectiveCategoryAllocations.single.amountMinor, 10000);
      expect(record.isCategorySplit, isFalse);
      expect(record.isSplit, isFalse);
    },
  );

  test(
    'one-line, mirrored, zero, and duplicate allocations are not splits',
    () {
      final oneLine = transaction(
        splitLines: const [
          TransactionSplitLine(
            id: 'one',
            categoryId: 'food',
            amountMinor: 10000,
          ),
        ],
      );
      final mirrored = transaction(
        splitLines: const [
          TransactionSplitLine(
            id: 'mirror',
            categoryId: 'food',
            amountMinor: 10000,
          ),
        ],
      );
      final zeroSecond = transaction(
        splitLines: const [
          TransactionSplitLine(
            id: 'food',
            categoryId: 'food',
            amountMinor: 10000,
          ),
          TransactionSplitLine(id: 'zero', categoryId: 'home', amountMinor: 0),
        ],
      );
      final duplicate = transaction(
        splitLines: const [
          TransactionSplitLine(
            id: 'first',
            categoryId: 'food',
            amountMinor: 4000,
          ),
          TransactionSplitLine(
            id: 'second',
            categoryId: 'food',
            amountMinor: 6000,
          ),
        ],
      );

      for (final record in [oneLine, mirrored, zeroSecond, duplicate]) {
        expect(record.isCategorySplit, isFalse);
        expect(record.effectiveCategoryAllocations, hasLength(1));
        expect(record.effectiveCategoryAllocations.single.categoryId, 'food');
        expect(record.effectiveCategoryAllocations.single.amountMinor, 10000);
      }
    },
  );

  test('two distinct positive category allocations remain a split', () {
    final record = transaction(
      splitLines: const [
        TransactionSplitLine(id: 'food', categoryId: 'food', amountMinor: 6000),
        TransactionSplitLine(id: 'home', categoryId: 'home', amountMinor: 4000),
      ],
    );

    expect(record.isCategorySplit, isTrue);
    expect(record.effectiveCategoryAllocations, hasLength(2));
    expect(record.splitTotalMinor, 10000);
    expect(record.hasValidSplitTotal, isTrue);
  });

  test('transfers are never category splits', () {
    final transfer = transaction(
      type: TransactionType.transfer,
      categoryId: null,
      splitLines: const [
        TransactionSplitLine(
          id: 'ignored',
          categoryId: 'food',
          amountMinor: 10000,
        ),
      ],
    );

    expect(transfer.effectiveCategoryAllocations, isEmpty);
    expect(transfer.isCategorySplit, isFalse);
  });

  test(
    'scheduled single category and genuine splits use the same semantics',
    () {
      final single = ScheduledTransactionRecord(
        id: 'single',
        type: TransactionType.expense,
        accountId: 'checking',
        categoryId: 'food',
        payee: 'Single',
        amountMinor: 10000,
        nextDate: DateTime(2026, 8, 1),
        frequency: RecurrenceFrequency.monthly,
        sync: metadata,
      );
      final split = single.copyWith(
        splitLines: const [
          TransactionSplitLine(
            id: 'food',
            categoryId: 'food',
            amountMinor: 6000,
          ),
          TransactionSplitLine(
            id: 'home',
            categoryId: 'home',
            amountMinor: 4000,
          ),
        ],
      );

      expect(single.isCategorySplit, isFalse);
      expect(single.effectiveCategoryAllocations, hasLength(1));
      expect(split.isCategorySplit, isTrue);
    },
  );

  test(
    'legacy one-line records retain category and amount in JSON and CSV',
    () {
      final legacyOneLine = transaction(
        id: 'legacy-one-line',
        splitLines: const [
          TransactionSplitLine(
            id: 'line',
            categoryId: 'food',
            amountMinor: 10000,
          ),
        ],
      );
      final genuineSplit = transaction(
        id: 'genuine-split',
        splitLines: const [
          TransactionSplitLine(
            id: 'food',
            categoryId: 'food',
            amountMinor: 6000,
          ),
          TransactionSplitLine(
            id: 'home',
            categoryId: 'home',
            amountMinor: 4000,
          ),
        ],
      );
      final dataSet = FinanceDataSet(
        accounts: const [],
        categories: const [],
        transactions: [legacyOneLine, genuineSplit],
        scheduledTransactions: const [],
        budgets: const [],
        preferences: const UserPreferences(),
      );
      const codec = BackupCodec();

      final restored = codec.decodeJson(codec.encodeJson(dataSet));
      expect(restored.transactions[0].isCategorySplit, isFalse);
      expect(
        restored
            .transactions[0]
            .effectiveCategoryAllocations
            .single
            .amountMinor,
        10000,
      );
      expect(restored.transactions[1].isCategorySplit, isTrue);

      final csvRows = codec.encodeTransactionsCsv(dataSet).split('\n');
      expect(
        csvRows,
        hasLength(4),
      ); // Header + one normal row + two split rows.
      expect(csvRows[1], contains(',food,'));
      expect(csvRows[1], contains(',100.00,'));
    },
  );

  testWidgets('Ledger row labels only genuine category splits', (tester) async {
    final falsePositive = transaction(
      splitLines: const [
        TransactionSplitLine(
          id: 'line',
          categoryId: 'food',
          amountMinor: 10000,
        ),
      ],
    );
    final genuineSplit = transaction(
      splitLines: const [
        TransactionSplitLine(id: 'food', categoryId: 'food', amountMinor: 6000),
        TransactionSplitLine(id: 'home', categoryId: 'home', amountMinor: 4000),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TransactionRow(
                transaction: falsePositive,
                accountName: 'Checking',
                categoryName: 'Food',
                currency: const CurrencyFormatSettings(),
              ),
              TransactionRow(
                transaction: genuineSplit,
                accountName: 'Checking',
                categoryName: 'Food',
                currency: const CurrencyFormatSettings(),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Checking • Food'), findsOneWidget);
    expect(find.text('Checking • Food • Split'), findsOneWidget);
  });
}
