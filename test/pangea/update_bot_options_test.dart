import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/chat_settings/models/bot_options_model.dart';
import 'package:fluffychat/pangea/chat_settings/utils/bot_client_extension.dart';
import 'package:fluffychat/pangea/learning_settings/gender_enum.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/user/user_model.dart';

void main() {
  // ---------------------------------------------------------------------------
  // buildUpdatedBotOptions — pure logic tests
  // ---------------------------------------------------------------------------
  group('buildUpdatedBotOptions', () {
    final baseSettings = UserSettings(
      targetLanguage: 'es',
      cefrLevel: LanguageLevelTypeEnum.b1,
      voice: 'voice_1',
      gender: GenderEnum.woman,
    );

    const userId = '@user:server';

    test('returns null when all relevant fields already match', () {
      final currentOptions = BotOptionsModel(
        targetLanguage: 'es',
        languageLevel: LanguageLevelTypeEnum.b1,
        targetVoice: 'voice_1',
        userGenders: const {userId: GenderEnum.woman},
      );

      final result = buildUpdatedBotOptions(
        currentOptions: currentOptions,
        userSettings: baseSettings,
        userId: userId,
      );

      expect(result, isNull);
    });

    test('returns updated model when targetLanguage differs', () {
      final currentOptions = BotOptionsModel(
        targetLanguage: 'fr',
        languageLevel: LanguageLevelTypeEnum.b1,
        targetVoice: 'voice_1',
        userGenders: const {userId: GenderEnum.woman},
      );

      final result = buildUpdatedBotOptions(
        currentOptions: currentOptions,
        userSettings: baseSettings,
        userId: userId,
      );

      expect(result, isNotNull);
      expect(result!.targetLanguage, 'es');
      // Other fields carried over
      expect(result.languageLevel, LanguageLevelTypeEnum.b1);
      expect(result.targetVoice, 'voice_1');
    });

    test('returns updated model when languageLevel differs', () {
      final currentOptions = BotOptionsModel(
        targetLanguage: 'es',
        languageLevel: LanguageLevelTypeEnum.a1,
        targetVoice: 'voice_1',
        userGenders: const {userId: GenderEnum.woman},
      );

      final result = buildUpdatedBotOptions(
        currentOptions: currentOptions,
        userSettings: baseSettings,
        userId: userId,
      );

      expect(result, isNotNull);
      expect(result!.languageLevel, LanguageLevelTypeEnum.b1);
    });

    test('returns updated model when voice differs', () {
      final currentOptions = BotOptionsModel(
        targetLanguage: 'es',
        languageLevel: LanguageLevelTypeEnum.b1,
        targetVoice: 'voice_2',
        userGenders: const {userId: GenderEnum.woman},
      );

      final result = buildUpdatedBotOptions(
        currentOptions: currentOptions,
        userSettings: baseSettings,
        userId: userId,
      );

      expect(result, isNotNull);
      expect(result!.targetVoice, 'voice_1');
    });

    test('returns updated model when gender differs', () {
      final currentOptions = BotOptionsModel(
        targetLanguage: 'es',
        languageLevel: LanguageLevelTypeEnum.b1,
        targetVoice: 'voice_1',
        userGenders: const {userId: GenderEnum.man},
      );

      final result = buildUpdatedBotOptions(
        currentOptions: currentOptions,
        userSettings: baseSettings,
        userId: userId,
      );

      expect(result, isNotNull);
      expect(result!.userGenders[userId], GenderEnum.woman);
    });

    test('defaults to empty BotOptionsModel when currentOptions is null', () {
      final result = buildUpdatedBotOptions(
        currentOptions: null,
        userSettings: baseSettings,
        userId: userId,
      );

      expect(result, isNotNull);
      expect(result!.targetLanguage, 'es');
      expect(result.languageLevel, LanguageLevelTypeEnum.b1);
      expect(result.targetVoice, 'voice_1');
      expect(result.userGenders[userId], GenderEnum.woman);
    });

    test('preserves gender entries for other users', () {
      final currentOptions = BotOptionsModel(
        targetLanguage: 'fr', // different → triggers update
        languageLevel: LanguageLevelTypeEnum.b1,
        targetVoice: 'voice_1',
        userGenders: const {
          '@other:server': GenderEnum.man,
          userId: GenderEnum.woman,
        },
      );

      final result = buildUpdatedBotOptions(
        currentOptions: currentOptions,
        userSettings: baseSettings,
        userId: userId,
      );

      expect(result, isNotNull);
      expect(result!.userGenders['@other:server'], GenderEnum.man);
      expect(result.userGenders[userId], GenderEnum.woman);
    });

    test('handles null userId gracefully', () {
      const currentOptions = BotOptionsModel(targetLanguage: 'fr');

      final result = buildUpdatedBotOptions(
        currentOptions: currentOptions,
        userSettings: baseSettings,
        userId: null,
      );

      expect(result, isNotNull);
      expect(result!.targetLanguage, 'es');
      // Gender not set because userId is null
      expect(result.userGenders, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // applyBotOptionUpdatesInOrder — async orchestration tests
  // ---------------------------------------------------------------------------
  group('applyBotOptionUpdatesInOrder', () {
    test('executes priority update before remaining updates', () async {
      final callLog = <String>[];

      await applyBotOptionUpdatesInOrder(
        priorityUpdate: () async {
          callLog.add('dm');
        },
        remainingUpdates: [
          () async {
            callLog.add('room_a');
          },
          () async {
            callLog.add('room_b');
          },
        ],
      );

      expect(callLog, ['dm', 'room_a', 'room_b']);
    });

    test('executes remaining updates sequentially, not in parallel', () async {
      final timestamps = <String, int>{};
      var counter = 0;

      await applyBotOptionUpdatesInOrder(
        priorityUpdate: () async {
          timestamps['dm_start'] = counter++;
          await Future.delayed(const Duration(milliseconds: 30));
          timestamps['dm_end'] = counter++;
        },
        remainingUpdates: [
          () async {
            timestamps['a_start'] = counter++;
            await Future.delayed(const Duration(milliseconds: 30));
            timestamps['a_end'] = counter++;
          },
          () async {
            timestamps['b_start'] = counter++;
            await Future.delayed(const Duration(milliseconds: 30));
            timestamps['b_end'] = counter++;
          },
        ],
      );

      // Sequential order: dm completes before a starts, a before b
      expect(timestamps['dm_end']!, lessThan(timestamps['a_start']!));
      expect(timestamps['a_end']!, lessThan(timestamps['b_start']!));
    });

    test('propagates priority update errors to caller', () async {
      expect(
        () => applyBotOptionUpdatesInOrder(
          priorityUpdate: () async {
            throw Exception('DM update failed');
          },
          remainingUpdates: [],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'remaining updates do NOT execute when priority update fails',
      () async {
        final callLog = <String>[];

        try {
          await applyBotOptionUpdatesInOrder(
            priorityUpdate: () async {
              throw Exception('DM failed');
            },
            remainingUpdates: [
              () async {
                callLog.add('room_a');
              },
            ],
          );
        } catch (_) {}

        expect(callLog, isEmpty);
      },
    );

    test(
      'isolates errors in remaining updates and continues to next room',
      () async {
        final callLog = <String>[];
        final errors = <Object>[];

        await applyBotOptionUpdatesInOrder(
          priorityUpdate: () async {
            callLog.add('dm');
          },
          remainingUpdates: [
            () async {
              callLog.add('room_a');
            },
            () async {
              throw Exception('room_b failed');
            },
            () async {
              callLog.add('room_c');
            },
          ],
          onError: (e, _) => errors.add(e),
        );

        // room_b's error didn't prevent room_c from running
        expect(callLog, ['dm', 'room_a', 'room_c']);
        expect(errors, hasLength(1));
        expect(errors.first, isA<Exception>());
      },
    );

    test('works correctly when priority update is null', () async {
      final callLog = <String>[];

      await applyBotOptionUpdatesInOrder(
        priorityUpdate: null,
        remainingUpdates: [
          () async {
            callLog.add('room_a');
          },
          () async {
            callLog.add('room_b');
          },
        ],
      );

      expect(callLog, ['room_a', 'room_b']);
    });

    test('handles empty remaining updates list', () async {
      final callLog = <String>[];

      await applyBotOptionUpdatesInOrder(
        priorityUpdate: () async {
          callLog.add('dm');
        },
        remainingUpdates: [],
      );

      expect(callLog, ['dm']);
    });

    test('handles all null / empty gracefully', () async {
      // Should complete without error
      await applyBotOptionUpdatesInOrder(
        priorityUpdate: null,
        remainingUpdates: [],
      );
    });

    test('multiple remaining errors are all reported', () async {
      final errors = <Object>[];

      await applyBotOptionUpdatesInOrder(
        priorityUpdate: null,
        remainingUpdates: [
          () async {
            throw Exception('fail_1');
          },
          () async {
            throw Exception('fail_2');
          },
          () async {
            throw Exception('fail_3');
          },
        ],
        onError: (e, _) => errors.add(e),
      );

      expect(errors, hasLength(3));
    });
  });
}
