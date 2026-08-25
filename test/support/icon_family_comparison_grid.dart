import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:money_tally/src/design/category_icon_catalog.dart';
import 'package:money_tally/src/design/design_tokens.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

@immutable
class IconFamilyComparisonEntry {
  const IconFamilyComparisonEntry({
    required this.semanticKey,
    required this.hugeIcon,
    required this.hugeName,
    required this.materialSymbol,
    required this.materialName,
    required this.tablerIcon,
    required this.tablerName,
  });

  final String semanticKey;
  final List<List<dynamic>> hugeIcon;
  final String hugeName;
  final IconData materialSymbol;
  final String materialName;
  final IconData tablerIcon;
  final String tablerName;

  AppCategoryIcon get current {
    final result = CategoryIconCatalog.find(semanticKey);
    assert(result != null, 'Unknown category icon key: $semanticKey');
    return result!;
  }
}

/// Representative semantic trouble spots from Trackmark's category catalog.
///
/// This list intentionally lives under `test/`: the candidate packages are
/// evaluation tools, not production dependencies, and none of these mappings
/// change persisted category icon keys.
const iconFamilyComparisonEntries = <IconFamilyComparisonEntry>[
  IconFamilyComparisonEntry(
    semanticKey: 'finance.wallet',
    hugeIcon: HugeIcons.strokeRoundedWallet01,
    hugeName: 'wallet01',
    materialSymbol: Symbols.wallet_rounded,
    materialName: 'wallet',
    tablerIcon: TablerIcons.wallet,
    tablerName: 'wallet',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'finance.investment',
    hugeIcon: HugeIcons.strokeRoundedChartUp,
    hugeName: 'chartUp',
    materialSymbol: Symbols.trending_up_rounded,
    materialName: 'trending_up',
    tablerIcon: TablerIcons.trendingUp,
    tablerName: 'trendingUp',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'food.fast',
    hugeIcon: HugeIcons.strokeRoundedFrenchFries01,
    hugeName: 'frenchFries01',
    materialSymbol: Symbols.fastfood_rounded,
    materialName: 'fastfood',
    tablerIcon: TablerIcons.burger,
    tablerName: 'burger',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'food.drink',
    hugeIcon: HugeIcons.strokeRoundedSoftDrink01,
    hugeName: 'softDrink01',
    materialSymbol: Symbols.local_drink_rounded,
    materialName: 'local_drink',
    tablerIcon: TablerIcons.cup,
    tablerName: 'cup',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'fuelpump',
    hugeIcon: HugeIcons.strokeRoundedFuelStation,
    hugeName: 'fuelStation',
    materialSymbol: Symbols.local_gas_station_rounded,
    materialName: 'gas_station',
    tablerIcon: TablerIcons.gasStation,
    tablerName: 'gasStation',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'fuel.carwash',
    hugeIcon: HugeIcons.strokeRoundedCar03,
    hugeName: 'car03 (closest)',
    materialSymbol: Symbols.local_car_wash_rounded,
    materialName: 'car_wash',
    tablerIcon: TablerIcons.carGarage,
    tablerName: 'carGarage (closest)',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'shopping.clothes',
    hugeIcon: HugeIcons.strokeRoundedTShirt,
    hugeName: 'tShirt',
    materialSymbol: Symbols.checkroom_rounded,
    materialName: 'checkroom',
    tablerIcon: TablerIcons.shirt,
    tablerName: 'shirt',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'shopping.store',
    hugeIcon: HugeIcons.strokeRoundedStore01,
    hugeName: 'store01',
    materialSymbol: Symbols.storefront_rounded,
    materialName: 'storefront',
    tablerIcon: TablerIcons.buildingStore,
    tablerName: 'buildingStore',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'medical.medicine',
    hugeIcon: HugeIcons.strokeRoundedPill,
    hugeName: 'pill',
    materialSymbol: Symbols.pill_rounded,
    materialName: 'pill',
    tablerIcon: TablerIcons.pill,
    tablerName: 'pill',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'medical.dental',
    hugeIcon: HugeIcons.strokeRoundedDentalTooth,
    hugeName: 'dentalTooth',
    materialSymbol: Symbols.dentistry_rounded,
    materialName: 'dentistry',
    tablerIcon: TablerIcons.dental,
    tablerName: 'dental',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'housing.rent',
    hugeIcon: HugeIcons.strokeRoundedKey01,
    hugeName: 'key01',
    materialSymbol: Symbols.key_rounded,
    materialName: 'key',
    tablerIcon: TablerIcons.key,
    tablerName: 'key',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'housing.mortgage',
    hugeIcon: HugeIcons.strokeRoundedRealEstate02,
    hugeName: 'realEstate02',
    materialSymbol: Symbols.real_estate_agent_rounded,
    materialName: 'real_estate_agent',
    tablerIcon: TablerIcons.homeDollar,
    tablerName: 'homeDollar',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'housing.furniture',
    hugeIcon: HugeIcons.strokeRoundedSofa01,
    hugeName: 'sofa01',
    materialSymbol: Symbols.chair_rounded,
    materialName: 'chair',
    tablerIcon: TablerIcons.sofa,
    tablerName: 'sofa',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'housing.garden',
    hugeIcon: HugeIcons.strokeRoundedPlant01,
    hugeName: 'plant01',
    materialSymbol: Symbols.yard_rounded,
    materialName: 'yard',
    tablerIcon: TablerIcons.plant2,
    tablerName: 'plant2',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'housing.cleaning',
    hugeIcon: HugeIcons.strokeRoundedCleaningBucket,
    hugeName: 'cleaningBucket',
    materialSymbol: Symbols.cleaning_services_rounded,
    materialName: 'cleaning_services',
    tablerIcon: TablerIcons.spray,
    tablerName: 'spray',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'business.payroll',
    hugeIcon: HugeIcons.strokeRoundedPayment01,
    hugeName: 'payment01',
    materialSymbol: Symbols.payments_rounded,
    materialName: 'payments',
    tablerIcon: TablerIcons.cashBanknote,
    tablerName: 'cashBanknote',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'technology.repair',
    hugeIcon: HugeIcons.strokeRoundedMobileProgramming01,
    hugeName: 'mobileProgramming01',
    materialSymbol: Symbols.phonelink_setup_rounded,
    materialName: 'phonelink_setup',
    tablerIcon: TablerIcons.deviceMobileCog,
    tablerName: 'deviceMobileCog',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'transport.toll',
    hugeIcon: HugeIcons.strokeRoundedRoadWayside,
    hugeName: 'roadWayside (closest)',
    materialSymbol: Symbols.toll_rounded,
    materialName: 'toll',
    tablerIcon: TablerIcons.barrierBlock,
    tablerName: 'barrierBlock',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'business.scaleTicket',
    hugeIcon: HugeIcons.strokeRoundedWeightScale,
    hugeName: 'weightScale',
    materialSymbol: Symbols.scale_rounded,
    materialName: 'scale',
    tablerIcon: TablerIcons.scaleOutline,
    tablerName: 'scaleOutline',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'pets.vet',
    hugeIcon: HugeIcons.strokeRoundedHorseHead,
    hugeName: 'horseHead (closest)',
    materialSymbol: Symbols.vaccines_rounded,
    materialName: 'vaccines',
    tablerIcon: TablerIcons.vaccine,
    tablerName: 'vaccine',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'pets.food',
    hugeIcon: HugeIcons.strokeRoundedBone01,
    hugeName: 'bone01 (closest)',
    materialSymbol: Symbols.pet_supplies_rounded,
    materialName: 'pet_supplies',
    tablerIcon: TablerIcons.dogBowl,
    tablerName: 'dogBowl',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'pets.boarding',
    hugeIcon: HugeIcons.strokeRoundedBirdhouse,
    hugeName: 'birdhouse (closest)',
    materialSymbol: Symbols.night_shelter_rounded,
    materialName: 'night_shelter',
    tablerIcon: TablerIcons.homeHeart,
    tablerName: 'homeHeart (closest)',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'travel.luggage',
    hugeIcon: HugeIcons.strokeRoundedLuggage01,
    hugeName: 'luggage01',
    materialSymbol: Symbols.luggage_rounded,
    materialName: 'luggage',
    tablerIcon: TablerIcons.luggage,
    tablerName: 'luggage',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'travel.camping',
    hugeIcon: HugeIcons.strokeRoundedTent,
    hugeName: 'tent',
    materialSymbol: Symbols.camping_rounded,
    materialName: 'camping',
    tablerIcon: TablerIcons.tent,
    tablerName: 'tent',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'entertainment.sports',
    hugeIcon: HugeIcons.strokeRoundedBasketball01,
    hugeName: 'basketball01',
    materialSymbol: Symbols.sports_basketball_rounded,
    materialName: 'sports_basketball',
    tablerIcon: TablerIcons.ballBasketball,
    tablerName: 'ballBasketball',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'education.course',
    hugeIcon: HugeIcons.strokeRoundedCourse,
    hugeName: 'course',
    materialSymbol: Symbols.cast_for_education_rounded,
    materialName: 'cast_for_education',
    tablerIcon: TablerIcons.presentation,
    tablerName: 'presentation',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'education.library',
    hugeIcon: HugeIcons.strokeRoundedLibrary,
    hugeName: 'library',
    materialSymbol: Symbols.local_library_rounded,
    materialName: 'local_library',
    tablerIcon: TablerIcons.books,
    tablerName: 'books',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'education.graduation',
    hugeIcon: HugeIcons.strokeRoundedSchool,
    hugeName: 'school',
    materialSymbol: Symbols.school_rounded,
    materialName: 'school',
    tablerIcon: TablerIcons.school,
    tablerName: 'school',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'taxes.sales',
    hugeIcon: HugeIcons.strokeRoundedTaxes,
    hugeName: 'taxes',
    materialSymbol: Symbols.point_of_sale_rounded,
    materialName: 'point_of_sale',
    tablerIcon: TablerIcons.receiptTax,
    tablerName: 'receiptTax',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'insurance.claim',
    hugeIcon: HugeIcons.strokeRoundedDocumentValidation,
    hugeName: 'documentValidation',
    materialSymbol: Symbols.fact_check_rounded,
    materialName: 'fact_check',
    tablerIcon: TablerIcons.fileCheck,
    tablerName: 'fileCheck',
  ),
];

