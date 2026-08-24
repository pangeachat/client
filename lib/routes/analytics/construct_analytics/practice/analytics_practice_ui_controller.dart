import 'package:collection/collection.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/listening_exposure_declaration.dart';
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
  /// **The room is always null here, and it takes an argument from nobody.**
  /// Analytics practice is reached from the learner's own progress pages, not
  /// from a chat, so the learner is in no room while any of these plays.
  ///
  /// The tempting mistake is the audio exercise, which IS built from a real
  /// message and whose model carries that message's room. That room is the
  /// provenance of the CONTENT, not the location of the LISTENING — the learner
  /// is drilling in analytics, not reading in that chat. Passing it would post
  /// a playback claiming the learner listened in that course's room, which
  /// inflates that course's listening with drill minutes that belong to the
  /// whole-language figure, and does it for one exercise type out of three so
  /// the same practice session would emit some roomed and some roomless rows.
  ///
  /// A null room is the honest statement, and it is what the serving side reads
  /// to place these minutes in the whole-language figure while leaving them out
  /// of a course's — where "none attributable to this course" is the true
  /// answer. `exercise.roomId` remains correct for FETCHING the example audio;
  /// it is only ever wrong as a listening location.
  static DosageTtsListeningProbe _listeningProbe() => DosageTtsListeningProbe(
    category: DosageListeningCategory.practiceAudio,
    roomId: null,
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
        // Roomless like its two siblings, even though this exercise is built
        // from a real message and the model carries that message's room. See
        // [_listeningProbe]: that room says where the CONTENT came from, not
        // where the learner was listening.
        listening: _listeningProbe(),
        exposure: token == null
            ? const ListeningExposureDeclaration.exempt(
                "choice text did not resolve to a token in this exercise",
              )
            : ListeningExposureDeclaration.ofTokens([token]),
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
      listening: _listeningProbe(),
      exposure: ListeningExposureDeclaration([cId]),
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
      listening: _listeningProbe(),
      exposure: ListeningExposureDeclaration.ofTokens([token]),
    );
  }
}
