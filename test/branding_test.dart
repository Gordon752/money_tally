import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart';

void main() {
  testWidgets('Trackmark sign-in presents the approved public copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: SignInView(
          isSigningIn: false,
          errorMessage: null,
          onAppleSignIn: () {},
          onContinueLocal: () {},
        ),
      ),
    );

    expect(find.text('TRACKMARK'), findsOneWidget);
    expect(find.text('MONEY'), findsOneWidget);
    expect(find.text('Manage your money with confidence.'), findsOneWidget);
    expect(
      find.text('Securely sync your data across your Apple devices.'),
      findsOneWidget,
    );
    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('Continue Local-Only'), findsOneWidget);
  });

  testWidgets('Trackmark startup uses the dark branded launch surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const StartupLoadingView()),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, TrackmarkBrandPalette.deepGreen);
    expect(find.text('TRACKMARK'), findsOneWidget);
    expect(find.text('MONEY'), findsOneWidget);
    expect(find.text('Smart today. Secure tomorrow.'), findsOneWidget);
  });
}
