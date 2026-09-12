import 'package:flutter/material.dart';

import '../design_tokens.dart';

class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({
    required this.spentMinor,
    required this.budgetMinor,
    super.key,
  });

  final int spentMinor;
  final int budgetMinor;

  @override
  Widget build(BuildContext context) {
    final ratio = budgetMinor <= 0 ? 0.0 : spentMinor / budgetMinor;
    final progress = budgetMinor <= 0 ? 0.0 : ratio.clamp(0.0, 1.0);
    final color = spentMinor == 0
        ? Theme.of(context).colorScheme.outlineVariant
        : ratio >= 1
        ? AppColors.danger
        : ratio >= .75
        ? AppColors.warning
        : AppColors.accent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: SizedBox(
        height: 5,
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          color: color,
        ),
      ),
    );
  }
}
