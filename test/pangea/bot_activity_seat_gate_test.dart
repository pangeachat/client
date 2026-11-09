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
  const otherHuman = '@other:server';

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

  group('isTwoPersonBotSession', () {
    test('a learner alone with the bot: two roles, one held by the bot — no '
        'poll to start and no End for all (#8982)', () {
      expect(isTwoPersonBotSession(2, assigned((_) => 'join'), bot), isTrue);
    });

    test('two humans, no bot — polls stay available', () {
      expect(
        isTwoPersonBotSession(
          2,
          filterAssignedRoles({
            'a': role('a', human),
            'b': role('b', otherHuman),
          }, (_) => 'join').values,
          bot,
        ),
        isFalse,
      );
    });

    test('three roles with the bot in one — another human is in the session, '
        'so polls stay available', () {
      expect(
        isTwoPersonBotSession(
          3,
          filterAssignedRoles({
            'a': role('a', human),
            'b': role('b', otherHuman),
            'c': role('c', bot),
          }, (_) => 'join').values,
          bot,
        ),
        isFalse,
      );
    });

    test('the bot has provably left its seat in a two-role session — the '
        'learner is alone, and a poll is again theirs to start', () {
      expect(
        isTwoPersonBotSession(
          2,
          assigned((id) => id == bot ? 'leave' : 'join'),
          bot,
        ),
        isFalse,
      );
    });
  });

  group('botFillTime', () {
    final created = DateTime.utc(2026, 10, 27, 12);

    DateTime? fillTime({
      Duration age = const Duration(minutes: 10),
      bool botChosen = false,
      bool creatorJoined = true,
      bool botJoined = true,
      bool anyRoleFinished = false,
      int seats = 2,
      int takenSeats = 1,
    }) => botFillTime(
      created: created,
      now: created.add(age),
      botChosen: botChosen,
      creatorJoined: creatorJoined,
      botJoined: botJoined,
      anyRoleFinished: anyRoleFinished,
      seats: seats,
      takenSeats: takenSeats,
    );

    test('one open seat with the creator and the bot in: the bot joins an '
        'hour after the session was created', () {
      expect(fillTime(), created.add(botFillDelay));
      // An invited friend holds their seat, so three seats with two taken
      // still leaves the bot exactly one.
      expect(fillTime(seats: 3, takenSeats: 2), created.add(botFillDelay));
    });

    test('past the hour it still reads the hour, so the line says the bot is '
        'joining until its seat lands', () {
      expect(
        fillTime(age: const Duration(hours: 2)),
        created.add(botFillDelay),
      );
    });

    test('no countdown when the bot will not join', () {
      expect(fillTime(seats: 3), isNull, reason: 'two seats open');
      expect(fillTime(takenSeats: 2), isNull, reason: 'no seat open');
      expect(fillTime(botChosen: true), isNull, reason: 'a learner asked');
      expect(fillTime(creatorJoined: false), isNull, reason: 'creator left');
      expect(fillTime(botJoined: false), isNull, reason: 'bot not in room');
      expect(fillTime(anyRoleFinished: true), isNull, reason: 'session ending');
      expect(fillTime(age: botFillMaxAge), isNull, reason: 'a day old');
    });
  });

  group('heldSeatCount', () {
    int held({
      List<ActivityRoleModel> assignedRoles = const [],
      int invitedMembers = 0,
      bool botInvited = false,
    }) => heldSeatCount(
      assignedRoles: assignedRoles,
      invitedMembers: invitedMembers,
      botInvited: botInvited,
      botUserId: bot,
    );

    test('a role holds a seat; a member who joined without one, such as a '
        'course admin reading along, does not (#9701)', () {
      // The admins are joined but appear nowhere in the count's inputs.
      expect(held(assignedRoles: [role('human-role', human)]), 1);
    });

    test('an invite holds a seat', () {
      expect(
        held(assignedRoles: [role('human-role', human)], invitedMembers: 1),
        2,
      );
    });

    test("the bot's own role or invite is not counted", () {
      expect(held(assignedRoles: roles.values.toList()), 1);
      expect(
        held(
          assignedRoles: [role('human-role', human)],
          invitedMembers: 1,
          botInvited: true,
        ),
        1,
      );
    });
  });
}
