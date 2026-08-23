import 'package:flutter/material.dart';

import '../../credit/credit_insights_calculator.dart';
import '../../credit/credit_insights_completeness_ui.dart';
import '../../domain/account.dart';
import '../../domain/money.dart';
import '../../domain/transaction.dart';
import '../account_balance_presentation.dart';
import '../app_icons.dart';
import '../design_tokens.dart';
import '../money_format.dart';
import 'account_balance_text.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    required this.account,
    required this.balanceMinor,
    this.metricBalanceMinor,
    this.creditInsightsBalanceMinor,
    this.pendingEffectMinor,
    this.reservedMinor,
    this.availableToSpendMinor,
    this.transactions = const [],
    this.nextScheduledPaymentDueDate,
    this.currency = const CurrencyFormatSettings(),
    this.groupLabel,
    this.subtitle,
    this.balanceFontSize = 17,
    this.leading,
    this.onTap,
    this.onAvailabilityTap,
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
  final int? metricBalanceMinor;
  final int? creditInsightsBalanceMinor;
  final int? pendingEffectMinor;
  final int? reservedMinor;
  final int? availableToSpendMinor;
  final Iterable<TransactionRecord> transactions;
  final DateTime? nextScheduledPaymentDueDate;
  final CurrencyFormatSettings currency;
  final String? groupLabel;
  final String? subtitle;
  final double balanceFontSize;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onAvailabilityTap;
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
                  KeyedSubtree(
                    key: ValueKey('account-leading-${account.id}'),
                    child: leading!,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        key: ValueKey('account-name-${account.id}'),
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
                      if (accountBalancePresentation(
                        account.type,
                        balanceMinor,
                      ).needsAttention)
                        Text(
                          'Needs attention',
                          key: ValueKey(
                            'account-needs-attention-${account.id}',
                          ),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                    ],
                  ),
                ),
                KeyedSubtree(
                  key: ValueKey('account-balance-${account.id}'),
                  child: AccountBalanceText(
                    accountType: account.type,
                    signedBalanceMinor: balanceMinor,
                    currency: currency,
                    fontSize: balanceFontSize,
                    fontWeight: FontWeight.w700,
                  ),
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
            if (_showsAvailabilitySummary) ...[
              const SizedBox(height: AppSpacing.xxs),
              Padding(
                padding: EdgeInsets.only(left: metricLeadingIndent),
                child: _availabilitySummaryWidget(context),
              ),
            ],
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
                currentBalanceMinor: creditInsightsBalanceMinor ?? balanceMinor,
                transactions: transactions,
                nextScheduledPaymentDueDate: nextScheduledPaymentDueDate,
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
    final metricBalance = metricBalanceMinor ?? balanceMinor;
    switch (account.type) {
      case AccountType.creditCard:
        final limit = account.creditLimitMinor;
        if (limit == null || limit <= 0) return null;
        final used = metricBalance.isNegative ? metricBalance.abs() : 0;
        final available = limit - used;
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
        final remaining = metricBalance.abs();
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

  bool get _showsAvailabilitySummary {
    if (availableToSpendMinor == null) return false;
    return (pendingEffectMinor ?? 0) != 0 || (reservedMinor ?? 0) != 0;
  }

  Widget _availabilitySummaryWidget(BuildContext context) {
    final text = Text(
      _availabilitySummary(),
      key: ValueKey('account-availability-${account.id}'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: _isOvercommitted
            ? AppColors.warning
            : Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
    if (onAvailabilityTap == null) {
      return Align(alignment: Alignment.centerLeft, child: text);
    }
    return Semantics(
      button: true,
      label: 'Open ${account.name} account details',
      child: InkWell(
        key: ValueKey('account-availability-action-${account.id}'),
        onTap: onAvailabilityTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(alignment: Alignment.centerLeft, child: text),
        ),
      ),
    );
  }

  String _availabilitySummary() {
    final formatter = MoneyFormatter(currency);
    if (_isOvercommitted) {
      final parts = <String>[
        'Overcommitted by ${formatter.formatMinor(availableToSpendMinor!.abs())}',
      ];
      if ((reservedMinor ?? 0) != 0) {
        parts.add('${formatter.formatMinor(reservedMinor!)} reserved');
      }
      return parts.join(' · ');
    }
    final parts = <String>[
      '${formatter.formatMinor(availableToSpendMinor!)} available',
    ];
    if ((reservedMinor ?? 0) != 0) {
      parts.add('${formatter.formatMinor(reservedMinor!)} reserved');
    } else if ((pendingEffectMinor ?? 0) != 0) {
      parts.add('${formatter.formatMinor(pendingEffectMinor!)} pending');
    }
    return parts.join(' · ');
  }

  bool get _isOvercommitted =>
      availableToSpendMinor != null &&
      availableToSpendMinor! < 0 &&
      balanceMinor >= 0;

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
    required this.transactions,
    required this.nextScheduledPaymentDueDate,
    required this.currency,
  });

  final AccountRecord account;
  final int currentBalanceMinor;
  final Iterable<TransactionRecord> transactions;
  final DateTime? nextScheduledPaymentDueDate;
  final CurrencyFormatSettings currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = MoneyFormatter(currency);
    const calculator = CreditInsightsCalculator();
    final now = DateTime.now();
    final estimate = calculator.calculate(
      account: account,
      transactions: transactions,
      currentBalanceMinor: currentBalanceMinor,
      today: now,
    );
    final nextPaymentDueDate =
        nextScheduledPaymentDueDate ??
        calculator.nextPaymentDueDate(
          paymentDueDay: account.paymentDueDay,
          today: now,
        );
    final completeness = estimate.estimateCompleteness;
    final isPartial =
        completeness == CreditInsightsEstimateCompleteness.partial;
    final hasInsufficientHistory =
        completeness == CreditInsightsEstimateCompleteness.insufficientHistory;
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
                flex: 23,
                child: _CreditInsightMetric(
                  label: 'Next Statement',
                  value: _compactDateLabel(estimate.nextStatementClosingDate),
                  supporting: _countdownLabel(
                    estimate.daysUntilStatementClosing,
                  ),
                ),
              ),
              const _CreditInsightDivider(),
              Expanded(
                flex: 20,
                child: _CreditInsightMetric(
                  label: 'Payment Due',
                  value: _compactDateLabel(nextPaymentDueDate),
                  supporting: _countdownLabel(
                    nextPaymentDueDate
                        ?.difference(DateTime(now.year, now.month, now.day))
                        .inDays,
                  ),
                ),
              ),
              const _CreditInsightDivider(),
              Expanded(
                flex: 27,
                child: _CreditInsightMetric(
                  label: 'Estimated Interest',
                  value: hasInsufficientHistory
                      ? ''
                      : estimate.estimatedInterestMinor == null
                      ? '–'
                      : formatter.formatMinor(estimate.estimatedInterestMinor!),
                  valueWidget: hasInsufficientHistory
                      ? CreditInsightsCompletenessIndicator(
                          completeness: completeness,
                          compact: true,
                        )
                      : null,
                  supportingWidget: isPartial
                      ? CreditInsightsCompletenessIndicator(
                          completeness: completeness,
                          compact: true,
                        )
                      : null,
                ),
              ),
              const _CreditInsightDivider(),
              Expanded(
                flex: 30,
                child: _CreditInsightMetric(
                  label: 'Projected Statement',
                  value: estimate.projectedStatementMinor == null ? '–' : '',
                  valueWidget: estimate.projectedStatementMinor == null
                      ? null
                      : AccountBalanceText(
                          accountType: AccountType.creditCard,
                          signedBalanceMinor: estimate.projectedStatementMinor!,
                          currency: currency,
                          // Match the peer metric values. The surrounding
                          // FittedBox still scales down only when a long value
                          // genuinely cannot fit on a compact screen.
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          compactCreditLabel: true,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _compactDateLabel(DateTime? date) {
    if (date == null) return '–';
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
    return '${monthNames[date.month - 1]} ${date.day}';
  }

  String? _countdownLabel(int? days) {
    if (days == null) return null;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return '$days days';
  }
}

class _CreditInsightMetric extends StatelessWidget {
  const _CreditInsightMetric({
    required this.label,
    required this.value,
    this.supporting,
    this.valueWidget,
    this.supportingWidget,
  });

  final String label;
  final String value;
  final String? supporting;
  final Widget? valueWidget;
  final Widget? supportingWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            height: 16,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.center,
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
              alignment: Alignment.center,
              child:
                  valueWidget ??
                  Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
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
            child:
                supportingWidget ??
                (supporting == null
                    ? null
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          supporting!,
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [AppTextStyles.tabularFigures],
                          ),
                        ),
                      )),
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