/// Strong existing mappings used as controls. A candidate family should not
/// solve weak concepts by making these familiar silhouettes less legible.
const iconFamilyBenchmarkEntries = <IconFamilyComparisonEntry>[
  IconFamilyComparisonEntry(
    semanticKey: 'finance.card',
    hugeIcon: HugeIcons.strokeRoundedCreditCard,
    hugeName: 'creditCard',
    materialSymbol: Symbols.credit_card_rounded,
    materialName: 'credit_card',
    tablerIcon: TablerIcons.creditCard,
    tablerName: 'creditCard',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'food.cafe',
    hugeIcon: HugeIcons.strokeRoundedCoffee01,
    hugeName: 'coffee01',
    materialSymbol: Symbols.coffee_rounded,
    materialName: 'coffee',
    tablerIcon: TablerIcons.coffee,
    tablerName: 'coffee',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'transport.flight',
    hugeIcon: HugeIcons.strokeRoundedAirplane01,
    hugeName: 'airplane01',
    materialSymbol: Symbols.flight_rounded,
    materialName: 'flight',
    tablerIcon: TablerIcons.plane,
    tablerName: 'plane',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'transport.bike',
    hugeIcon: HugeIcons.strokeRoundedBicycle,
    hugeName: 'bicycle',
    materialSymbol: Symbols.pedal_bike_rounded,
    materialName: 'pedal_bike',
    tablerIcon: TablerIcons.bike,
    tablerName: 'bike',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'transport.parking',
    hugeIcon: HugeIcons.strokeRoundedParkingAreaSquare,
    hugeName: 'parkingAreaSquare',
    materialSymbol: Symbols.local_parking_rounded,
    materialName: 'local_parking',
    tablerIcon: TablerIcons.parking,
    tablerName: 'parking',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'shopping.gift',
    hugeIcon: HugeIcons.strokeRoundedGift,
    hugeName: 'gift',
    materialSymbol: Symbols.card_giftcard_rounded,
    materialName: 'card_giftcard',
    tablerIcon: TablerIcons.gift,
    tablerName: 'gift',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'travel.hotel',
    hugeIcon: HugeIcons.strokeRoundedHotel01,
    hugeName: 'hotel01',
    materialSymbol: Symbols.hotel_rounded,
    materialName: 'hotel',
    tablerIcon: TablerIcons.bed,
    tablerName: 'bed',
  ),
  IconFamilyComparisonEntry(
    semanticKey: 'technology.gaming',
    hugeIcon: HugeIcons.strokeRoundedGameController01,
    hugeName: 'gameController01',
    materialSymbol: Symbols.sports_esports_rounded,
    materialName: 'sports_esports',
    tablerIcon: TablerIcons.deviceGamepad,
    tablerName: 'deviceGamepad',
  ),
];

