import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_input_context/text_input_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pangea/text_input_context');
  final calls = <MethodCall>[];
  bool installed = true;

  setUp(() {
    calls.clear();
    installed = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return installed;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('on iOS sends the identifier and reports the patch state', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await TextInputContext.setIdentifier('app.field.es'), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'setIdentifier');
    expect(calls.single.arguments, {'identifier': 'app.field.es'});
  });

  test('on iOS clears with null', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await TextInputContext.setIdentifier(null);
    expect(calls.single.arguments, {'identifier': null});
  });

  test(
    'on iOS reports false when the engine already owns the property',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      installed = false;
      expect(await TextInputContext.setIdentifier('app.field.es'), isFalse);
    },
  );

  test('is a no-op off iOS', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(await TextInputContext.setIdentifier('app.field.es'), isFalse);
    }
    expect(calls, isEmpty);
  });
}
