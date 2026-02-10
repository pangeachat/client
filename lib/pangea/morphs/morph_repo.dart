import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/morphs/default_morph_mapping.dart';
import 'package:fluffychat/pangea/morphs/morph_models.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../common/network/requests.dart';

class _APICallCacheItem {
  final DateTime time;
  final Future<MorphFeaturesAndTags> future;

  _APICallCacheItem(this.time, this.future);
}

class _MorphRepoCacheItem {
  final DateTime time;
  final MorphFeaturesAndTags morphs;

  _MorphRepoCacheItem(this.time, this.morphs);

  bool get isExpired =>
      DateTime.now().difference(time).inMinutes > 1440; // 24 hours

  Map<String, dynamic> toJson() => {
    "time": time.toIso8601String(),
    "morphs": morphs.toJson(),
  };

  factory _MorphRepoCacheItem.fromJson(Map<String, dynamic> json) {
    return _MorphRepoCacheItem(
      DateTime.parse(json["time"]),
      MorphFeaturesAndTags.fromJson(json["morphs"]),
    );
  }
}

class MorphsRepo {
  // long-term storage of morphs
  static final GetStorage _morphsStorage = GetStorage('morphs_storage');

  // to avoid multiple fetches for the same language code
  // by different parts of the app within a short time
  static final shortTermCache = <String, _APICallCacheItem>{};
  static const int _cacheDurationMinutes = 1;

  static void set(String languageCode, MorphFeaturesAndTags response) {
    final entry = _MorphRepoCacheItem(DateTime.now(), response);
    _morphsStorage.write(languageCode, entry.toJson());
  }

  static Future<MorphFeaturesAndTags> _fetch(String languageCode) async {
    try {
      final Requests req = Requests(
        choreoApiKey: Environment.choreoApiKey,
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );

      final Response res = await req.get(
        url: '${PApiUrls.morphFeaturesAndTags}/$languageCode',
      );

      final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
      final response = MorphFeaturesAndTags.fromJson(decodedBody);

      set(languageCode, response);

      return response;
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(e: e, s: s, data: {"languageCode": languageCode});
      return defaultMorphMapping;
    }
  }

  /// this function fetches the morphs for a given language code
  /// while remaining synchronous by using a default value
  /// if the morphs are not yet fetched. we'll see if this works well
  /// if not, we can make it async and update uses of this function
  /// to be async as well
  static Future<MorphFeaturesAndTags> get([LanguageModel? language]) async {
    language ??= MatrixState.pangeaController.userController.userL2;

    if (language == null) {
      return defaultMorphMapping;
    }

    // does not differ based on locale
    final langCodeShort = language.langCodeShort;

    // check if we have a cached morphs for this language code
    final cachedJson = _morphsStorage.read(langCodeShort);
    if (cachedJson != null) {
      try {
        final cacheItem = _MorphRepoCacheItem.fromJson(cachedJson);
        if (!cacheItem.isExpired) {
          return cacheItem.morphs;
        } else {
          _morphsStorage.remove(langCodeShort);
        }
      } catch (e) {
        _morphsStorage.remove(langCodeShort);
      }
    }

    // check if we have a cached call for this language code
    final _APICallCacheItem? cachedCall = shortTermCache[langCodeShort];
    if (cachedCall != null) {
      if (DateTime.now().difference(cachedCall.time).inMinutes <
          _cacheDurationMinutes) {
        return cachedCall.future;
      } else {
        shortTermCache.remove(langCodeShort);
      }
    }

    // fetch the morphs but don't wait for it
    final future = _fetch(langCodeShort);
    shortTermCache[langCodeShort] = _APICallCacheItem(DateTime.now(), future);
    return future;
  }

  static MorphFeaturesAndTags get cached {
    if (MatrixState.pangeaController.userController.userL2?.langCodeShort ==
        null) {
      return defaultMorphMapping;
    }
    final cachedJson = _morphsStorage.read(
      MatrixState.pangeaController.userController.userL2!.langCodeShort,
    );
    if (cachedJson != null) {
      final cacheItem = _MorphRepoCacheItem.fromJson(cachedJson);
      if (!cacheItem.isExpired) {
        return cacheItem.morphs;
      }
    }
    return defaultMorphMapping;
  }
}
