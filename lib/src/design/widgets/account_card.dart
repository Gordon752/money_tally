import 'package:flutter/material.dart';

import '../../domain/account.dart';
import '../../domain/money.dart';
import '../design_tokens.dart';
import 'money_text.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    required this.account,
    required this.balanceMinor,
    this.currency = const CurrencyFormatSettings(),
    this.leading,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final AccountRecord account;
  final int balanceMinor;
  final CurrencyFormatSettings currency;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _groupLabel(account.group.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              MoneyText(
                amountMinor: balanceMinor,
                currency: currency,
                color: balanceMinor < 0 ? AppColors.danger : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _groupLabel(String groupName) {
    return switch (groupName) {
      'banking' => 'Banking',
      'cash' => 'Cash',
      'creditCards' => 'Credit Cards',
      'loans' => 'Loans',
      _ => groupName,
    };
  }
}
