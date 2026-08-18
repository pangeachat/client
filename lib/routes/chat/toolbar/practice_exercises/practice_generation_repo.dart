import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/expiring_storage_box.dart';
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

/// Controller for handling exercise completions.
class PracticeRepo {
  static const Duration _cacheDuration = Duration(minutes: 1);

  /// Generated exercises keyed by request hash.
  static final ExpiringStorageBox _cache = ExpiringStorageBox(
    'practice_activity_cache',
    ttl: _cacheDuration,
    payloadKey: 'practiceActivity',
  );

  /// [event] is optional and used for saving the event to Matrix
  static Future<Result<PracticeExerciseModel>> getPracticeExercise(
    MessagePracticeExerciseRequest req, {
    required Map<String, dynamic> messageInfo,
  }) async {
    final cached = _getCached(req);
    if (cached != null) return Result.value(cached);

    try {
      final MessagePracticeExerciseResponse res = await _routePracticeExercise(
        accessToken: MatrixState.pangeaController.userController.accessToken,
        req: req,
        messageInfo: messageInfo,
      );

      await _setCached(req, res);
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

  /// Drop the cached exercise for [req] so the next fetch regenerates it —
  /// e.g. after lemma content is corrected via user feedback.
  static Future<void> invalidate(MessagePracticeExerciseRequest req) =>
      _cache.remove(_cacheKey(req));

  static String _cacheKey(MessagePracticeExerciseRequest req) =>
      req.hashCode.toString();

  static PracticeExerciseModel? _getCached(MessagePracticeExerciseRequest req) {
    final key = _cacheKey(req);
    final json = _cache.read(key);
    if (json == null) return null;

    try {
      return PracticeExerciseModel.fromJson(json);
    } catch (e) {
      _cache.remove(key);
      return null;
    }
  }

  static Future<void> _setCached(
    MessagePracticeExerciseRequest req,
    MessagePracticeExerciseResponse res,
  ) => _cache.write(_cacheKey(req), res.exercise.toJson());
}
