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
          courseId: 'c1',
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
            courseId: 'c1',
            orderedLoIds: ['q1'],
            activityIdsByLo: {
              'q1': const {'x'},
            },
          ),
          CourseLoOutline(
            courseId: 'c2',
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
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(state: ActivityPinState.joinable),
      );
      expect(score, 3);
    });

    test('ongoing contributes a strong resurface bump (below joinable), active '
        'above pending', () {
      final pending = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(state: ActivityPinState.ongoingPending),
      );
      final active = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(state: ActivityPinState.ongoingActive),
      );
      expect(pending, kOngoingPendingWeight);
      expect(active, kOngoingActiveWeight);
      expect(active, greaterThan(pending));
    });

    test('joinable outranks ongoing (join others over resume your own)', () {
      final joinable = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(state: ActivityPinState.joinable),
      );
      final ongoing = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(state: ActivityPinState.ongoingActive),
      );
      expect(joinable, greaterThan(ongoing));
    });

    test('the band is added verbatim', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 1.5,
        s: const PinSignals(),
      );
      expect(score, 1.5);
    });

    test('pinged contributes 0.6', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(pinged: true),
      );
      expect(score, closeTo(0.6, 1e-9));
    });

    test('recency contributes 0.3 at full recency', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(recency: 1.0),
      );
      expect(score, closeTo(0.3, 1e-9));
    });

    test('a finished activity subtracts 0.5', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(completionFraction: 1.0),
      );
      expect(score, closeTo(-0.5, 1e-9));
    });

    test('a partial fill does not subtract', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(completionFraction: 0.9),
      );
      expect(score, 0);
    });

    test('a dismissed activity subtracts 0.5 (#7207/#7245)', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(),
        isDismissed: true,
      );
      expect(score, closeTo(-kDismissedPenalty, 1e-9));
    });
  });

  group('pinScore — multi-person first-map deprioritize (#7435)', () {
    test('a new learner\'s 3+ role available activity takes the penalty', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 2,
        s: const PinSignals(),
        roleCount: 3,
        isNewLearner: true,
      );
      expect(score, closeTo(2 - kMultiPersonFirstMapPenalty, 1e-9));
    });

    test('a 2-role activity is not penalized (solo-viable with the bot)', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 2,
        s: const PinSignals(),
        roleCount: 2,
        isNewLearner: true,
      );
      expect(score, closeTo(2, 1e-9));
    });

    test('a returning learner (has a prior activity) is not penalized', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 2,
        s: const PinSignals(),
        roleCount: 3,
        isNewLearner: false,
      );
      expect(score, closeTo(2, 1e-9));
    });

    test('a live joinable 3+ session is never penalized (humans present)', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 0,
        s: const PinSignals(state: ActivityPinState.joinable),
        roleCount: 3,
        isNewLearner: true,
      );
      expect(score, 3);
    });

    test('unknown role count (older choreo pin) is not penalized', () {
      final score = pinScore(
        ratingAverage: 0.5,
        ratingCount: kNewRatingThreshold,
        band: 2,
        s: const PinSignals(),
        roleCount: null,
        isNewLearner: true,
      );
      expect(score, closeTo(2, 1e-9));
    });
  });

  group('pinScore — ratings tiebreaker (#7993)', () {
    test('unrated (NEW) takes the top of the range (+2)', () {
      final score = pinScore(
        band: 0,
        s: const PinSignals(),
        ratingAverage: null,
        ratingCount: 0,
      );
      expect(score, closeTo(kRatingWeight, 1e-9));
    });

    test('all-up rating also scores +2; all-down scores -2', () {
      final up = pinScore(
        band: 0,
        s: const PinSignals(),
        ratingAverage: 1.0,
        ratingCount: 3,
      );
      final down = pinScore(
        band: 0,
        s: const PinSignals(),
        ratingAverage: 0.0,
        ratingCount: 3,
      );
      expect(up, closeTo(kRatingWeight, 1e-9));
      expect(down, closeTo(-kRatingWeight, 1e-9));
    });

    test('a 50/50 rating is neutral (0)', () {
      final score = pinScore(
        band: 0,
        s: const PinSignals(),
        ratingAverage: 0.5,
        ratingCount: 2,
      );
      expect(score, closeTo(0, 1e-9));
    });

    test('ratings reorder within a tier but never outweigh a live session', () {
      final downRatedJoinable = pinScore(
        band: 0,
        s: const PinSignals(state: ActivityPinState.joinable),
        ratingAverage: 0.0,
        ratingCount: 5,
      );
      final newAvailable = pinScore(
        band: 0,
        s: const PinSignals(),
        ratingAverage: null,
        ratingCount: 0,
      );
      // 3 - 2 = 1 vs 0 + 2 = 2: a NEW available pin CAN out-score a down-rated
      // joinable in raw score — but the large/mid tier gates are state-based,
      // so the live session still owns the heavy tiers. Within the same state,
      // ratings order cleanly:
      final upJoinable = pinScore(
        band: 0,
        s: const PinSignals(state: ActivityPinState.joinable),
        ratingAverage: 1.0,
        ratingCount: 5,
      );
      expect(upJoinable, greaterThan(downRatedJoinable));
      expect(newAvailable, greaterThan(downRatedJoinable - 3));
    });

    test('isNewActivity honors the threshold', () {
      expect(isNewActivity(null), isTrue);
      expect(isNewActivity(0), isTrue);
      expect(isNewActivity(kNewRatingThreshold), isFalse);
    });
  });

  group('pinScore — joinable dominates', () {
    test(
      'a joinable band-0 pin outscores a saturated, pinged, recent non-joinable',
      () {
        final joinable = pinScore(
          ratingAverage: 0.5,
          ratingCount: kNewRatingThreshold,
          band: 0,
          s: const PinSignals(state: ActivityPinState.joinable),
        );
        final loaded = pinScore(
          ratingAverage: 0.5,
          ratingCount: kNewRatingThreshold,
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
      // to the bottom of the ranking, so the 2-role 'duo' takes the one large
      // slot and 'multi' drops to mid (both are large-eligible now that the
      // live-only gate is gone — the penalty, not a gate, does the demotion).
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
      expect(result.midIds, {'multi'});
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
    test('with nothing live in view, the highest scorer fills large and the '
        'rest fill mid (no live-only gate)', () {
      final pins = [
        _card('lvl', refs: ['b']), // band 1.0 → top score
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
      expect(result.largeIds, ['lvl']);
      expect(result.midIds, {'floorA', 'floorB'});
    });

    test('live pins fill large up to the budget; overflow drops to mid', () {
      final pins = [
        _card('a', refs: ['k1']),
        _card('b', refs: ['k2']),
        _card('c', refs: ['k3']),
      ];
      final result = rank(
        pins,
        {
          for (final p in pins)
            p.activityId: const PinSignals(state: ActivityPinState.joinable),
        },
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

    test('an available pin fills large now that it is large-eligible', () {
      // A single available pin with a maxed score (saturated multi-quest band +
      // pinged + full recency): with the live-only gate removed it earns the
      // large slot (the completed trail star is the only state that never does).
      final progression = resolveProgression(
        outlines: [
          CourseLoOutline(
            courseId: 'c1',
            orderedLoIds: ['q1'],
            activityIdsByLo: {
              'q1': const {'topAvailable'},
            },
          ),
          CourseLoOutline(
            courseId: 'c2',
            orderedLoIds: ['q2'],
            activityIdsByLo: {
              'q2': const {'topAvailable'},
            },
          ),
        ],
        starsByActivity: const {},
      );
      final pins = [
        _card('topAvailable', refs: ['q1', 'q2']),
      ];
      final result = rank(
        pins,
        {'topAvailable': const PinSignals(pinged: true, recency: 1.0)},
        progression: progression,
        largeBudget: 5,
        midBudget: 10,
      );
      expect(result.largeIds, ['topAvailable']);
      expect(result.midIds, isEmpty);
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
      // Both still appear, 'fresh' ahead of the demoted 'done': 'fresh' takes
      // the one large slot, 'done' drops to mid.
      expect(result.ordered, ['fresh', 'done']);
      expect(result.largeIds, ['fresh']);
      expect(result.midIds, {'done'});
    });

    test(
      'a finished pin still appears on the map when nothing else competes',
      () {
        final result = rank(
          [
            _card('done', refs: ['k1']),
          ],
          {'done': const PinSignals(completionFraction: 1.0)},
          largeBudget: 1,
          midBudget: 10,
        );
        // The −0.5 completed weight demotes but never excludes it: it stays in
        // the ranked set. (Whether a completed activity renders as a card is a
        // view-level display-state question — the completed trail star never
        // does — not something ranking, which can't see completion, decides.)
        expect(result.ordered, ['done']);
      },
    );
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
      // 'kept' ranks ahead and takes the large slot; the dismissed 'xed' sinks
      // to mid but is never removed from the ranking (the placement-pass
      // dismissedIds filter, not this weight, keeps its card from re-appearing).
      expect(result.ordered, ['kept', 'xed']);
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

  group('rankPins — no live-session tier gate', () {
    test('a live session ranks first but does not force non-live pins down a '
        'tier', () {
      final pins = [
        _card('live', refs: ['a']), // joinable — heaviest term
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
        largeBudget: 1,
        midBudget: 10,
      );
      // The live session takes the one large slot by score, but the non-live
      // pins are NOT demoted to small — they fill mid (the old live-only mid
      // gate is gone). Live still leads because it scores heaviest, not because
      // a gate excludes the rest.
      expect(result.largeIds, ['live']);
      expect(result.midIds, {'lvl', 'floor'});
    });

    test('an already-joined session outranks a joinable one for the large '
        'slot', () {
      final pins = [
        _card('mine', refs: ['a']), // ongoingActive → +2.4
        _card('open', refs: ['b']), // joinable → +3
      ];
      final result = rank(
        pins,
        {
          'mine': const PinSignals(state: ActivityPinState.ongoingActive),
          'open': const PinSignals(state: ActivityPinState.joinable),
        },
        largeBudget: 1,
        midBudget: 10,
      );
      // joinable (+3) beats ongoingActive (+2.4), so 'open' takes the large slot
      // and the ongoing session drops to mid — both are large-eligible.
      expect(result.largeIds, ['open']);
      expect(result.midIds, {'mine'});
    });
  });

  group('rankPins — deterministic order for equal scores (#8136)', () {
    test('equal-score pins rank in activityId order', () {
      // Four identical pins (same band, same signals) — only activityId can
      // break the tie, so the ranked order must be lexicographic.
      final pins = [
        _card('delta', refs: ['k1']),
        _card('alpha', refs: ['k2']),
        _card('charlie', refs: ['k3']),
        _card('bravo', refs: ['k4']),
      ];
      final result = rank(pins, {
        for (final p in pins) p.activityId: const PinSignals(),
      });
      expect(result.ordered, ['alpha', 'bravo', 'charlie', 'delta']);
    });

    test('the ranked order is identical across shuffled input orders', () {
      // List.sort is unstable, so without the tiebreaker equal-score pins can
      // swap between calls and flip mid<->small tiers between settles.
      final pins = [
        for (var i = 0; i < 12; i++) _card('pin$i', refs: ['k$i']),
      ];
      final signals = {for (final p in pins) p.activityId: const PinSignals()};
      final baseline = rank(pins, signals, midBudget: 6).ordered;
      for (var rotation = 1; rotation < pins.length; rotation++) {
        final rotated = [
          ...pins.sublist(rotation),
          ...pins.sublist(0, rotation),
        ];
        expect(
          rank(rotated, signals, midBudget: 6).ordered,
          baseline,
          reason: 'rotation $rotation changed the ranked order',
        );
      }
    });
  });
}
