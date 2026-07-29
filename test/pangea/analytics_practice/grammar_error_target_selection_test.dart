import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_target_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

OneConstructUse _use({
  required ConstructUseTypeEnum type,
  required DateTime timeStamp,
  String? eventId,
  String lemma = 'hablar',
}) => OneConstructUse(
  useType: type,
  lemma: lemma,
  constructType: ConstructTypeEnum.vocab,
  metadata: ConstructUseMetaData(
    roomId: null,
    eventId: eventId,
    timeStamp: timeStamp,
  ),
  category: 'verb',
  form: lemma,
  xp: type.pointValue,
);

ConstructUses _construct(String lemma, List<OneConstructUse> uses) =>
    ConstructUses(
      uses: uses,
      constructType: ConstructTypeEnum.vocab,
      lemma: lemma,
      category: 'verb',
    );

void main() {
  // now = noon Jan 2; the 24h cooldown cutoff is therefore noon Jan 1.
  final now = DateTime(2026, 1, 2, 12);
  final within24h = DateTime(2026, 1, 2, 6); // 6h ago — after cutoff
  final over24h = DateTime(2026, 1, 1, 6); // 30h ago — before cutoff

  group('GrammarErrorTargetGenerator.recentlyPracticedEventIDs (#7360)', () {
    test(
      'collects the eventID of a sentence practiced correctly within 24h',
      () {
        final constructs = [
          _construct('hablar', [
            _use(
              type: ConstructUseTypeEnum.corGE,
              eventId: r'$evt1',
              timeStamp: within24h,
            ),
          ]),
        ];

        expect(
          GrammarErrorTargetGenerator.recentlyPracticedEventIDs(
            constructs,
            now: now,
          ),
          {r'$evt1'},
        );
      },
    );

    test(
      'collects incorrect (incGE) practice too — practiced is practiced',
      () {
        final constructs = [
          _construct('hablar', [
            _use(
              type: ConstructUseTypeEnum.incGE,
              eventId: r'$evt2',
              timeStamp: within24h,
            ),
          ]),
        ];

        expect(
          GrammarErrorTargetGenerator.recentlyPracticedEventIDs(
            constructs,
            now: now,
          ),
          {r'$evt2'},
        );
      },
    );

    test('excludes practice older than the 24h cooldown', () {
      final constructs = [
        _construct('hablar', [
          _use(
            type: ConstructUseTypeEnum.corGE,
            eventId: r'$evtOld',
            timeStamp: over24h,
          ),
        ]),
      ];

      expect(
        GrammarErrorTargetGenerator.recentlyPracticedEventIDs(
          constructs,
          now: now,
        ),
        isEmpty,
      );
    });

    test('ignores non-practice use types (e.g. the chat-side corIGC error use) '
        'even when recent and event-bearing', () {
      final constructs = [
        _construct('hablar', [
          _use(
            type: ConstructUseTypeEnum.corIGC,
            eventId: r'$evtChat',
            timeStamp: within24h,
          ),
        ]),
      ];

      expect(
        GrammarErrorTargetGenerator.recentlyPracticedEventIDs(
          constructs,
          now: now,
        ),
        isEmpty,
      );
    });

    test('ignores recent practice uses that carry no eventID', () {
      final constructs = [
        _construct('hablar', [
          _use(type: ConstructUseTypeEnum.corGE, timeStamp: within24h),
        ]),
      ];

      expect(
        GrammarErrorTargetGenerator.recentlyPracticedEventIDs(
          constructs,
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('GrammarErrorPracticeExerciseModel eventID stamping (#7360)', () {
    GrammarErrorPracticeExerciseModel model(String eventID) =>
        GrammarErrorPracticeExerciseModel(
          tokens: const [],
          langCode: 'es',
          multipleChoiceContent: MultipleChoicePracticeExercise(
            choices: {'hablo', 'hablas'},
            answers: {'hablo'},
          ),
          text: 'yo hablo',
          errorOffset: 3,
          errorLength: 5,
          eventID: eventID,
          translation: 'I speak',
        );

    test('stamps the source eventID onto recorded practice uses so selection '
        'can dedup by sentence', () {
      expect(model(r'$evt1').constructUseMetadata.eventId, r'$evt1');
    });
  });
}
