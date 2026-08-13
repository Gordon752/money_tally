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
}
