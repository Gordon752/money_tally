import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as app;
import 'package:money_tally/src/migration/v1_snapshot_migrator.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';
import 'package:money_tally/src/support/support_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'public destinations are app-specific HTTPS links with no user data',
    () {
      expect(
        TrackmarkSupportLink.support.uri.toString(),
        'https://mileandmarker.com/apps/trackmark-money/support/',
      );
      expect(
        TrackmarkSupportLink.privacy.uri.toString(),
        'https://mileandmarker.com/apps/trackmark-money/privacy/',
      );
      expect(
        TrackmarkSupportLink.help.uri.toString(),
        'https://mileandmarker.com/apps/trackmark-money/help/',
      );
      for (final link in TrackmarkSupportLink.values) {
        expect(link.uri.scheme, 'https');
        expect(link.uri.hasQuery, isFalse);
        expect(link.uri.hasFragment, isFalse);
        expect(link.uri.userInfo, isEmpty);
      }
    },
  );

  for (final link in TrackmarkSupportLink.values) {
    testWidgets(
      '${link.name} opens the exact URL externally without changing data',
      (tester) async {
        final store = _store();
        final before = store.dataSet.toJson();
        final storage = await SharedPreferences.getInstance();
        await storage.setInt('trackmark.onboardingVersionSeen', 1);
        final beforePreferences = {
          for (final key in storage.getKeys()) key: storage.get(key),
        };
        final launches = <Uri>[];
        final service = SupportLinkService(
          launcher: (uri, {required mode}) async {
            expect(mode, LaunchMode.externalApplication);
            launches.add(uri);
            return true;
          },
        );
        await _row(tester, link: link, service: service, store: store);
        expect(
          launches,
          isEmpty,
          reason: 'No navigation until an explicit tap',
        );
        await tester.tap(find.text(link.title));
        await tester.pumpAndSettle();
        expect(launches, [link.uri]);
        expect(find.byType(SnackBar), findsNothing);
        expect(store.dataSet.toJson(), before);
        expect({
          for (final key in storage.getKeys()) key: storage.get(key),
        }, beforePreferences);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final throws in [false, true]) {
    testWidgets(
      'launch failure (throws=$throws) offers a copyable link and retry',
      (tester) async {
        var successful = false;
        String? copied;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final service = SupportLinkService(
          launcher: (uri, {required mode}) async {
            if (!successful && throws) {
              throw PlatformException(code: 'unavailable');
            }
            return successful;
          },
        );
        await _row(tester, service: service);
        await tester.tap(find.text('Support'));
        await tester.pumpAndSettle();
        expect(
          find.text('Could not open Support. Please try again.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Copy link'));
        await tester.pumpAndSettle();
        expect(copied, TrackmarkSupportLink.support.uri.toString());
        await tester.tap(find.text('Support'));
        await tester.pumpAndSettle();
        successful = true;
        await tester.tap(find.text('Support'));
        await tester.pumpAndSettle();
        expect(
          find.text('Could not open Support. Please try again.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('repeated taps cannot launch twice while waiting', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var calls = 0;
    await _row(
      tester,
      service: SupportLinkService(
        launcher: (uri, {required mode}) {
          calls++;
          return pending.future;
        },
      ),
    );
    await tester.tap(find.text('Support'));
    await tester.pump();
    await tester.tap(find.text('Support'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leaving Settings during a launch does not use a disposed context',
    (tester) async {
      final pending = Completer<bool>();
      await _row(
        tester,
        service: SupportLinkService(
          launcher: (uri, {required mode}) => pending.future,
        ),
      );
      await tester.tap(find.text('Support'));
      await tester.pumpWidget(const SizedBox());
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Settings exposes Support/Privacy and retains offline Guides and Replay',
    (tester) async {
      final store = _store();
      final before = store.dataSet.toJson();
      await tester.pumpWidget(
        FinanceDataStoreScope(
          store: store,
          child: MaterialApp(
            theme: app.AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: app.SettingsView()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in {
        'settings-support-link': TrackmarkSupportLink.support,
        'settings-privacy-link': TrackmarkSupportLink.privacy,
      }.entries) {
        final finder = find.byKey(ValueKey(entry.key));
        await tester.ensureVisible(finder);
        expect(finder.hitTestable(), findsOneWidget);
        expect(
          tester.widget<app.TrackmarkSupportLinkRow>(finder).link,
          entry.value,
        );
      }
      expect(
        find.byKey(const ValueKey('settings-replay-onboarding')),
        findsOneWidget,
      );
      final guides = find.byKey(const ValueKey('settings-help-guides'));
      await tester.ensureVisible(guides);
      await tester.tap(guides);
      await tester.pumpAndSettle();
      expect(find.byType(app.TrackmarkGuidesPage), findsOneWidget);
      final help = find.byKey(const ValueKey('guides-website-link'));
      expect(help.hitTestable(), findsOneWidget);
      expect(
        tester.widget<app.TrackmarkSupportLinkRow>(help).link,
        TrackmarkSupportLink.help,
      );
      expect(find.text('Know what your money is doing'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(app.SettingsView), findsOneWidget);
      expect(store.dataSet.toJson(), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final layout in [
    (
      name: 'iphone',
      size: const Size(320, 568),
      scale: 1.0,
      platform: TargetPlatform.iOS,
    ),
    (
      name: 'iphone_large_text',
      size: const Size(320, 568),
      scale: 2.0,
      platform: TargetPlatform.iOS,
    ),
    (
      name: 'iphone_landscape',
      size: const Size(852, 393),
      scale: 1.0,
      platform: TargetPlatform.iOS,
    ),
    (
      name: 'ipad',
      size: const Size(768, 1024),
      scale: 1.0,
      platform: TargetPlatform.iOS,
    ),
    (
      name: 'mac',
      size: const Size(1120, 700),
      scale: 1.0,
      platform: TargetPlatform.macOS,
    ),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'support rows wrap and remain tappable: ${layout.name}, dark=$dark',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = layout.size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final base = dark ? app.AppTheme.dark() : app.AppTheme.light();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('support-render'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: base.copyWith(
                  platform: layout.platform,
                  textTheme: base.textTheme.apply(fontFamily: 'SupportText'),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: app.SettingsSectionCard(
                            title: 'Help & Support',
                            children: [
                              for (final link in TrackmarkSupportLink.values)
                                app.TrackmarkSupportLinkRow(
                                  link: link,
                                  showDivider:
                                      link != TrackmarkSupportLink.privacy,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final link in TrackmarkSupportLink.values) {
            final row = find.widgetWithText(
              app.TrackmarkSupportLinkRow,
              link.title,
            );
            await tester.ensureVisible(row);
            await tester.pumpAndSettle();
            expect(find.text(link.title).hitTestable(), findsOneWidget);
            expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
          }
          for (final paragraph in tester.renderObjectList<RenderParagraph>(
            find.byType(RichText),
          )) {
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: paragraph.text.toPlainText(),
            );
          }
          expect(tester.takeException(), isNull);
          await _render(tester, '${layout.name}_${dark ? 'dark' : 'light'}');
        },
      );
    }
  }
}

FinanceDataStore _store() => FinanceDataStore(
  dataSet: const V1SnapshotMigrator().migrate(
    app.FinanceStore.seeded().snapshot().toJson(),
  ),
);

Future<void> _row(
  WidgetTester tester, {
  required SupportLinkService service,
  TrackmarkSupportLink link = TrackmarkSupportLink.support,
  FinanceDataStore? store,
}) async {
  await tester.pumpWidget(
    FinanceDataStoreScope(
      store: store ?? _store(),
      child: MaterialApp(
        theme: app.AppTheme.light(),
        home: Scaffold(
          body: app.TrackmarkSupportLinkRow(link: link, service: service),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  for (final font in {
    'SupportText': 'Roboto-Regular.ttf',
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
  final directory = Platform.environment['TRACKMARK_SUPPORT_RENDER_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('support-render')),
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
