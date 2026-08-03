import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/bot_activty_role_room_extension.dart';

/// The "Play with Pangea Bot" gate behind #8099: the button must track the
/// bot's LIVE seat, not the sticky pangea.bot_participant marker. The
/// regression this locks: the bot dropped out of a session mid-activity, its
/// role went unfilled, and the button stayed dead because the marker written
/// on the first click exists forever — leaving no way to bring the bot back.
void main() {
  const bot = '@bot:server';
  const human = '@human:server';

  ActivityRoleModel role(String id, String userId) =>
      ActivityRoleModel(id: id, userId: userId, role: id);

  final roles = {
    'bot-role': role('bot-role', bot),
    'human-role': role('human-role', human),
  };

  Iterable<ActivityRoleModel> assigned(String? Function(String) membershipOf) =>
      filterAssignedRoles(roles, membershipOf).values;

  group('botHoldsLiveSeat', () {
    test('a provably-left bot holds no seat — the #8099 case: its role shows '
        'unfilled, so Play with Pangea Bot must come back', () {
      expect(
        botHoldsLiveSeat(assigned((id) => id == bot ? 'leave' : 'join'), bot),
        isFalse,
      );
    });

    test('a joined bot holds its seat, so the button stays disabled while a '
        'session with the bot is live', () {
      expect(botHoldsLiveSeat(assigned((_) => 'join'), bot), isTrue);
    });

    test('an unloaded bot member event (lazy loading) keeps the seat occupied '
        '— same conservative default as the seat math (#7556)', () {
      expect(
        botHoldsLiveSeat(assigned((id) => id == bot ? null : 'join'), bot),
        isTrue,
      );
    });

    test('a re-invited bot counts as seated again — the recovery path settles '
        'as soon as the invite lands', () {
      expect(
        botHoldsLiveSeat(assigned((id) => id == bot ? 'invite' : 'join'), bot),
        isTrue,
      );
    });

    test('no role entry for the bot at all — never added — leaves the button '
        'available', () {
      expect(
        botHoldsLiveSeat(
          filterAssignedRoles({
            'human-role': role('human-role', human),
          }, (_) => 'join').values,
          bot,
        ),
        isFalse,
      );
    });

    test('a room with no role state has no bot seat', () {
      expect(botHoldsLiveSeat(const [], bot), isFalse);
    });
  });
}
