import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// One user report, as the Synapse module records it.
///
/// [reportId] is generated once per report and reused on every retry: the
/// module stores the report under `report:<reportId>` and ignores a repeat, so
/// a retry after a lost response can never record the same report twice.
class ReportSubmission {
  final String reportId;
  final String roomId;

  /// The revision the reporter sees — the latest `m.replace` when the message
  /// was edited — so the module snapshots the text that was on screen.
  final String eventId;
  final String reason;

  const ReportSubmission({
    required this.reportId,
    required this.roomId,
    required this.eventId,
    required this.reason,
  });

  factory ReportSubmission.fromJson(Map<String, dynamic> json) =>
      ReportSubmission(
        reportId: json['report_id'] as String,
        roomId: json['room_id'] as String,
        eventId: json['event_id'] as String,
        reason: json['reason'] as String,
      );

  /// The same report as a fresh submission under [reportId].
  ReportSubmission withReportId(String reportId) => ReportSubmission(
    reportId: reportId,
    roomId: roomId,
    eventId: eventId,
    reason: reason,
  );

  Map<String, String> toJson() => {
    'report_id': reportId,
    'room_id': roomId,
    'event_id': eventId,
    'reason': reason,
  };
}

extension ReportEventApiExtension on Api {
  /// Records [report] with the module (`POST /_synapse/client/pangea/v1/report`),
  /// which snapshots the message for the course admins' Safety page.
  ///
  /// Returns the module's `incident_id`. Throws [PangeaHttpException] on any
  /// non-200: 404 for an unknown event, 403 when the event is not in that room
  /// or not visible to the reporter. Safe to call again with the same
  /// [ReportSubmission] — the module is idempotent on `report_id`.
  ///
  /// Throws [TimeoutException] when no answer arrives within [timeout]. The
  /// SDK client bounds only a stalled response body, not the wait for its
  /// headers, and the reporter is held on a progress dialog meanwhile; a
  /// request that lands after the timeout is harmless, because the retry
  /// carries the same `report_id`.
  Future<String> captureReport(
    ReportSubmission report, {
    Duration timeout = const Duration(seconds: 30),
  }) => _captureReport(report).timeout(timeout);

  Future<String> _captureReport(ReportSubmission report) async {
    final requestUri = Uri(path: '_synapse/client/pangea/v1/report');
    final request = Request('POST', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    request.bodyBytes = utf8.encode(jsonEncode(report.toJson()));

    // Every failure below leaves as a typed error that carries no response
    // text: whatever the server sent back can echo the reason, and these
    // errors are logged and reported to Sentry.
    final Response response;
    try {
      response = await Response.fromStream(await httpClient.send(request));
    } on ClientException {
      // Kept a ClientException so the error handler still treats it as "no
      // response" (warning, once per session), but with a message of our own.
      throw ClientException('report request got no response', request.url);
    } catch (e) {
      throw ReportCaptureException('transport failed (${e.runtimeType})');
    }

    // Decoded here, never through `response.body`: that getter picks a
    // charset from the server's Content-Type and throws, quoting it, when
    // the header is malformed.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode != 200) {
      // This call bypasses `Requests` (Synapse endpoint, Matrix SDK client and
      // token), so it raises the typed failure itself rather than throwing the
      // response — see repos-and-error-handling.instructions.md. Its detail is
      // one of a fixed set of Matrix errcodes, never text from the body: an
      // errcode-shaped string can still be the reason echoed back.
      throw PangeaHttpException(
        statusCode: response.statusCode,
        method: request.method,
        path: PangeaHttpException.normalizePath(request.url),
        detail: _knownErrcodeOf(body),
        retryAfter: PangeaHttpException.retryAfterFromResponse(response),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      // Not rethrown: a FormatException quotes the source it failed on.
      throw const ReportCaptureException('200 with an unreadable body');
    }
    final incidentId = decoded is Map ? decoded['incident_id'] : null;
    if (incidentId != 'report:${report.reportId}') {
      // Anything but this report's own incident id means we cannot tell
      // whether the module recorded THIS report. Treated as a failure, so the
      // stored copy is kept and the reporter is offered a retry, which is
      // safe: the same report_id is never stored twice.
      throw const ReportCaptureException(
        '200 without this report\'s incident_id',
      );
    }
    return incidentId as String;
  }
}

/// The body's Matrix `errcode` when it is one of [_knownErrcodes], else null.
String? _knownErrcodeOf(String body) {
  try {
    final decoded = jsonDecode(body);
    final errcode = decoded is Map ? decoded['errcode'] : null;
    return _knownErrcodes.contains(errcode) ? errcode as String : null;
  } catch (_) {
    // silent-ok: an unreadable error body just has no errcode; the status is
    // still reported.
    return null;
  }
}

/// The errcodes a report request can meaningfully come back with. Only these
/// are copied into an error; any other value is dropped, because a server
/// that echoes the request can put the reason where an errcode belongs.
const _knownErrcodes = {
  'M_FORBIDDEN',
  'M_NOT_FOUND',
  'M_UNRECOGNIZED',
  'M_UNKNOWN',
  'M_BAD_JSON',
  'M_NOT_JSON',
  'M_MISSING_PARAM',
  'M_INVALID_PARAM',
  'M_LIMIT_EXCEEDED',
  'M_UNKNOWN_TOKEN',
  'M_MISSING_TOKEN',
};

/// A report request that failed in a way no HTTP status describes. Carries a
/// fixed description only — never anything the server sent back.
class ReportCaptureException implements Exception {
  final String description;

  const ReportCaptureException(this.description);

  @override
  String toString() => 'ReportCaptureException: $description';
}

/// How one attempt to record a report ended.
enum CaptureResult {
  /// The module answered 200 with this report's incident id.
  recorded,

  /// A 409: this report id is already the module's for a different reporter
  /// or event. It can never be recorded under this id, so the stored copy is
  /// dropped and the report starts again under a new id. A genuine retry
  /// never sees this: it sends the same id, event and reporter.
  conflict,

  /// Anything else. Even a refusal is kept and resent: a 404 is also what a
  /// homeserver without the module yet answers, so no other failure is taken
  /// as final.
  failed,
}

/// One attempt at recording [report]. Reports a failure to Sentry once, with
/// ids only — never the reason, which is the reporter's own words, and never
/// the response, which can echo it.
Future<CaptureResult> attemptReportCapture(
  Api api,
  ReportSubmission report,
) async {
  try {
    await api.captureReport(report);
    return CaptureResult.recorded;
  } catch (e, s) {
    await ErrorHandler.logError(
      e: e,
      s: s,
      data: {
        'report_id': report.reportId,
        'room_id': report.roomId,
        'event_id': report.eventId,
      },
    );
    return PangeaHttpException.statusCodeOf(e) == 409
        ? CaptureResult.conflict
        : CaptureResult.failed;
  }
}
