import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_request_model.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_response_model.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _ActivitySummaryCacheItem {
  final Completer<ActivitySummaryResponseModel> completer;
  final DateTime timestamp;

  _ActivitySummaryCacheItem(this.completer) : timestamp = DateTime.now();
}

class ActivitySummaryRepo {
  static final Map<String, _ActivitySummaryCacheItem> _cache = {};
  static const Duration cacheDuration = Duration(minutes: 10);

  /// Local cache key. Includes `viewerL1` so two L1-different viewers in
  /// the same room do not collide on cache — the choreographer returns
  /// different responses per viewer (group summary in viewer's L1).
  static String _storageKey(
    String roomId,
    ActivityPlanModel activity,
    String? viewerL1,
  ) {
    return '${roomId}_${activity.hashCode}_${viewerL1 ?? "default"}';
  }

  static Future<ActivitySummaryResponseModel> get(
    String roomId,
    ActivitySummaryRequestModel request,
  ) async {
    final storageKey = _storageKey(
      roomId,
      request.activity,
      request.viewerL1,
    );
    final cached = _cache[storageKey];
    if (cached != null) {
      return _cache[storageKey]!.completer.future;
    }

    _cache[storageKey] = _ActivitySummaryCacheItem(
      Completer<ActivitySummaryResponseModel>(),
    );

    try {
      final response = await _fetch(request);
      _cache[storageKey]!.completer.complete(response);
      return response;
    } catch (e) {
      _cache[storageKey]!.completer.completeError(e);
      _cache.remove(storageKey);
      rethrow;
    }
  }

  static Future<ActivitySummaryResponseModel> _fetch(
    ActivitySummaryRequestModel request,
  ) async {
    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.activitySummary,
      body: request.toJson(),
    );

    final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
    return ActivitySummaryResponseModel.fromJson(decodedBody);
  }

  static void delete(String roomId, ActivityPlanModel activity) async {
    // Cache keys now include viewerL1 — clear every viewer's entry for
    // this (room, activity) on invalidation. In practice only one viewer
    // ever runs in a single client process, but the prefix sweep is
    // robust against any future fan-out.
    final prefix = '${roomId}_${activity.hashCode}_';
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }
}
