import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/design/app_icons.dart';
import 'package:money_tally/src/design/category_icon_catalog.dart';
import 'package:money_tally/src/design/widgets/category_icon_badge.dart';
import 'package:money_tally/src/design/widgets/category_icon_picker.dart';
import 'package:money_tally/src/domain/category.dart';

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

    for (final newKey in [
      'food.tip',
      'transport.truckStop',
      'maintenance.tires',
      'business.scaleTicket',
      'finance.cashAdvance',
    ]) {
      expect(CategoryIconCatalog.find(newKey), isNotNull);
    }
    expect(CategoryIconCatalog.find('old-unknown-icon'), isNull);
  });

  test(
    'weak semantic mappings remain storage compatible but render clearly',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(
        CategoryIconCatalog.find('fork.knife')?.icon,
        Icons.restaurant_outlined,
      );
      expect(
        CategoryIconCatalog.find('food.cafe')?.icon,
        Icons.local_cafe_outlined,
      );
      expect(
        CategoryIconCatalog.find('transport.bike')?.icon,
        Icons.pedal_bike_outlined,
      );
      expect(
        CategoryIconCatalog.find('transport.parking')?.icon,
        Icons.local_parking_outlined,
      );
      expect(
        CategoryIconCatalog.find('transport.toll')?.icon,
        Icons.toll_outlined,
      );
      expect(
        CategoryIconCatalog.find('fuel.air')?.icon,
        Icons.tire_repair_outlined,
      );
    },
  );

  test('natural search aliases find canonical entries without duplicates', () {
    final expectations = <String, String>{
      'tip': 'food.tip',
      'gratuity': 'food.tip',
      'restaurant': 'fork.knife',
      'truck stop': 'transport.truckStop',
      'tire': 'fuel.air',
      'scale': 'business.scaleTicket',
      'cash advance': 'finance.cashAdvance',
      'highway fee': 'transport.toll',
      'nest egg': 'finance.savings',
    };

    for (final entry in expectations.entries) {
      final matches = CategoryIconCatalog.matching(entry.key);
      expect(matches.map((icon) => icon.key), contains(entry.value));
      expect(matches.map((icon) => icon.key).toSet().length, matches.length);
    }
  });

  testWidgets('category badge uses assigned color and safe unknown fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Row(
            children: [
              CategoryIconBadge(
                iconName: 'food.tip',
                kind: CategoryKind.expense,
                colorValue: 0xFF7C3AED,
                semanticLabel: 'Tips category',
                selected: true,
              ),
              CategoryIconBadge(
                iconName: 'old-unknown-icon',
                kind: CategoryKind.income,
                semanticLabel: 'Legacy category',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Tips category'), findsOneWidget);
    expect(find.byIcon(Icons.price_change_outlined), findsOneWidget);
    expect(find.byIcon(AppIcon.income), findsOneWidget);
  });

  testWidgets('category badge remains visible in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(),
        home: const Material(
          child: Center(
            child: CategoryIconBadge(
              iconName: 'transport.truckStop',
              kind: CategoryKind.expense,
              colorValue: 0xFF60A5FA,
              semanticLabel: 'Truck Stop category',
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Truck Stop category'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
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