class IconFamilyComparisonGrid extends StatelessWidget {
  const IconFamilyComparisonGrid({
    required this.title,
    required this.entries,
    super.key,
  });

  final String title;
  final List<IconFamilyComparisonEntry> entries;

  static const _familyWidth = 280.0;
  static const _labelWidth = 198.0;
  static const _rowHeight = 86.0;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('icon-family-comparison-grid'),
      child: ColoredBox(
        color: AppColors.pageLight,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.panelLight,
              border: Border.all(color: AppColors.lineLight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Same Trackmark badge treatment at 14 / 17 / 20 px. '
                        'Current uses the present iOS mapping.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.lineLight),
                const _HeaderRow(),
                for (final entry in entries) ...[
                  const Divider(height: 1, color: AppColors.lineLight),
                  SizedBox(
                    height: _rowHeight,
                    child: _ComparisonRow(entry: entry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 62,
      child: Row(
        children: [
          SizedBox(width: 24),
          SizedBox(
            width: IconFamilyComparisonGrid._labelWidth,
            child: _HeaderLabel('Concept'),
          ),
          _HeaderFamily('Current iOS'),
          _HeaderFamily('Hugeicons'),
          _HeaderFamily('Material Symbols'),
          _HeaderFamily('Tabler'),
          SizedBox(width: 24),
        ],
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    );
  }
}

class _HeaderFamily extends StatelessWidget {
  const _HeaderFamily(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: IconFamilyComparisonGrid._familyWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _HeaderLabel(label),
          const SizedBox(height: 2),
          Text(
            '14     17     20',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.muted,
              fontFeatures: const [AppTextStyles.tabularFigures],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.entry});

  final IconFamilyComparisonEntry entry;

  @override
  Widget build(BuildContext context) {
    final current = entry.current;
    return Row(
      children: [
        const SizedBox(width: 24),
        SizedBox(
          width: IconFamilyComparisonGrid._labelWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                entry.semanticKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        _FamilyCell(
          name: 'current',
          builders: [
            for (final size in _PreviewSize.values)
              (color) =>
                  Icon(current.cupertinoIcon, size: size.glyph, color: color),
          ],
        ),
        _FamilyCell(
          name: entry.hugeName,
          builders: [
            for (final size in _PreviewSize.values)
              (color) => HugeIcon(
                icon: entry.hugeIcon,
                size: size.glyph,
                color: color,
                strokeWidth: 1.8,
              ),
          ],
        ),
        _FamilyCell(
          name: entry.materialName,
          builders: [
            for (final size in _PreviewSize.values)
              (color) => Icon(
                entry.materialSymbol,
                size: size.glyph,
                color: color,
                weight: 400,
                opticalSize: size.glyph,
              ),
          ],
        ),
        _FamilyCell(
          name: entry.tablerName,
          builders: [
            for (final size in _PreviewSize.values)
              (color) => Icon(entry.tablerIcon, size: size.glyph, color: color),
          ],
        ),
        const SizedBox(width: 24),
      ],
    );
  }
}

typedef _IconBuilder = Widget Function(Color color);

class _FamilyCell extends StatelessWidget {
  const _FamilyCell({required this.name, required this.builders});

  final String name;
  final List<_IconBuilder> builders;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: IconFamilyComparisonGrid._familyWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (
                var index = 0;
                index < _PreviewSize.values.length;
                index++
              ) ...[
                _PreviewBadge(
                  previewSize: _PreviewSize.values[index],
                  child: builders[index](AppColors.accent),
                ),
                if (index != _PreviewSize.values.length - 1)
                  const SizedBox(width: 16),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.muted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PreviewSize {
  compact(glyph: 14, container: 28),
  row(glyph: 17, container: 34),
  form(glyph: 20, container: 40);

  const _PreviewSize({required this.glyph, required this.container});

  final double glyph;
  final double container;
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.previewSize, required this.child});

  final _PreviewSize previewSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: previewSize.container,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accent.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.18)),
        ),
        child: Center(child: child),
      ),
    );
  }
}
