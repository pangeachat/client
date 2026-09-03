import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_filled_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'get_test_client.dart';

/// #8735 — a coursemate's course page kept showing a session as Open after
/// its last seat was taken, because the role write that filled it happens in
/// the session room, which they never sync. The client that fills a session
/// announces it into every joined course listing the session, and that
/// announcement is the sync tick their discovery pass needs.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const otherId = '@other:fakeServer.notExisting';
  const activityId = 'activity-123';

  /// The one room id FakeMatrixApi accepts state and timeline writes for.
  const writableRoomId = '!1234:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
    FakeMatrixApi.calledEndpoints.clear();
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

  /// A space listing [childId] as an `m.space.child`, registered on the client
  /// so `pangeaSpaceParents` sees it. A [course] carries a course plan.
  Room space(
    String id, {
    required String childId,
    bool course = true,
    Membership membership = Membership.join,
  }) {
    final space = Room(id: id, client: client, membership: membership);
    space.setState(
      stateEvent(
        space,
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    if (course) {
      space.setState(
        stateEvent(
          space,
          type: PangeaEventTypes.coursePlan,
          content: CoursePlanEvent(uuid: 'quest-1', l2: 'de').toJson(),
        ),
      );
    }
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

  /// A two-seat plan, embedded in room state so the session's plan resolves
  /// without hydrating through `ActivityPlanRepo`.
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
    roles: {
      'r1': ActivityRole(id: 'r1', name: 'Interviewer', goal: null, goals: []),
      'r2': ActivityRole(id: 'r2', name: 'Candidate', goal: null, goals: []),
    },
  );

  Room session(String id, {Map<String, ActivityRoleModel> roles = const {}}) {
    final room = Room(id: id, client: client, membership: Membership.join);
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
        content: plan().toJson(),
      ),
    );
    room.setState(
      stateEvent(
        room,
        type: PangeaEventTypes.activityRole,
        content: ActivityRolesModel(roles).toJson(),
      ),
    );
    client.rooms.add(room);
    return room;
  }

  /// Room id → content, for every session-filled send the fake API recorded
  /// (bodies are kept as the JSON strings that went over the wire).
  /// Recorded even where the fake API rejects the write, so a send to a room
  /// other than [writableRoomId] still shows up here.
  Map<String, dynamic> filledSends() {
    final pattern = RegExp(
      '^/client/v3/rooms/([^/]+)/send/'
      '${RegExp.escape(PangeaEventTypes.activitySessionFilled)}/',
    );
    final sends = <String, dynamic>{};
    for (final entry in FakeMatrixApi.calledEndpoints.entries) {
      final match = pattern.firstMatch(entry.key);
      if (match == null) continue;
      sends[Uri.decodeComponent(match.group(1)!)] = jsonDecode(
        entry.value.single as String,
      );
    }
    return sends;
  }

  group('announceActivitySessionFilled', () {
    test(
      'reaches every joined course listing the session, and nothing else',
      () async {
        const sessionId = '!session:fakeServer.notExisting';
        const fannedOutCourseId = '!fannedOut:fakeServer.notExisting';
        final room = session(sessionId);
        space(writableRoomId, childId: sessionId);
        space(fannedOutCourseId, childId: sessionId);
        space(
          '!plainSpace:fakeServer.notExisting',
          childId: sessionId,
          course: false,
        );
        space(
          '!leftCourse:fakeServer.notExisting',
          childId: sessionId,
          membership: Membership.leave,
        );

        await room.announceActivitySessionFilled();

        final sends = filledSends();
        expect(
          sends.keys,
          unorderedEquals([writableRoomId, fannedOutCourseId]),
        );
        expect(sends[writableRoomId], {
          ActivitySessionConstants.activityId: activityId,
          ActivitySessionConstants.sessionRoomId: sessionId,
        });
      },
    );
  });

  group('joinActivity', () {
    const courseId = '!course:fakeServer.notExisting';

    test('a claim that leaves a seat open announces nothing', () async {
      final room = session(writableRoomId);
      space(courseId, childId: writableRoomId);

      await room.joinActivity(plan().roles['r1']!);

      expect(filledSends(), isEmpty);
    });

    test('the claim that takes the last seat announces the fill', () async {
      final room = session(
        writableRoomId,
        roles: {
          'r2': ActivityRoleModel(id: 'r2', userId: otherId, role: 'Candidate'),
        },
      );
      space(courseId, childId: writableRoomId);

      await room.joinActivity(plan().roles['r1']!);

      expect(filledSends(), {
        courseId: {
          ActivitySessionConstants.activityId: activityId,
          ActivitySessionConstants.sessionRoomId: writableRoomId,
        },
      });
    });
  });
}
