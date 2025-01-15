import 'dart:convert';
import 'dart:developer';

import 'package:fluffychat/pangea/analytics/repo/lemma_info_request.dart';
import 'package:fluffychat/pangea/analytics/repo/lemma_info_response.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/models/content_feedback.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

import '../../common/config/environment.dart';
import '../../common/network/requests.dart';

class LemmaInfoRepo {
  // In-memory cache with timestamps
  static final Map<LemmaInfoRequest, LemmaInfoResponse> _cache = {};
  static final Map<LemmaInfoRequest, DateTime> _cacheTimestamps = {};

  static const Duration _cacheDuration = Duration(days: 60);

  static void set(LemmaInfoRequest request, LemmaInfoResponse response) {
    _cache[request] = response;

    // set it to sometime in the future so we keep it in the cache for a while
    _cacheTimestamps[request] = DateTime.now().add(const Duration(days: 365));
  }

  static Future<LemmaInfoResponse> get(
    LemmaInfoRequest request, [
    String? feedback,
  ]) async {
    _clearExpiredEntries();

    if (_cache.containsKey(request)) {
      final cached = _cache[request]!;

      if (feedback == null) {
        // in this case, we just return the cached response
        return cached;
      } else {
        // we're adding this within the service to avoid needing to have the widgets
        // save state including the bad response
        request.feedback = ContentFeedback(
          cached,
          feedback,
        );
      }
    } else if (feedback != null) {
      // the cache should have the request in order for the user to provide feedback
      // this would be a strange situation and indicate some error in our logic
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        m: 'Feedback provided for a non-cached request',
        data: request.toJson(),
      );
    } else {
      debugPrint('No cached response for lemma ${request.lemma}');
    }

    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final requestBody = request.toJson();
    final Response res = await req.post(
      url: PApiUrls.lemmaDictionary,
      body: requestBody,
    );

    final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
    final response = LemmaInfoResponse.fromJson(decodedBody);

    // Store the response and timestamp in the cache
    _cache[request] = response;
    _cacheTimestamps[request] = DateTime.now();

    return response;
  }

  static void _clearExpiredEntries() {
    final now = DateTime.now();
    final expiredKeys = _cacheTimestamps.entries
        .where((entry) => now.difference(entry.value) > _cacheDuration)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }
}
