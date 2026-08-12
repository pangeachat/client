import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'get_test_client.dart';

/// #8097 — the waiting room offered "Ping course participants" for a session
/// launched from the world map. Launching shares the session into EVERY eligible
/// joined course as an `m.space.child` while only the launched-from course is
/// pinned as `source_course_id` (activities.instructions.md), so `courseParent`
/// picks up a course the session was never launched from and the button both
/// showed and would have broadcast into that course's room.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const activityId = 'activity-123';
  const sessionId = '!session:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Event stateEvent(
    Room room, {
    required String type,
    required Map<String, dynamic> content,
    String stateKey = '',
  }) => Event(
    type: type,
    content: content,
    stateKey: stateKey,
    senderId: userId,
    eventId: '\$${type}_$stateKey',
    originServerTs: DateTime.utc(2026, 1, 1),
    room: room,
  );

  /// A course space that lists [childId] as an `m.space.child`, registered on
  /// the client so `pangeaSpaceParents` (which scans `client.rooms`) sees it.
  /// It carries a course plan, so `courseParent` sees it too.
  Room courseSpace(String id, {required String childId}) {
    final space = Room(id: id, client: client, membership: Membership.join);
    space.setState(
      stateEvent(
        space,
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    space.setState(
      stateEvent(
        space,
        type: PangeaEventTypes.coursePlan,
        content: CoursePlanEvent(uuid: 'quest-1', l2: 'de').toJson(),
      ),
    );
    space.setState(
      stateEvent(
        space,
        type: EventTypes.SpaceChild,
        content: {
          'via': ['fakeServer.notExisting'],
        },
        stateKey: childId,
      ),
    );
    client.rooms.add(space);
    return space;
  }

  ActivityPlanModel plan() => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'jobs',
      mode: 'Roleplay',
      objective: 'introduce yourself',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'de',
      numberOfParticipants: 2,
    ),
    title: 'Speed-Dating Interview',
    learningObjective: 'introduce yourself',
    instructions: 'i',
    vocab: const [],
    activityId: activityId,
    roles: const {},
  );

  /// An activity session room, optionally pinning the course it was launched
  /// from. No pin = launched from the world map. The plan is carried inline so
  /// `isActivitySession` resolves without hydrating through `ActivityPlanRepo`.
  Room activitySession({String? sourceCourseId}) {
    final room = Room(
      id: sessionId,
      client: client,
      membership: Membership.join,
    );
    room.setState(
      stateEvent(
        room,
        type: EventTypes.RoomCreate,
        content: {'type': '${PangeaRoomTypes.activitySession}:$activityId'},
      ),
    );
    room.setState(
      stateEvent(
        room,
        type: PangeaEventTypes.activityPlan,
        content: {
          ...plan().toJson(),
          ActivitySessionConstants.sourceCourseId: ?sourceCourseId,
        },
      ),
    );
    client.rooms.add(room);
    return room;
  }

  group('sourceCourse', () {
    test('is null for a world-launched session fanned out into a course', () {
      final session = activitySession();
      courseSpace('!fannedOut:fakeServer.notExisting', childId: sessionId);

      // The fan-out course is a real course parent — the old gate for the ping
      // button — but the session was never launched from it.
      expect(session.courseParent, isNotNull);
      expect(session.sourceCourse, isNull);
    });

    test('is the launching course for a course-launched session', () {
      const courseId = '!launchedFrom:fakeServer.notExisting';
      final session = activitySession(sourceCourseId: courseId);
      final course = courseSpace(courseId, childId: sessionId);

      expect(session.sourceCourse, course);
    });

    test('picks the pinned course, not a fan-out course parent', () {
      const courseId = '!launchedFrom:fakeServer.notExisting';
      final session = activitySession(sourceCourseId: courseId);
      // Registered first, so it is `courseParent` / `pangeaSpaceParents.first`.
      final fannedOut = courseSpace(
        '!fannedOut:fakeServer.notExisting',
        childId: sessionId,
      );
      final course = courseSpace(courseId, childId: sessionId);

      expect(session.courseParent, fannedOut);
      expect(session.sourceCourse, course);
    });

    test('is null when the pinned course is no longer a parent', () {
      final session = activitySession(
        sourceCourseId: '!leftCourse:fakeServer.notExisting',
      );
      courseSpace('!fannedOut:fakeServer.notExisting', childId: sessionId);

      expect(session.sourceCourse, isNull);
    });
  });
}
