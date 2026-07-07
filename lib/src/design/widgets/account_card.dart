import 'package:flutter/material.dart';

import '../../domain/account.dart';
import '../design_tokens.dart';
import 'money_text.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    required this.account,
    required this.balanceMinor,
    this.leading,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final AccountRecord account;
  final int balanceMinor;
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      account.group.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              MoneyText(
                amountMinor: balanceMinor,
                color: balanceMinor < 0 ? AppColors.danger : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
