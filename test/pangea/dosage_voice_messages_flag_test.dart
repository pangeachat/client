import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/constants/local.key.dart';

/// Plumbing for the `Environment.dosageVoiceMessagesEnabled` capability gate and
/// the [DosageSignalsRepo.voiceMessagesEnabled] AND-gate on top of it.
///
/// This flag is the ONE thing standing between the client and a 422 storm on
/// every already-live audio-signals POST once this build ships ahead of a server
/// that predates #150: the `voice_messages` field it guards is `extra="forbid"`
/// on the server, so an unknown-key body takes the sibling playback + coverage
/// lanes down with it. So the "ships dark" default and the precedence are pinned
/// here, and the AND with [DosageSignalsRepo.isEnabled] is what stops the field
/// going out on a build that has the capability flag but not the base dosage
/// flags.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'dosage_vm_flag_test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() async {
    dotenv.testLoad(mergeWith: <String, String>{});
    await Environment.appConfigurationStorage.remove(
      PLocalKey.appConfigOverride,
    );
  });

  group('Environment.dosageVoiceMessagesEnabled', () {
    test('ships dark: unset in dotenv AND no override -> false', () {
      expect(Environment.dosageVoiceMessagesEnabled, isFalse);
    });

    test('dotenv DOSAGE_VOICE_MESSAGES_ENABLED="true" -> true', () {
      dotenv.testLoad(
        mergeWith: <String, String>{'DOSAGE_VOICE_MESSAGES_ENABLED': 'true'},
      );
      expect(Environment.dosageVoiceMessagesEnabled, isTrue);
    });

    test(
      'appConfigOverride TRUE wins even when dotenv is false/unset',
      () async {
        dotenv.testLoad(
          mergeWith: <String, String>{'DOSAGE_VOICE_MESSAGES_ENABLED': 'false'},
        );
        await Environment.appConfigurationStorage.write(
          PLocalKey.appConfigOverride,
          const AppConfigOverride(dosageVoiceMessagesEnabled: true).toJson(),
        );
        expect(Environment.dosageVoiceMessagesEnabled, isTrue);
      },
    );

    test('AppConfigOverride carries the flag through a JSON round-trip', () {
      const original = AppConfigOverride(dosageVoiceMessagesEnabled: true);
      final roundTripped = AppConfigOverride.fromJson(original.toJson());

      expect(original.toJson()['dosageVoiceMessagesEnabled'], isTrue);
      expect(roundTripped.dosageVoiceMessagesEnabled, isTrue);
      // A fromJson with the key absent stays null (additive/back-compatible).
      expect(
        AppConfigOverride.fromJson(
          <String, dynamic>{},
        ).dosageVoiceMessagesEnabled,
        isNull,
      );
    });
  });

  group('DosageSignalsRepo.voiceMessagesEnabled ANDs the base dosage gate', () {
    Map<String, String> allBaseFlags({required bool voice}) => {
      'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
      'DOSAGE_SIGNALS_ENABLED': 'true',
      'TEACHER_BFF_API': 'https://bff.test.example',
      if (voice) 'DOSAGE_VOICE_MESSAGES_ENABLED': 'true',
    };

    test('base dosage on + capability on -> true', () {
      dotenv.testLoad(mergeWith: allBaseFlags(voice: true));
      expect(DosageSignalsRepo.isEnabled, isTrue);
      expect(DosageSignalsRepo.voiceMessagesEnabled, isTrue);
    });

    test('capability on but base dosage OFF -> false', () {
      // The capability flag alone must not open the lane: without the base
      // dosage flags the audio-signals POST is a no-op anyway, and letting the
      // field through would be a contract the rest of the body cannot honour.
      dotenv.testLoad(
        mergeWith: <String, String>{'DOSAGE_VOICE_MESSAGES_ENABLED': 'true'},
      );
      expect(DosageSignalsRepo.isEnabled, isFalse);
      expect(DosageSignalsRepo.voiceMessagesEnabled, isFalse);
    });

    test(
      'base dosage on but capability OFF -> false (the old-server default)',
      () {
        dotenv.testLoad(mergeWith: allBaseFlags(voice: false));
        expect(DosageSignalsRepo.isEnabled, isTrue);
        expect(DosageSignalsRepo.voiceMessagesEnabled, isFalse);
      },
    );
  });
}
