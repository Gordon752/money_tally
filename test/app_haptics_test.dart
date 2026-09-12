import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/src/design/app_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('user toggle handler requests one subtle selection haptic', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    var value = false;

    AppHaptics.toggleHandler((next) => value = next)!(true);
    await Future<void>.delayed(Duration.zero);

    expect(value, isTrue);
    expect(
      calls.where(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      hasLength(1),
    );
  });

  test('programmatic value changes do not request haptics', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    var value = false;
    value = true;
    await Future<void>.delayed(Duration.zero);

    expect(value, isTrue);
    expect(calls, isEmpty);
  });

  testWidgets('committed page pop requests one navigation haptic', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [TrackmarkNavigationObserver()],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back'),
                  ),
                ),
              ),
            ),
            child: const Text('Forward'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();
    expect(_selectionHaptics(calls), 0);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(_selectionHaptics(calls), 1);
  });

  testWidgets('strong action can suppress duplicate route-pop haptic', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [TrackmarkNavigationObserver()],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () {
                      AppHaptics.suppressNextNavigation();
                      Navigator.pop(context);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ),
            ),
            child: const Text('Forward'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();
    calls.clear();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(_selectionHaptics(calls), 0);
  });
}

int _selectionHaptics(List<MethodCall> calls) => calls
    .where(
      (call) =>
          call.method == 'HapticFeedback.vibrate' &&
          call.arguments == 'HapticFeedbackType.selectionClick',
    )
    .length;
