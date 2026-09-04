import 'dart:convert';

import 'package:http/http.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

extension GrantAnalyticsAccessExtension on Api {
  /// Force-joins the course's instructors into the caller's own analytics room,
  /// server-side — an invite alone would leave every analytics read 403ing until
  /// the instructor accepted it, and a dashboard-only instructor never opens the
  /// app to accept.
  ///
  /// Without [instructorId] the grant is gated on the course having "require
  /// analytics access to join" on. Pass [instructorId] to gate it on that
  /// instructor's standing request instead — the server checks they are
  /// knocking on the analytics room, which is the request the learner just
  /// consented to — so the grant also works on courses where analytics is
  /// optional. Either way the server grants the course's whole instructor
  /// cohort, so co-teachers who did not personally ask are not left behind.
  Future<void> grantInstructorAnalyticsAccess(
    String courseRoomId,
    String analyticsRoomId, {
    String? instructorId,
  }) async {
    final requestUri = Uri(
      path: '_synapse/client/pangea/v1/grant_instructor_analytics_access',
    );
    final request = Request('POST', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    request.bodyBytes = utf8.encode(
      jsonEncode({
        'mx_course_id': courseRoomId,
        'mx_analytics_room_id': analyticsRoomId,
        'mx_instructor_id': ?instructorId,
      }),
    );
    final response = await Response.fromStream(await httpClient.send(request));
    if (response.statusCode != 200) {
      // This call bypasses `Requests` (Synapse endpoint, Matrix SDK client and
      // token), so it raises the typed failure itself rather than throwing the
      // response — see repos-and-error-handling.instructions.md.
      throw PangeaHttpException.fromResponse(response);
    }

    _reportGrantFailures(response, courseRoomId, analyticsRoomId);
  }

  /// The endpoint answers 200 even when it could not grant some instructors,
  /// listing each failure in `errors`. Reading only the status code turns that
  /// into silent data loss — the instructor is simply absent from this
  /// student's analytics room and nobody finds out — so the failures are
  /// reported here, which every caller passes through.
  ///
  /// Reports without throwing: the instructors that were granted still are, and
  /// making a partial success read as a total failure would change what all
  /// three call sites do.
  void _reportGrantFailures(
    Response response,
    String courseRoomId,
    String analyticsRoomId,
  ) {
    final data = {
      'course_room_id': courseRoomId,
      'analytics_room_id': analyticsRoomId,
    };

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      // Not a failed grant, but we can no longer tell a granted instructor from
      // an ungranted one — which is the silence this reporting exists to break.
      ErrorHandler.logError(
        e: 'grant_instructor_analytics_access returned an unreadable body',
        data: data,
      );
      return;
    }

    final errors = decoded is Map<String, dynamic> ? decoded['errors'] : null;
    if (errors is! List || errors.isEmpty) return;

    ErrorHandler.logError(
      e: 'grant_instructor_analytics_access returned per-instructor errors',
      data: {
        ...data,
        'failure_count': errors.length,
        // Server-side reasons only — instructor IDs stay out of Sentry.
        'grant_errors': errors
            .map((error) => error is Map ? error['error']?.toString() : null)
            .nonNulls
            .toList(),
      },
    );
  }
}
