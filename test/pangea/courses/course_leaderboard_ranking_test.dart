import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/pangea/spaces/course_leaderboard.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import '../get_test_client.dart';

/// The one ranking behind the course page's Leaderboard section and its full
/// page (course-leaderboard.instructions.md): stars, then level, then name and
/// id; admins ranked and also listed; the bot never; invited and knocking
/// members listed but never ranked.
void main() {
  late Client client;
  late Room room;

  const botId = '@bot:example.org';

  setUpAll(() async {
    // The bot's id is resolved from the environment, which reads GetStorage
    // (path_provider-backed) and dotenv.
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp('leaderboard');
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

  AnalyticsProfileModel profile({
    required String lang,
    required int stars,
    int? level,
  }) => AnalyticsProfileModel(
    targetLanguage: lang,
    languageAnalytics: {
      lang: LanguageAnalyticsProfileEntry(level ?? 0, 0, stars: stars),
    },
  );

  test('ranks by stars, then level, then name, then id', () {
    final profiles = {
      '@amy:fakeServer.notExisting': profile(lang: 'es', stars: 8, level: 4),
      '@bob:fakeServer.notExisting': profile(lang: 'es', stars: 10, level: 2),
      '@cat:fakeServer.notExisting': profile(lang: 'es', stars: 8, level: 7),
      // Same stars and level as Amy, later by name.
      '@dan:fakeServer.notExisting': profile(lang: 'es', stars: 8, level: 4),
      '@eve:fakeServer.notExisting': profile(lang: 'es', stars: 8, level: 4),
    };
    final board = CourseLeaderboard.rank(
      [
        member('eve', name: 'Zed'),
        member('dan', name: 'amy'),
        member('cat'),
        member('bob'),
        member('amy', name: 'Amy'),
      ],
      langCode: 'es',
      profileOf: (id) => profiles[id],
    );

    expect(board.ranked.map((e) => e.user.id.split(':').first), [
      '@bob',
      '@cat',
      // Amy and dan share "amy" ignoring case, so the id decides.
      '@amy',
      '@dan',
      '@eve',
    ]);
    expect(board.ranked.map((e) => e.rank), [1, 2, 3, 4, 5]);
    expect(board.ranked.first.stars, 10);
    expect(board.ranked.first.level, 2);
    expect(board.podium.length, CourseLeaderboard.podiumSize);
    expect(board.rest.map((e) => e.rank), [4, 5]);
  });

  test('admins are ranked and also listed; the bot is nowhere', () {
    final board = CourseLeaderboard.rank(
      [
        member('teacher', powerLevel: SpaceConstants.powerLevelOfAdmin),
        member('bot', powerLevel: SpaceConstants.powerLevelOfAdmin),
        member('student'),
      ],
      langCode: 'es',
      profileOf: (_) => null,
    );

    expect(board.admins.map((u) => u.id), ['@teacher:fakeServer.notExisting']);
    expect(board.ranked.map((e) => e.user.id), [
      '@student:fakeServer.notExisting',
      '@teacher:fakeServer.notExisting',
    ]);
  });

  test('invited and knocking members are listed after, never ranked', () {
    final board = CourseLeaderboard.rank(
      [
        member('knocker', membership: Membership.knock),
        member('student'),
        member('invitee', membership: Membership.invite),
      ],
      langCode: 'es',
      profileOf: (_) => null,
    );

    expect(board.ranked.map((e) => e.user.id), [
      '@student:fakeServer.notExisting',
    ]);
    expect(board.pending.map((u) => u.id), [
      '@invitee:fakeServer.notExisting',
      '@knocker:fakeServer.notExisting',
    ]);
  });

  test('a member with no profile yet ranks last with nothing earned', () {
    final profiles = {
      '@amy:fakeServer.notExisting': profile(lang: 'es', stars: 1),
    };
    final board = CourseLeaderboard.rank(
      [member('zed'), member('amy')],
      langCode: 'es',
      profileOf: (id) => profiles[id],
    );

    expect(board.ranked.last.user.id, '@zed:fakeServer.notExisting');
    expect(board.ranked.last.stars, 0);
    expect(board.ranked.last.level, isNull);
    expect(board.ranked.last.language, 'es');
  });

  test("with no course language, each member ranks on their own target", () {
    final profiles = {
      '@amy:fakeServer.notExisting': profile(lang: 'fr', stars: 3, level: 1),
      '@bob:fakeServer.notExisting': profile(lang: 'de', stars: 5, level: 1),
    };
    final board = CourseLeaderboard.rank(
      [member('amy'), member('bob')],
      langCode: null,
      profileOf: (id) => profiles[id],
    );

    expect(board.ranked.first.user.id, '@bob:fakeServer.notExisting');
    expect(board.ranked.first.language, 'de');
    expect(board.ranked.last.language, 'fr');
  });
}
