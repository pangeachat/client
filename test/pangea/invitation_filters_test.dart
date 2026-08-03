import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'get_test_client.dart';

/// #8097 — the invite page offered "in this course" to activity sessions
/// launched from the world map. Launching a session shares it into EVERY
/// eligible joined course as an `m.space.child`, while only the launched-from
/// course is pinned as `source_course_id` (activities.instructions.md), so a
/// world-launched session collects course parents it was never "in" and the
/// filter appeared — and was auto-selected — for someone not in a course at all.
///
/// Same issue: an activity session's start page already lists every
/// participant by role, so the invite page's roster filter is redundant there.
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
    originServerTs: DateTime.now(),
    room: room,
  );

  /// A course space that lists [childId] as an `m.space.child`, registered on
  /// the client so `pangeaSpaceParents` (which scans `client.rooms`) sees it.
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

  group('invitationCourseSpace', () {
    test('is null for a world-launched session fanned out into a course', () {
      final session = activitySession();
      courseSpace('!fannedOut:fakeServer.notExisting', childId: sessionId);

      expect(session.pangeaSpaceParents, isNotEmpty);
      expect(session.invitationCourseSpace, isNull);
    });

    test('is the launching course for a course-launched session', () {
      const courseId = '!launchedFrom:fakeServer.notExisting';
      final session = activitySession(sourceCourseId: courseId);
      final course = courseSpace(courseId, childId: sessionId);

      expect(session.invitationCourseSpace, course);
    });

    test(
      'ignores fan-out courses and picks the pinned one when both are parents',
      () {
        const courseId = '!launchedFrom:fakeServer.notExisting';
        final session = activitySession(sourceCourseId: courseId);
        // Registered first, so it is `pangeaSpaceParents.first`.
        courseSpace('!fannedOut:fakeServer.notExisting', childId: sessionId);
        final course = courseSpace(courseId, childId: sessionId);

        expect(session.pangeaSpaceParents, hasLength(2));
        expect(session.invitationCourseSpace, course);
      },
    );

    test('is null when the pinned course is no longer a parent', () {
      final session = activitySession(
        sourceCourseId: '!leftCourse:fakeServer.notExisting',
      );
      courseSpace('!fannedOut:fakeServer.notExisting', childId: sessionId);

      expect(session.invitationCourseSpace, isNull);
    });

    test('is the first space parent for a non-session room', () {
      const chatId = '!chat:fakeServer.notExisting';
      final chat = Room(
        id: chatId,
        client: client,
        membership: Membership.join,
      );
      client.rooms.add(chat);
      final course = courseSpace(
        '!course:fakeServer.notExisting',
        childId: chatId,
      );

      expect(chat.isActivitySession, isFalse);
      expect(chat.invitationCourseSpace, course);
    });

    test('is null for a room with no space parents', () {
      final chat = Room(
        id: '!orphan:fakeServer.notExisting',
        client: client,
        membership: Membership.join,
      );
      client.rooms.add(chat);

      expect(chat.invitationCourseSpace, isNull);
    });
  });

  group('showInvitationParticipantsFilter', () {
    test('is false for an activity session', () {
      expect(activitySession().showInvitationParticipantsFilter, isFalse);
    });

    test('is true for a regular chat', () {
      final chat = Room(
        id: '!chat:fakeServer.notExisting',
        client: client,
        membership: Membership.join,
      );
      expect(chat.showInvitationParticipantsFilter, isTrue);
    });
  });
}
