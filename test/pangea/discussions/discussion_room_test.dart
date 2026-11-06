import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/features/discussions/discussion_standing.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/courses/course_objectives/discussion_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import '../activity_session_fixtures.dart';
import '../get_test_client.dart';

/// A discussion room on the client (#9647, pangeachat/.github#700): how the
/// app knows one, where it reads the learner's own awards, how a student's
/// "I'm done" counts for them alone, where the learner stands in each
/// discussion, and which arrivals the chat shows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const me = testSessionUserId;
  const classmate = '@classmate:fakeServer.notExisting';
  const admin = '@teacher:fakeServer.notExisting';
  final ended = DateTime.utc(2026, 11, 3, 12);

  late Client client;

  setUpAll(() async {
    // A discussion room is one the bot created; the bot's name is read
    // through dotenv and a GetStorage box, which needs path_provider.
    dotenv.testLoad(fileInput: 'BOT_NAME=$testDiscussionBotId');
    final tempDir = await Directory.systemTemp.createTemp('discussion_room');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  group('recognising a discussion room', () {
    test('a room the bot created with the discussion marker', () {
      final room = discussionRoom(client);
      expect(room.isDiscussionRoom, isTrue);
      expect(room.activityMode, ActivityMode.discussion);
      expect(room.discussionActivityId, testSessionActivityId);
    });

    test('the marker from anyone but the bot is not one', () {
      final room = discussionRoom(client, creator: me);
      expect(room.isDiscussionRoom, isFalse);
      expect(room.activityMode, ActivityMode.roleplay);
      expect(room.discussionActivityId, isNull);
    });

    test('a session whose plan reads "Discussion" but has no marker is a '
        'roleplay', () {
      final room = discussionRoom(client, marked: false);
      expect(room.activityPlan?.req.mode, 'Discussion');
      expect(room.activityMode, ActivityMode.roleplay);
    });

    test('a room that is no activity session has no mode', () {
      final room = Room(
        id: '!plain:fakeServer.notExisting',
        client: client,
        membership: Membership.join,
      );
      expect(room.activityMode, isNull);
    });
  });

  group('the learner\'s own awards', () {
    test('a discussion reads them under the learner\'s seat key', () {
      final room = discussionRoom(
        client,
        seats: [discussionSeat(me), discussionSeat(classmate)],
        awarded: {
          discussionSeatKey(me): ['slug-1', 'slug-2'],
          // A classmate's answers are theirs.
          discussionSeatKey(classmate): ['slug-3'],
        },
      );
      expect(room.ownAwardKey, discussionSeatKey(me));
      expect(room.ownCompletedGoals.map((g) => g.id), ['g1', 'g2']);
      expect(room.isOwnGoalCompleted('g1', goalSlug: 'slug-1'), isTrue);
      expect(room.isOwnGoalCompleted('g3', goalSlug: 'slug-3'), isFalse);
      // The header's question is the first one not yet answered.
      expect(room.currentGoal?.id, 'g3');
      expect(room.hasCompletedOwnGoals, isFalse);
    });

    test('awards under the bare role id are nobody\'s in a discussion', () {
      final room = discussionRoom(
        client,
        seats: [discussionSeat(me)],
        awarded: {
          ActivityMode.discussionRoleId: ['slug-1'],
        },
      );
      expect(room.ownCompletedGoals, isEmpty);
    });

    test('a roleplay still reads them under its role id', () {
      final room = activitySessionRoom(
        client,
        roles: {
          'r1': ActivityRoleModel(id: 'r1', userId: me, role: 'Fan'),
          'r2': ActivityRoleModel(id: 'r2', userId: classmate, role: 'V'),
        },
        awarded: {
          'r1': ['slug-1'],
          'r2': ['slug-4'],
        },
      );
      expect(room.ownAwardKey, 'r1');
      expect(room.ownCompletedGoals.map((g) => g.id), ['g1']);
    });

    test('a learner without a seat has no awards', () {
      final room = discussionRoom(
        client,
        seats: [discussionSeat(classmate)],
        awarded: {
          discussionSeatKey(classmate): ['slug-1'],
        },
      );
      expect(room.ownAwardKey, isNull);
      expect(room.ownCompletedGoals, isEmpty);
    });
  });

  group('ending is per student', () {
    test('the room never ends as a whole, even when every seat is done', () {
      final room = discussionRoom(
        client,
        seats: [discussionSeat(me, finishedAt: ended, archivedAt: ended)],
      );
      expect(room.hasCompletedRole, isTrue);
      expect(room.isActivityFinished, isFalse);
    });

    test('a roleplay whose every seat is done has ended', () {
      final room = activitySessionRoom(
        client,
        roles: {
          'r1': ActivityRoleModel(id: 'r1', userId: me, finishedAt: ended),
          'r2': ActivityRoleModel(
            id: 'r2',
            userId: classmate,
            finishedAt: ended,
          ),
        },
      );
      expect(room.isActivityFinished, isTrue);
    });

    test('it has started once it has had a seat', () {
      expect(discussionRoom(client).isActivityStarted, isFalse);
      expect(
        discussionRoom(
          client,
          seats: [discussionSeat(classmate)],
        ).isActivityStarted,
        isTrue,
      );
    });

    test('there is no End for all', () {
      final room = discussionRoom(client, seats: [discussionSeat(me)]);
      expect(room.finishActivityForAll, throwsStateError);
    });

    test('an admin without a seat reads and writes; an ended student does '
        'not write', () {
      expect(
        discussionRoom(
          client,
          seats: [discussionSeat(classmate)],
        ).writesInActivity,
        isTrue,
      );
      expect(
        discussionRoom(
          client,
          seats: [discussionSeat(me, finishedAt: ended, archivedAt: ended)],
        ).writesInActivity,
        isFalse,
      );
      // A roleplay's seatless member does not write.
      expect(activitySessionRoom(client).writesInActivity, isFalse);
    });

    test('it counts as saved only once the learner has ended it', () {
      final open = discussionRoom(
        client,
        roomId: '!open:fakeServer.notExisting',
        activityId: 'joined-only',
        seats: [discussionSeat(me)],
        awarded: {
          discussionSeatKey(me): ['slug-1'],
        },
      );
      final done = discussionRoom(
        client,
        roomId: '!done:fakeServer.notExisting',
        activityId: 'ended',
        seats: [discussionSeat(me, finishedAt: ended, archivedAt: ended)],
      );
      client.rooms.addAll([open, done]);

      final saved = client.savedSessionsByActivity;
      expect(saved.keys, ['ended']);
      expect(saved['ended']!.single.id, done.id);
    });
  });

  group('where the learner stands', () {
    test('a seat they have not ended: joined', () {
      final room = discussionRoom(client, seats: [discussionSeat(me)]);
      client.rooms.add(room);

      final standing = client.discussionStandingFor(testSessionActivityId);
      expect(standing.joined, isTrue);
      expect(standing.answered, isFalse);
      expect(standing.room?.id, room.id);
      expect(DiscussionCard.stateOf(standing), ActivityPinState.ongoingActive);
    });

    test('a seat they have ended: answered', () {
      final room = discussionRoom(
        client,
        seats: [discussionSeat(me, finishedAt: ended, archivedAt: ended)],
      );
      client.rooms.add(room);

      final standing = client.discussionStandingFor(testSessionActivityId);
      expect(standing.joined, isFalse);
      expect(standing.answered, isTrue);
      expect(standing.room?.id, room.id);
      expect(DiscussionCard.stateOf(standing), isNull);
    });

    test('an admin joined to watch, without a seat, has no standing', () {
      client.rooms.add(
        discussionRoom(
          client,
          seats: [discussionSeat(classmate)],
          powerLevels: {me: 50, testDiscussionBotId: 100},
        ),
      );

      final standing = client.discussionStandingFor(testSessionActivityId);
      expect(standing.room, isNull);
      expect(client.discussionStandings, isEmpty);
    });

    test('a learner who left the room has no standing', () {
      client.rooms.add(
        discussionRoom(
          client,
          seats: [discussionSeat(me)],
          membership: Membership.leave,
        ),
      );
      expect(client.discussionStandings, isEmpty);
    });

    test('a roleplay session is no discussion standing', () {
      client.rooms.add(
        activitySessionRoom(
          client,
          roles: {'r1': ActivityRoleModel(id: 'r1', userId: me)},
        ),
      );
      expect(client.discussionStandings, isEmpty);
    });
  });

  group('arrivals in the chat', () {
    Event joinOf(Room room, String userId) => Event(
      type: EventTypes.RoomMember,
      content: {'membership': 'join'},
      stateKey: userId,
      senderId: userId,
      eventId: '\$join_$userId',
      originServerTs: DateTime.utc(2026, 11, 3),
      room: room,
    );

    Room room() => discussionRoom(
      client,
      seats: [discussionSeat(classmate)],
      powerLevels: {admin: 50, testDiscussionBotId: 100},
    );

    test('a student arriving shows, unfolded', () {
      final join = joinOf(room(), classmate);
      expect(join.isAnnouncedArrival, isTrue);
      expect(join.isVisibleInPangeaGui, isTrue);
      expect(join.isCollapsedState, isFalse);
    });

    test('an admin or the bot arriving does not', () {
      final r = room();
      for (final userId in [admin, testDiscussionBotId]) {
        final join = joinOf(r, userId);
        expect(join.isAnnouncedArrival, isFalse, reason: userId);
        expect(join.isVisibleInPangeaGui, isFalse, reason: userId);
      }
    });

    test('a roleplay announces no arrivals', () {
      final join = joinOf(activitySessionRoom(client), classmate);
      expect(join.isAnnouncedArrival, isFalse);
      expect(join.isVisibleInPangeaGui, isFalse);
    });
  });
}
