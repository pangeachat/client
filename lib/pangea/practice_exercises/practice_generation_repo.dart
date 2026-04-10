import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/analytics_practice/grammar_error_practice_generator.dart';
import 'package:fluffychat/pangea/analytics_practice/morph_category_practice_exercise_generator.dart';
import 'package:fluffychat/pangea/analytics_practice/vocab_audio_practice_exercise_generator.dart';
import 'package:fluffychat/pangea/analytics_practice/vocab_meaning_practice_exercise_generator.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/practice_exercises/emoji_practice_exercise_generator.dart';
import 'package:fluffychat/pangea/practice_exercises/lemma_meaning_practice_exercise_generator.dart';
import 'package:fluffychat/pangea/practice_exercises/lemma_practice_exercise_generator.dart';
import 'package:fluffychat/pangea/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/pangea/practice_exercises/morph_practice_exercise_generator.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/word_audio_practice_exercise_generator.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Represents an item in the completion cache.
class _RequestCacheItem {
  final PracticeExerciseModel practiceExercise;
  final DateTime timestamp;

  _RequestCacheItem({required this.practiceExercise, required this.timestamp});

  bool get isExpired =>
      DateTime.now().difference(timestamp) > PracticeRepo._cacheDuration;

  factory _RequestCacheItem.fromJson(Map<String, dynamic> json) {
    return _RequestCacheItem(
      practiceExercise: PracticeExerciseModel.fromJson(
        json['practiceActivity'],
      ),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() => {
    'practiceActivity': practiceExercise.toJson(),
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Controller for handling exercise completions.
class PracticeRepo {
  static final GetStorage _storage = GetStorage('practice_activity_cache');
  static const Duration _cacheDuration = Duration(minutes: 1);

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
    final Requests request = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );
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
        debugger(when: kDebugMode);
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

  static PracticeExerciseModel? _getCached(MessagePracticeExerciseRequest req) {
    final keys = List.from(_storage.getKeys());
    for (final k in keys) {
      try {
        final item = _RequestCacheItem.fromJson(_storage.read(k));
        if (item.isExpired) {
          _storage.remove(k);
        }
      } catch (e) {
        _storage.remove(k);
      }
    }

    try {
      final entry = _RequestCacheItem.fromJson(
        _storage.read(req.hashCode.toString()),
      );
      return entry.practiceExercise;
    } catch (e) {
      _storage.remove(req.hashCode.toString());
    }
    return null;
  }

  static Future<void> _setCached(
    MessagePracticeExerciseRequest req,
    MessagePracticeExerciseResponse res,
  ) => _storage.write(
    req.hashCode.toString(),
    _RequestCacheItem(
      practiceExercise: res.exercise,
      timestamp: DateTime.now(),
    ).toJson(),
  );
}
