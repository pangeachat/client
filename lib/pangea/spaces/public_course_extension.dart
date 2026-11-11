import 'dart:convert';

import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/course_itinerary.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

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
      throw PangeaHttpException.fromStreamedResponse(
        request,
        response,
        responseBody,
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

  /// Every public course in [targetLanguage], all pages read (the catalog
  /// pages by 100). The world view draws them as ships.
  Future<List<PublicCoursesChunk>> allPublicCourses(
    String targetLanguage,
  ) async {
    final courses = <PublicCoursesChunk>[];
    String? since;
    do {
      final page = await requestPublicCourses(
        limit: 100,
        since: since,
        targetLanguage: targetLanguage,
      );
      courses.addAll(page.courses);
      since = page.nextBatch;
    } while (since != null);
    return courses;
  }
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

/// The course search's one match and order, shared by the add-course list
/// and the world view so the two can't drift: a course matches when its
/// name contains [query] (case-folded); matches whose name starts with it
/// come first, then more members, then an open course before one you ask
/// to join. An empty [query] keeps every course, in the same order after
/// the first rule.
List<T> rankCoursesByName<T>(
  Iterable<T> courses,
  String query, {
  required String Function(T) name,
  required int Function(T) members,
  required String? Function(T) joinRule,
}) {
  final q = query.trim().toLowerCase();
  final matches = [
    for (final c in courses)
      if (q.isEmpty || name(c).toLowerCase().contains(q)) c,
  ];
  matches.sort((a, b) {
    if (q.isNotEmpty) {
      final aStarts = name(a).toLowerCase().startsWith(q);
      final bStarts = name(b).toLowerCase().startsWith(q);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
    }
    final byMembers = members(b) - members(a);
    if (byMembers != 0) return byMembers;
    final aRule = joinRule(a);
    final bRule = joinRule(b);
    if (aRule == JoinRules.public.name && bRule == JoinRules.knock.name) {
      return -1;
    }
    if (aRule == JoinRules.knock.name && bRule == JoinRules.public.name) {
      return 1;
    }
    return 0;
  });
  return matches;
}

class PublicCoursesChunk {
  final PublishedRoomsChunk room;
  final String courseId;
  final String? targetLanguage;

  /// The course's current `pangea.course_missions` and
  /// `pangea.course_position` state, verbatim from the catalog, so a course
  /// the learner is not in is placed by the same rule as one they are
  /// (org world-view doc). Null when the room has none, or the homeserver
  /// predates them.
  final CourseMissionsEvent? courseMissions;
  final CoursePositionEvent? coursePosition;

  /// The course's admins still in it who are not bots, as the catalog names
  /// them: a display name where the room has one, else the user id.
  final List<String> adminNames;

  /// The course's affiliated institution (`pangea.course_institution`),
  /// when the catalog carries it.
  final CourseInstitution? institution;

  PublicCoursesChunk({
    required this.room,
    required this.courseId,
    this.targetLanguage,
    this.courseMissions,
    this.coursePosition,
    this.adminNames = const [],
    this.institution,
  });

  /// Returns null when the entry carries no course id.
  static PublicCoursesChunk? tryParse(Map<String, dynamic> json) {
    final courseId = json['course_id'];
    if (courseId is! String || courseId.isEmpty) return null;
    return PublicCoursesChunk(
      room: PublishedRoomsChunk.fromJson(json),
      courseId: courseId,
      targetLanguage: json[ModelKey.targetLanguage] as String?,
      courseMissions: CourseMissionsEvent.tryParse(json['course_missions']),
      coursePosition: CoursePositionEvent.tryParse(json['course_position']),
      institution: CourseInstitution.tryParse(json['institution']),
      adminNames: [
        if (json['admins'] case final List admins)
          for (final admin in admins)
            if (admin is Map)
              if (admin['display_name'] case final String name
                  when name.isNotEmpty)
                name
              else if (admin['user_id'] case final String userId)
                userId,
      ],
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
