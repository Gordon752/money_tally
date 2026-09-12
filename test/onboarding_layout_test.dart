import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as app;

const _renderKey = ValueKey('onboarding-render');
const _next = ValueKey('onboarding-continue');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  final layouts = [
    (
      name: 'iphone_narrow',
      size: const Size(320, 568),
      scale: 1.0,
      platform: TargetPlatform.iOS,
      dark: false,
    ),
    (
      name: 'iphone',
      size: const Size(393, 852),
      scale: 1.0,
      platform: TargetPlatform.iOS,
      dark: false,
    ),
    (
      name: 'iphone_compact',
      size: const Size(375, 812),
      scale: 1.0,
      platform: TargetPlatform.iOS,
      dark: false,
    ),
    (
      name: 'iphone_landscape',
      size: const Size(852, 393),
      scale: 1.0,
      platform: TargetPlatform.iOS,
      dark: false,
    ),
    (
      name: 'iphone_large_text',
      size: const Size(320, 568),
      scale: 2.0,
      platform: TargetPlatform.iOS,
      dark: false,
    ),
    (
      name: 'ipad',
      size: const Size(768, 1024),
      scale: 1.0,
      platform: TargetPlatform.iOS,
      dark: false,
    ),
    (
      name: 'ipad_landscape',
      size: const Size(1194, 834),
      scale: 1.0,
      platform: TargetPlatform.iOS,
      dark: false,
    ),
    (
      name: 'ipad_large_text',
      size: const Size(768, 1024),
      scale: 2.0,
      platform: TargetPlatform.iOS,
      dark: false,
    ),
    (
      name: 'mac',
      size: const Size(1440, 900),
      scale: 1.0,
      platform: TargetPlatform.macOS,
      dark: false,
    ),
    (
      name: 'mac_small',
      size: const Size(800, 600),
      scale: 1.0,
      platform: TargetPlatform.macOS,
      dark: false,
    ),
    (
      name: 'mac_short',
      size: const Size(1000, 500),
      scale: 1.0,
      platform: TargetPlatform.macOS,
      dark: false,
    ),
    (
      name: 'mac_compact',
      size: const Size(500, 600),
      scale: 1.0,
      platform: TargetPlatform.macOS,
      dark: false,
    ),
    (
      name: 'mac_dark',
      size: const Size(1024, 768),
      scale: 1.0,
      platform: TargetPlatform.macOS,
      dark: true,
    ),
  ];
  for (final layout in layouts) {
    for (final replay in [false, true]) {
      testWidgets(
        'all five pages fit and remain readable: ${layout.name}, replay=$replay',
        (tester) async {
          var completions = 0;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = layout.size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final base = layout.dark ? app.AppTheme.dark() : app.AppTheme.light();
          final theme = base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: 'OnboardingText'),
            primaryTextTheme: base.primaryTextTheme.apply(
              fontFamily: 'OnboardingText',
            ),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: _renderKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(layout.scale),
                    padding: layout.platform == TargetPlatform.iOS
                        ? EdgeInsets.only(
                            top: layout.size.shortestSide >= 600 ? 24 : 59,
                            bottom: layout.size.shortestSide >= 600 ? 20 : 34,
                          )
                        : EdgeInsets.zero,
                  ),
                  child: child!,
                ),
                home: app.TrackmarkOnboarding(
                  onClose: replay ? () {} : null,
                  onComplete: () async {
                    completions++;
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final initialButtonBottom = tester.getRect(find.byKey(_next)).bottom;
          for (var page = 0; page < 5; page++) {
            expect(find.text('${page + 1} of 5'), findsOneWidget);
            final close = find.byKey(const ValueKey('onboarding-close'));
            expect(close, replay ? findsOneWidget : findsNothing);
            if (replay) {
              expect(close.hitTestable(), findsOneWidget);
              expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
            }
            if (page == 4) {
              expect(
                find.text(replay ? 'Done' : 'Start Using Trackmark'),
                findsOneWidget,
              );
            }
            for (final paragraph in tester.renderObjectList<RenderParagraph>(
              find.byType(RichText),
            )) {
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason:
                    'Truncated on ${layout.name} page ${page + 1}: ${paragraph.text.toPlainText()}',
              );
            }
            final button = find.byKey(_next);
            final expectedGap = page == 1;
            final gap = find.byKey(
              const ValueKey('onboarding-money-navigation-gap'),
            );
            expect(gap, expectedGap ? findsOneWidget : findsNothing);
            if (expectedGap) {
              expect(tester.getSize(gap).height, 16);
            }
            if (page < 4) {
              expect(tester.getRect(button).bottom, initialButtonBottom);
            }
            expect(button.hitTestable(), findsOneWidget);
            expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
            expect(
              tester.getRect(button).bottom,
              lessThanOrEqualTo(layout.size.height),
            );
            expect(tester.takeException(), isNull);
            await _render(
              tester,
              '${replay ? 'replay_' : ''}${layout.name}_${page + 1}',
            );
            if (page == 1) {
              expect(find.text(r'Starting balance: $2,000'), findsOneWidget);
              expect(find.text(r'1. Reserve $500 for Bills'), findsOneWidget);
              expect(
                find.text(r'2. Spend $100 from the Bills Fund'),
                findsOneWidget,
              );
              expect(
                find.text(r'3. Return $200 from the Fund'),
                findsOneWidget,
              );
              expect(find.text(r'$2,000'), findsOneWidget);
              expect(find.text(r'$1,900'), findsNWidgets(2));
              expect(find.text(r'$1,500'), findsNWidgets(2));
              expect(find.text(r'$1,700'), findsOneWidget);
              if (layout.scale == 1 &&
                  [
                    'iphone',
                    'iphone_compact',
                    'ipad',
                    'ipad_landscape',
                    'mac',
                    'mac_dark',
                  ].contains(layout.name)) {
                final viewport = tester.state<ScrollableState>(
                  find.descendant(
                    of: find.byKey(const ValueKey('onboarding-page-1')),
                    matching: find.byType(Scrollable),
                  ),
                );
                expect(
                  viewport.position.maxScrollExtent,
                  0,
                  reason: 'Screen 2 must fit without scrolling: ${layout.name}',
                );
              }
              await tester.ensureVisible(
                find.text('The money doesn’t move. Its job changes.'),
              );
              await tester.pumpAndSettle();
              expect(
                find
                    .text('The money doesn’t move. Its job changes.')
                    .hitTestable(),
                findsOneWidget,
              );
              final closing = find.text(
                'The money doesn’t move. Its job changes.',
              );
              final navigation = find
                  .ancestor(of: button, matching: find.byType(Row))
                  .first;
              expect(
                tester.getRect(navigation).top - tester.getRect(closing).bottom,
                greaterThanOrEqualTo(expectedGap ? 16 : 0),
                reason: 'Closing line must clear navigation on ${layout.name}',
              );
              await _render(
                tester,
                '${replay ? 'replay_' : ''}${layout.name}_example',
              );
            }
            await tester.tap(button);
            await tester.pumpAndSettle();
          }
          expect(completions, 1);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({layout.platform}),
      );
    }
  }

  testWidgets(
    'reduced motion disables transitions and progress is accessible',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: app.TrackmarkOnboarding(onComplete: () async {}),
          ),
        );
        expect(
          tester
              .widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher))
              .duration,
          Duration.zero,
        );
        await tester.tap(find.byKey(_next));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('2 of 5'), findsOneWidget);
        await tester.ensureVisible(find.text(r'$2,000'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(RegExp(r'Balance \$2,000')),
          findsOneWidget,
        );
        expect(find.text('Know what your money is doing'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}

Future<void> _loadFonts() async {
  for (final font in {
    'OnboardingText': 'Roboto-Regular.ttf',
    'MaterialIcons': 'MaterialIcons-Regular.otf',
  }.entries) {
    var directory = File(Platform.resolvedExecutable).parent;
    File? file;
    while (directory.parent.path != directory.path && file == null) {
      for (final relative in [
        'material_fonts/${font.value}',
        'artifacts/material_fonts/${font.value}',
      ]) {
        final candidate = File('${directory.path}/$relative');
        if (candidate.existsSync()) {
          file = candidate;
          break;
        }
      }
      directory = directory.parent;
    }
    if (file == null) throw StateError('Flutter font not found: ${font.value}');
    final bytes = await file.readAsBytes();
    await (FontLoader(
      font.key,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
  await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      ))
      .load();
}

Future<void> _render(WidgetTester tester, String name) async {
  final directory = Platform.environment['TRACKMARK_ONBOARDING_RENDER_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_renderKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
