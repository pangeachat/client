import 'dart:convert';

import 'package:http/http.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

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
    final response = await httpClient.send(request);
    if (response.statusCode != 200) {
      // This call bypasses `Requests` (Synapse endpoint, Matrix SDK client and
      // token), so it raises the typed failure itself rather than throwing the
      // response — see repos-and-error-handling.instructions.md.
      throw PangeaHttpException.fromResponse(
        await Response.fromStream(response),
      );
    }
  }
}
