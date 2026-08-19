import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_practice_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/morph_category_practice_exercise_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_audio_practice_exercise_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_meaning_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/emoji_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/lemma_meaning_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/lemma_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/morph_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/word_audio_practice_exercise_generator.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Generates one practice exercise per request.
///
/// Stateless by design: an exercise the learner may return to is held by the
/// practice that requested it (see `PracticeExerciseMemo`), never cached here.
/// A repo-level cache is shared by every surface and outlives the practice it
/// belongs to, which is what made the previous one unsafe as well as inert
/// (#8432).
class PracticeRepo {
  /// [event] is optional and used for saving the event to Matrix
  static Future<Result<PracticeExerciseModel>> getPracticeExercise(
    MessagePracticeExerciseRequest req, {
    required Map<String, dynamic> messageInfo,
  }) async {
    try {
      final MessagePracticeExerciseResponse res = await _routePracticeExercise(
        accessToken: MatrixState.pangeaController.userController.accessToken,
        req: req,
        messageInfo: messageInfo,
      );

      return Result.value(res.exercise);
    } on HttpException catch (e, s) {
      return Result.error(e, s);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'message': 'Error fetching practice exercise',
          'request': req.toJson(),
        },
      );
      return Result.error(e, s);
    }
  }

  static Future<MessagePracticeExerciseResponse> _fetch({
    required String accessToken,
    required MessagePracticeExerciseRequest requestModel,
  }) async {
    final Requests request = Requests(accessToken: accessToken);
    final Response res = await request.post(
      url: PApiUrls.messagePracticeExerciseGeneration,
      body: requestModel.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch exercise');
    }

    final Map<String, dynamic> json = jsonDecode(utf8.decode(res.bodyBytes));
    return MessagePracticeExerciseResponse.fromJson(json);
  }

  static Future<MessagePracticeExerciseResponse> _routePracticeExercise({
    required String accessToken,
    required MessagePracticeExerciseRequest req,
    required Map<String, dynamic> messageInfo,
  }) async {
    // some activities we'll get from the server and others we'll generate locally
    switch (req.target.exerciseType) {
      case PracticeExerciseTypeEnum.emoji:
        return EmojiPracticeExerciseGenerator.get(
          req,
          messageInfo: messageInfo,
        );
      case PracticeExerciseTypeEnum.lemmaId:
        return LemmaPracticeExerciseGenerator.get(req);
      case PracticeExerciseTypeEnum.lemmaMeaning:
        return VocabMeaningPracticeExerciseGenerator.get(req);
      case PracticeExerciseTypeEnum.lemmaAudio:
        return VocabAudioPracticeExerciseGenerator.get(req);
      case PracticeExerciseTypeEnum.grammarCategory:
        return MorphCategoryPracticeExerciseGenerator.get(req);
      case PracticeExerciseTypeEnum.grammarError:
        assert(
          req.grammarErrorInfo != null,
          'Grammar error info must be provided for grammar error activities',
        );
        return GrammarErrorPracticeGenerator.get(req);
      case PracticeExerciseTypeEnum.morphId:
        return MorphPracticeExerciseGenerator.get(req);
      case PracticeExerciseTypeEnum.wordMeaning:
        return LemmaMeaningPracticeExerciseGenerator.get(
          req,
          messageInfo: messageInfo,
        );
      case PracticeExerciseTypeEnum.messageMeaning:
      case PracticeExerciseTypeEnum.wordFocusListening:
        return WordAudioPracticeExerciseGenerator.get(req);
      case PracticeExerciseTypeEnum.hiddenWordListening:
        return _fetch(accessToken: accessToken, requestModel: req);
    }
  }
}
