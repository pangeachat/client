import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/example_message_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_meaning_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/lemma_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class VocabAudioPracticeExerciseGenerator {
  static Future<MessagePracticeExerciseResponse> get(
    MessagePracticeExerciseRequest req,
  ) async {
    final token = req.target.tokens.first;

    // The audio example message is resolved HERE (in the eager background
    // queue), not at selection — resolving it during selection blocked first
    // paint on N serial event fetches (#7702). If it can't be resolved, fall
    // back to a meaning exercise for the same lemma so the slot isn't lost.
    final audioExample =
        req.audioExampleMessage ?? await _resolveAudioExample(req);
    if (audioExample == null) {
      return VocabMeaningPracticeExerciseGenerator.get(_asMeaningRequest(req));
    }

    // Find the matching token in the audio example message to get the correct form
    final matchingToken = audioExample.tokens.firstWhere(
      (t) => t.lemma.text.toLowerCase() == token.lemma.text.toLowerCase(),
      orElse: () => token,
    );
    final PangeaToken targetToken = matchingToken;

    final Set<String> answers = {};
    final Set<String> wordsInMessage = {};
    final Set<String> lemmasInMessage = {};
    final List<PangeaToken> answerTokens = [targetToken];

    // Collect all words/lemmas in message and select additional answer words
    final List<PangeaToken> potentialAnswers = [];

    for (final t in audioExample.tokens) {
      wordsInMessage.add(t.text.content.toLowerCase());
      lemmasInMessage.add(t.lemma.text.toLowerCase());

      if (t != targetToken &&
          t.lemma.saveVocab &&
          t.text.content.trim().isNotEmpty) {
        potentialAnswers.add(t);
      }
    }

    // Shuffle and select up to 3 additional answer words
    potentialAnswers.shuffle();
    final otherAnswerTokens = potentialAnswers.take(3).toList();

    answerTokens.addAll(otherAnswerTokens);
    answers.addAll(answerTokens.map((t) => t.text.content.toLowerCase()));

    // Generate distractors, filtering out anything in the message (by form or lemma)
    final choices =
        await LemmaPracticeExerciseGenerator.lemmaPracticeExerciseDistractors(
          targetToken,
          maxChoices: 20,
          language: req.userL2.split('-').first,
        );
    final choicesList = choices
        .map((c) => c.lemma)
        .where(
          (lemma) =>
              !answers.contains(lemma.toLowerCase()) &&
              !wordsInMessage.contains(lemma.toLowerCase()) &&
              !lemmasInMessage.contains(lemma.toLowerCase()),
        )
        .take(4)
        .toList();

    final allChoices = [...choicesList, ...answers];
    allChoices.shuffle();

    return MessagePracticeExerciseResponse(
      exercise: VocabAudioPracticeExerciseModel(
        tokens: answerTokens,
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoicePracticeExercise(
          choices: allChoices.toSet(),
          answers: answers,
        ),
        roomId: audioExample.roomId,
        eventId: audioExample.eventId,
        exampleMessage: audioExample.exampleMessage,
      ),
    );
  }

  /// Resolve the audio example message for [req]'s lemma at generation time
  /// (off the selection critical path, #7702). Looks the construct up from
  /// local analytics, then finds an audio-capable example message. Null when
  /// no usable example exists — the caller falls back to a meaning exercise.
  static Future<AudioExampleMessage?> _resolveAudioExample(
    MessagePracticeExerciseRequest req,
  ) async {
    final id = req.target.tokens.first.vocabConstructID;
    final l2 = req.userL2.split('-').first;
    final constructs = await MatrixState
        .pangeaController
        .matrixState
        .analyticsDataService
        .getConstructUses([id], l2);
    final construct = constructs[id];
    if (construct == null) return null;
    return ExampleMessageUtil.getAudioExampleMessage(construct, noBold: true);
  }

  /// A meaning-exercise request for the same lemma, used when an audio example
  /// can't be resolved. Meaning has no example-message dependency.
  static MessagePracticeExerciseRequest _asMeaningRequest(
    MessagePracticeExerciseRequest req,
  ) => MessagePracticeExerciseRequest(
    userL1: req.userL1,
    userL2: req.userL2,
    exerciseQualityFeedback: null,
    target: PracticeTarget(
      tokens: req.target.tokens,
      exerciseType: PracticeExerciseTypeEnum.lemmaMeaning,
    ),
  );
}
