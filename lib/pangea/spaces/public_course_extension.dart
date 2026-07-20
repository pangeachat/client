import 'dart:convert';

import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';

extension PublicCourseExtension on Api {
  Future<PublicCoursesResponse> getPublicCourses({
    int limit = 10,
    String? since,
    String? targetLanguage,
  }) async {
    final requestUri = Uri(
      path: '/_synapse/client/unstable/org.pangea/public_courses',
      queryParameters: {
        'limit': limit.toString(),
        'since': ?since,
        ModelKey.targetLanguage: ?targetLanguage,
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
    String? targetLanguage,
  }) => getPublicCourses(
    limit: limit,
    since: since,
    targetLanguage: targetLanguage,
  );
}

class PublicCoursesResponse extends GetPublicRoomsResponse {
  final List<PublicCoursesChunk> courses;

  PublicCoursesResponse({
    required super.chunk,
    required super.nextBatch,
    required super.prevBatch,
    required super.totalRoomCountEstimate,
    required this.courses,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'chunk': courses.map((e) => e.toJson()).toList(),
    };
  }

  /// Entries without a usable course id are dropped rather than surfaced as
  /// broken cards. The catalog should never send one — a room with no plan id
  /// is not a course — but during a rollout an older homeserver still can, and
  /// one bad entry must not fail the whole page.
  @override
  PublicCoursesResponse.fromJson(super.json)
    : courses = (json['chunk'] as List)
          .map((e) => PublicCoursesChunk.tryParse(e))
          .nonNulls
          .toList(),
      super.fromJson();

  PublicCoursesResponse copyWith({
    List<PublishedRoomsChunk>? chunk,
    String? nextBatch,
    String? prevBatch,
    int? totalRoomCountEstimate,
    List<PublicCoursesChunk>? courses,
  }) {
    return PublicCoursesResponse(
      chunk: chunk ?? this.chunk,
      nextBatch: nextBatch ?? this.nextBatch,
      prevBatch: prevBatch ?? this.prevBatch,
      totalRoomCountEstimate:
          totalRoomCountEstimate ?? this.totalRoomCountEstimate,
      courses: courses ?? this.courses,
    );
  }
}

class PublicCoursesChunk {
  final PublishedRoomsChunk room;
  final String courseId;
  final String? targetLanguage;

  PublicCoursesChunk({
    required this.room,
    required this.courseId,
    this.targetLanguage,
  });

  /// Returns null when the entry carries no course id.
  static PublicCoursesChunk? tryParse(Map<String, dynamic> json) {
    final courseId = json['course_id'];
    if (courseId is! String || courseId.isEmpty) return null;
    return PublicCoursesChunk(
      room: PublishedRoomsChunk.fromJson(json),
      courseId: courseId,
      targetLanguage: json[ModelKey.targetLanguage] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'room': room.toJson(),
      'course_id': courseId,
      if (targetLanguage != null) ModelKey.targetLanguage: targetLanguage,
    };
  }
}
