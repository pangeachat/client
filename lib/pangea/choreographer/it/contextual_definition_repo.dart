import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/choreographer/it/contextual_definition_request_model.dart';
import 'package:fluffychat/pangea/choreographer/it/contextual_definition_response_model.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';

class ContextualDefinitionRepo {
  static final Map<String, Future<String>> _cache = {};

  static Future<Result<String>> get(
    String accessToken,
    ContextualDefinitionRequestModel request,
  ) async {
    final cached = _getCached(request);
    if (cached != null) {
      try {
        return Result.value(await cached);
      } catch (e, s) {
        _cache.remove(request.hashCode.toString());
        ErrorHandler.logError(e: e, s: s, data: request.toJson());
        return Result.error(e);
      }
    }

    final future = _fetch(accessToken, request);
    _setCached(request, future);
    return _getResult(request, future);
  }

  static Future<String> _fetch(
    String accessToken,
    ContextualDefinitionRequestModel request,
  ) async {
    final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: accessToken,
    );

    final Response res = await req.post(
      url: PApiUrls.contextualDefinition,
      body: request.toJson(),
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Contextual definition request failed with status code ${res.statusCode}",
      );
    }

    final ContextualDefinitionResponseModel response =
        ContextualDefinitionResponseModel.fromJson(
          jsonDecode(utf8.decode(res.bodyBytes).toString()),
        );

    if (response.text.isEmpty) {
      ErrorHandler.logError(
        e: Exception("empty text in contextual definition response"),
        data: {"request": request.toJson(), "accessToken": accessToken},
      );
    }

    return response.text;
  }

  static Future<Result<String>> _getResult(
    ContextualDefinitionRequestModel request,
    Future<String> future,
  ) async {
    try {
      final res = await future;
      return Result.value(res);
    } catch (e, s) {
      _cache.remove(request.hashCode.toString());
      ErrorHandler.logError(e: e, s: s, data: request.toJson());
      return Result.error(e);
    }
  }

  static Future<String>? _getCached(ContextualDefinitionRequestModel request) =>
      _cache[request.hashCode.toString()];

  static void _setCached(
    ContextualDefinitionRequestModel request,
    Future<String> response,
  ) => _cache[request.hashCode.toString()] = response;
}
