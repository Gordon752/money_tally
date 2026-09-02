import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import 'credit_insights_calculator.dart';

class CreditInsightsCompletenessIndicator extends StatelessWidget {
  const CreditInsightsCompletenessIndicator({
    required this.completeness,
    this.compact = false,
    super.key,
  }) : assert(
         completeness != CreditInsightsEstimateCompleteness.complete,
         'Complete estimates do not need a status indicator.',
       );

  final CreditInsightsEstimateCompleteness completeness;
  final bool compact;

  String get _label => switch (completeness) {
    CreditInsightsEstimateCompleteness.partial => 'Partial',
    CreditInsightsEstimateCompleteness.insufficientHistory =>
      'Not enough history',
    CreditInsightsEstimateCompleteness.complete => '',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: completeness == CreditInsightsEstimateCompleteness.partial
          ? 'About this partial estimate'
          : 'About insufficient account history',
      child: InkWell(
        key: ValueKey('credit-estimate-status-${completeness.name}'),
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: () =>
            showCreditInsightsCompletenessDialog(context, completeness),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 1 : AppSpacing.xxs,
            vertical: compact ? 1 : AppSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (compact
                              ? theme.textTheme.labelSmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(
                            color: color,
                            fontSize: compact ? 9 : null,
                            fontWeight: FontWeight.w500,
                            height: 1,
                          ),
                ),
              ),
              SizedBox(width: compact ? 2 : AppSpacing.xxs),
              Icon(
                Icons.info_outline_rounded,
                size: compact ? 12 : 16,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showCreditInsightsCompletenessDialog(
  BuildContext context,
  CreditInsightsEstimateCompleteness completeness,
) {
  final (title, message) = switch (completeness) {
    CreditInsightsEstimateCompleteness.partial => (
      'Partial Estimate',
      'Trackmark only has part of this statement cycle’s account history. '
          'This estimate is based on the days Trackmark can reliably '
          'reconstruct.\n\nOnce a complete statement cycle has been recorded, '
          'the Partial indicator will disappear automatically.',
    ),
    CreditInsightsEstimateCompleteness.insufficientHistory => (
      'Not Enough History',
      'Trackmark does not yet have enough reliable account history to '
          'estimate interest for this statement cycle.\n\nAs more account '
          'history is recorded, Credit Projection will begin estimating '
          'interest automatically.',
    ),
    CreditInsightsEstimateCompleteness.complete => ('', ''),
  };
  if (completeness == CreditInsightsEstimateCompleteness.complete) {
    return Future.value();
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
