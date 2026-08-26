import 'package:flutter/material.dart';

import '../../domain/money.dart';
import '../../domain/scheduled_transaction.dart';
import '../../domain/transaction.dart';
import '../design_tokens.dart';
import 'money_text.dart';

class ScheduledTransactionRow extends StatelessWidget {
  const ScheduledTransactionRow({
    required this.scheduledTransaction,
    this.currency = const CurrencyFormatSettings(),
    this.needsAttention = false,
    this.metadata,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final ScheduledTransactionRecord scheduledTransaction;
  final CurrencyFormatSettings currency;
  final bool needsAttention;
  final String? metadata;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final signedAmount = scheduledTransaction.type == TransactionType.expense
        ? -scheduledTransaction.amountMinor.abs()
        : scheduledTransaction.amountMinor.abs();

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scheduledTransaction.isScheduledFundFunding
                        ? scheduledTransaction.payee
                        : scheduledTransaction.isScheduledGoalFunding
                        ? 'Goal Funding'
                        : scheduledTransaction.payee,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    metadata ?? _compactDate(scheduledTransaction.nextDate),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (needsAttention) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Needs attention',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            MoneyText(
              amountMinor: signedAmount,
              currency: currency,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: signedAmount < 0 ? AppColors.danger : null,
            ),
          ],
        ),
      ),
    );
  }
}

String _compactDate(DateTime date) {
  final year = (date.year % 100).toString().padLeft(2, '0');
  return '${date.month}/${date.day}/$year';
}
