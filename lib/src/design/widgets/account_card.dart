import 'package:flutter/material.dart';

import '../../domain/account.dart';
import '../../domain/money.dart';
import '../design_tokens.dart';
import '../money_format.dart';
import 'money_text.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    required this.account,
    required this.balanceMinor,
    this.currency = const CurrencyFormatSettings(),
    this.groupLabel,
    this.subtitle,
    this.balanceFontSize = 17,
    this.leading,
    this.onTap,
    this.onLongPress,
    this.framed = true,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    super.key,
  });

  final AccountRecord account;
  final int balanceMinor;
  final CurrencyFormatSettings currency;
  final String? groupLabel;
  final String? subtitle;
  final double balanceFontSize;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool framed;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final metric = _accountMetric();
    final content = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Padding(
        padding: padding,
        child: Column(
          children: [
            Row(
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle ??
                            groupLabel ??
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
                  fontSize: balanceFontSize,
                  fontWeight: FontWeight.w700,
                ),
              ],
            ),
            if (metric != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _AccountMetricBar(metric: metric),
            ],
          ],
        ),
      ),
    );
    if (!framed) return content;
    return Card(child: content);
  }

  _AccountMetric? _accountMetric() {
    final formatter = MoneyFormatter(currency);
    switch (account.type) {
      case AccountType.creditCard:
        final limit = account.creditLimitMinor;
        if (limit == null || limit <= 0) return null;
        final used = balanceMinor.isNegative ? balanceMinor.abs() : 0;
        final progress = (used / limit).clamp(0.0, 1.0).toDouble();
        return _AccountMetric(
          label:
              'Credit used ${formatter.formatMinor(used)} of ${formatter.formatMinor(limit)}',
          progress: progress,
          isOver: used > limit,
        );
      case AccountType.loan:
        final original = account.originalLoanAmountMinor;
        if (original == null || original <= 0) return null;
        final remaining = balanceMinor.abs();
        final rawPaidDown = original - remaining;
        final paidDown = rawPaidDown < 0
            ? 0
            : rawPaidDown > original
            ? original
            : rawPaidDown;
        return _AccountMetric(
          label:
              'Paid down ${formatter.formatMinor(paidDown)} of ${formatter.formatMinor(original)}',
          progress: paidDown / original,
        );
      case AccountType.checking:
      case AccountType.savings:
      case AccountType.cash:
      case AccountType.otherBanking:
        return null;
    }
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

class _AccountMetric {
  const _AccountMetric({
    required this.label,
    required this.progress,
    this.isOver = false,
  });

  final String label;
  final double progress;
  final bool isOver;
}

class _AccountMetricBar extends StatelessWidget {
  const _AccountMetricBar({required this.metric});

  final _AccountMetric metric;

  @override
  Widget build(BuildContext context) {
    final progress = metric.progress.clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFeatures: const [AppTextStyles.tabularFigures],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: SizedBox(
            height: 5,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              color: metric.isOver ? AppColors.danger : AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}
