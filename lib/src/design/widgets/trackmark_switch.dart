import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Trackmark's consistent, slightly restrained visual switch.
///
/// The visible control is scaled without shrinking its surrounding 48-point
/// interaction area. Callers remain responsible for invoking user-action
/// haptics so programmatic value restoration stays silent.
class TrackmarkSwitch extends StatelessWidget {
  const TrackmarkSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 48,
      child: Center(
        child: Transform.scale(
          scale: 0.88,
          transformHitTests: false,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
            activeTrackColor: AppColors.accent.withValues(alpha: 0.40),
          ),
        ),
      ),
    );
  }
}

/// A merged, native-style switch row using [TrackmarkSwitch].
class TrackmarkSwitchListTile extends StatelessWidget {
  const TrackmarkSwitchListTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    super.key,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      toggled: value,
      enabled: onChanged != null,
      child: ListTile(
        contentPadding: contentPadding,
        leading: secondary,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: ExcludeSemantics(
          child: TrackmarkSwitch(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}
