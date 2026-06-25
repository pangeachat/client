import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo/validate_promo_code_request.dart';
import 'package:fluffychat/features/subscription/repo/validate_promo_code_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ValidatePromoCodeCacheEntry {
  final ValidatePromoCodeResponse response;
  final DateTime timestamp;

  const ValidatePromoCodeCacheEntry({
    required this.response,
    required this.timestamp,
  });

  static const Duration _cacheDuration = Duration(minutes: 10);

  bool get isExpired =>
      timestamp.isBefore(DateTime.now().subtract(_cacheDuration));
}

class ValidatePromoCodeRepo {
  static final Map<String, Future<Result<ValidatePromoCodeResponse>>>
  _inflightCache = {};

  static final Map<String, ValidatePromoCodeCacheEntry> _cache = {};

  static Future<Result<ValidatePromoCodeResponse>> get(
    ValidatePromoCodeRequest request,
  ) async {
    final cached = _cache[request.storageKey];
    if (cached != null) {
      if (cached.isExpired) {
        _cache.remove(request.storageKey);
      } else {
        return Result.value(cached.response);
      }
    }

    final inflight = _inflightCache[request.storageKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _fetch(request);

    _inflightCache[request.storageKey] = future;
    final result = await future;

    final response = result.result;
    if (response != null) {
      _cache[request.storageKey] = ValidatePromoCodeCacheEntry(
        response: response,
        timestamp: DateTime.now(),
      );
    }

    _inflightCache.remove(request.storageKey);

    return result;
  }

  static Future<Result<ValidatePromoCodeResponse>> _fetch(
    ValidatePromoCodeRequest request,
  ) async {
    try {
      final Requests req = Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
      );

      String requestUrl =
          "${PApiUrls.validatePromoCode}?code=${Uri.encodeComponent(request.code)}";

      final duration = request.duration;
      if (duration != null) {
        requestUrl = "$requestUrl&duration=${duration.name}";
      }

      final Response res = await req.get(url: requestUrl);
      if (res.statusCode != 200) {
        throw res;
      }

      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      final response = ValidatePromoCodeResponse.fromJson(json);
      return Result.value(response);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: request.toJson());
      return Result.error(e);
    }
  }
}
