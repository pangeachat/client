import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_request_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _ActivitySummaryCacheItem {
  final Future<Result<ActivitySummaryResponseModel>> future;
  final DateTime timestamp;

  _ActivitySummaryCacheItem(this.future) : timestamp = DateTime.now();

  static const Duration _cacheDuration = Duration(minutes: 10);

  bool get isExpired =>
      timestamp.isBefore(DateTime.now().subtract(_cacheDuration));
}

class ActivitySummaryRepo {
  static final Map<String, _ActivitySummaryCacheItem> _cache = {};

  /// Local cache key. Includes `langCode` so two L1-different viewers in
  /// the same room do not collide on cache — the choreographer returns
  /// different responses per viewer (group summary in viewer's L1).
  static String _storageKey(
    String roomId,
    ActivityPlanModel activity,
    String? langCode,
  ) => '${roomId}_${activity.activityId}_${langCode ?? "default"}';

  static Future<Result<ActivitySummaryResponseModel>> get(
    String roomId,
    ActivitySummaryRequestModel request,
  ) async {
    final storageKey = _storageKey(roomId, request.activity, request.langCode);
    final cached = _getCached(storageKey);
    if (cached != null) return cached;

    final future = _fetch(request);
    _cache[storageKey] = _ActivitySummaryCacheItem(future);
    final result = await future;
    if (result.isError) {
      _cache.remove(storageKey);
    }
    return result;
  }

  static Future<Result<ActivitySummaryResponseModel>>? _getCached(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }

    return entry.future;
  }

  static Future<Result<ActivitySummaryResponseModel>> _fetch(
    ActivitySummaryRequestModel request,
  ) async {
    try {
      final Requests req = Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );

      final Response res = await req.post(
        url: PApiUrls.activitySummary,
        body: request.toJson(),
      );

      if (res.statusCode != 200) {
        throw res;
      }

      final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
      return Result.value(ActivitySummaryResponseModel.fromJson(decodedBody));
    } catch (e, s) {
      if (e is! UnsubscribedException) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {'activity_summary_request': request.toJson()},
        );
      }
      return Result.error(e);
    }
  }

  static void delete(String roomId, ActivitySummaryRequestModel request) {
    final key = _storageKey(roomId, request.activity, request.langCode);
    _cache.remove(key);
  }
}
