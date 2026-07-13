import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

QuestActivityCard _card(
  String id, {
  String l2 = 'es',
  String cefr = 'A2',
  List<String> refs = const [],
  int? roleCount,
}) => QuestActivityCard(
  activityId: id,
  title: id,
  l2: l2,
  coordinates: null,
  learningObjectiveRefs: refs,
  cefr: cefr,
  roleCount: roleCount,
);

/// A one-quest progression whose anchor (next) Mission is [anchor], built so the
/// band ranks an activity carrying [anchor] at gradient 1.0 (no stars earned).
ProgressionResolution _progressionWithAnchor(String anchor) =>
    resolveProgression(
      outlines: [
        CourseLoOutline(
          orderedLoIds: [anchor],
          activityIdsByLo: {
            anchor: const {'someActivity'},
          },
        ),
      ],
      starsByActivity: const {},
    );

void main() {
  const userL2 = 'es';
  final userCefr = LanguageLevelTypeEnum.b1; // storageInt 3

  double band(
    QuestActivityCard c, {
    ProgressionResolution progression = ProgressionResolution.empty,
  }) => relevanceBand(
    c,
    userL2: userL2,
    userCefr: userCefr,
    progression: progression,
  );

  group('relevanceBand', () {
    test('an anchor-Mission activity gets the in-quest gradient (1.0)', () {
      final p = _progressionWithAnchor('lo1');
      expect(band(_card('a', refs: ['lo1']), progression: p), 1.0);
    });

    test('a level-appropriate in-L2 objective-bearing pin is band 1.0', () {
      // No in-quest gradient (empty progression) → the level-fit floor.
      expect(band(_card('b', cefr: 'A2', refs: ['x'])), 1.0);
    });

    test('an above-level in-L2 pin falls to the 0.5 floor', () {
      expect(band(_card('c', cefr: 'C2', refs: ['x'])), 0.5);
    });

    test('an in-L2 pin with no objective is the 0.5 floor', () {
      expect(band(_card('d', refs: const [])), 0.5);
    });

    test('a different L2 is global, band 0', () {
      expect(band(_card('e', l2: 'fr', refs: ['x'])), 0);
    });

    test('an accumulating multi-quest gradient outranks the level-fit floor', () {
      // An activity carrying both quests' anchors accumulates to 2.0, above the
      // 1.0 objective-bearing level-fit floor a non-quest pin tops out at.
      final p = resolveProgression(
        outlines: [
          CourseLoOutline(
            orderedLoIds: ['q1'],
            activityIdsByLo: {
              'q1': const {'x'},
            },
          ),
          CourseLoOutline(
            orderedLoIds: ['q2'],
            activityIdsByLo: {
              'q2': const {'y'},
            },
          ),
        ],
        starsByActivity: const {},
      );
      final inQuest = band(_card('f', refs: ['q1', 'q2']), progression: p);
      final floor = band(_card('g', refs: ['other']), progression: p);
      expect(inQuest, 2.0);
      expect(floor, 1.0);
      expect(inQuest, greaterThan(floor));
    });

    test('with no user L2 set, nothing is foreign (not band 0)', () {
      final b = relevanceBand(
        _card('h', l2: 'fr', refs: const []),
        userL2: null,
        userCefr: userCefr,
        progression: ProgressionResolution.empty,
      );
      expect(b, isNot(0));
    });
  });

  group('pinScore — each term in isolation', () {
    test('joinable contributes 3', () {
      final score = pinScore(
        band: 0,
        s: const PinSignals(state: ActivityPinState.joinable),
      );
      expect(score, 3);
    });

    test('joined contributes 2 (a strong resurface bump, below joinable)', () {
      final score = pinScore(
        band: 0,
        s: const PinSignals(state: ActivityPinState.joined),
      );
      expect(score, 2);
    });

    test('joinable outranks joined (join others over resume your own)', () {
      final joinable = pinScore(
        band: 0,
        s: const PinSignals(state: ActivityPinState.joinable),
      );
      final joined = pinScore(
        band: 0,
        s: const PinSignals(state: ActivityPinState.joined),
      );
      expect(joinable, greaterThan(joined));
    });

    test('the band is added verbatim', () {
      final score = pinScore(band: 1.5, s: const PinSignals());
      expect(score, 1.5);
    });

    test('pinged contributes 0.6', () {
      final score = pinScore(band: 0, s: const PinSignals(pinged: true));
      expect(score, closeTo(0.6, 1e-9));
    });

    test('recency contributes 0.3 at full recency', () {
      final score = pinScore(band: 0, s: const PinSignals(recency: 1.0));
      expect(score, closeTo(0.3, 1e-9));
    });

    test('a finished activity subtracts 0.5', () {
      final score = pinScore(
        band: 0,
        s: const PinSignals(completionFraction: 1.0),
      );
      expect(score, closeTo(-0.5, 1e-9));
    });

    test('a partial fill does not subtract', () {
      final score = pinScore(
        band: 0,
        s: const PinSignals(completionFraction: 0.9),
      );
      expect(score, 0);
    });

    test('a dismissed activity subtracts 0.5 (#7207/#7245)', () {
      final score = pinScore(band: 0, s: const PinSignals(), isDismissed: true);
      expect(score, closeTo(-kDismissedPenalty, 1e-9));
    });
  });

  group('pinScore — multi-person first-map deprioritize (#7435)', () {
    test('a new learner\'s 3+ role available activity takes the penalty', () {
      final score = pinScore(
        band: 2,
        s: const PinSignals(),
        roleCount: 3,
        isNewLearner: true,
      );
      expect(score, closeTo(2 - kMultiPersonFirstMapPenalty, 1e-9));
    });

    test('a 2-role activity is not penalized (solo-viable with the bot)', () {
      final score = pinScore(
        band: 2,
        s: const PinSignals(),
        roleCount: 2,
        isNewLearner: true,
      );
      expect(score, closeTo(2, 1e-9));
    });

    test('a returning learner (has a prior activity) is not penalized', () {
      final score = pinScore(
        band: 2,
        s: const PinSignals(),
        roleCount: 3,
        isNewLearner: false,
      );
      expect(score, closeTo(2, 1e-9));
    });

    test('a live joinable 3+ session is never penalized (humans present)', () {
      final score = pinScore(
        band: 0,
        s: const PinSignals(state: ActivityPinState.joinable),
        roleCount: 3,
        isNewLearner: true,
      );
      expect(score, 3);
    });

    test('unknown role count (older choreo pin) is not penalized', () {
      final score = pinScore(
        band: 2,
        s: const PinSignals(),
        roleCount: null,
        isNewLearner: true,
      );
      expect(score, closeTo(2, 1e-9));
    });
  });

  group('pinScore — joinable dominates', () {
    test(
      'a joinable band-0 pin outscores a saturated, pinged, recent non-joinable',
      () {
        final joinable = pinScore(
          band: 0,
          s: const PinSignals(state: ActivityPinState.joinable),
        );
        final loaded = pinScore(
          band: kBandCeiling, // 2.0, the saturated band
          s: const PinSignals(pinged: true, recency: 1.0),
        );
        // 3.0 vs 2.0 + 0.6 + 0.3 = 2.9 — joining a live session always wins.
        expect(joinable, greaterThan(loaded));
      },
    );
  });

  RankingResult rank(
    List<QuestActivityCard> pins,
    Map<String, PinSignals> signals, {
    ProgressionResolution progression = ProgressionResolution.empty,
    int largeBudget = 3,
    int midBudget = 10,
    int smallBudget = 0,
    int trailBudget = 0,
    Set<String> progressedIds = const {},
    int maxPerDiversityKey = 2,
    bool isNewLearner = false,
    Set<String> dismissedIds = const {},
  }) => rankPins(
    inViewPins: pins,
    userL2: userL2,
    userCefr: userCefr,
    progression: progression,
    signals: signals,
    largeBudget: largeBudget,
    midBudget: midBudget,
    smallBudget: smallBudget,
    trailBudget: trailBudget,
    progressedIds: progressedIds,
    maxPerDiversityKey: maxPerDiversityKey,
    isNewLearner: isNewLearner,
    dismissedIds: dismissedIds,
  );

  group('rankPins — multi-person deprioritize for a new learner (#7435)', () {
    test('a 3+ role activity drops below a 2-role one of equal band', () {
      // Both score band 1.0 (in-L2, level-ok, objective-bearing); role count is
      // the only differentiator. For a new learner the 3-role pin is penalized
      // into the tail while the solo-viable 2-role pin takes the large card.
      final pins = [
        _card('multi', refs: ['a'], roleCount: 3),
        _card('duo', refs: ['b'], roleCount: 2),
      ];
      final result = rank(
        pins,
        {'multi': const PinSignals(), 'duo': const PinSignals()},
        largeBudget: 1,
        midBudget: 10,
        isNewLearner: true,
      );
      expect(result.largeIds, ['duo']);
      expect(result.ordered.last, 'multi');
    });

    test(
      'the same 3+ role activity is not demoted once the learner is not new',
      () {
        final pins = [
          _card('multi', refs: ['a'], roleCount: 3),
          _card('duo', refs: ['b'], roleCount: 2),
        ];
        final result = rank(
          pins,
          {'multi': const PinSignals(), 'duo': const PinSignals()},
          largeBudget: 1,
          midBudget: 10,
          // isNewLearner defaults to false — no penalty; equal band, both compete.
        );
        expect(result.ordered.toSet(), {'multi', 'duo'});
        expect(result.midIds.length + result.largeIds.length, 2);
      },
    );
  });

  group('rankPins — large/mid fill by score', () {
    test('the highest-scoring pins fill large, the next fill mid', () {
      // No live session in view, so the gate is inert and tiers fill by score.
      final pins = [
        _card('lvl', refs: ['b']), // band 1.0 → top
        _card('floorA', refs: const []), // band 0.5
        _card('floorB', refs: const []), // band 0.5
      ];
      final result = rank(
        pins,
        {
          'lvl': const PinSignals(),
          'floorA': const PinSignals(),
          'floorB': const PinSignals(),
        },
        largeBudget: 1,
        midBudget: 10,
      );
      expect(result.largeIds, ['lvl']); // top of the score
      expect(result.midIds, {'floorA', 'floorB'}); // the rest, by score
    });

    test('the large budget caps the large set; overflow drops to mid', () {
      final pins = [
        _card('a', refs: ['k1']),
        _card('b', refs: ['k2']),
        _card('c', refs: ['k3']),
      ];
      final result = rank(
        pins,
        {for (final p in pins) p.activityId: const PinSignals()},
        largeBudget: 2,
        midBudget: 10,
      );
      expect(result.largeIds.length, 2);
      expect(result.midIds.length, 1);
    });

    test('the mid budget bounds the mid set', () {
      final pins = [
        _card('a', refs: ['k1']),
        _card('b', refs: ['k2']),
        _card('c', refs: ['k3']),
      ];
      final result = rank(
        pins,
        {for (final p in pins) p.activityId: const PinSignals()},
        largeBudget: 0,
        midBudget: 2,
      );
      expect(result.largeIds, isEmpty);
      expect(result.midIds.length, 2);
    });
  });

  group('rankPins — diversity', () {
    test(
      'a per-objective cap stops one objective monopolising the featured set',
      () {
        final pins = [
          _card('a', refs: ['loX']),
          _card('b', refs: ['loX']),
          _card('c', refs: ['loX']),
        ];
        final result = rank(
          pins,
          {for (final p in pins) p.activityId: const PinSignals()},
          largeBudget: 3,
          midBudget: 10,
          maxPerDiversityKey: 2,
        );
        // Only 2 of the same-objective pins are featured (large+mid combined).
        final featured = {...result.largeIds, ...result.midIds};
        expect(featured.length, 2);
      },
    );
  });

  group('rankPins — finished is demoted, not excluded', () {
    test('a finished pin still appears, behind an unfinished peer', () {
      final pins = [
        _card('done', refs: ['k1']),
        _card('fresh', refs: ['k2']),
      ];
      final result = rank(
        pins,
        {
          'done': const PinSignals(completionFraction: 1.0), // -0.5
          'fresh': const PinSignals(), // band 0.5 floor
        },
        largeBudget: 1,
        midBudget: 10,
      );
      // Both are present; the fresher one takes the single large slot.
      expect(result.largeIds, ['fresh']);
      expect(result.midIds, contains('done')); // present, just demoted
    });

    test('a finished pin is featured when nothing better competes', () {
      final result = rank(
        [
          _card('done', refs: ['k1']),
        ],
        {'done': const PinSignals(completionFraction: 1.0)},
        largeBudget: 1,
        midBudget: 10,
      );
      // No gate excludes it — it earns the slot when it is all there is.
      expect(result.largeIds, ['done']);
    });
  });

  group('rankPins — dismissed is demoted, not excluded (#7207/#7245)', () {
    test('a dismissed pin sinks behind an otherwise-equal peer', () {
      final pins = [
        _card('xed', refs: ['k1']),
        _card('kept', refs: ['k2']),
      ];
      final result = rank(
        pins,
        {for (final p in pins) p.activityId: const PinSignals()},
        largeBudget: 1,
        midBudget: 10,
        dismissedIds: {'xed'},
      );
      expect(result.largeIds, ['kept']);
      expect(result.midIds, contains('xed')); // present, just demoted
    });

    test(
      'the weight alone cannot keep a competition-free dismissed pin out of '
      'the ranking top — that guarantee is the placement eligibility rule',
      () {
        // With nothing else in view the dismissed pin still tops the ranking:
        // by design the score demotes relatively, and placeLargeCards'
        // dismissedIds filter (covered in world_map_placement_test.dart) is
        // what keeps its card from re-appearing.
        final result = rank(
          [
            _card('xed', refs: ['k1']),
          ],
          {'xed': const PinSignals()},
          largeBudget: 1,
          midBudget: 10,
          dismissedIds: {'xed'},
        );
        expect(result.ordered, ['xed']);
      },
    );
  });

  group('rankPins — total cap N and the trail reservation', () {
    test('the on-screen cap N is large + mid + small', () {
      final pins = [_card('a'), _card('b'), _card('c'), _card('d')];
      final result = rank(
        pins,
        {for (final p in pins) p.activityId: const PinSignals()},
        largeBudget: 1,
        midBudget: 1,
        smallBudget: 1,
      );
      expect(result.ordered.length, 3); // one of four drops past N = 3
    });

    test('the trail reserves a slot for a low-ranked progressed activity', () {
      final pins = [
        _card('live'), // joinable → 3.5
        _card('recent'), // recency 1.0 → 0.8
        _card('other'), // recency 0.2 → 0.56
        _card('prog'), // plain → 0.5, but progressed
      ];
      final signals = {
        'live': const PinSignals(state: ActivityPinState.joinable),
        'recent': const PinSignals(recency: 1.0),
        'other': const PinSignals(recency: 0.2),
        'prog': const PinSignals(),
      };

      // N = 2, no trail: the top two by score.
      final noTrail = rank(pins, signals, largeBudget: 0, midBudget: 2);
      expect(noTrail.ordered, ['live', 'recent']);

      // N = 2, trail = 1 for the progressed 'prog': it is guaranteed a slot,
      // displacing the lowest-ranked non-progressed chosen ('recent'), so the
      // count stays at N.
      final withTrail = rank(
        pins,
        signals,
        largeBudget: 0,
        midBudget: 2,
        trailBudget: 1,
        progressedIds: {'prog'},
      );
      expect(withTrail.ordered.toSet(), {'live', 'prog'});
      expect(withTrail.ordered.length, 2);
    });
  });

  group('rankPins — live-session gate on the heavy tiers', () {
    test('with a live session in view, only it is heavy-eligible', () {
      final pins = [
        _card('live', refs: ['a']), // joinable
        _card('lvl', refs: ['b']), // band 1.0 — a high-relevance non-live pin
        _card('floor', refs: const []), // band 0.5
      ];
      final result = rank(
        pins,
        {
          'live': const PinSignals(state: ActivityPinState.joinable),
          'lvl': const PinSignals(),
          'floor': const PinSignals(),
        },
        largeBudget: 3,
        midBudget: 10,
      );
      // The gate is active; only the live session earns large/mid, and the
      // high-relevance non-live pins get neither (they render small).
      expect(result.heavyEligibleIds, {'live'});
      expect(result.largeIds, ['live']);
      expect(result.midIds, isEmpty);
    });

    test('a joined session also activates the gate', () {
      final pins = [
        _card('mine', refs: ['a']),
        _card('lvl', refs: ['b']),
      ];
      final result = rank(
        pins,
        {
          'mine': const PinSignals(state: ActivityPinState.joined),
          'lvl': const PinSignals(),
        },
        largeBudget: 3,
        midBudget: 10,
      );
      expect(result.heavyEligibleIds, {'mine'});
      expect(result.largeIds, ['mine']);
      expect(result.midIds, isEmpty);
    });

    test('with nothing live in view the gate is inert (null); all compete', () {
      final pins = [
        _card('a', refs: ['k1']),
        _card('b', refs: ['k2']),
      ];
      final result = rank(
        pins,
        {for (final p in pins) p.activityId: const PinSignals()},
        largeBudget: 1,
        midBudget: 10,
      );
      expect(result.heavyEligibleIds, isNull);
      expect(result.largeIds.length, 1);
      // Non-live still fills mid when nothing live gates the tier.
      expect(result.midIds.length, 1);
    });
  });
}
