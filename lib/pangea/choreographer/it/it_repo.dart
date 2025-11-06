import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';
import 'it_request_model.dart';
import 'it_response_model.dart';

class _ITCacheItem {
  final Future<ITResponseModel> response;
  final DateTime timestamp;

  const _ITCacheItem({
    required this.response,
    required this.timestamp,
  });
}

class ITRepo {
  static final Map<String, _ITCacheItem> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<Result<ITResponseModel>> get(
    ITRequestModel request,
  ) {
    final cached = _getCached(request);
    if (cached != null) {
      return _getResult(request, cached);
    }

    final future = _fetch(request);
    _setCached(request, future);
    return _getResult(request, future);
  }

  static Future<ITResponseModel> _fetch(
    ITRequestModel request,
  ) async {
    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    final Response res =
        await req.post(url: PApiUrls.firstStep, body: request.toJson());

    if (res.statusCode != 200) {
      throw Exception('Failed to load interactive translation');
    }

    final json = jsonDecode(utf8.decode(res.bodyBytes).toString());
    return ITResponseModel.fromJson(json);
  }

  static Future<Result<ITResponseModel>> _getResult(
    ITRequestModel request,
    Future<ITResponseModel> future,
  ) async {
    try {
      final res = await future;
      return Result.value(res);
    } catch (e, s) {
      _cache.remove(request.hashCode.toString());
      ErrorHandler.logError(
        e: e,
        s: s,
        data: request.toJson(),
      );
      return Result.error(e);
    }
  }

  static Future<ITResponseModel>? _getCached(
    ITRequestModel request,
  ) {
    final cacheKeys = [..._cache.keys];
    for (final key in cacheKeys) {
      if (DateTime.now().difference(_cache[key]!.timestamp) >= _cacheDuration) {
        _cache.remove(key);
      }
    }
    return _cache[request.hashCode.toString()]?.response;
  }

  static void _setCached(
    ITRequestModel request,
    Future<ITResponseModel> response,
  ) {
    _cache[request.hashCode.toString()] = _ITCacheItem(
      response: response,
      timestamp: DateTime.now(),
    );
  }
}
