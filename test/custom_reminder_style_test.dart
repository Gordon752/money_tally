import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as app;
import 'package:money_tally/src/design/design_tokens.dart';

const _daysKey = ValueKey('custom-reminder-days');
const _timeKey = ValueKey('custom-reminder-time');
const _saveKey = ValueKey('custom-reminder-save');
const _warningKey = ValueKey('custom-reminder-time-warning');
const _renderKey = ValueKey('reminder-style-render');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  final layouts = [
    (
      name: 'iphone_narrow',
      size: const Size(320, 568),
      platform: TargetPlatform.iOS,
      scale: 1.0,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'iphone',
      size: const Size(393, 852),
      platform: TargetPlatform.iOS,
      scale: 1.0,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'iphone_keyboard',
      size: const Size(393, 852),
      platform: TargetPlatform.iOS,
      scale: 1.0,
      keyboard: 320.0,
      dark: false,
    ),
    (
      name: 'iphone_large_text',
      size: const Size(320, 568),
      platform: TargetPlatform.iOS,
      scale: 1.6,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'iphone_compact_keyboard',
      size: const Size(320, 568),
      platform: TargetPlatform.iOS,
      scale: 1.4,
      keyboard: 216.0,
      dark: false,
    ),
    (
      name: 'ipad',
      size: const Size(768, 1024),
      platform: TargetPlatform.iOS,
      scale: 1.0,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'ipad_landscape',
      size: const Size(1194, 834),
      platform: TargetPlatform.iOS,
      scale: 1.0,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'mac',
      size: const Size(1440, 900),
      platform: TargetPlatform.macOS,
      scale: 1.0,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'mac_dark',
      size: const Size(1024, 768),
      platform: TargetPlatform.macOS,
      scale: 1.0,
      keyboard: 0.0,
      dark: true,
    ),
  ];

  for (final layout in layouts) {
    testWidgets(
      'Custom Reminder uses Trackmark form layout: ${layout.name}',
      (tester) async {
        ({int daysBefore, int timeMinutes, String? timeZone})? result;
        await _open(
          tester,
          size: layout.size,
          scale: layout.scale,
          keyboard: layout.keyboard,
          dark: layout.dark,
          onResult: (value) => result = value,
        );

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(app.TransactionSheetFrame), findsOneWidget);
        expect(find.byType(app.TransactionFormActions), findsOneWidget);
        expect(find.byType(app.TransactionFormDivider), findsNWidgets(2));
        expect(find.byType(app.TransactionFormIcon), findsNWidgets(3));
        expect(find.byKey(_timeKey), findsOneWidget);
        expect(
          tester.widget(find.byKey(_timeKey)),
          isA<app.PolishedFormValueRow>(),
        );
        expect(find.text('Days before'), findsOneWidget);
        expect(find.text('Reminder time'), findsOneWidget);
        expect(find.text('0 means same day'), findsOneWidget);

        final field = tester.widget<TextField>(find.byKey(_daysKey));
        expect(field.decoration!.border, InputBorder.none);
        expect(field.decoration!.focusedBorder, InputBorder.none);
        expect(field.decoration!.filled, isFalse);
        expect(field.decoration!.labelText, isNull);
        expect(field.keyboardType, TextInputType.number);
        expect(
          tester.getSize(find.byKey(_daysKey)).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byKey(_timeKey)).height,
          greaterThanOrEqualTo(48),
        );

        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        final theme = Theme.of(tester.element(find.text('Custom Reminder')));
        expect(dialog.backgroundColor, theme.colorScheme.surface);
        expect(
          (dialog.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(28),
        );
        expect(
          tester.widget<Text>(find.text('Custom Reminder')).style!.fontWeight,
          FontWeight.w700,
        );
        final warning = tester.widget<Text>(find.byKey(_warningKey));
        expect(
          warning.data,
          'This reminder is at or after the scheduled time.',
        );
        expect(warning.style!.color, AppColors.warning);
        expect(warning.style!.fontWeight, FontWeight.w700);
        expect(
          find.ancestor(
            of: find.byKey(_warningKey),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.liveRegion == true,
            ),
          ),
          findsOneWidget,
        );

        final saveRect = tester.getRect(find.byKey(_saveKey));
        final cancelRect = tester.getRect(
          find.widgetWithText(OutlinedButton, 'Cancel'),
        );
        expect(saveRect.height, 48);
        expect(cancelRect.height, 48);
        expect(saveRect.width, closeTo(cancelRect.width, 0.01));
        expect(saveRect.top, cancelRect.top);
        expect(
          saveRect.bottom,
          lessThanOrEqualTo(layout.size.height - layout.keyboard),
        );
        expect(
          tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed,
          isNotNull,
          reason: 'The same-day timing warning must remain non-blocking.',
        );
        expect(tester.takeException(), isNull);

        await _renderIfRequested(tester, layout.name);
        // Even with a keyboard and large text, all content remains scrollable
        // and the shared action footer stays reachable.
        await tester.ensureVisible(find.byKey(_timeKey));
        await tester.pumpAndSettle();
        expect(find.byKey(_timeKey).hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.byKey(_daysKey));
        await tester.enterText(find.byKey(_daysKey), '3');
        await tester.pumpAndSettle();
        expect(find.byKey(_warningKey), findsNothing);
        await tester.tap(find.byKey(_saveKey));
        await tester.pumpAndSettle();
        expect(result, (daysBefore: 3, timeMinutes: 540, timeZone: null));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({layout.platform}),
    );
  }

  testWidgets(
    'Styled day input keeps accessible label and wraps validation errors',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _open(tester, size: const Size(320, 568), scale: 1.6);
        expect(find.bySemanticsLabel('Days before'), findsWidgets);
        await tester.enterText(find.byKey(_daysKey), '36501');
        await tester.pumpAndSettle();
        final error = find.text('Enter a whole number from 0 to 36500');
        expect(error, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(error).didExceedMaxLines,
          isFalse,
        );
        expect(
          tester.widget<FilledButton>(find.byKey(_saveKey)).onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'Standard Cancel discards edits without returning a reminder rule',
    (tester) async {
      var completed = false;
      ({int daysBefore, int timeMinutes, String? timeZone})? result;
      await _open(
        tester,
        onResult: (value) {
          completed = true;
          result = value;
        },
      );
      await tester.enterText(find.byKey(_daysKey), '7');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, isNull);
      expect(find.text('Custom Reminder'), findsNothing);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1,
  double keyboard = 0,
  bool dark = false,
  void Function(({int daysBefore, int timeMinutes, String? timeZone})?)?
  onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.view.resetViewInsets();
  });
  final base = dark ? app.AppTheme.dark() : app.AppTheme.light();
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'ReminderStyleText'),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: 'ReminderStyleText',
    ),
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: _renderKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  final value = await app.showCustomReminderDialog(
                    context,
                    daysBefore: 0,
                    timeMinutes: 540,
                    scheduledTimeMinutes: 540,
                  );
                  onResult?.call(value);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  for (final font in {
    'ReminderStyleText': 'Roboto-Regular.ttf',
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

// Optional visual review artifacts; normal test runs never write screenshots.
Future<void> _renderIfRequested(WidgetTester tester, String name) async {
  final directory = Platform.environment['TRACKMARK_REMINDER_RENDER_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_renderKey),
  );
  await tester.runAsync(() async {
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
