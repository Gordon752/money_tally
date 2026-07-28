import 'dart:convert';

import '../domain/finance_data_set.dart';
import '../domain/transaction.dart';

class BackupCodec {
  const BackupCodec();

  String encodeJson(FinanceDataSet dataSet) {
    return const JsonEncoder.withIndent('  ').convert(dataSet.toJson());
  }

  FinanceDataSet decodeJson(String rawJson) {
    final decoded = jsonDecode(rawJson) as Map<String, Object?>;
    return FinanceDataSet.fromJson(decoded);
  }

  String encodeTransactionsCsv(FinanceDataSet dataSet) {
    final accountsById = {
      for (final account in dataSet.accounts) account.id: account.name,
    };
    final categoriesById = {
      for (final category in dataSet.categories) category.id: category.name,
    };
    final rows = <List<String>>[
      [
        'transaction_id',
        'split_line_id',
        'date',
        'type',
        'account',
        'transfer_account',
        'category',
        'payee',
        'note',
        'amount',
        'status',
        'scheduled_transaction_id',
        'deleted',
      ],
    ];

    for (final transaction in dataSet.transactions) {
      if (transaction.isCategorySplit) {
        for (final splitLine in transaction.effectiveCategoryAllocations) {
          rows.add(
            _transactionCsvRow(
              transaction,
              accountsById: accountsById,
              categoriesById: categoriesById,
              splitLine: splitLine,
            ),
          );
        }
        continue;
      }
      final effectiveCategoryId =
          transaction.effectiveCategoryAllocations.firstOrNull?.categoryId;
      rows.add(
        _transactionCsvRow(
          transaction,
          accountsById: accountsById,
          categoriesById: categoriesById,
          categoryIdOverride: effectiveCategoryId,
        ),
      );
    }

    return rows.map(_csvRow).join('\n');
  }

  List<String> _transactionCsvRow(
    TransactionRecord transaction, {
    required Map<String, String> accountsById,
    required Map<String, String> categoriesById,
    TransactionSplitLine? splitLine,
    String? categoryIdOverride,
  }) {
    final categoryId =
        splitLine?.categoryId ?? categoryIdOverride ?? transaction.categoryId;
    final amountMinor = splitLine?.amountMinor ?? transaction.amountMinor;
    return [
      transaction.id,
      splitLine?.id ?? '',
      _dateOnly(transaction.date),
      transaction.type.name,
      accountsById[transaction.accountId] ?? transaction.accountId,
      transaction.transferAccountId == null
          ? ''
          : accountsById[transaction.transferAccountId] ??
                transaction.transferAccountId!,
      categoryId == null ? '' : categoriesById[categoryId] ?? categoryId,
      transaction.payee,
      splitLine?.note ?? transaction.note,
      _minorToDecimal(amountMinor),
      transaction.status.name,
      transaction.scheduledTransactionId ?? '',
      transaction.isDeleted ? 'true' : 'false',
    ];
  }

  String _csvRow(List<String> values) {
    return values.map(_csvCell).join(',');
  }

  String _csvCell(String value) {
    if (!value.contains(',') &&
        !value.contains('"') &&
        !value.contains('\n') &&
        !value.contains('\r')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _minorToDecimal(int minor) {
    final sign = minor < 0 ? '-' : '';
    final absMinor = minor.abs();
    final whole = absMinor ~/ 100;
    final cents = (absMinor % 100).toString().padLeft(2, '0');
    return '$sign$whole.$cents';
  }
}
