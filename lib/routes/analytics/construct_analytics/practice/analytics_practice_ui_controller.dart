import 'package:collection/collection.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_tts_listening_probe.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsPracticeUiController {
  static String getChoiceTargetId(String choiceId, ConstructTypeEnum type) =>
      '${type.name}-choice-card-${choiceId.replaceAll(' ', '_')}';

  /// One measurement of one drill playback on the analytics practice surface.
  ///
  /// [roomId] is null for every exercise that has no room, which is most of
  /// them: analytics practice is reached from the learner's own progress pages,
  /// not from a chat. A null room is the honest statement of that, and it is
  /// what the serving side reads to place these minutes in the whole-language
  /// figure while leaving them out of a course's — where "none attributable to
  /// this course" is the true answer. Only the audio exercise carries a room,
  /// because it is built from a real message; nothing here may invent one.
  static DosageTtsListeningProbe _listeningProbe(String? roomId) =>
      DosageTtsListeningProbe(
        category: DosageListeningCategory.practiceAudio,
        roomId: roomId,
        // Read LIVE, not captured: an account switch or a token refresh
        // mid-playback must not post under a stale identity.
        userId: () => MatrixState.pangeaController.matrixState.client.userID,
        accessToken: () =>
            MatrixState.pangeaController.matrixState.client.accessToken,
      );

  /// Speak the lemma behind a tapped choice. Wrong taps flip the card to
  /// reveal that lemma, so the reveal gets audio too, not just the correct
  /// answer (#8277).
  static void playChoiceAudio(
    MultipleChoicePracticeExerciseModel exercise,
    String choiceId,
    String language,
  ) {
    // The audio exercise asks the learner to match a sound to a written word,
    // so its choices are the words themselves — speaking the tapped one is the
    // feedback the exercise is about (#8310). Only words drawn from the example
    // message have a token; distractors speak with no pos or morph.
    if (exercise is VocabAudioPracticeExerciseModel) {
      final token = exercise.tokens.firstWhereOrNull(
        (t) => t.text.content.toLowerCase() == choiceId.toLowerCase(),
      );
      TtsController.tryToSpeak(
        choiceId,
        langCode: language,
        useCase: TtsUseCase.choices,
        pos: token?.pos,
        morph: token?.morph.map((k, v) => MapEntry(k.name, v)),
        // Listening category 6 (#104): audio a DRILL played — the tapped choice
        // spoken back as the exercise's own feedback.
        //
        // The ONE exercise here with a room. It is built from a real message,
        // and the model carries that message's room, so this listening can be
        // attributed to a course the way the in-chat drills are. It stays a
        // nullable read: the field is optional on the model and a missing one is
        // roomless, not an invitation to substitute something else.
        listening: _listeningProbe(exercise.roomId),
      );
      return;
    }

    if (exercise is! VocabMeaningPracticeExerciseModel) return;

    final cId = ConstructIdentifier.fromString(choiceId);
    if (cId == null) return;
    TtsController.tryToSpeak(
      cId.lemma,
      langCode: language,
      useCase: TtsUseCase.choices,
      pos: cId.category,
      // Roomless drill listening: a meaning exercise is assembled from the
      // learner's own construct history, not from a message, so there is no
      // room to attribute it to and none is invented. See [_listeningProbe].
      listening: _listeningProbe(null),
    );
  }

  static void playTargetAudio(
    MultipleChoicePracticeExerciseModel exercise,
    ConstructTypeEnum type,
    String language,
  ) {
    if (exercise is! VocabMeaningPracticeExerciseModel) return;

    final token = exercise.tokens.first;
    TtsController.tryToSpeak(
      token.vocabConstructID.lemma,
      langCode: language,
      useCase: TtsUseCase.choices,
      pos: token.pos,
      morph: token.morph.map((k, v) => MapEntry(k.name, v)),
      // Roomless drill listening, for the same reason as the choice above: this
      // is the meaning exercise's prompt, and it has no message behind it.
      listening: _listeningProbe(null),
    );
  }
}
