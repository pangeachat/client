import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';

/// Plumbing tests for the `Environment.liveStreamingSttEnabled` flag — the same
/// coverage `voiceTranscriptDecoupleEnabled` carries: ships dark by default,
/// dotenv opt-in, `appConfigOverride` precedence, and JSON round-trip. These
/// guard the pilot's "ships dark" guarantee against a default/precedence
/// regression.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Environment.appConfigOverride reads a GetStorage('env_override') box that
    // needs path_provider; stub the channel to a temp dir so init is silent.
    final tempDir = await Directory.systemTemp.createTemp('live_stt_flag_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() async {
    // Reset both layers before each test so precedence is asserted cleanly.
    dotenv.testLoad(mergeWith: <String, String>{});
    await Environment.appConfigurationStorage.remove(
      PLocalKey.appConfigOverride,
    );
  });

  test('ships dark: unset in dotenv AND no override -> false', () {
    expect(Environment.liveStreamingSttEnabled, isFalse);
  });

  test('dotenv LIVE_STREAMING_STT_ENABLED="true" -> true', () {
    dotenv.testLoad(
      mergeWith: <String, String>{'LIVE_STREAMING_STT_ENABLED': 'true'},
    );
    expect(Environment.liveStreamingSttEnabled, isTrue);
  });

  test('appConfigOverride TRUE wins even when dotenv is false/unset', () async {
    // dotenv explicitly false: the override must still flip it on. (Reverting
    // the `appConfigOverride?.liveStreamingSttEnabled ??` read => the getter
    // returns the dotenv false => RED.)
    dotenv.testLoad(
      mergeWith: <String, String>{'LIVE_STREAMING_STT_ENABLED': 'false'},
    );
    await Environment.appConfigurationStorage.write(
      PLocalKey.appConfigOverride,
      const AppConfigOverride(liveStreamingSttEnabled: true).toJson(),
    );

    expect(Environment.liveStreamingSttEnabled, isTrue);
  });

  test(
    'AppConfigOverride carries liveStreamingSttEnabled through JSON round-trip',
    () {
      const original = AppConfigOverride(liveStreamingSttEnabled: true);
      final roundTripped = AppConfigOverride.fromJson(original.toJson());

      expect(original.toJson()['liveStreamingSttEnabled'], isTrue);
      expect(roundTripped.liveStreamingSttEnabled, isTrue);
      // A fromJson with the key absent stays null (additive/back-compatible).
      expect(
        AppConfigOverride.fromJson(<String, dynamic>{}).liveStreamingSttEnabled,
        isNull,
      );
    },
  );
}
