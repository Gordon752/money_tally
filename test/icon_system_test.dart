import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/design/app_icons.dart';
import 'package:money_tally/src/design/category_icon_catalog.dart';
import 'package:money_tally/src/design/widgets/category_icon_picker.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('semantic icons resolve to the appropriate platform language', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(AppIcon.bank, CupertinoIcons.building_2_fill);
    expect(AppIcon.transfer, CupertinoIcons.arrow_right_arrow_left);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(AppIcon.bank, Icons.account_balance_outlined);
    expect(AppIcon.transfer, Icons.swap_horiz);
  });

  test('category catalog is curated, grouped, and storage-key safe', () {
    expect(CategoryIconCatalog.icons.length, inInclusiveRange(150, 250));
    expect(
      CategoryIconCatalog.icons.map((icon) => icon.key).toSet().length,
      CategoryIconCatalog.icons.length,
    );
    expect(
      CategoryIconCatalog.icons.map((icon) => icon.label).toSet().length,
      CategoryIconCatalog.icons.length,
    );
    expect(
      CategoryIconCatalog.icons.map((icon) => icon.group).toSet(),
      containsAll(CategoryIconCatalog.groups),
    );

    for (final legacyKey in [
      'fork.knife',
      'cart',
      'car',
      'fuelpump',
      'film',
      'house',
      'cross.case',
      'phone',
      'bolt',
      'shield',
      'wrench.adjustable',
      'tag',
    ]) {
      expect(CategoryIconCatalog.find(legacyKey), isNotNull);
    }
  });

  testWidgets('category icon picker searches and returns a selection', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  selected = await showCategoryIconPicker(
                    context,
                    selectedKey: 'cart',
                  );
                },
                child: const Text('Open icons'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open icons'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Icon'), findsOneWidget);
    expect(find.text('Finance'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'piggy');
    await tester.pump();
    expect(find.text('Piggy Bank'), findsOneWidget);
    expect(find.text('Dining'), findsNothing);

    await tester.tap(find.text('Piggy Bank'));
    await tester.pumpAndSettle();
    expect(selected, 'goals.piggy');
  });
}
