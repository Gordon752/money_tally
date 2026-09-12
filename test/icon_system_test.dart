import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:money_tally/src/design/app_icons.dart';
import 'package:money_tally/src/design/category_icon_catalog.dart';
import 'package:money_tally/src/design/credit_card_appearance.dart';
import 'package:money_tally/src/design/widgets/category_icon_badge.dart';
import 'package:money_tally/src/design/widgets/category_icon_picker.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/category.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';

const _phaseOneCategoryGlyphs = <String, IconData>{
  'finance.wallet': Icons.wallet_outlined,
  'finance.investment': Icons.trending_up_outlined,
  'food.fast': Icons.fastfood_outlined,
  'food.drink': Icons.local_drink_outlined,
  'food.delivery': Icons.delivery_dining_outlined,
  'fuelpump': Icons.local_gas_station_outlined,
  'fuel.ev': Icons.ev_station_outlined,
  'fuel.charger': Icons.electrical_services_outlined,
  'fuel.carwash': Icons.local_car_wash_outlined,
  'cart': Icons.shopping_bag_outlined,
  'shopping.clothes': Icons.checkroom_outlined,
  'shopping.store': Icons.storefront_outlined,
  'shopping.jewelry': Icons.diamond_outlined,
  'cross.case': Icons.medical_services_outlined,
  'medical.pharmacy': Icons.local_pharmacy_outlined,
  'medical.fitness': Icons.fitness_center_outlined,
  'medical.therapy': Icons.psychology_outlined,
  'housing.rent': Icons.key_outlined,
  'housing.mortgage': Icons.real_estate_agent_outlined,
  'housing.property': Icons.other_houses_outlined,
  'housing.furniture': Icons.chair_outlined,
  'housing.garden': Icons.yard_outlined,
  'housing.cleaning': Icons.cleaning_services_outlined,
  'business.invoice': Icons.receipt_long_outlined,
  'business.payroll': Icons.payments_outlined,
  'business.subscription': Icons.handshake_outlined,
  'technology.storage': Icons.storage_outlined,
  'technology.repair': Icons.phonelink_setup_outlined,
  'travel.luggage': Icons.luggage_outlined,
  'travel.camping': Icons.festival_outlined,
  'entertainment.sports': Icons.sports_basketball_outlined,
  'education.course': Icons.cast_for_education_outlined,
  'education.childcare': Icons.child_care_outlined,
  'education.library': Icons.local_library_outlined,
  'education.graduation': Icons.school_outlined,
  'taxes.sales': Icons.point_of_sale_outlined,
  'maintenance.auto': Icons.car_repair_outlined,
  'maintenance.home': Icons.home_repair_service_outlined,
  'personal.wellness': Icons.self_improvement_outlined,
  'personal.children': Icons.child_friendly_outlined,
  'personal.donation': Icons.volunteer_activism_outlined,
  'misc.membership': Icons.card_membership_outlined,
};

const _phaseTwoCategoryGlyphs = <String, IconData>{
  'medical.medicine': Icons.medication_outlined,
  'technology.software': Icons.code_outlined,
  'pets.food': Icons.set_meal_outlined,
  'pets.vet': Icons.vaccines_outlined,
  'pets.boarding': Icons.night_shelter_outlined,
  'taxes.receipt': Icons.receipt_outlined,
  'taxes.federal': Icons.assured_workload_outlined,
  'insurance.health': Icons.health_and_safety_outlined,
  'insurance.claim': Icons.fact_check_outlined,
};

