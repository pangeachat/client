import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';

/// Covers #7488: a joinable pin whose session the learner has not joined (a
/// coursemate's discovered session, or an invite) renders its large-card
/// participants and open seats from the `room_preview` summary — never from
/// local room state, which for an invite is stripped (no role assignments) and
/// reports phantom free seats. As in activity_session_join_gate_test.dart, the
/// full-plan seat arithmetic needs a heavy plan fixture and is exercised on
/// live data; these lock the cheap contracts around it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:test.pangea.chat';

  setUpAll(() async {
    // The joinable gate's presence check → BotName.byEnvironment →
    // Environment.botName touches the GetStorage('env_override') box, which
    // needs path_provider. Stub the channel to a temp dir so the box
    // initializes silently (its read returns null and botName falls back to
    // dotenv) — same pattern as activity_session_join_gate_test.dart.
    final tempDir = await Directory.systemTemp.createTemp('summary_card_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    // The presence check filters the bot by BotName.byEnvironment
    // (dotenv-backed).
    dotenv.testLoad(mergeWith: {'BOT_NAME': bot});
    // Thin refs resolve via plan hydration in production; headless tests have
    // no repo context, so pin resolution to "still hydrating".
    RoomSummaryResponse.referencePlanResolver = (_) => null;
  });

  tearDown(() {
    RoomSummaryResponse.referencePlanResolver =
        RoomSummaryResponse.defaultReferencePlanResolver;
  });

  RoomSummaryResponse summary(
    Map<String, String> members, {
    Map<String, String> roles = const {},
  }) => RoomSummaryResponse(
    membershipSummary: members,
    activityId: 'act-1',
    activityRoles: ActivityRolesModel({
      for (final e in roles.entries)
        e.key: ActivityRoleModel(id: e.key, userId: e.value),
    }),
  );

  group('WorldMapSummaryExtension — participants from the preview', () {
    test('a circle per joined role holder, including the bot when it holds a '
        'role; invitees do not appear', () {
      final s = summary(
        {'@ana:pangea.chat': 'join', bot: 'join', '@ben:pangea.chat': 'invite'},
        roles: {'r1': '@ana:pangea.chat', 'r2': bot},
      );
      expect(s.largeCardParticipantIds, ['@ana:pangea.chat', bot]);
    });

    test('the moderation bot gets no circle when it holds no role — only role '
        'holders do', () {
      final s = summary(
        {'@ana:pangea.chat': 'join', bot: 'join'},
        roles: {'r1': '@ana:pangea.chat'},
      );
      expect(s.largeCardParticipantIds, ['@ana:pangea.chat']);
    });

    test('a thin-ref preview whose plan has not hydrated shows zero open '
        'slots — seats unknown, so nothing rather than phantoms', () {
      expect(summary({'@ana:pangea.chat': 'join'}).openSlots, 0);
    });
  });

  group('DiscoveredSessionsCache.bestOpenSummary', () {
    test('picks the open session and skips a dead (memberless) one', () {
      final open = summary({'@ana:pangea.chat': 'join'});
      DiscoveredSessionsCache.instance.replaceAll({
        'act-1': {'!dead:x': summary({}), '!open:x': open},
      });
      expect(DiscoveredSessionsCache.instance.bestOpenSummary('act-1'), open);
      DiscoveredSessionsCache.instance.clear();
    });

    test('null on a cache miss', () {
      expect(DiscoveredSessionsCache.instance.bestOpenSummary('nope'), isNull);
    });
  });
}
