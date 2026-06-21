import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
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

void main() {
  const userL2 = 'es';
  final userCefr = LanguageLevelTypeEnum.b1; // storageInt 3

  int band(QuestActivityCard c, {Set<String> joined = const {}}) =>
      relevanceBand(
        c,
        userL2: userL2,
        userCefr: userCefr,
        joinedObjectiveIds: joined,
      );

  group('relevanceBand', () {
    test('joined-course objective is band 3', () {
      expect(band(_card('a', refs: ['lo1']), joined: {'lo1'}), 3);
    });

    test('level-appropriate L2 objective is band 2', () {
      expect(band(_card('b', cefr: 'A2', refs: ['x'])), 2);
    });

    test('above-level L2 objective falls to band 1', () {
      expect(band(_card('c', cefr: 'C2', refs: ['x'])), 1);
    });

    test('in-L2 with no objective is band 1', () {
      expect(band(_card('d', refs: const [])), 1);
    });

    test('a different L2 is global, band 0', () {
      expect(band(_card('e', l2: 'fr', refs: ['x'])), 0);
    });

    test('with no user L2 set, nothing is foreign (not band 0)', () {
      final b = relevanceBand(
        _card('f', l2: 'fr', refs: const []),
        userL2: null,
        userCefr: userCefr,
        joinedObjectiveIds: const {},
      );
      expect(b, isNot(0));
    });
  });

  group('pinScore', () {
    test('adds the pinged and recency boosts to the band', () {
      expect(pinScore(3, const PinSignals(pinged: true, recency: 1.0)), 3.9);
      expect(pinScore(2, const PinSignals(pinged: false, recency: 0.0)), 2.0);
    });

    test('boosts never cross a band step', () {
      final lowerBandMax = pinScore(
        2,
        const PinSignals(pinged: true, recency: 1.0),
      );
      final higherBandMin = pinScore(3, const PinSignals());
      expect(lowerBandMax, lessThan(higherBandMin));
    });
  });

  RankingResult rank(
    List<QuestActivityCard> pins,
    Map<String, PinSignals> signals, {
    int midBudget = 10,
    int maxPerDiversityKey = 2,
  }) => rankPins(
    inViewPins: pins,
    userL2: userL2,
    userCefr: userCefr,
    joinedObjectiveIds: const {},
    signals: signals,
    midBudget: midBudget,
    maxPerDiversityKey: maxPerDiversityKey,
  );

  group('rankPins', () {
    test('large pool is the joinable pins ordered by score', () {
      final pins = [_card('quiet'), _card('pinged')];
      final result = rank(pins, {
        'quiet': const PinSignals(state: ActivityPinState.joinable),
        'pinged': const PinSignals(
          state: ActivityPinState.joinable,
          pinged: true,
        ),
      });
      expect(result.largePool, ['pinged', 'quiet']);
      expect(result.midIds, isEmpty);
    });

    test('locked pins and finished activities are never promoted', () {
      final pins = [_card('done'), _card('locked'), _card('open')];
      final result = rank(pins, {
        // A finished activity is unlocked with a full progress fill.
        'done': const PinSignals(
          state: ActivityPinState.unlocked,
          completionFraction: 1.0,
        ),
        'locked': const PinSignals(state: ActivityPinState.locked),
        'open': const PinSignals(state: ActivityPinState.unlocked),
      });
      expect(result.largePool, isEmpty);
      expect(result.midIds, {'open'});
    });

    test(
      'in-course unlocked activities join the large pool, joinable first',
      () {
        final pins = [
          _card('lesson', refs: ['loJoined']), // in-course unlocked
          _card('live', refs: ['loJoined']), // joinable
        ];
        final result = rankPins(
          inViewPins: pins,
          userL2: userL2,
          userCefr: userCefr,
          joinedObjectiveIds: {'loJoined'},
          signals: {
            'lesson': const PinSignals(state: ActivityPinState.unlocked),
            'live': const PinSignals(state: ActivityPinState.joinable),
          },
        );
        expect(result.largePool, ['live', 'lesson']); // joinable featured first
        expect(result.midIds, isEmpty); // a large-pool member isn't also mid
      },
    );

    test('a finished in-course activity is not featured large', () {
      final result = rankPins(
        inViewPins: [
          _card('done', refs: ['loJoined']),
        ],
        userL2: userL2,
        userCefr: userCefr,
        joinedObjectiveIds: {'loJoined'},
        signals: {
          'done': const PinSignals(
            state: ActivityPinState.unlocked,
            completionFraction: 1.0,
          ),
        },
      );
      expect(result.largePool, isEmpty);
    });

    test(
      'a level-appropriate (not in-course) unlocked stays mid, not large',
      () {
        final result = rankPins(
          inViewPins: [
            _card('lvl', refs: ['loX']),
          ], // band 2, not joined
          userL2: userL2,
          userCefr: userCefr,
          joinedObjectiveIds: const {},
          signals: {'lvl': const PinSignals(state: ActivityPinState.unlocked)},
        );
        expect(result.largePool, isEmpty);
        expect(result.midIds, {'lvl'});
      },
    );

    test('diversity caps how many of one objective fill mid', () {
      final pins = [
        _card('a', refs: ['loX']),
        _card('b', refs: ['loX']),
        _card('c', refs: ['loX']),
      ];
      final result = rank(pins, {
        for (final p in pins) p.activityId: const PinSignals(),
      }, maxPerDiversityKey: 2);
      expect(result.midIds.length, 2);
    });

    test('mid budget bounds the mid set', () {
      final pins = [
        _card('a', refs: ['l1']),
        _card('b', refs: ['l2']),
        _card('c', refs: ['l3']),
      ];
      final result = rank(pins, {
        for (final p in pins) p.activityId: const PinSignals(),
      }, midBudget: 2);
      expect(result.midIds.length, 2);
    });
  });
}
