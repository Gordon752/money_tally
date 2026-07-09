import 'package:flutter/material.dart';

import '../design_tokens.dart';

class MoneyTallyFloatingActionButton extends StatelessWidget {
  const MoneyTallyFloatingActionButton({
    required this.onPressed,
    required this.child,
    this.tooltip,
    super.key,
  });

  final VoidCallback onPressed;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Opacity(
        opacity: 0.86,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: SizedBox(
                width: 50,
                height: 50,
                child: IconTheme(
                  data: const IconThemeData(color: Colors.white, size: 23),
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
