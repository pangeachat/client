import 'dart:convert';

import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

extension PublicCourseExtension on Api {
  Future<PublicCoursesResponse> getPublicCourses({
    int limit = 10,
    String? since,
  }) async {
    final requestUri = Uri(
      path: '/_synapse/client/unstable/org.pangea/public_courses',
      queryParameters: {
        'limit': limit.toString(),
        'since': since,
      },
    );
    final request = Request('GET', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    final responseString = utf8.decode(responseBody);
    if (response.statusCode != 200) {
      throw Exception(
        'HTTP error response: statusCode=${response.statusCode}, body=$responseString',
      );
    }
    final json = jsonDecode(responseString);
    return PublicCoursesResponse.fromJson(json);
  }
}

extension PublicCoursesRequest on Client {
  Future<PublicCoursesResponse> requestPublicCourses({
    int limit = 10,
    String? since,
  }) =>
      getPublicCourses(
        limit: limit,
        since: since,
      );
}

class PublicCoursesResponse extends GetPublicRoomsResponse {
  PublicCoursesResponse({
    required super.chunk,
    required super.nextBatch,
    required super.prevBatch,
    required super.totalRoomCountEstimate,
  });

  @override
  PublicCoursesResponse.fromJson(super.json) : super.fromJson();
}
