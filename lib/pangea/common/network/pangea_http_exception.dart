import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
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

  /// How long the server asked us to wait before retrying, from its
  /// `Retry-After` header. Null when it said nothing.
  ///
  /// Only a throttle sends this, and honouring it matters more than it looks:
  /// a rejection is far cheaper for the server to produce than a success, so a
  /// client that guesses its own backoff and guesses short raises load at the
  /// exact moment it should be shedding it. That is the 2026-08-04 staging
  /// latch — a 429 returned ~100x faster than a success and turned one fetch
  /// per 5s into ~20/sec per card.
  final Duration? retryAfter;

  PangeaHttpException({
    required this.statusCode,
    required this.method,
    required this.path,
    String? detail,
    this.retryAfter,
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
      retryAfter: retryAfterFromResponse(response),
    );
  }

  /// The `Retry-After` delay, or null when absent or unparseable.
  ///
  /// Only the delta-seconds form is read. The HTTP-date form is legal but we
  /// never send it, and a client clock that disagrees with the server's would
  /// turn it into an arbitrary wait — so an unrecognised value is treated as
  /// "no advice given" and the caller falls back to its own default, rather
  /// than being handed a number that could be wildly wrong.
  static Duration? retryAfterFromResponse(http.Response response) {
    final raw = response.headers['retry-after'];
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }

  /// [retryAfter] when [error] is a throttle that carried one.
  static Duration? retryAfterOf(Object? error) =>
      error is PangeaHttpException ? error.retryAfter : null;

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
    // Headers come across too: `http.Response.bytes` defaults them to empty, so
    // omitting them silently drops `Retry-After` on this path and the caller
    // falls back to guessing — the one thing the header exists to stop.
    http.Response.bytes(
      body,
      response.statusCode,
      request: request,
      headers: response.headers,
    ),
  );

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _objectId = RegExp(r'^[0-9a-fA-F]{24}$');
  static final _numericId = RegExp(r'^\d+$');

  /// A hyphenated slug carrying at least one digit — the shape of our
  /// human-readable content ids (`sp101-m1-a`, `germ1-nyc-m13`).
  ///
  /// A digit is what separates them from the hyphenated words that are real
  /// route segments: every one the client can build (`analytics-events`,
  /// `audio-signals`, `engagement-spans`, `message-events`,
  /// `session-outcomes`, and the CMS's `quest-plans`) is letters-only, so
  /// requiring both a hyphen and a digit templates the ids without ever
  /// renaming an endpoint. Underscored (`text_to_speech`,
  /// `phonetic_transcription_v2`) and dotted (`org.matrix.msc4075.rtc`)
  /// segments cannot match at all — the character class excludes both — which
  /// is what keeps a versioned endpoint from reading as a resource.
  static final _slugId = RegExp(
    r'^(?=.*\d)[a-z0-9]+(-[a-z0-9]+)+$',
    caseSensitive: false,
  );

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
      _slugId.hasMatch(segment) ||
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

  /// Namespaces [fingerprintOf] so a Pangea HTTP failure can never collide
  /// with another hand-set fingerprint, and so the group is identifiable as
  /// this rule's rather than Sentry's.
  static const String fingerprintNamespace = 'pangea-http';

  /// Namespaces the grouping key of a named [TimeoutException], for the same
  /// reasons as [fingerprintNamespace].
  static const String timeoutFingerprintNamespace = 'pangea-timeout';

  /// The Sentry grouping key for [error]: status, method, and normalized path
  /// for a [PangeaHttpException]; the operation for a [TimeoutException] that
  /// names one (`timeoutNamed`); null for anything else, which keeps Sentry's
  /// default grouping.
  ///
  /// Sentry groups by stack trace, and every [PangeaHttpException] is raised
  /// through the same frame in `Requests`, so grouping collapsed every failure
  /// on every endpoint into one catch-all issue regardless of status or
  /// meaning: CLIENT-DWD held a routine 404 for a removed activity, a 401
  /// token refresh, and a 5xx backend regression under one status, one
  /// assignee, and one ignore switch (#8469). [toString] already reads per
  /// endpoint; this makes the grouping match what the title says.
  ///
  /// [detail] is deliberately excluded: it embeds the resource id, as in
  /// `No canonical activity found for activity_id='<uuid>'`, so fingerprinting
  /// on it would split one endpoint into an issue per resource — the thing
  /// [normalizePath] exists to prevent.
  ///
  /// A timeout needs the same treatment for the opposite reason: on the web a
  /// bare `timeout()` has no app frame at all — the stack is the timer
  /// callback — so every expired wait in the app collapsed into one issue that
  /// said nothing (CLIENT-AXX, #8889). An unnamed timeout deliberately keeps
  /// default grouping, so anything still landing there is a site that has not
  /// been named.
  static List<String>? fingerprintOf(Object? error) {
    if (error is TimeoutException) {
      final operation = error.message;
      return operation == null
          ? null
          : [timeoutFingerprintNamespace, operation];
    }
    if (error is! PangeaHttpException) return null;
    return [
      fingerprintNamespace,
      '${error.statusCode}',
      error.method,
      error.path,
    ];
  }

  /// Matrix errcodes that mean the homeserver refused what the learner typed:
  /// an unknown email on password reset, a username it will not accept, an
  /// email or username already taken. Expected, and only the learner can act
  /// on it (#8836).
  static const Set<MatrixError> _rejectedInputErrors = {
    MatrixError.M_THREEPID_NOT_FOUND,
    MatrixError.M_INVALID_USERNAME,
    MatrixError.M_USER_IN_USE,
    MatrixError.M_THREEPID_IN_USE,
  };

  /// The one severity table for a repo-layer fetch failure
  /// (repos-and-error-handling.instructions.md § Severity policy). Severity is
  /// a property of the failure, not of the author's judgment at the call site:
  /// input the homeserver refused ([_rejectedInputErrors]) is info; timeouts
  /// are transient, a request that never reached a server (offline, DNS,
  /// CORS, a blocked request — every one a [http.ClientException]) has
  /// nothing in code to fix, 401 is token lifecycle, 404/410 mean the
  /// resource is gone (a normal state), 429 is expected under load — all
  /// warnings. Everything else — malformed requests (4xx) and backend
  /// regressions (5xx) — is an error.
  static SentryLevel severityOf(Object? error) {
    if (error is TimeoutException) return SentryLevel.warning;
    if (error is http.ClientException) return SentryLevel.warning;
    if (error is MatrixException &&
        _rejectedInputErrors.contains(error.error)) {
      return SentryLevel.info;
    }
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
