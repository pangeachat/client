import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/spaces/course_participants.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import '../get_test_client.dart';

/// The one list behind the course page's Participants section and its full
/// page (course-participants.instructions.md).
void main() {
  late Client client;
  late Room room;

  const botId = '@bot:example.org';

  setUpAll(() async {
    // The bot's id is resolved from the environment, which reads GetStorage
    // (path_provider-backed) and dotenv.
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp(
      'course_participants',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': botId});
  });

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!course:fakeServer.notExisting', client: client);
  });

  tearDown(() async {
    await client.dispose();
  });

  User member(
    String localpart, {
    String? name,
    Membership membership = Membership.join,
    int powerLevel = 0,
  }) =>
      User(
          localpart == 'bot' ? botId : '@$localpart:fakeServer.notExisting',
          displayName: name ?? localpart,
          membership: membership.name,
          room: room,
          // The SDK reads power from room state; a User built directly reports 0,
          // so the level is set through the state it reads.
        )
        ..room.setState(
          Event(
            type: EventTypes.RoomPowerLevels,
            content: {
              'users': {
                ...?(room.getState(EventTypes.RoomPowerLevels)?.content['users']
                    as Map<String, Object?>?),
                if (powerLevel != 0)
                  (localpart == 'bot'
                          ? botId
                          : '@$localpart:fakeServer.notExisting'):
                      powerLevel,
              },
            },
            stateKey: '',
            senderId: '@test:fakeServer.notExisting',
            eventId: '\$power',
            originServerTs: DateTime.now(),
            room: room,
          ),
        );

  String localpart(User user) => user.id.split(':').first;

  test('members are by name, then id, ignoring case', () {
    final list = CourseParticipants.from([
      member('eve', name: 'Zed'),
      member('dan', name: 'amy'),
      member('bob', name: 'Bob'),
      member('amy', name: 'Amy'),
    ]);

    // Amy and dan share "amy" ignoring case, so the id decides.
    expect(list.members.map(localpart), ['@amy', '@dan', '@bob', '@eve']);
  });

  test('admins come first, in their own list', () {
    final list = CourseParticipants.from([
      member('zoe', name: 'Zoe', powerLevel: SpaceConstants.powerLevelOfAdmin),
      member('amy', name: 'Amy'),
      member('bea', name: 'Bea', powerLevel: SpaceConstants.powerLevelOfAdmin),
    ]);

    expect(list.admins.map(localpart), ['@bea', '@zoe']);
    expect(list.members.map(localpart), ['@amy']);
    expect(list.joined.map(localpart), ['@bea', '@zoe', '@amy']);
  });

  test('the bot is never listed', () {
    final list = CourseParticipants.from([
      member('bot', powerLevel: SpaceConstants.powerLevelOfAdmin),
      member('amy'),
    ]);

    expect(list.admins, isEmpty);
    expect(list.members.map(localpart), ['@amy']);
  });

  test('invited come before knocking, and neither counts as joined', () {
    final list = CourseParticipants.from([
      member('kim', name: 'Amy', membership: Membership.knock),
      member('ian', name: 'Zed', membership: Membership.invite),
      member('amy'),
    ]);

    expect(list.pending.map(localpart), ['@ian', '@kim']);
    expect(list.joined.map(localpart), ['@amy']);
  });

  test('a member who left is not listed', () {
    final list = CourseParticipants.from([
      member('amy', membership: Membership.leave),
      member('ban', membership: Membership.ban),
    ]);

    expect(list.joined, isEmpty);
    expect(list.pending, isEmpty);
  });
}
