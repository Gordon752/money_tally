import 'package:flutter/material.dart';

import '../../credit/credit_insights_calculator.dart';
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
            if (account.type == AccountType.creditCard &&
                account.interestEstimationEnabled) ...[
              const SizedBox(height: AppSpacing.md),
              _CreditInsightsPreview(
                account: account,
                currentBalanceMinor: balanceMinor,
                currency: currency,
              ),
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
        final available = limit - balanceMinor.abs();
        final progress = (used / limit).clamp(0.0, 1.0).toDouble();
        return _AccountMetric(
          label:
              'Credit Available ${formatter.formatMinor(available)} of ${formatter.formatMinor(limit)}',
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

class _CreditInsightsPreview extends StatelessWidget {
  const _CreditInsightsPreview({
    required this.account,
    required this.currentBalanceMinor,
    required this.currency,
  });

  final AccountRecord account;
  final int currentBalanceMinor;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = MoneyFormatter(currency);
    final estimate = const CreditInsightsCalculator().calculate(
      currentBalanceMinor: currentBalanceMinor,
      annualPercentageRate: account.annualPercentageRate,
      statementClosingDay: account.statementClosingDay,
    );
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Credit Insights',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _CreditInsightRow(
            label: 'APR',
            value: account.annualPercentageRate == null
                ? '–'
                : '${account.annualPercentageRate!.toStringAsFixed(2)}%',
          ),
          _CreditInsightRow(
            label: 'Statement Closes',
            value: _statementCloseLabel(estimate),
          ),
          if (estimate.hasInterestEstimate) ...[
            const SizedBox(height: AppSpacing.xxs),
            _CreditInsightRow(
              label: 'Projected Statement',
              value: formatter.formatMinor(estimate.projectedStatementMinor!),
            ),
            _CreditInsightRow(
              label: 'Estimated Interest',
              value:
                  '≈ ${formatter.formatMinor(estimate.estimatedInterestMinor!)}',
            ),
          ],
        ],
      ),
    );
  }

  String _statementCloseLabel(CreditInsightsEstimate estimate) {
    final closing = estimate.nextStatementClosingDate;
    final days = estimate.daysUntilStatementClosing;
    if (closing == null || days == null) return '–';
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final suffix = days == 0 ? 'today' : '$days ${days == 1 ? 'day' : 'days'}';
    return '${monthNames[closing.month - 1]} ${closing.day} ($suffix)';
  }
}

class _CreditInsightRow extends StatelessWidget {
  const _CreditInsightRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [AppTextStyles.tabularFigures],
            ),
          ),
        ],
      ),
    );
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
