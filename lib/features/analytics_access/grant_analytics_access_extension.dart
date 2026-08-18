import 'dart:convert';

import 'package:http/http.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

extension GrantAnalyticsAccessExtension on Api {
  Future<void> grantInstructorAnalyticsAccess(
    String courseRoomId,
    String analyticsRoomId,
  ) async {
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
