import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/models/base_request_model.dart';

class ChoreoException implements Exception {
  final String message;
  final http.Response response;

  const ChoreoException({required this.message, required this.response});

  String get errorMessage => "${response.statusCode}: $message";
}

class Requests {
  late String? accessToken;

  /// Optional injected HTTP client. Production callers leave this null, so the
  /// package's top-level `http.post`/`http.get` are used exactly as before
  /// (behavior unchanged). Tests pass a `MockClient` to capture the outbound
  /// request — the repo's established seam (see PayloadClient).
  final http.Client? client;

  /// Optional override for the user-context injector, defaulting to
  /// [BaseRequestModel.injectUserContext]. Production leaves this null. It
  /// exists ONLY so tests can prove the routing honestly: the real injector
  /// reads `MatrixState`, which is unavailable under `flutter test`, so without
  /// this seam the `injectUserContext: true` path is indistinguishable from a
  /// verbatim copy for a bare body. A test spy makes the routing observable.
  final Map<String, dynamic> Function(Map<dynamic, dynamic>)? contextInjector;

  Requests({this.accessToken, this.client, this.contextInjector});

  Future<http.Response> post({
    required String url,
    required Map<dynamic, dynamic> body,
    bool injectUserContext = true,
  }) async {
    // I8 (finding #7): whether user context (cefr_level / user_gender) is added
    // is controlled ONLY by this param, NEVER by any feature flag. Callers that
    // hit an `extra="forbid"` choreo schema (v2 `/checkout`, `/cancel`) pass
    // `injectUserContext: false` so the body is sent verbatim; every existing
    // caller keeps the default `true`.
    final inject = contextInjector ?? BaseRequestModel.injectUserContext;
    final Map<String, dynamic> enrichedBody = injectUserContext
        ? inject(body)
        : Map<String, dynamic>.from(body);

    dynamic encoded;
    encoded = jsonEncode(enrichedBody);

    final http.Response response = await (client?.post ?? http.post)(
      Uri.parse(url),
      body: encoded,
      headers: _headers,
    );

    handleError(response, body: body);
    return response;
  }

  Future<http.Response> get({required String url}) async {
    final http.Response response = await (client?.get ?? http.get)(
      Uri.parse(url),
      headers: _headers,
    );

    handleError(response);
    return response;
  }

  void addBreadcrumb(http.Response response, {Map<dynamic, dynamic>? body}) {
    debugPrint("Error - code: ${response.statusCode}");
    debugPrint("api: ${response.request?.url}");
    debugPrint("request body: $body");
    Sentry.addBreadcrumb(
      Breadcrumb.http(
        url: response.request?.url ?? Uri(path: "not available"),
        method: response.request?.method ?? "not available",
        statusCode: response.statusCode,
      ),
    );
    Sentry.addBreadcrumb(Breadcrumb(data: {"body": body}));
  }

  void handleError(http.Response response, {Map<dynamic, dynamic>? body}) {
    if (response.statusCode < 400) return;

    String? message;
    try {
      final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
      message = responseBody['detail'];
    } catch (e) {
      Logs().w("Failed to parse error response body");
      message = null;
    }

    if (response.statusCode == 401 &&
        message == 'No active subscription found') {
      throw UnsubscribedException();
    }

    addBreadcrumb(response, body: body);
    if (message is String) {
      throw ChoreoException(message: message, response: response);
    }
    throw response;
  }

  Map<String, String> get _headers {
    final Map<String, String> headers = {
      "Content-Type": "application/json",
      "Accept": "application/json",
    };
    if (accessToken != null) {
      headers["Authorization"] = 'Bearer ${accessToken!}';
    }
    return headers;
  }
}

class UnsubscribedException implements Exception {}
