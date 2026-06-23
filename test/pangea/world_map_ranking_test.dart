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
}) => QuestActivityCard(
  activityId: id,
  title: id,
  l2: l2,
  coordinates: null,
  learningObjectiveRefs: refs,
  cefr: cefr,
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
    int maxPerDiversityKey = 2,
  }) => rankPins(
    inViewPins: pins,
    userL2: userL2,
    userCefr: userCefr,
    progression: progression,
    signals: signals,
    largeBudget: largeBudget,
    midBudget: midBudget,
    maxPerDiversityKey: maxPerDiversityKey,
  );

  group('rankPins — large/mid fill by score', () {
    test('the highest-scoring pins fill large, the next fill mid', () {
      final pins = [
        _card('live', refs: ['a']), // joinable → top
        _card('lvl', refs: ['b']), // band 1.0
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
      expect(result.largeIds, ['live']); // top of the score
      expect(result.midIds, {'lvl', 'floor'}); // the rest, by score
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
}
