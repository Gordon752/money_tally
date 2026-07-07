import 'package:flutter/material.dart';

import '../../domain/scheduled_transaction.dart';
import '../../domain/transaction.dart';
import '../design_tokens.dart';
import 'money_text.dart';

class ScheduledTransactionRow extends StatelessWidget {
  const ScheduledTransactionRow({
    required this.scheduledTransaction,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final ScheduledTransactionRecord scheduledTransaction;
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
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scheduledTransaction.payee,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    scheduledTransaction.nextDate
                        .toLocal()
                        .toString()
                        .split(' ')
                        .first,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            MoneyText(
              amountMinor: signedAmount,
              color: signedAmount < 0 ? AppColors.danger : null,
            ),
          ],
        ),
      ),
    );
  }
}
