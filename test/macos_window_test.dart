import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';
import 'package:money_tally/src/onboarding/onboarding_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Mac native opening size shows expanded sidebar and remains resizable',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        OnboardingPreferences.storageKey: currentOnboardingVersion,
      });
      final nib = File(
        'macos/Runner/Base.lproj/MainMenu.xib',
      ).readAsStringSync();
      final contentRect = RegExp(
        r'<rect key="contentRect"[^>]*width="([\d.]+)" height="([\d.]+)"',
      ).firstMatch(nib)!;
      final openingSize = Size(
        double.parse(contentRect.group(1)!),
        double.parse(contentRect.group(2)!),
      );
      expect(openingSize, const Size(1120, 700));
      expect(nib, contains('resizable="YES"'));
      expect(
        nib,
        contains('key="frame" x="0.0" y="0.0" width="1120" height="700"'),
      );
      tester.view.physicalSize = openingSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MoneyTallyApp(initialOnboardingVersionSeen: currentOnboardingVersion),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue,
      );
      for (final label in [
        'Dashboard',
        'Accounts',
        'Ledger',
        'Plan',
        'Scheduled',
        'Reports',
        'Categories',
        'Settings',
      ]) {
        expect(
          find
              .descendant(
                of: find.byType(NavigationRail),
                matching: find.text(label),
              )
              .hitTestable(),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);

      // The startup size must not force the desktop layout after resizing.
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
