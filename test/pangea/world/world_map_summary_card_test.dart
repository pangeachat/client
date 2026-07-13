import 'package:flutter_test/flutter_test.dart';

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

  RoomSummaryResponse summary(Map<String, String> members) =>
      RoomSummaryResponse(membershipSummary: members, activityId: 'act-1');

  group('WorldMapSummaryExtension — participants from the preview', () {
    test('joined humans appear by localpart; the bot and invitees do not', () {
      final s = summary({
        '@ana:pangea.chat': 'join',
        bot: 'join',
        '@ben:pangea.chat': 'invite',
      });
      expect(s.largeCardParticipants(botUserId: bot), [
        (avatar: null, name: 'ana'),
      ]);
    });

    test('a thin-ref preview (no embedded plan) shows zero open slots — seats '
        'unknown, so nothing rather than phantoms', () {
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
