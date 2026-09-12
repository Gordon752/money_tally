# Icon family comparison

These developer-only goldens compare Trackmark's current iOS category icons
with representative Hugeicons, Material Symbols Rounded, and Tabler icons at
the actual 14, 17, and 20 px glyph sizes used by Trackmark badges.

The control image contains mappings that already work well so candidate
families are judged on both improvement and regression risk.

The candidate libraries are dev dependencies only. Production category keys,
mappings, picker behavior, and persisted user selections remain unchanged.

`banking_icon_comparison.png` is a focused Hugeicons review using the exact
18/23/27 px glyph sizes and 36/46/54 px rounded-square containers used by
Trackmark account appearances. It is also developer-only; it does not change
the production banking picker.

Regenerate after intentionally changing the comparison set:

```sh
flutter test --update-goldens test/icon_family_comparison_golden_test.dart
```
