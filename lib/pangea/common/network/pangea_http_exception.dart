import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

/// A failed HTTP call, typed. Thrown by [Requests] (and [PayloadClient]) for
/// any response ≥ 400 — never the raw [http.Response], whose missing
/// `toString()` collapsed every failure across every endpoint into one Sentry
/// title, `Instance of 'Response'` (#8094).
///
/// Carries only what a Sentry title needs to be diagnosable and groupable:
/// status, method, normalized path, and the parsed `detail` field. Never the
/// response body — bodies carry learner content, and Sentry is not where that
/// belongs (repos-and-error-handling.instructions.md).
class PangeaHttpException implements Exception {
  final int statusCode;
  final String method;

  /// Request path with opaque id segments (UUIDs, CMS ObjectIds, numeric ids,
  /// Matrix identifiers) replaced by `{id}`, so titles group per endpoint
  /// rather than per resource. Query strings are dropped entirely.
  final String path;

  /// The backend's parsed failure identifier, capped at [maxDetailLength] —
  /// choreo's `detail` message, or a Synapse module's Matrix `errcode`. Only
  /// ever one of those two fields — never the body.
  final String? detail;

  static const int maxDetailLength = 200;

  PangeaHttpException({
    required this.statusCode,
    required this.method,
    required this.path,
    String? detail,
  }) : detail = detail == null || detail.length <= maxDetailLength
           ? detail
           : detail.substring(0, maxDetailLength);

  factory PangeaHttpException.fromResponse(
    http.Response response, {
    String? detail,
  }) {
    final request = response.request;
    return PangeaHttpException(
      statusCode: response.statusCode,
      method: request?.method ?? 'UNKNOWN',
      path: request == null ? 'unknown' : normalizePath(request.url),
      detail: detail ?? detailFromResponse(response),
    );
  }

  /// The typed failure for a Synapse Pangea module call. Those sites reach the
  /// homeserver through the Matrix SDK's `Api.httpClient` rather than
  /// `Requests`, so they raise the typed failure themselves.
  ///
  /// [request] is taken from the caller rather than read off
  /// [http.StreamedResponse.request], which is only as reliable as the client
  /// implementation that filled it in — the method and path are the whole
  /// point of the title, so they are not left to that. [body] is passed
  /// separately because the caller has already drained [response]'s stream.
  factory PangeaHttpException.fromStreamedResponse(
    http.BaseRequest request,
    http.StreamedResponse response,
    List<int> body,
  ) => PangeaHttpException.fromResponse(
    http.Response.bytes(body, response.statusCode, request: request),
  );

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _objectId = RegExp(r'^[0-9a-fA-F]{24}$');
  static final _numericId = RegExp(r'^\d+$');
  static const _matrixSigils = ['!', '@', r'$', '#', '+'];

  /// The path of [url] with each opaque id segment replaced by `{id}`.
  static String normalizePath(Uri url) {
    final segments = url.pathSegments
        .where((s) => s.isNotEmpty)
        .map((s) => _isOpaqueId(s) ? '{id}' : s);
    return '/${segments.join('/')}';
  }

  static bool _isOpaqueId(String segment) =>
      _uuid.hasMatch(segment) ||
      _objectId.hasMatch(segment) ||
      _numericId.hasMatch(segment) ||
      _matrixSigils.any(segment.startsWith);

  /// The HTTP status of [error] when it carries one — a [PangeaHttpException],
  /// or a raw [http.Response] from a not-yet-migrated throw site — else null.
  /// The single test callers use instead of type-testing `Response` directly.
  static int? statusCodeOf(Object? error) {
    if (error is PangeaHttpException) return error.statusCode;
    if (error is http.Response) return error.statusCode;
    return null;
  }

  /// `detail` is the choreo (FastAPI) shape; `errcode` is the Matrix shape the
  /// Synapse modules answer with. Both are short, server-generated identifiers.
  /// Matrix's sibling `error` field is deliberately never read — it is
  /// free text, which is the body rule's whole concern.
  static String? detailFromResponse(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final detail = decoded['detail'] ?? decoded['errcode'];
      return detail is String ? detail : null;
    } catch (_) {
      return null;
    }
  }

  /// The one severity table for a repo-layer fetch failure
  /// (repos-and-error-handling.instructions.md § Severity policy). Severity is
  /// a property of the failure, not of the author's judgment at the call site:
  /// timeouts are transient, 401 is token lifecycle, 404/410 mean the resource
  /// is gone (a normal state), 429 is expected under load — all warnings.
  /// Everything else — malformed requests (4xx) and backend regressions (5xx)
  /// — is an error.
  static SentryLevel severityOf(Object? error) {
    if (error is TimeoutException) return SentryLevel.warning;
    switch (statusCodeOf(error)) {
      case 401:
      case 404:
      case 410:
      case 429:
        return SentryLevel.warning;
      default:
        return SentryLevel.error;
    }
  }

  @override
  String toString() =>
      'PangeaHttpException: $statusCode $method $path'
      '${detail == null ? '' : ' — $detail'}';
}
