import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The rule choosing the ONE activity the world tutorial points at: the first
/// placed activity at the lowest level, preferring an available one.
///
/// Blunt on purpose. The step teaches what an activity is, so the easiest one
/// wins and there is nothing to tune — an earlier design shimmered every
/// two-role pin and needed level matching, keyword matching and a second copy
/// string for the "nothing in view" case.
void main() {
  QuestActivityCard card(
    String id, {
    String? cefr,
    bool placed = true,
    int? roleCount = 2,
    bool starter = false,
  }) => QuestActivityCard(
    activityId: id,
    title: id,
    l2: 'es',
    cefr: cefr,
    roleCount: roleCount,
    coordinates: placed ? const [10.0, 20.0] : null,
    learningObjectiveRefs: const [],
    starter: starter,
  );

  ActivityPinState Function(QuestActivityCard) states(
    Map<String, ActivityPinState> byId,
  ) =>
      (c) => byId[c.activityId] ?? ActivityPinState.available;

  group('pickStarterActivity', () {
    test('no placed activity yields nothing — the step is skipped', () {
      expect(
        pickStarterActivity(
          candidates: [card('a', placed: false)],
          stateOf: states(const {}),
        ),
        isNull,
      );
      expect(
        pickStarterActivity(candidates: [], stateOf: states(const {})),
        isNull,
      );
    });

    test('an unplaced activity is never chosen — the camera has nowhere to '
        'go and there is no pin to light', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('unplaced', cefr: 'A1', placed: false),
          card('b'),
        ],
        stateOf: states(const {}),
      );
      expect(chosen?.activityId, 'b');
    });

    test('the lowest level wins', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('b1', cefr: 'B1'),
          card('a1', cefr: 'A1'),
          card('a2', cefr: 'A2'),
        ],
        stateOf: states(const {}),
      );
      expect(chosen?.activityId, 'a1');
    });

    test('an unknown level sorts last — unknown is not evidence of easy', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('none'),
          card('b2', cefr: 'B2'),
        ],
        stateOf: states(const {}),
      );
      expect(chosen?.activityId, 'b2');
    });

    test('available beats a lower-level live session', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('joinable', cefr: 'A1'),
          card('open', cefr: 'B2'),
        ],
        stateOf: states(const {'joinable': ActivityPinState.joinable}),
      );
      expect(chosen?.activityId, 'open');
    });

    test('state is a preference, not a filter — a map of only live sessions '
        'still gets a starter', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('live', cefr: 'B1'),
          card('done', cefr: 'A1'),
        ],
        stateOf: states(const {
          'live': ActivityPinState.ongoingActive,
          'done': ActivityPinState.inProgress,
        }),
      );
      expect(chosen?.activityId, 'done', reason: 'lowest level among the rest');
    });

    test('a completed trail star is not preferred over an available one', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('done', cefr: 'A1'),
          card('fresh', cefr: 'A1'),
        ],
        stateOf: states(const {'done': ActivityPinState.inProgress}),
      );
      expect(chosen?.activityId, 'fresh');
    });

    test('equal candidates break on input order, so the answer is stable', () {
      final list = [card('x', cefr: 'A1'), card('y', cefr: 'A1')];
      expect(
        pickStarterActivity(
          candidates: list,
          stateOf: states(const {}),
        )?.activityId,
        'x',
      );
      expect(
        pickStarterActivity(
          candidates: list.reversed.toList(),
          stateOf: states(const {}),
        )?.activityId,
        'y',
      );
    });
  });

  // Content marked as a starter is made for this step (org activities doc,
  // "Starter activities"), so it wins over the blunt level rule — which, with
  // no starter in view, still decides exactly as before (#9561).
  group('pickStarterActivity — a starter pin wins first', () {
    test('a starter beats a lower-level, available non-starter', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('easy', cefr: 'A1'),
          card('starter', cefr: 'A2', starter: true),
        ],
        stateOf: states(const {}),
      );
      expect(chosen?.activityId, 'starter');
    });

    test('a starter wins whatever its state — a live session of it still '
        'points at the right activity', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('fresh', cefr: 'A1'),
          card('starter', cefr: 'A1', starter: true),
        ],
        stateOf: states(const {'starter': ActivityPinState.joinable}),
      );
      expect(chosen?.activityId, 'starter');
    });

    test('with no starter in view the level rule decides, as before', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('b1', cefr: 'B1'),
          card('a1', cefr: 'A1'),
        ],
        stateOf: states(const {}),
      );
      expect(chosen?.activityId, 'a1');
    });

    test('the two-role gate and placement still apply to a starter', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('crowded', cefr: 'A1', roleCount: 3, starter: true),
          card('unplaced', cefr: 'A1', placed: false, starter: true),
          card('plain', cefr: 'B2'),
        ],
        stateOf: states(const {}),
      );
      expect(chosen?.activityId, 'plain');
    });

    test('among starters, state then level then input order break ties', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('live-a1', cefr: 'A1', starter: true),
          card('open-b1', cefr: 'B1', starter: true),
          card('open-a2', cefr: 'A2', starter: true),
        ],
        stateOf: states(const {'live-a1': ActivityPinState.ongoingActive}),
      );
      expect(chosen?.activityId, 'open-a2');
    });
  });

  // The spotlight hole is drawn over a pin, so it has to know how each tier
  // anchors its box to the geographic point. The bug this locks: the hole was
  // sized for a mid pin and centred on the point, so over a large card it
  // appeared below the card's tail, in open map.
  // The hard gate, and the reason the whole step exists in this shape: the bot
  // fills exactly ONE seat, so a two-role activity is the only kind a learner
  // with nobody around can start. The bug this locks: selection ignored the role
  // count and picked a 4-role activity, then told the learner to tap it — a
  // start page waiting on three humans who are not coming.
  group('pickStarterActivity — the two-role gate', () {
    test('a 3+ role activity is never chosen, even alone on the map', () {
      expect(
        pickStarterActivity(
          candidates: [card('four', cefr: 'A1', roleCount: 4)],
          stateOf: states(const {}),
        ),
        isNull,
      );
    });

    test('a one-role activity is not chosen either — nothing for the bot or a '
        'partner to do, so it teaches the wrong thing', () {
      expect(
        pickStarterActivity(
          candidates: [card('solo', cefr: 'A1', roleCount: 1)],
          stateOf: states(const {}),
        ),
        isNull,
      );
    });

    test(
      'an unknown role count is excluded — it cannot be confirmed as two',
      () {
        expect(
          pickStarterActivity(
            candidates: [card('unknown', cefr: 'A1', roleCount: null)],
            stateOf: states(const {}),
          ),
          isNull,
        );
      },
    );

    test('two roles beats a lower level and a better state', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('easy-but-crowded', cefr: 'A1', roleCount: 5),
          card('harder-but-startable', cefr: 'C1'),
        ],
        stateOf: states(const {}),
      );
      expect(chosen?.activityId, 'harder-but-startable');
    });

    test('the rest of the ladder still applies among two-role activities', () {
      final chosen = pickStarterActivity(
        candidates: [
          card('b1', cefr: 'B1'),
          card('a1-live', cefr: 'A1'),
          card('a2', cefr: 'A2'),
        ],
        stateOf: states(const {'a1-live': ActivityPinState.joinable}),
      );
      expect(chosen?.activityId, 'a2', reason: 'available, then lowest level');
    });
  });

  group('pinRectAt', () {
    const tip = Offset(100, 200);

    test('a small dot is a box centred on the point', () {
      final rect = pinRectAt(
        tip,
        tier: PinTier.small,
        state: ActivityPinState.available,
        largeTailHeight: 11,
        largeBadgeOverhang: 8,
      );
      expect(rect.center, tip);
    });

    test('a mid teardrop hangs ABOVE the point, tip on it', () {
      final rect = pinRectAt(
        tip,
        tier: PinTier.mid,
        state: ActivityPinState.available,
        largeTailHeight: 11,
        largeBadgeOverhang: 8,
      );
      expect(rect.bottom, tip.dy, reason: 'the tip is the box floor');
      expect(rect.center.dx, tip.dx);
      expect(rect.top, lessThan(tip.dy));
    });

    test('a mid inProgress star is a plain centred box, not a teardrop', () {
      final rect = pinRectAt(
        tip,
        tier: PinTier.mid,
        state: ActivityPinState.inProgress,
        largeTailHeight: 11,
        largeBadgeOverhang: 8,
      );
      expect(rect.center, tip);
    });

    test('a large card sits above the point in its own marker box', () {
      final rect = pinRectAt(
        tip,
        tier: PinTier.large,
        state: ActivityPinState.joinable,
        largeTailHeight: 11,
        largeBadgeOverhang: 8,
      );
      expect(rect.bottom, tip.dy);
      expect(rect.center.dx, tip.dx);
      if (kMapActivityCards) {
        // The activity card's box already holds its tail and focus gutter.
        expect(rect.size, PinSize.mapCardBox(standsOnStamp: true));
      } else {
        expect(
          rect.width,
          PinTier.large.dotWidth + 16,
          reason: 'overhang on both sides',
        );
        expect(
          rect.height,
          PinTier.large.dotHeight(ActivityPinState.joinable) + 11 + 8,
        );
      }
    });

    test('a large card is far bigger than a mid pin — the two are not '
        'interchangeable, which is what made the hole miss', () {
      final mid = pinRectAt(
        tip,
        tier: PinTier.mid,
        state: ActivityPinState.available,
        largeTailHeight: 11,
        largeBadgeOverhang: 8,
      );
      final large = pinRectAt(
        tip,
        tier: PinTier.large,
        state: ActivityPinState.available,
        largeTailHeight: 11,
        largeBadgeOverhang: 8,
      );
      expect(large.height, greaterThan(mid.height));
      expect(large.width, greaterThan(mid.width));
    });
  });
}
