import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/analytics_practice/morph_category_activity_generator.dart';
import 'package:fluffychat/pangea/analytics_practice/vocab_audio_activity_generator.dart';
import 'package:fluffychat/pangea/analytics_practice/vocab_meaning_activity_generator.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/emoji_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/lemma_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/lemma_meaning_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/morph_activity_generator.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/word_focus_listening_generator.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Represents an item in the completion cache.
class _RequestCacheItem {
  final PracticeActivityModel practiceActivity;
  final DateTime timestamp;

  _RequestCacheItem({
    required this.practiceActivity,
    required this.timestamp,
  });

  bool get isExpired =>
      DateTime.now().difference(timestamp) > PracticeRepo._cacheDuration;

  factory _RequestCacheItem.fromJson(Map<String, dynamic> json) {
    return _RequestCacheItem(
      practiceActivity:
          PracticeActivityModel.fromJson(json['practiceActivity']),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() => {
        'practiceActivity': practiceActivity.toJson(),
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Controller for handling activity completions.
class PracticeRepo {
  static final GetStorage _storage = GetStorage('practice_activity_cache');
  static const Duration _cacheDuration = Duration(minutes: 1);

  /// [event] is optional and used for saving the activity event to Matrix
  static Future<Result<PracticeActivityModel>> getPracticeActivity(
    MessageActivityRequest req, {
    required Map<String, dynamic> messageInfo,
  }) async {
    final cached = _getCached(req);
    if (cached != null) return Result.value(cached);

    try {
      final MessageActivityResponse res = await _routePracticeActivity(
        accessToken: MatrixState.pangeaController.userController.accessToken,
        req: req,
        messageInfo: messageInfo,
      );

      await _setCached(req, res);
      return Result.value(res.activity);
    } on HttpException catch (e, s) {
      return Result.error(e, s);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'message': 'Error fetching practice activity',
          'request': req.toJson(),
        },
      );
      return Result.error(e, s);
    }
  }

  static Future<MessageActivityResponse> _fetch({
    required String accessToken,
    required MessageActivityRequest requestModel,
  }) async {
    final Requests request = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );
    final Response res = await request.post(
      url: PApiUrls.messageActivityGeneration,
      body: requestModel.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch activity');
    }

    final Map<String, dynamic> json = jsonDecode(utf8.decode(res.bodyBytes));
    return MessageActivityResponse.fromJson(json);
  }

  static Future<MessageActivityResponse> _routePracticeActivity({
    required String accessToken,
    required MessageActivityRequest req,
    required Map<String, dynamic> messageInfo,
  }) async {
    // some activities we'll get from the server and others we'll generate locally
    switch (req.targetType) {
      case ActivityTypeEnum.emoji:
        return EmojiActivityGenerator.get(req, messageInfo: messageInfo);
      case ActivityTypeEnum.lemmaId:
        return LemmaActivityGenerator.get(req);
      case ActivityTypeEnum.lemmaMeaning:
        return VocabMeaningActivityGenerator.get(req);
      case ActivityTypeEnum.lemmaAudio:
        return VocabAudioActivityGenerator.get(req);
      case ActivityTypeEnum.grammarCategory:
        return MorphCategoryActivityGenerator.get(req);
      case ActivityTypeEnum.morphId:
        return MorphActivityGenerator.get(req);
      case ActivityTypeEnum.wordMeaning:
        debugger(when: kDebugMode);
        return LemmaMeaningActivityGenerator.get(req, messageInfo: messageInfo);
      case ActivityTypeEnum.messageMeaning:
      case ActivityTypeEnum.wordFocusListening:
        return WordFocusListeningGenerator.get(req);
      case ActivityTypeEnum.hiddenWordListening:
        return _fetch(
          accessToken: accessToken,
          requestModel: req,
        );
    }
  }

  static PracticeActivityModel? _getCached(
    MessageActivityRequest req,
  ) {
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
      return entry.practiceActivity;
    } catch (e) {
      _storage.remove(req.hashCode.toString());
    }
    return null;
  }

  static Future<void> _setCached(
    MessageActivityRequest req,
    MessageActivityResponse res,
  ) =>
      _storage.write(
        req.hashCode.toString(),
        _RequestCacheItem(
          practiceActivity: res.activity,
          timestamp: DateTime.now(),
        ).toJson(),
      );
}
