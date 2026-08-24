import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'analytics_fixtures.dart';

/// Golden tests for [ConstructUses]. These pin the observable contract that
/// the memoized / linear-merge implementation (#8416 stage 1) must keep:
/// chronological order, the 100-XP cap, capped-use derivation, category
/// adoption on merge, and JSON round-tripping.
void main() {
  List<DateTime> stamps(ConstructUses c) =>
      c.uses.map((u) => u.timeStamp).toList();

  bool isChronological(List<DateTime> ts) {
    for (var i = 1; i < ts.length; i++) {
      if (ts[i].isBefore(ts[i - 1])) return false;
    }
    return true;
  }

  group('ConstructUses ordering', () {
    test('constructor sorts uses chronologically', () {
      final shuffled = usesFor('casa', count: 6)..shuffle(Random(1));
      final c = constructUses('casa', uses: shuffled);
      expect(isChronological(stamps(c)), isTrue);
      expect(c.numTotalUses, 6);
    });

    test('addUses keeps chronological order for interleaved input', () {
      final c = constructUses('casa', uses: usesFor('casa', count: 5));
      // odd minutes interleave with the existing 0..4
      final later = [
        use(lemma: 'casa', ts: at(2).add(const Duration(seconds: 30)), xp: 1),
        use(lemma: 'casa', ts: at(-1), xp: 1),
        use(lemma: 'casa', ts: at(10), xp: 1),
      ];
      c.addUses(later);
      expect(c.numTotalUses, 8);
      expect(isChronological(stamps(c)), isTrue);
      expect(c.uses.first.timeStamp, at(-1));
      expect(c.uses.last.timeStamp, at(10));
    });

    test('addUses accepts an unsorted list', () {
      final c = constructUses('casa');
      c.addUses(usesFor('casa', count: 5)..shuffle(Random(2)));
      expect(isChronological(stamps(c)), isTrue);
    });

    test('merge keeps chronological order and totals', () {
      final a = constructUses(
        'casa',
        uses: usesFor('casa', count: 4, startMinute: 0),
      );
      final b = constructUses(
        'casa',
        uses: usesFor('casa', count: 4, startMinute: 2),
      );
      a.merge(b);
      expect(a.numTotalUses, 8);
      expect(isChronological(stamps(a)), isTrue);
      // stable for equal timestamps: 2 and 3 appear twice
      expect(stamps(a).where((t) => t == at(2)).length, 2);
    });

    test('merge is a plain concatenation — duplicates are not deduped', () {
      final a = constructUses('casa', uses: usesFor('casa', count: 3));
      final b = constructUses('casa', uses: usesFor('casa', count: 3));
      a.merge(b);
      expect(a.numTotalUses, 6);
    });

    test('property: any sequence of addUses/merge equals concat-then-sort', () {
      final rng = Random(42);
      for (var trial = 0; trial < 50; trial++) {
        final all = <OneConstructUse>[];
        final c = constructUses('x');
        final steps = 1 + rng.nextInt(6);
        for (var s = 0; s < steps; s++) {
          final chunk = List.generate(
            rng.nextInt(8),
            (_) => use(
              lemma: 'x',
              ts: at(rng.nextInt(20)),
              xp: rng.nextInt(20) - 5,
              id: 'u${all.length + s}',
            ),
          );
          all.addAll(chunk);
          if (rng.nextBool()) {
            c.addUses(chunk);
          } else {
            c.merge(constructUses('x', uses: chunk));
          }
        }
        final expected = List<OneConstructUse>.from(all)
          ..sort((a, b) => a.timeStamp.compareTo(b.timeStamp));
        expect(stamps(c), expected.map((u) => u.timeStamp).toList());
        expect(
          c.points,
          min(
            expected.fold<int>(0, (t, u) => t + u.xp),
            AnalyticsConstants.xpForFlower,
          ),
        );
      }
    });
  });

  group('ConstructUses points / cap', () {
    test('points sums xp and caps at xpForFlower', () {
      final c = constructUses(
        'casa',
        uses: usesFor('casa', count: 30, xpEach: 5),
      );
      expect(c.points, AnalyticsConstants.xpForFlower);
      final small = constructUses(
        'casa',
        uses: usesFor('casa', count: 3, xpEach: 5),
      );
      expect(small.points, 15);
    });

    test('points can go negative and are not floored', () {
      final c = constructUses(
        'casa',
        uses: [use(lemma: 'casa', ts: at(0), xp: -7)],
      );
      expect(c.points, -7);
    });

    test('points reflect uses added after construction', () {
      final c = constructUses(
        'casa',
        uses: usesFor('casa', count: 2, xpEach: 5),
      );
      expect(c.points, 10);
      c.addUses(usesFor('casa', count: 1, xpEach: 5, startMinute: 10));
      expect(c.points, 15);
      c.merge(
        constructUses(
          'casa',
          uses: usesFor('casa', count: 1, xpEach: 5, startMinute: 20),
        ),
      );
      expect(c.points, 20);
    });

    test('lemmaCategory / constructLevel thresholds', () {
      ConstructUses withXp(int xp) => constructUses(
        'w',
        uses: [use(lemma: 'w', ts: at(0), xp: xp)],
      );
      expect(withXp(0).lemmaCategory, ConstructLevelEnum.seeds);
      expect(
        withXp(AnalyticsConstants.xpForGreens - 1).lemmaCategory,
        ConstructLevelEnum.seeds,
      );
      expect(
        withXp(AnalyticsConstants.xpForGreens).lemmaCategory,
        ConstructLevelEnum.greens,
      );
      expect(
        withXp(AnalyticsConstants.xpForFlower).lemmaCategory,
        ConstructLevelEnum.flowers,
      );
      expect(withXp(500).constructLevel, ConstructLevelEnum.flowers);
    });

    test('cappedUses stops once the running total reaches the cap', () {
      // 5 xp each: uses 0..19 sum to 100; use 20 must be excluded
      final c = constructUses(
        'casa',
        uses: usesFor('casa', count: 25, xpEach: 5),
      );
      final capped = c.cappedUses;
      expect(capped.length, 20);
      expect(capped.last.timeStamp, at(19));
      expect(c.cappedLastUse, at(19));
    });

    test('cappedUses includes the use that crosses the cap', () {
      // 30 xp each: 30, 60, 90 (<100, so use 3 is added → 120), then stop
      final c = constructUses(
        'casa',
        uses: usesFor('casa', count: 6, xpEach: 30),
      );
      expect(c.cappedUses.length, 4);
      expect(c.cappedLastUse, at(3));
    });

    test('cappedUses is all uses when under the cap', () {
      final c = constructUses(
        'casa',
        uses: usesFor('casa', count: 3, xpEach: 5),
      );
      expect(c.cappedUses.length, 3);
      expect(c.cappedLastUse, at(2));
      expect(c.lastUsed, at(2));
    });

    test('empty construct: null last-use, zero points, empty capped', () {
      final c = constructUses('casa');
      expect(c.points, 0);
      expect(c.lastUsed, isNull);
      expect(c.cappedLastUse, isNull);
      expect(c.cappedUses, isEmpty);
      expect(c.hasCorrectUse, isFalse);
      expect(c.hasIncorrectUse, isFalse);
    });

    test('capped derivations refresh after mutation', () {
      final c = constructUses(
        'casa',
        uses: usesFor('casa', count: 10, xpEach: 5),
      );
      expect(c.cappedUses.length, 10);
      c.addUses(usesFor('casa', count: 15, xpEach: 5, startMinute: 10));
      expect(c.cappedUses.length, 20);
      expect(c.cappedLastUse, at(19));
      expect(c.lastUsed, at(24));
      // an earlier-dated use shifts the cap boundary backwards
      c.merge(
        constructUses(
          'casa',
          uses: [use(lemma: 'casa', ts: at(-1), xp: 5)],
        ),
      );
      expect(c.cappedUses.length, 20);
      expect(c.cappedLastUse, at(18));
    });
  });

  group('ConstructUses category / merge rules', () {
    test('category normalises: empty → other, lower-cased', () {
      expect(constructUses('a', category: '').category, 'other');
      expect(constructUses('a', category: 'NOUN').category, 'noun');
      expect(
        constructUses(
          'a',
          category: 'Tense',
          type: ConstructTypeEnum.morph,
        ).category,
        'tense',
      );
    });

    test('merge adopts a specific category over other', () {
      final a = constructUses('casa', category: '');
      final b = constructUses('casa', category: 'noun');
      a.merge(b);
      expect(a.category, 'noun');
      expect(a.id.category, 'noun');
    });

    test('merge does not overwrite a specific category', () {
      final a = constructUses('casa', category: 'noun');
      final b = constructUses('casa', category: 'verb');
      a.merge(b);
      expect(a.category, 'noun');
    });

    test('merge is case-insensitive on lemma but strict on type', () {
      final a = constructUses('Casa', uses: usesFor('Casa', count: 1));
      final b = constructUses('casa', uses: usesFor('casa', count: 1));
      a.merge(b);
      expect(a.numTotalUses, 2);
      expect(a.lemma, 'Casa');

      expect(
        () => a.merge(constructUses('casa', type: ConstructTypeEnum.morph)),
        throwsArgumentError,
      );
      expect(() => a.merge(constructUses('perro')), throwsArgumentError);
    });

    test('uses getter is unmodifiable', () {
      final c = constructUses('casa', uses: usesFor('casa', count: 1));
      expect(() => c.uses.add(c.uses.first), throwsUnsupportedError);
    });

    test('copyWith with no uses keeps the same use list', () {
      final c = constructUses('casa', uses: usesFor('casa', count: 3));
      final copy = c.copyWith(lemma: 'CASA');
      expect(copy.numTotalUses, 3);
      expect(copy.lemma, 'CASA');
      expect(copy.points, c.points);
    });
  });

  group('ConstructUses JSON', () {
    test('toJson exposes capped points and round-trips uses', () {
      final c = constructUses(
        'casa',
        uses: usesFor('casa', count: 25, xpEach: 5),
      );
      final json = c.toJson();
      expect(json['xp'], AnalyticsConstants.xpForFlower);
      expect(json['last_used'], at(24).toIso8601String());
      expect((json['construct_id'] as Map)['lemma'], 'casa');

      final back = ConstructUses.fromJson(json);
      expect(back.numTotalUses, 25);
      expect(back.points, c.points);
      expect(back.lemma, 'casa');
      expect(back.category, 'noun');
      expect(back.constructType, ConstructTypeEnum.vocab);
      expect(stamps(back), stamps(c));
    });

    test('fromJson tolerates a missing uses list', () {
      final back = ConstructUses.fromJson({
        'construct_id': {'lemma': 'x', 'type': 'vocab', 'cat': 'noun'},
      });
      expect(back.numTotalUses, 0);
      expect(back.points, 0);
    });
  });

  group('OneConstructUse.toJson timeStamp is absolute UTC', () {
    // The construct-use timeStamp must ride the wire as an ABSOLUTE UTC instant
    // (…Z), never a naive local wall-clock string. The server's analytics
    // ts_parsed reads a zoneless stamp AS UTC, so a naive local stamp shifted
    // every non-UTC user's analytics by their device offset and de-corroborated
    // engagement spans. These pin the .toUtc() so the regression cannot return.
    test(
      'serializes a local DateTime as an absolute UTC instant (ends with Z)',
      () {
        // A LOCAL wall-clock instant (isUtc == false), like DateTime.now() at the
        // call sites — the discriminating case, since toUtc() adds the zone.
        final local = DateTime(2026, 8, 18, 14, 22, 27);
        expect(local.isUtc, isFalse);

        final wire =
            use(lemma: 'casa', ts: local).toJson()['timeStamp'] as String;

        // Zone-carrying UTC, not a zoneless local string: FAILS if the emitter
        // drops .toUtc() (a naive local string has no trailing Z).
        expect(
          wire.endsWith('Z'),
          isTrue,
          reason: 'timeStamp must be UTC (…Z)',
        );
        expect(DateTime.parse(wire).isUtc, isTrue);
        // No instant is lost: the UTC wire value is the SAME moment as the local one.
        expect(DateTime.parse(wire).isAtSameMomentAs(local), isTrue);
      },
    );

    test('round-trips through fromJson to the same instant', () {
      final local = DateTime(2026, 8, 18, 14, 22, 27, 611);
      final back = OneConstructUse.fromJson(
        use(lemma: 'casa', ts: local).toJson(),
      );
      expect(back.timeStamp.isAtSameMomentAs(local), isTrue);
    });
  });
}
