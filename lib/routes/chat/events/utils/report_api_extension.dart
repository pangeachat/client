import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

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
    final response = await Response.fromStream(await httpClient.send(request));
    if (response.statusCode != 200) {
      // This call bypasses `Requests` (Synapse endpoint, Matrix SDK client and
      // token), so it raises the typed failure itself rather than throwing the
      // response — see repos-and-error-handling.instructions.md. The typed
      // failure never carries the body, which here could echo the reason.
      throw PangeaHttpException.fromResponse(response);
    }

    final decoded = jsonDecode(response.body);
    final incidentId = decoded is Map ? decoded['incident_id'] : null;
    if (incidentId is! String) {
      // A 200 without the contract's incident id means we cannot tell whether
      // the module recorded this report. Treated as a failure so the reporter
      // is offered a retry, which is safe: the same report_id is never stored
      // twice.
      throw FormatException(
        'report endpoint answered 200 without an incident_id',
      );
    }
    return incidentId;
  }
}
