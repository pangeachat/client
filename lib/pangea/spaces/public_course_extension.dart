import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/course_itinerary.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

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

  /// The course Start my own opens instead of the picked quest (#9590), or
  /// null when the learner should create their own. A failed lookup is
  /// reported and also returns null, so Start my own falls back to creating
  /// rather than blocking the learner.
  Future<String?> courseToJoinInstead(
    String questId,
    String targetLanguage,
  ) async {
    try {
      final courses = await _allPublicCourses(
        targetLanguage,
      ).timeout(const Duration(seconds: 10));
      return PublicCoursesChunk.toJoinInstead(courses, questId)?.room.roomId;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'quest_id': questId, 'target_language': targetLanguage},
      );
      return null;
    }
  }

  /// [targetLanguage]'s central course (#9591), or null when it has none. A
  /// failed lookup is reported and also returns null, so the learner carries
  /// on without one and the next check tries again.
  Future<PublicCoursesChunk?> centralCourseFor(String targetLanguage) async {
    try {
      final courses = await _allPublicCourses(
        targetLanguage,
      ).timeout(const Duration(seconds: 10));
      return PublicCoursesChunk.centralOf(courses);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'target_language': targetLanguage},
      );
      return null;
    }
  }

  /// Every public course in [targetLanguage], all pages read (the catalog
  /// pages by 100). The world view draws them as ships; the central-course
  /// and join-instead lookups read the same list.
  Future<List<PublicCoursesChunk>> allPublicCourses(String targetLanguage) =>
      _allPublicCourses(targetLanguage);

  Future<List<PublicCoursesChunk>> _allPublicCourses(
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

class PublicCoursesChunk {
  final PublishedRoomsChunk room;
  final String courseId;
  final String? targetLanguage;

  /// Whether the catalog marks this as its language's central course.
  final bool central;

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

  /// The course's affiliated institution from its course-plan state, when
  /// the catalog carries it.
  final String? institution;

  PublicCoursesChunk({
    required this.room,
    required this.courseId,
    this.targetLanguage,
    this.central = false,
    this.courseMissions,
    this.coursePosition,
    this.adminNames = const [],
    this.institution,
  });

  /// The central course, else the public course on [questId] with the most
  /// members (#9590). Two central courses in one language is a setup mistake;
  /// the bigger one still wins.
  static PublicCoursesChunk? toJoinInstead(
    List<PublicCoursesChunk> courses,
    String questId,
  ) =>
      centralOf(courses) ??
      _biggestFirst(courses).firstWhereOrNull(
        (c) =>
            c.courseId == questId && c.room.joinRule == JoinRules.public.name,
      );

  static PublicCoursesChunk? centralOf(List<PublicCoursesChunk> courses) =>
      _biggestFirst(courses).firstWhereOrNull((c) => c.central);

  static List<PublicCoursesChunk> _biggestFirst(
    List<PublicCoursesChunk> courses,
  ) => courses.sortedBy<num>((c) => -c.room.numJoinedMembers);

  /// Returns null when the entry carries no course id.
  static PublicCoursesChunk? tryParse(Map<String, dynamic> json) {
    final courseId = json['course_id'];
    if (courseId is! String || courseId.isEmpty) return null;
    return PublicCoursesChunk(
      room: PublishedRoomsChunk.fromJson(json),
      courseId: courseId,
      targetLanguage: json[ModelKey.targetLanguage] as String?,
      central: json['central'] == true,
      courseMissions: CourseMissionsEvent.tryParse(json['course_missions']),
      coursePosition: CoursePositionEvent.tryParse(json['course_position']),
      institution: switch (json['institution']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => null,
      },
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
      if (central) 'central': true,
    };
  }
}
