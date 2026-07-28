import 'package:flutter/material.dart';

import '../../domain/money.dart';
import '../../domain/transaction.dart';
import '../design_tokens.dart';
import 'money_text.dart';

class TransactionRow extends StatelessWidget {
  const TransactionRow({
    required this.transaction,
    this.currency = const CurrencyFormatSettings(),
    this.categoryName,
    this.accountName,
    this.dateLabel,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final TransactionRecord transaction;
  final CurrencyFormatSettings currency;
  final String? categoryName;
  final String? accountName;
  final String? dateLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final signedAmount = switch (transaction.type) {
      TransactionType.expense => -transaction.amountMinor.abs(),
      TransactionType.income => transaction.amountMinor.abs(),
      TransactionType.transfer => transaction.amountMinor.abs(),
      TransactionType.goalFunding => transaction.amountMinor.abs(),
      TransactionType.adjustment => transaction.amountMinor,
    };

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.payee,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    [
                      if (accountName != null) accountName,
                      if (categoryName != null) categoryName,
                      if (dateLabel != null) dateLabel,
                      if (transaction.isSplit) 'Split',
                      if (transaction.isTransfer) 'Transfer',
                    ].join(' • '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            MoneyText(
              amountMinor: signedAmount,
              currency: currency,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              showPositiveSign: transaction.type == TransactionType.income,
              color: signedAmount < 0
                  ? AppColors.danger
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}
