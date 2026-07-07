import 'package:flutter/material.dart';

import '../design_tokens.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    required this.title,
    required this.value,
    this.subtitle,
    this.leading,
    this.isPrimary = false,
    super.key,
  });

  final String title;
  final Widget value;
  final String? subtitle;
  final Widget? leading;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leading != null) ...[
                  IconTheme(
                    data: IconThemeData(
                      color: isPrimary ? AppColors.accent : scheme.outline,
                      size: 20,
                    ),
                    child: leading!,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            value,
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
