import 'package:flutter/services.dart';

/// Keeps deliberate, non-destructive interaction feedback consistent.
///
/// Long-press actions use a light impact after Flutter has recognized the
/// gesture. This intentionally stays separate from tap and save feedback.
abstract final class AppHaptics {
  static void longPressAction() => HapticFeedback.lightImpact();

  static void toggleSelection() => HapticFeedback.selectionClick();

  static ValueChanged<bool>? toggleHandler(ValueChanged<bool>? onChanged) {
    if (onChanged == null) return null;
    return (value) {
      toggleSelection();
      onChanged(value);
    };
  }
}
