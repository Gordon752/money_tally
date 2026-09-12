import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/design/design_tokens.dart';

import 'support/banking_icon_comparison_grid.dart';
import 'support/icon_family_comparison_grid.dart';

Future<void> _loadComparisonFonts() async {
  final robotoBytes = await _flutterMaterialFont(
    'Roboto-Regular.ttf',
  ).readAsBytes();
  final roboto = FontLoader('Roboto')
    ..addFont(
      Future.value(
        ByteData.view(
          robotoBytes.buffer,
          robotoBytes.offsetInBytes,
          robotoBytes.lengthInBytes,
        ),
      ),
    );
  final materialIconsBytes = await _flutterMaterialFont(
    'MaterialIcons-Regular.otf',
  ).readAsBytes();
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.view(
          materialIconsBytes.buffer,
          materialIconsBytes.offsetInBytes,
          materialIconsBytes.lengthInBytes,
        ),
      ),
    );
  final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
  final materialSymbols =
      FontLoader(
        'packages/material_symbols_icons/MaterialSymbolsRounded',
      )..addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
        ),
      );
  final tabler = FontLoader('packages/tabler_icons_plus/tabler-icons')
    ..addFont(
      rootBundle.load('packages/tabler_icons_plus/lib/fonts/tabler-icons.ttf'),
    );
  await Future.wait([
    roboto.load(),
    materialIcons.load(),
    cupertino.load(),
    materialSymbols.load(),
    tabler.load(),
  ]);
}

File _flutterMaterialFont(String fileName) {
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final direct = File('${directory.path}/material_fonts/$fileName');
    if (direct.existsSync()) return direct;

    final belowArtifacts = File(
      '${directory.path}/artifacts/material_fonts/$fileName',
    );
    if (belowArtifacts.existsSync()) return belowArtifacts;
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter material font $fileName.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadComparisonFonts);

  test('comparison catalog keeps stable Trackmark semantic keys', () {
    expect(iconFamilyComparisonEntries, hasLength(30));
    expect(iconFamilyBenchmarkEntries, hasLength(8));
    expect(
      [
        ...iconFamilyComparisonEntries,
        ...iconFamilyBenchmarkEntries,
      ].map((entry) => entry.semanticKey).toSet(),
      hasLength(
        iconFamilyComparisonEntries.length + iconFamilyBenchmarkEntries.length,
      ),
    );
    for (final entry in [
      ...iconFamilyComparisonEntries,
      ...iconFamilyBenchmarkEntries,
    ]) {
      expect(entry.current.key, entry.semanticKey);
    }
  });

  testWidgets('strong current mappings remain comparison controls', (
    tester,
  ) async {
    await _pumpComparison(
      tester,
      title: 'Icon family comparison · Strong controls',
      entries: iconFamilyBenchmarkEntries,
    );

    await expectLater(
      find.byKey(const Key('icon-family-comparison-grid')),
      matchesGoldenFile('goldens/icon_family_comparison_controls.png'),
    );
  });

  testWidgets('daily-use icon families at Trackmark sizes', (tester) async {
    await _pumpComparison(
      tester,
      title: 'Icon family comparison · Daily categories',
      entries: iconFamilyComparisonEntries.take(15).toList(),
    );

    await expectLater(
      find.byKey(const Key('icon-family-comparison-grid')),
      matchesGoldenFile('goldens/icon_family_comparison_daily.png'),
    );
  });

  testWidgets('specialized icon families at Trackmark sizes', (tester) async {
    await _pumpComparison(
      tester,
      title: 'Icon family comparison · Specialized categories',
      entries: iconFamilyComparisonEntries.skip(15).toList(),
    );

    await expectLater(
      find.byKey(const Key('icon-family-comparison-grid')),
      matchesGoldenFile('goldens/icon_family_comparison_specialized.png'),
    );
  });

  test('banking comparison candidates remain uniquely named', () {
    expect(bankingIconCandidates, hasLength(10));
    expect(
      bankingIconCandidates.map((candidate) => candidate.hugeName).toSet(),
      hasLength(bankingIconCandidates.length),
    );
  });

  testWidgets('Hugeicons banking candidates at account badge sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(
      1061,
      112 +
          58 +
          (BankingIconComparisonGrid.rowHeight * bankingIconCandidates.length) +
          48,
    );
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _comparisonTheme(),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: BankingIconComparisonGrid(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('banking-icon-comparison-grid')),
      matchesGoldenFile('goldens/banking_icon_comparison.png'),
    );
  });
}

Future<void> _pumpComparison(
  WidgetTester tester, {
  required String title,
  required List<IconFamilyComparisonEntry> entries,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(1414, 112 + 62 + (86 * entries.length) + 48);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _comparisonTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: IconFamilyComparisonGrid(title: title, entries: entries),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ThemeData _comparisonTheme() {
  final theme = AppThemeBuilder.theme(Brightness.light);
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
  );
}
