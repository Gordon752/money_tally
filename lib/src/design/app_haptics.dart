import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps deliberate, non-destructive interaction feedback consistent.
///
/// Long-press actions use a light impact after Flutter has recognized the
/// gesture. This intentionally stays separate from tap and save feedback.
abstract final class AppHaptics {
  static bool _suppressNextNavigation = false;

  /// A committed transition to or from a full Trackmark screen.
  static void navigation() => HapticFeedback.selectionClick();

  /// A committed discrete choice, disclosure, or binary selection.
  static void selection() => HapticFeedback.selectionClick();

  static void longPressAction() => HapticFeedback.lightImpact();

  static void toggleSelection() => selection();

  /// Prevents a stronger action that also closes a full-screen route from
  /// immediately receiving a second, navigation-strength haptic.
  static void suppressNextNavigation() {
    _suppressNextNavigation = true;
  }

  static bool consumeNavigationSuppression() {
    final suppressed = _suppressNextNavigation;
    _suppressNextNavigation = false;
    return suppressed;
  }

  static ValueChanged<bool>? toggleHandler(ValueChanged<bool>? onChanged) {
    if (onChanged == null) return null;
    return (value) {
      toggleSelection();
      onChanged(value);
    };
  }
}

/// Emits one navigation haptic only after a full-screen route commits.
///
/// Flutter reports a completed interactive iOS back gesture through [didPop],
/// while a cancelled gesture reports no pop. Restricting this observer to
/// [PageRoute] deliberately excludes dialogs and bottom sheets.
class TrackmarkNavigationObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute<dynamic> &&
        !AppHaptics.consumeNavigationSuppression()) {
      AppHaptics.navigation();
    }
  }
}
