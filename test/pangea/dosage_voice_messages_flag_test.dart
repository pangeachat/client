import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
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

  // The parity test DosageAudioBuffer._seal()'s docstring promises: coverage
  // is the client's assertion "I instrument this counter", so `voice_send`
  // may be declared only for a build whose duration recorder can actually
  // report. _voiceSendCovered (envelope pending/lost tracking) is a
  // NECESSARY condition for that, but it is not SUFFICIENT: it defaults to
  // true (0 in flight, nothing lost) regardless of whether
  // [DosageSignalsRepo.voiceMessagesEnabled] is even on, because
  // `DosageAudioBuffer.recordVoiceMessage` — the only thing that flips it
  // false — never runs when the capability is off. That gap is
  // pangeachat/client#8946: a build that cannot measure speaking still
  // declared coverage for it, so the server served a confident 0 instead of
  // withholding the counter.
  group(
    '_seal() coverage parity: voice_send only when the recorder can report',
    () {
      setUp(DosageAudioBuffer.debugResetAccounts);
      tearDown(DosageAudioBuffer.debugResetAccounts);

      Map<String, String> baseFlags({required bool voice}) => {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
        if (voice) 'DOSAGE_VOICE_MESSAGES_ENABLED': 'true',
      };

      test(
        'capability OFF: voice_send is withheld even with a clean envelope',
        () async {
          dotenv.testLoad(mergeWith: baseFlags(voice: false));
          expect(DosageSignalsRepo.voiceMessagesEnabled, isFalse);

          var clock = DateTime.utc(2026, 1, 1, 12);
          final buffer = DosageAudioBuffer(now: () => clock);
          buffer.start();
          clock = clock.add(const Duration(minutes: 5));
          // No accessToken: _seal() runs synchronously inside flush() either
          // way, and the batch lands in pendingBatches without an attempted
          // delivery, so the declaration can be inspected directly.
          await buffer.flush();

          final declared = buffer.pendingBatches.single.coverage
              .map((c) => c.category)
              .toSet();
          expect(
            declared,
            isNot(contains(DosageCoverageCategory.voiceSend)),
            reason:
                'the recorder cannot report on this build, so the server '
                'must see an undeclared counter, never a confident 0',
          );
          expect(
            declared,
            {
              DosageCoverageCategory.peer,
              DosageCoverageCategory.autoRead,
              DosageCoverageCategory.tapRead,
              DosageCoverageCategory.toolbarRead,
              DosageCoverageCategory.wordAudio,
              DosageCoverageCategory.practiceAudio,
            },
            reason:
                'suppression is scoped to voice_send alone — the six '
                'listening categories this build DOES instrument still '
                'declare, unconditionally, exactly as before',
          );
        },
      );

      test(
        'capability ON: voice_send is still declared with a clean envelope',
        () async {
          // Pins the direction a careless fix could break: the capability
          // flag alone must not withhold voice_send when the recorder CAN
          // report and no envelope was lost or left pending.
          dotenv.testLoad(mergeWith: baseFlags(voice: true));
          expect(DosageSignalsRepo.voiceMessagesEnabled, isTrue);

          var clock = DateTime.utc(2026, 1, 1, 12);
          final buffer = DosageAudioBuffer(now: () => clock);
          buffer.start();
          clock = clock.add(const Duration(minutes: 5));
          await buffer.flush();

          final declared = buffer.pendingBatches.single.coverage
              .map((c) => c.category)
              .toSet();
          expect(
            declared,
            contains(DosageCoverageCategory.voiceSend),
            reason:
                'a build that CAN report must still declare it — the fix '
                'must not silently disable the counter altogether',
          );
          expect(declared, hasLength(7));
        },
      );
    },
  );
}
