import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/models/base_request_model.dart';
import 'package:fluffychat/pangea/common/utils/error_response_parser.dart';

class Requests {
  late String? accessToken;

  Requests({this.accessToken});

  Future<http.Response> post({
    required String url,
    required Map<dynamic, dynamic> body,
    bool enrichBody = true,
    ErrorResponseParser? errorResponseParser,
  }) async {
    final enrichedBody = enrichBody
        ? BaseRequestModel.injectUserContext(body)
        : body;

    dynamic encoded;
    encoded = jsonEncode(enrichedBody);

    final http.Response response = await http.post(
      Uri.parse(url),
      body: encoded,
      headers: _headers,
    );

    _handleError(
      response,
      body: body,
      errorResponseParser: errorResponseParser,
    );
    return response;
  }

  Future<http.Response> get({
    required String url,
    ErrorResponseParser? errorResponseParser,
  }) async {
    final http.Response response = await http.get(
      Uri.parse(url),
      headers: _headers,
    );

    _handleError(response, errorResponseParser: errorResponseParser);
    return response;
  }

  void _addBreadcrumb(http.Response response, {Map<dynamic, dynamic>? body}) {
    Sentry.addBreadcrumb(
      Breadcrumb.http(
        url: response.request?.url ?? Uri(path: "not available"),
        method: response.request?.method ?? "not available",
        statusCode: response.statusCode,
      ),
    );
    Sentry.addBreadcrumb(Breadcrumb(data: {"body": body}));
  }

  void _handleError(
    http.Response response, {
    Map<dynamic, dynamic>? body,
    ErrorResponseParser? errorResponseParser,
  }) {
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

    _addBreadcrumb(response, body: body);
    throw errorResponseParser?.parse(response) ?? response;
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
