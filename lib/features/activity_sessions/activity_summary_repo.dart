import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/features/activity_sessions/activity_summary_request_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
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

  /// One translation per source row and target language: a regenerated
  /// summary is a new row, so it is translated afresh.
  static String _storageKey(
    String roomId,
    ActivitySummaryRequestModel request,
  ) => '${roomId}_${request.sourceRequestHash}_${request.viewerL1}';

  static Future<Result<ActivitySummaryResponseModel>> get(
    String roomId,
    ActivitySummaryRequestModel request,
  ) async {
    final storageKey = _storageKey(roomId, request);
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

      // `req.post` already threw typed for anything ≥ 400, so this only guards
      // a success status the parser cannot consume (201/202/204/3xx).
      if (res.statusCode != 200) {
        throw PangeaHttpException.fromResponse(res);
      }

      final decodedBody = jsonDecode(utf8.decode(res.bodyBytes));
      return Result.value(ActivitySummaryResponseModel.fromJson(decodedBody));
    } catch (e, s) {
      if (e is! UnsubscribedException) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {'activity_summary_request': request.toJson()},
          level: PangeaHttpException.severityOf(e),
        );
      }
      return Result.error(e);
    }
  }
}
