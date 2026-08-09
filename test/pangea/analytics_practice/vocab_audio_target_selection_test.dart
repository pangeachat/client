import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_audio_target_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';

/// One use, optionally message-bearing (eventId + roomId), aged so it never
/// trips the recent-practice skip.
OneConstructUse _use({
  required String lemma,
  String? eventId,
  String? roomId,
  ConstructUseTypeEnum type = ConstructUseTypeEnum.ta,
}) => OneConstructUse(
  useType: type,
  lemma: lemma,
  constructType: ConstructTypeEnum.vocab,
  metadata: ConstructUseMetaData(
    roomId: roomId,
    eventId: eventId,
    timeStamp: DateTime(2020),
  ),
  category: 'noun',
  form: lemma,
  xp: type.pointValue,
);

ConstructUses _construct(String lemma, List<OneConstructUse> uses) =>
    ConstructUses(
      uses: uses,
      constructType: ConstructTypeEnum.vocab,
      lemma: lemma,
      category: 'noun',
    );

void main() {
  group('VocabAudioTargetGenerator selection (#7702)', () {
    test('selects a lemma with a message-bearing use, without resolving the '
        'example message (no MatrixState / network needed)', () async {
      final constructs = [
        _construct('gato', [
          _use(lemma: 'gato', eventId: r'$evt1', roomId: '!room1'),
        ]),
      ];

      // No MatrixState is initialized in this test — if selection still tried
      // to resolve the example message (the #7702 front-load), this would throw.
      final targets = await VocabAudioTargetGenerator.get(constructs);

      expect(targets, hasLength(1));
      expect(
        targets.single.target.exerciseType,
        PracticeExerciseTypeEnum.lemmaAudio,
      );
      // The example is resolved later, at generation — never at selection.
      expect(targets.single.audioExampleMessage, isNull);
    });

    test('skips a lemma whose uses point at no message (no eventId/roomId), so '
        'an audio example could never resolve', () async {
      final constructs = [
        _construct('perro', [_use(lemma: 'perro')]),
      ];

      final targets = await VocabAudioTargetGenerator.get(constructs);
      expect(targets, isEmpty);
    });
  });
}
