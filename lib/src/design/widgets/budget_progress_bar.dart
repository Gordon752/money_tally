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
    final isOver = spentMinor > budgetMinor && budgetMinor > 0;
    final progress = budgetMinor <= 0
        ? 0.0
        : (spentMinor / budgetMinor).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: SizedBox(
        height: 5,
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          color: isOver ? AppColors.danger : AppColors.accent,
        ),
      ),
    );
  }
}
