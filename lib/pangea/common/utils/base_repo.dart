import 'dart:convert';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' hide BaseResponse, BaseRequest;
import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class RepoCacheItem<TResponse extends BaseResponse> {
  final DateTime timestamp;
  final TResponse response;

  const RepoCacheItem({required this.timestamp, required this.response});

  bool isExpired(Duration cacheDuration) =>
      timestamp.isBefore(DateTime.now().subtract(cacheDuration));

  Map<String, dynamic> toJson() => {
    "timestamp": timestamp.millisecondsSinceEpoch,
    "response": response.toJson(),
  };

  factory RepoCacheItem.fromJson(
    Map<String, dynamic> json, {
    required TResponse Function(Map<String, dynamic>) responseFromJson,
  }) {
    return RepoCacheItem(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json["timestamp"]),
      response: responseFromJson(json["response"]),
    );
  }
}

abstract class BaseRepo<
  TRequest extends BaseRequest,
  TResponse extends BaseResponse
> {
  final Map<String, Future<Result<TResponse>>> _inflightCache = {};
  final GetStorage _storage;
  final Duration cacheDuration;
  final TResponse Function(Map<String, dynamic>) responseFromJson;

  late Future<bool> _storageInit;

  BaseRepo({
    required String boxName,
    required this.responseFromJson,
    required this.cacheDuration,
    required void Function(String) registerBoxName,
  }) : _storage = GetStorage(boxName) {
    _storageInit = GetStorage.init(boxName);
    registerBoxName(boxName);
  }

  Future<Result<TResponse>> get(TRequest request, String accessToken) async {
    final cached = await _getCached(request);
    if (cached != null) {
      return Result.value(cached);
    }

    final key = request.storageKey;
    final inflight = _inflightCache[key];
    if (inflight != null) {
      return inflight;
    }

    final future = _fetch(request, accessToken);
    _inflightCache[key] = future;
    final result = await future;

    final response = result.result;
    if (response != null) {
      await _setCached(request, response);
    }

    _inflightCache.remove(key);
    return result;
  }

  Future<Response> fetch(Requests req, TRequest request);

  Future<Result<TResponse>> _fetch(TRequest request, String accessToken) async {
    try {
      final Requests req = Requests(
        accessToken: accessToken,
        choreoApiKey: Environment.choreoApiKey,
      );

      final Response res = await fetch(req, request);
      if (res.statusCode >= 400) {
        throw res;
      }

      final Map<String, dynamic> json = jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      );

      return Result.value(responseFromJson(json));
    } catch (e, s) {
      Logs().w("Error: $e\n$s");
      if (e is! UnsubscribedException) {
        ErrorHandler.logError(e: e, s: s, data: request.toJson());
      }
      return Result.error(e);
    }
  }

  Future<void> _setCached(TRequest request, TResponse response) async {
    await _storageInit;
    final key = request.storageKey;
    final value = RepoCacheItem<TResponse>(
      timestamp: DateTime.now(),
      response: response,
    );
    await _storage.write(key, value.toJson());
  }

  Future<TResponse?> _getCached(TRequest request) async {
    await _storageInit;

    final key = request.storageKey;
    final entry = _storage.read(key);
    if (entry == null) return null;

    try {
      final RepoCacheItem<TResponse> value = RepoCacheItem<TResponse>.fromJson(
        entry,
        responseFromJson: responseFromJson,
      );

      if (value.isExpired(cacheDuration)) {
        await _storage.remove(key);
        return null;
      }

      return value.response;
    } catch (_) {
      await _storage.remove(key);
      return null;
    }
  }
}
