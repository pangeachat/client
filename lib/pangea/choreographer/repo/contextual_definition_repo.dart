import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart';

import 'package:fluffychat/pangea/choreographer/repo/contextual_definition_request_model.dart';
import 'package:fluffychat/pangea/choreographer/repo/contextual_definition_response_model.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import '../../common/network/requests.dart';
import '../../common/network/urls.dart';

class ContextualDefinitionRepo {
  static final Map<String, Future<ContextualDefinitionResponseModel>> _cache =
      {};

  static Future<Result<ContextualDefinitionResponseModel>> get(
    String accessToken,
    ContextualDefinitionRequestModel request,
  ) async {
    final cached = _getCached(request);
    if (cached != null) {
      try {
        return Result.value(await cached);
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

    final future = _fetch(accessToken, request);
    _setCached(request, future);
    return _getResult(request, future);
  }

  static Future<ContextualDefinitionResponseModel> _fetch(
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
      throw res;
    }

    final ContextualDefinitionResponseModel response =
        ContextualDefinitionResponseModel.fromJson(
      jsonDecode(
        utf8.decode(res.bodyBytes).toString(),
      ),
    );

    if (response.text.isEmpty) {
      ErrorHandler.logError(
        e: Exception(
          "empty text in contextual definition response",
        ),
        data: {
          "request": request.toJson(),
          "accessToken": accessToken,
        },
      );
    }

    return response;
  }

  static Future<Result<ContextualDefinitionResponseModel>> _getResult(
    ContextualDefinitionRequestModel request,
    Future<ContextualDefinitionResponseModel> future,
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

  static Future<ContextualDefinitionResponseModel>? _getCached(
    ContextualDefinitionRequestModel request,
  ) =>
      _cache[request.hashCode.toString()];

  static void _setCached(
    ContextualDefinitionRequestModel request,
    Future<ContextualDefinitionResponseModel> response,
  ) =>
      _cache[request.hashCode.toString()] = response;
}
