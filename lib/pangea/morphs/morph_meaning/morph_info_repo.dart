import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning/morph_info_request.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning/morph_info_response.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _APICallCacheItem {
  final DateTime time;
  final Future<MorphInfoResponse> future;

  _APICallCacheItem(this.time, this.future);
}

class MorphInfoRepo {
  static final GetStorage _morphMeaningStorage = GetStorage(
    'morph_meaning_storage',
  );
  static final shortTermCache = <String, _APICallCacheItem>{};
  static const int _cacheDurationMinutes = 1;

  static void set(MorphInfoRequest request, MorphInfoResponse response) {
    _morphMeaningStorage.write(request.storageKey, response.toJson());
  }

  static Future<MorphInfoResponse> _fetch(MorphInfoRequest request) async {
    try {
      final Requests req = Requests(
        choreoApiKey: Environment.choreoApiKey,
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );

      final Response res = await req.post(
        url: PApiUrls.morphDictionary,
        body: request.toJson(),
      );

      final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
      final response = MorphInfoResponse.fromJson(decodedBody);

      set(request, response);

      return response;
    } catch (e) {
      debugPrint('Error fetching morph info: $e');
      return Future.error(e);
    }
  }

  static Future<MorphInfoResponse> _get(MorphInfoRequest request) async {
    request.userL1 == request.userL1.split('-').first;
    request.userL2 == request.userL2.split('-').first;

    final cachedJson = _morphMeaningStorage.read(request.storageKey);
    if (cachedJson != null) {
      return MorphInfoResponse.fromJson(cachedJson);
    }

    final _APICallCacheItem? cachedCall = shortTermCache[request.storageKey];
    if (cachedCall != null) {
      if (DateTime.now().difference(cachedCall.time).inMinutes <
          _cacheDurationMinutes) {
        return cachedCall.future;
      } else {
        shortTermCache.remove(request.storageKey);
      }
    }

    final future = _fetch(request);
    shortTermCache[request.storageKey] = _APICallCacheItem(
      DateTime.now(),
      future,
    );
    return future;
  }

  static Future<String?> get({
    required MorphFeaturesEnum feature,
    required String tag,
  }) async {
    final res = await _get(
      MorphInfoRequest(
        userL1:
            MatrixState.pangeaController.languageController.userL1?.langCode ??
            LanguageKeys.defaultLanguage,
        userL2:
            MatrixState.pangeaController.languageController.userL2?.langCode ??
            LanguageKeys.defaultLanguage,
      ),
    );
    final morph = res.getFeatureByCode(feature.name);

    final data = morph?.getTagByCode(tag);

    return data?.l1Description;
  }

  static Future<void> setMorphDefinition({
    required MorphFeaturesEnum feature,
    required String tag,
    required String defintion,
  }) async {
    final userL1 =
        MatrixState.pangeaController.languageController.userL1?.langCode ??
        LanguageKeys.defaultLanguage;
    final userL2 =
        MatrixState.pangeaController.languageController.userL2?.langCode ??
        LanguageKeys.defaultLanguage;
    final userL1Short = userL1.split('-').first;
    final userL2Short = userL2.split('-').first;
    final cachedJson = _morphMeaningStorage.read(userL1Short + userL2Short);

    MorphInfoResponse? resp = MorphInfoResponse(
      userL1: userL1,
      userL2: userL2,
      features: [],
    );

    if (cachedJson is Map<String, dynamic>) {
      resp = MorphInfoResponse.fromJson(cachedJson);
    }

    resp.setMorphDefinition(feature.name, tag, defintion);
    await _morphMeaningStorage.write(userL1Short + userL2Short, resp.toJson());
  }
}