const _hugeCategoryGlyphs = <String, List<List<dynamic>>>{
  'finance.wallet': HugeIcons.strokeRoundedWallet01,
  'finance.investment': HugeIcons.strokeRoundedChartUp,
  'food.fast': HugeIcons.strokeRoundedFrenchFries01,
  'food.drink': HugeIcons.strokeRoundedSoftDrink01,
  'fuelpump': HugeIcons.strokeRoundedFuelStation,
  'shopping.clothes': HugeIcons.strokeRoundedTShirt,
  'shopping.store': HugeIcons.strokeRoundedStore01,
  'medical.medicine': HugeIcons.strokeRoundedPill,
  'medical.dental': HugeIcons.strokeRoundedDentalTooth,
  'housing.rent': HugeIcons.strokeRoundedKey01,
  'housing.mortgage': HugeIcons.strokeRoundedRealEstate02,
  'housing.furniture': HugeIcons.strokeRoundedSofa01,
  'housing.garden': HugeIcons.strokeRoundedPlant01,
  'housing.cleaning': HugeIcons.strokeRoundedCleaningBucket,
  'business.payroll': HugeIcons.strokeRoundedPayment01,
  'technology.repair': HugeIcons.strokeRoundedMobileProgramming01,
  'travel.luggage': HugeIcons.strokeRoundedLuggage01,
  'travel.camping': HugeIcons.strokeRoundedTent,
  'entertainment.sports': HugeIcons.strokeRoundedBasketball01,
  'education.course': HugeIcons.strokeRoundedCourse,
  'education.library': HugeIcons.strokeRoundedLibrary,
  'education.graduation': HugeIcons.strokeRoundedSchool,
  'insurance.claim': HugeIcons.strokeRoundedDocumentValidation,
};

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

    for (final icon in CategoryIconCatalog.icons) {
      expect(
        CategoryIconCatalog.find(icon.key),
        same(icon),
        reason: 'Persisted semantic key ${icon.key} must continue to resolve.',
      );
    }
  });

  test('Phase 1 category semantic keys resolve to approved iOS glyphs', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    for (final entry in _phaseOneCategoryGlyphs.entries) {
      expect(
        CategoryIconCatalog.find(entry.key)?.icon,
        entry.value,
        reason: '${entry.key} must retain its key and use its approved glyph.',
      );
    }
  });

  test('Phase 2 category semantic keys resolve to approved iOS glyphs', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    for (final entry in _phaseTwoCategoryGlyphs.entries) {
      expect(
        CategoryIconCatalog.find(entry.key)?.icon,
        entry.value,
        reason: '${entry.key} must retain its key and use its approved glyph.',
      );
    }
    expect(
      CategoryIconCatalog.find('medical.dental')?.icon,
      CupertinoIcons.smiley,
      reason: 'The persisted Dental fallback remains storage compatible.',
    );
  });

  test('selected category keys resolve to production Hugeicons', () {
    for (final entry in _hugeCategoryGlyphs.entries) {
      final option = CategoryIconCatalog.find(entry.key);
      expect(option, isNotNull);
      expect(
        option?.hugeIcon,
        same(entry.value),
        reason: '${entry.key} must retain its key and use its approved vector.',
      );
      expect(
        option?.icon,
        isA<IconData>(),
        reason: '${entry.key} must preserve its Flutter fallback.',
      );
    }

    for (final deferredKey in [
      'fuel.carwash',
      'transport.toll',
      'business.scaleTicket',
      'pets.vet',
      'pets.food',
      'pets.boarding',
      'taxes.sales',
    ]) {
      expect(
        CategoryIconCatalog.find(deferredKey)?.hugeIcon,
        isNull,
        reason: '$deferredKey remains on its clearer existing glyph.',
      );
    }
  });

  test('Phase 1 account appearance IDs resolve to approved glyphs', () {
    final expectations = <(AccountType, String), IconData>{
      (AccountType.checking, 'checking'): Icons.account_balance_wallet_outlined,
      (AccountType.savings, 'savings'): Icons.savings_outlined,
      (AccountType.checking, 'portfolio'): Icons.trending_up_outlined,
      (AccountType.cash, 'cashWallet'): Icons.wallet_outlined,
      (AccountType.loan, 'loanFinance'): Icons.request_quote_outlined,
    };

    for (final entry in expectations.entries) {
      final (type, id) = entry.key;
      final option = AccountAppearanceCatalog.iconFor(type, id);
      expect(option.id, id, reason: 'Persisted account icon ID must survive.');
      expect(option.icon, entry.value);
    }
  });

  test('banking appearance IDs resolve to the approved Hugeicons set', () {
    final expectations = <String, List<List<dynamic>>>{
      'bank': HugeIcons.strokeRoundedBank,
      'checking': HugeIcons.strokeRoundedWallet01,
      'savings': HugeIcons.strokeRoundedSafeBox,
      'portfolio': HugeIcons.strokeRoundedChartUp,
      'cashWallet': HugeIcons.strokeRoundedWallet04,
      'savingsPiggy': HugeIcons.strokeRoundedPiggyBank,
      'cash': HugeIcons.strokeRoundedMoney02,
    };

    expect(
      AccountAppearanceCatalog.iconsFor(
        AccountType.checking,
      ).map((option) => option.id),
      expectations.keys,
    );
    for (final entry in expectations.entries) {
      final option = AccountAppearanceCatalog.iconFor(
        AccountType.checking,
        entry.key,
      );
      expect(option.id, entry.key, reason: 'Persisted icon ID must be stable.');
      expect(option.hugeIcon, same(entry.value));
    }
    expect(
      AccountAppearanceCatalog.creditCardIcons.every(
        (option) => option.hugeIcon == null,
      ),
      isTrue,
      reason: 'Credit-card choices remain type-specific and unchanged.',
    );
  });

  test('new banking appearance IDs round-trip without stored-data changes', () {
    final account = AccountRecord(
      id: 'savings',
      name: 'Emergency Savings',
      type: AccountType.savings,
      openingBalanceMinor: 250000,
      creditCardIconId: 'savingsPiggy',
      creditCardAccentId: 'gold',
      sync: SyncMetadata.fresh(now: DateTime(2026, 8, 24)),
    );

    final restored = AccountRecord.fromJson(account.toJson());

    expect(restored.appearanceIconId, 'savingsPiggy');
    expect(restored.appearanceAccentId, 'gold');
    expect(
      AccountAppearanceCatalog.iconFor(
        restored.type,
        restored.appearanceIconId,
      ).hugeIcon,
      same(HugeIcons.strokeRoundedPiggyBank),
    );
  });

  testWidgets(
    'account appearance renderer supports Hugeicons and IconData together',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                AccountAppearanceBadge(
                  accountType: AccountType.checking,
                  iconId: 'bank',
                  accentId: 'teal',
                  size: 36,
                ),
                AccountAppearanceBadge(
                  accountType: AccountType.checking,
                  iconId: 'savings',
                  accentId: 'teal',
                  size: 46,
                ),
                AccountAppearanceBadge(
                  accountType: AccountType.checking,
                  iconId: 'portfolio',
                  accentId: 'teal',
                  size: 54,
                ),
                AccountAppearanceBadge(
                  accountType: AccountType.creditCard,
                  iconId: 'creditcard',
                  accentId: 'teal',
                ),
              ],
            ),
          ),
        ),
      );

      final vectorIcons = tester.widgetList<HugeIcon>(find.byType(HugeIcon));
      expect(vectorIcons.map((icon) => icon.size), [18, 23, 27]);
      expect(vectorIcons.every((icon) => icon.strokeWidth == 1.8), isTrue);
      expect(find.byIcon(CupertinoIcons.creditcard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

    expect(CategoryIconCatalog.find('transport.truckStop')?.label, 'Truck');
    expect(CategoryIconCatalog.find('business.scaleTicket')?.label, 'Scale');
  });

  test('Phase 1 aliases find the intended semantic entries', () {
    final expectations = <String, String>{
      'billfold': 'finance.wallet',
      'brokerage': 'finance.investment',
      'drive thru': 'food.fast',
      'fountain drink': 'food.drink',
      'delivery app': 'food.delivery',
      'gasoline': 'fuelpump',
      'detailing': 'fuel.carwash',
      'apparel': 'shopping.clothes',
      'storefront': 'shopping.store',
      'health care': 'cross.case',
      'drugstore': 'medical.pharmacy',
      'landlord': 'housing.rent',
      'home loan': 'housing.mortgage',
      'sofa': 'housing.furniture',
      'landscaping': 'housing.garden',
      'housekeeping': 'housing.cleaning',
      'receivable': 'business.invoice',
      'paycheck': 'business.payroll',
      'phone repair': 'technology.repair',
      'suitcase': 'travel.luggage',
      'campground': 'travel.camping',
      'athletics': 'entertainment.sports',
      'lesson': 'education.course',
      'daycare': 'education.childcare',
      'reading': 'education.library',
      'point of sale': 'taxes.sales',
      'mechanic': 'maintenance.auto',
      'handyman': 'maintenance.home',
    };

    for (final entry in expectations.entries) {
      expect(
        CategoryIconCatalog.matching(entry.key).map((icon) => icon.key),
        contains(entry.value),
        reason: 'Search alias ${entry.key} must find ${entry.value}.',
      );
    }
  });

  test('Phase 2 aliases find the intended semantic entries', () {
    final expectations = <String, String>{
      'capsule': 'medical.medicine',
      'dentistry': 'medical.dental',
      'coding': 'technology.software',
      'kibble': 'pets.food',
      'animal doctor': 'pets.vet',
      'kennel': 'pets.boarding',
      'tax filing': 'taxes.receipt',
      'irs': 'taxes.federal',
      'health coverage': 'insurance.health',
      'claim review': 'insurance.claim',
    };

    for (final entry in expectations.entries) {
      expect(
        CategoryIconCatalog.matching(entry.key).map((icon) => icon.key),
        contains(entry.value),
        reason: 'Search alias ${entry.key} must find ${entry.value}.',
      );
    }
  });

  testWidgets('Phase 1 iOS glyphs render at Ledger and picker sizes', (
    tester,
  ) async {
    const sizes = <double>[14, 17, 20];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Wrap(
              children: [
                for (final size in sizes)
                  for (final key in _phaseOneCategoryGlyphs.keys)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        CategoryIconCatalog.find(key)!.cupertinoIcon,
                        key: ValueKey('$key@$size'),
                        size: size,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final size in sizes) {
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.size == size,
        ),
        findsNWidgets(_phaseOneCategoryGlyphs.length),
      );
    }
    expect(
      find.byKey(const ValueKey('technology.repair@14.0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phase 2 iOS glyphs render at Ledger and picker sizes', (
    tester,
  ) async {
    const sizes = <double>[14, 17, 20];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Wrap(
              children: [
                for (final size in sizes)
                  for (final key in _phaseTwoCategoryGlyphs.keys)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        CategoryIconCatalog.find(key)!.cupertinoIcon,
                        key: ValueKey('phase2:$key@$size'),
                        size: size,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final size in sizes) {
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.size == size,
        ),
        findsNWidgets(_phaseTwoCategoryGlyphs.length),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'category badge renders approved Hugeicons at Ledger and picker sizes',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: Row(
              children: [
                CategoryIconBadge(
                  iconName: 'medical.dental',
                  kind: CategoryKind.expense,
                  size: CategoryIconBadgeSize.compact,
                ),
                CategoryIconBadge(
                  iconName: 'finance.wallet',
                  kind: CategoryKind.expense,
                  size: CategoryIconBadgeSize.row,
                ),
                CategoryIconBadge(
                  iconName: 'travel.camping',
                  kind: CategoryKind.expense,
                  size: CategoryIconBadgeSize.form,
                ),
                CategoryIconBadge(
                  iconName: 'food.tip',
                  kind: CategoryKind.expense,
                  size: CategoryIconBadgeSize.row,
                ),
              ],
            ),
          ),
        ),
      );

      final vectorIcons = tester.widgetList<HugeIcon>(find.byType(HugeIcon));
      expect(vectorIcons.map((icon) => icon.size), [14, 17, 20]);
      expect(vectorIcons.every((icon) => icon.strokeWidth == 1.8), isTrue);
      expect(vectorIcons.first.icon, same(HugeIcons.strokeRoundedDentalTooth));
      expect(find.byIcon(Icons.price_change_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
              semanticLabel: 'Truck category',
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Truck category'), findsOneWidget);
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
