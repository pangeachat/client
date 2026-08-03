import 'package:flutter_test/flutter_test.dart';

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
  const bot = '@bot:test.pangea.chat';

  setUp(() {
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
        {
          '@ana:pangea.chat': 'join',
          bot: 'join',
          '@ben:pangea.chat': 'invite',
        },
        roles: {'r1': '@ana:pangea.chat', 'r2': bot},
      );
      expect(s.largeCardParticipants, [
        (avatar: null, name: 'ana', userId: '@ana:pangea.chat'),
        (avatar: null, name: 'bot', userId: bot),
      ]);
    });

    test('the moderation bot gets no circle when it holds no role — only role '
        'holders do', () {
      final s = summary(
        {'@ana:pangea.chat': 'join', bot: 'join'},
        roles: {'r1': '@ana:pangea.chat'},
      );
      expect(s.largeCardParticipants, [
        (avatar: null, name: 'ana', userId: '@ana:pangea.chat'),
      ]);
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
