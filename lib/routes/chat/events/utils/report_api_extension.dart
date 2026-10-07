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

    if (response.statusCode != 200) {
      // This call bypasses `Requests` (Synapse endpoint, Matrix SDK client and
      // token), so it raises the typed failure itself rather than throwing the
      // response — see repos-and-error-handling.instructions.md. The typed
      // failure never carries the body, only its errcode — and not the
      // body's `detail`, which the shared parser would prefer and which a
      // server can fill with anything, the reason included.
      throw PangeaHttpException(
        statusCode: response.statusCode,
        method: request.method,
        path: PangeaHttpException.normalizePath(request.url),
        detail: _errcodeOf(response.body),
        retryAfter: PangeaHttpException.retryAfterFromResponse(response),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      // Not rethrown: a FormatException quotes the source it failed on.
      throw const ReportCaptureException('200 with an unreadable body');
    }
    final incidentId = decoded is Map ? decoded['incident_id'] : null;
    if (incidentId is! String) {
      // A 200 without the contract's incident id means we cannot tell whether
      // the module recorded this report. Treated as a failure so the reporter
      // is offered a retry, which is safe: the same report_id is never stored
      // twice.
      throw const ReportCaptureException('200 without an incident_id');
    }
    return incidentId;
  }
}

/// The body's Matrix `errcode`, only when it has an errcode's shape
/// (`M_FORBIDDEN`, `ORG.PANGEA.X`): an identifier, never free text.
String? _errcodeOf(String body) {
  try {
    final decoded = jsonDecode(body);
    final errcode = decoded is Map ? decoded['errcode'] : null;
    return errcode is String && _errcodeShape.hasMatch(errcode)
        ? errcode
        : null;
  } catch (_) {
    // silent-ok: an unreadable error body just has no errcode; the status is
    // still reported.
    return null;
  }
}

final _errcodeShape = RegExp(r'^[A-Z][A-Z0-9_.]{0,63}$');

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
  /// The module answered 200 with an incident id.
  recorded,

  /// The module refused it in a way a retry cannot change: the event is
  /// unknown, not in that room, not visible to the reporter, or the request
  /// is malformed.
  rejected,

  /// Anything else — offline, a timeout, a server error, an unreadable
  /// answer. Worth trying again with the same report id.
  failed,
}

/// Statuses that a retry with the same body can never turn into a 200.
const _rejectedStatuses = {400, 403, 404, 422};

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
    return e is PangeaHttpException && _rejectedStatuses.contains(e.statusCode)
        ? CaptureResult.rejected
        : CaptureResult.failed;
  }
}
