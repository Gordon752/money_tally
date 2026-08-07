import 'package:flutter/material.dart';

import '../../credit/credit_insights_calculator.dart';
import '../../domain/account.dart';
import '../../domain/money.dart';
import '../app_icons.dart';
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
    this.showNavigationChevron = false,
    this.borderRadius,
    this.metricLeadingIndent = 0,
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
  final bool showNavigationChevron;
  final double? borderRadius;
  final double metricLeadingIndent;
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
                if (showNavigationChevron) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    AppIcon.chevronRight,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            if (metric != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: EdgeInsets.only(left: metricLeadingIndent),
                child: _AccountMetricBar(metric: metric),
              ),
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
    final inheritedShape = Theme.of(context).cardTheme.shape;
    final shape = borderRadius == null
        ? null
        : inheritedShape is RoundedRectangleBorder
        ? inheritedShape.copyWith(
            borderRadius: BorderRadius.circular(borderRadius!),
          )
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius!),
          );
    return Card(shape: shape, clipBehavior: Clip.antiAlias, child: content);
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
          showPercentage: true,
          isCreditUtilization: true,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 16,
                child: _CreditInsightMetric(
                  label: 'APR',
                  value: account.annualPercentageRate == null
                      ? '–'
                      : '${account.annualPercentageRate!.toStringAsFixed(2)}%',
                ),
              ),
              const _CreditInsightDivider(),
              Expanded(
                flex: 26,
                child: _CreditInsightMetric(
                  label: 'Next Statement',
                  value: _statementCloseDateLabel(estimate),
                  supporting: _statementCloseDaysLabel(estimate),
                ),
              ),
              if (estimate.hasInterestEstimate) ...[
                const _CreditInsightDivider(),
                Expanded(
                  flex: 28,
                  child: _CreditInsightMetric(
                    label: 'Estimated Interest',
                    value:
                        '≈ ${formatter.formatMinor(estimate.estimatedInterestMinor!)}',
                  ),
                ),
                const _CreditInsightDivider(),
                Expanded(
                  flex: 30,
                  child: _CreditInsightMetric(
                    label: 'Projected Statement',
                    value:
                        '≈ ${formatter.formatMinor(estimate.projectedStatementMinor!)}',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _statementCloseDateLabel(CreditInsightsEstimate estimate) {
    final closing = estimate.nextStatementClosingDate;
    if (closing == null) return '–';
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[closing.month - 1]} ${closing.day}, ${closing.year}';
  }

  String? _statementCloseDaysLabel(CreditInsightsEstimate estimate) {
    final days = estimate.daysUntilStatementClosing;
    if (days == null) return null;
    if (days == 0) return 'Today';
    return '$days ${days == 1 ? 'day' : 'days'}';
  }
}

class _CreditInsightMetric extends StatelessWidget {
  const _CreditInsightMetric({
    required this.label,
    required this.value,
    this.supporting,
  });

  final String label;
  final String value;
  final String? supporting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: 16,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            width: double.infinity,
            height: 22,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [AppTextStyles.tabularFigures],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            height: 16,
            child: supporting == null
                ? null
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      supporting!,
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [AppTextStyles.tabularFigures],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreditInsightDivider extends StatelessWidget {
  const _CreditInsightDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 52,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
  );
}

class _AccountMetric {
  const _AccountMetric({
    required this.label,
    required this.progress,
    this.isOver = false,
    this.showPercentage = false,
    this.isCreditUtilization = false,
  });

  final String label;
  final double progress;
  final bool isOver;
  final bool showPercentage;
  final bool isCreditUtilization;
}

class _AccountMetricBar extends StatelessWidget {
  const _AccountMetricBar({required this.metric});

  final _AccountMetric metric;

  @override
  Widget build(BuildContext context) {
    final progress = metric.progress.clamp(0.0, 1.0).toDouble();
    final fillColor = metric.isCreditUtilization
        ? creditUtilizationFillColor(
            metric.progress,
            brightness: Theme.of(context).brightness,
          )
        : metric.isOver
        ? AppColors.danger
        : AppColors.accent;
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
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: SizedBox(
                  height: 5,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    color: fillColor,
                  ),
                ),
              ),
            ),
            if (metric.showPercentage) ...[
              const SizedBox(width: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: creditUtilizationLabelMinWidth,
                ),
                child: Text(
                  '${(metric.progress * 100).round()}% utilized',
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [AppTextStyles.tabularFigures],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
