import 'package:flutter/material.dart';

class TrackmarkAccentOption {
  const TrackmarkAccentOption({
    required this.id,
    required this.label,
    required this.value,
  });

  final String id;
  final String label;
  final int value;

  Color get color => Color(value);
}

/// The single curated accent palette shared by user-customizable Trackmark
/// surfaces. Stored color integers remain stable for existing categories.
abstract final class TrackmarkAccentCatalog {
  static const options = <TrackmarkAccentOption>[
    TrackmarkAccentOption(id: 'teal', label: 'Teal', value: 0xFF0F766E),
    TrackmarkAccentOption(id: 'mint', label: 'Mint', value: 0xFF3D8F7B),
    TrackmarkAccentOption(id: 'green', label: 'Green', value: 0xFF16A34A),
    TrackmarkAccentOption(id: 'blue', label: 'Blue', value: 0xFF2563EB),
    TrackmarkAccentOption(id: 'indigo', label: 'Indigo', value: 0xFF5367A8),
    TrackmarkAccentOption(id: 'purple', label: 'Purple', value: 0xFF765A9A),
    TrackmarkAccentOption(id: 'rose', label: 'Rose', value: 0xFFE11D48),
    TrackmarkAccentOption(id: 'red', label: 'Red', value: 0xFFA84F52),
    TrackmarkAccentOption(id: 'orange', label: 'Orange', value: 0xFFB96735),
    TrackmarkAccentOption(id: 'amber', label: 'Amber', value: 0xFFD97706),
    TrackmarkAccentOption(id: 'gold', label: 'Gold', value: 0xFFA68A49),
    TrackmarkAccentOption(id: 'slate', label: 'Slate', value: 0xFF475569),
  ];

  static TrackmarkAccentOption? findById(String? id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }
}
