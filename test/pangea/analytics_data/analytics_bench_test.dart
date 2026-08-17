// Micro-benchmark for the analytics data layer hot paths (#8416).
//
// Not a correctness test and not run in CI: it is skipped unless
// ANALYTICS_BENCH=1 is set in the environment. Run with:
//
//   ANALYTICS_BENCH=1 fvm flutter test test/pangea/analytics_data/analytics_bench_test.dart
//
// It reproduces, in isolation, the work done by:
//   A. AnalyticsDatabase.getAggregatedConstructs (vocab + morph) + points fold
//      — the body of the pre-#8418 AnalyticsDataService._recomputeTotalXP.
//   A2. AnalyticsDatabase.getAggregateXPSums + foldTotalXP — the #8418 body.
//   B. AnalyticsDataService.getAggregatedConstructs' merge loop shape:
//      ConstructUses.merge of case-variant pairs.
//   C. Repeated `points` / `cappedLastUse` reads over every aggregate — the
//      shape of the per-use loop in AnalyticsDataService.getUses.
//   D. AnalyticsDatabase._aggregateConstructs: fromJson existing aggregate +
//      addUses(small chunk) — the per-sync aggregate update.
//   E. Pure ConstructUses.merge of two large sorted lists.
//   F. ConstructUses.fromJson over every aggregate (parse cost attribution).
//   G. ConstructUses constructor over already-parsed uses (sort cost).
//   H. AnalyticsDatabase.getUses — level page (count) and activity-summary
//      (roomId + since) shapes over 400 extra server events.
//   J. Merge-table init: getAggregatedConstructs + capped uses (before) vs
//      getAggregateIds + addIdentifiers (after).
//   I. AnalyticsDatabase.getConstructUses for 500 ids — the service getUses
//      capped-last-use lookup, batched.
//
// Output is a small table of best-of-N wall-clock milliseconds.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/construct_merge_table.dart';
import 'analytics_fixtures.dart';

const _vocabConstructs = 4000;
const _morphConstructs = 150;
const _morphUsesEach = 400;
const _runs = 5;

/// Real UD feature names so morph rows pass ConstructIdentifier.isInvalid.
const _morphFeatures = [
  'Aspect',
  'Case',
  'Definite',
  'Degree',
  'Gender',
  'Mood',
  'Number',
  'Person',
  'Polarity',
  'Tense',
  'VerbForm',
  'Voice',
];

int _bestOf(int runs, void Function() body) {
  var best = 1 << 62;
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    best = min(best, sw.elapsedMicroseconds);
  }
  return best;
}

Future<int> _bestOfAsync(int runs, Future<void> Function() body) async {
  var best = 1 << 62;
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    best = min(best, sw.elapsedMicroseconds);
  }
  return best;
}

String _ms(int micros) => (micros / 1000).toStringAsFixed(1).padLeft(8);

void main() {
  final enabled = Platform.environment['ANALYTICS_BENCH'] == '1';
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'analytics data layer micro-benchmark',
    () async {
      final rng = Random(7);

      // ---- fixture: realistic heavy-user corpus -------------------------
      final vocabUses = <OneConstructUse>[];
      for (var i = 0; i < _vocabConstructs; i++) {
        // long-tail distribution: most words a handful of uses, some many
        final n = rng.nextInt(10) == 0
            ? 20 + rng.nextInt(60)
            : 1 + rng.nextInt(12);
        vocabUses.addAll(
          usesFor(
            'w$i',
            count: n,
            xpEach: 5,
            startMinute: rng.nextInt(100000),
            category: rng.nextBool() ? 'noun' : 'verb',
          ),
        );
      }
      final morphUses = <OneConstructUse>[];
      for (var i = 0; i < _morphConstructs; i++) {
        morphUses.addAll(
          usesFor(
            'tag$i',
            count: _morphUsesEach,
            xpEach: 5,
            startMinute: rng.nextInt(100000),
            type: ConstructTypeEnum.morph,
            category: _morphFeatures[i % _morphFeatures.length],
          ),
        );
      }
      final totalUses = vocabUses.length + morphUses.length;

      final events = await ServerEventFactory.create();
      final db = await freshDatabase();

      // Load the corpus as one big server catch-up (bulkUpdate shape).
      final loadMicros = await _bestOfAsync(1, () async {
        await db.updateServerAnalytics([
          events.event([...vocabUses, ...morphUses], ts: at(200000)),
        ], testLang);
      });

      // Plus a spread of small server events, so getUses walks real history.
      for (var i = 0; i < 400; i++) {
        await db.updateServerAnalytics([
          events.event(
            usesFor(
              'w${i * 7}',
              count: 5,
              startMinute: 200000 + i * 5,
              roomId: i % 10 == 0 ? '!hot' : '!r${i % 37}',
            ),
            ts: at(200001 + i * 5),
          ),
        ], testLang);
      }

      // ---- H. getUses shapes (level page / activity summary) --------------
      final hMicros = await _bestOfAsync(_runs, () async {
        await db.getUses(testLang, count: 100);
      });
      final h2Micros = await _bestOfAsync(_runs, () async {
        await db.getUses(testLang, roomId: '!hot', since: at(200000 + 300 * 5));
      });

      // ---- I. batched aggregate lookup (service getUses hoist) -----------
      final ids = List.generate(
        500,
        (i) => ConstructIdentifier(
          lemma: 'w${i * 3}',
          type: ConstructTypeEnum.vocab,
          category: 'noun',
        ),
      );
      final iMicros = await _bestOfAsync(_runs, () async {
        await db.getConstructUses({
          for (final id in ids) id: [id],
        }, testLang);
      });

      // Cold variants: drop the boxes' decoded-value caches before each run so
      // every box read is a real sqlite round-trip.
      final h2ColdMicros = await _bestOfAsync(_runs, () async {
        db.clearQuickAccessCaches();
        await db.getUses(testLang, roomId: '!hot', since: at(200000 + 300 * 5));
      });
      final iColdMicros = await _bestOfAsync(_runs, () async {
        db.clearQuickAccessCaches();
        await db.getConstructUses({
          for (final id in ids) id: [id],
        }, testLang);
      });

      // ---- J. merge-table init: full read vs ids-only ----------------------
      final jOldMicros = await _bestOfAsync(_runs, () async {
        final (v, m) = await (
          db.getAggregatedConstructs(ConstructTypeEnum.vocab, testLang),
          db.getAggregatedConstructs(ConstructTypeEnum.morph, testLang),
        ).wait;
        ConstructMergeTable()
          ..addConstructsByUses(v.expand((c) => c.cappedUses).toList(), {})
          ..addConstructsByUses(m.expand((c) => c.cappedUses).toList(), {});
      });
      final jNewMicros = await _bestOfAsync(_runs, () async {
        final (v, m) = await (
          db.getAggregateIds(ConstructTypeEnum.vocab, testLang),
          db.getAggregateIds(ConstructTypeEnum.morph, testLang),
        ).wait;
        ConstructMergeTable()
          ..addIdentifiers(v, {})
          ..addIdentifiers(m, {});
      });

      // ---- A. recompute-equivalent ---------------------------------------
      int lastTotal = 0;
      final aMicros = await _bestOfAsync(_runs, () async {
        final vocab = await db.getAggregatedConstructs(
          ConstructTypeEnum.vocab,
          testLang,
        );
        final morph = await db.getAggregatedConstructs(
          ConstructTypeEnum.morph,
          testLang,
        );
        lastTotal = [...vocab, ...morph].fold(0, (t, c) => t + c.points);
      });

      // ---- A2. recompute via raw xp sums (#8418) ---------------------------
      int lastTotal2 = 0;
      final a2Micros = await _bestOfAsync(_runs, () async {
        final sums = await Future.wait([
          db.getAggregateXPSums(ConstructTypeEnum.vocab, testLang),
          db.getAggregateXPSums(ConstructTypeEnum.morph, testLang),
        ]);
        lastTotal2 = AnalyticsDataService.foldTotalXP(
          sums.expand((s) => s),
          resolve: (id) => id,
          blocked: const {},
        );
      });

      // Materialise once for the in-memory sections.
      final vocabAgg = await db.getAggregatedConstructs(
        ConstructTypeEnum.vocab,
        testLang,
      );
      final morphAgg = await db.getAggregatedConstructs(
        ConstructTypeEnum.morph,
        testLang,
      );
      final all = [...vocabAgg, ...morphAgg];
      final rawJson = all.map((c) => c.toJson()).toList();

      // ---- B. service-side merge loop (case-variant merges) ---------------
      final bMicros = _bestOf(_runs, () {
        for (final c in all) {
          final variant = ConstructUses(
            uses: c.uses.take(3).toList(),
            constructType: c.constructType,
            lemma: c.lemma.toUpperCase(),
            category: c.category,
          );
          // fresh copy so each run does the same work
          ConstructUses.fromJson(c.toJson()).merge(variant);
        }
      });

      // ---- C. repeated derived reads -------------------------------------
      final cMicros = _bestOf(_runs, () {
        var acc = 0;
        for (var rep = 0; rep < 5; rep++) {
          for (final c in all) {
            acc += c.points;
            acc += c.cappedLastUse?.millisecondsSinceEpoch ?? 0;
            acc += c.lemmaCategory.index;
          }
        }
        if (acc == 42) throw StateError('unreachable');
      });

      // ---- D. per-sync aggregate update ----------------------------------
      final dMicros = _bestOf(_runs, () {
        for (final json in rawJson) {
          final model = ConstructUses.fromJson(json);
          model.addUses(usesFor(model.lemma, count: 2, startMinute: 300000));
          model.toJson();
        }
      });

      // ---- F/G. attribution: parse vs construct ---------------------------
      final fMicros = _bestOf(_runs, () {
        for (final json in rawJson) {
          ConstructUses.fromJson(json);
        }
      });
      final parsedUses = all.map((c) => c.uses).toList();
      final gMicros = _bestOf(_runs, () {
        for (var i = 0; i < all.length; i++) {
          ConstructUses(
            uses: parsedUses[i],
            constructType: all[i].constructType,
            lemma: all[i].lemma,
            category: all[i].category,
          );
        }
      });

      // ---- E. pure merge of two large sorted lists -----------------------
      final big1 = usesFor('big', count: 20000, startMinute: 0);
      final big2 = usesFor('big', count: 20000, startMinute: 10000);
      final eMicros = _bestOf(_runs, () {
        final a = ConstructUses(
          uses: big1,
          constructType: ConstructTypeEnum.vocab,
          lemma: 'big',
          category: 'noun',
        );
        a.merge(
          ConstructUses(
            uses: big2,
            constructType: ConstructTypeEnum.vocab,
            lemma: 'big',
            category: 'noun',
          ),
        );
        a.points;
      });

      // ---- report --------------------------------------------------------
      final report = StringBuffer()
        ..writeln('')
        ..writeln(
          'analytics bench — $_vocabConstructs vocab + $_morphConstructs morph '
          'constructs, $totalUses uses, best of $_runs',
        )
        ..writeln(
          '  load corpus (updateServerAnalytics)  ${_ms(loadMicros)} ms',
        )
        ..writeln(
          '  A recompute total XP (DB read+fold)  ${_ms(aMicros)} ms  (total=$lastTotal)',
        )
        ..writeln(
          '  A2 recompute via raw xp sums + fold  ${_ms(a2Micros)} ms  (total=$lastTotal2)',
        )
        ..writeln('  B service merge loop (variant merge) ${_ms(bMicros)} ms')
        ..writeln('  C 5x points/cappedLastUse/level     ${_ms(cMicros)} ms')
        ..writeln('  D per-sync aggregate update          ${_ms(dMicros)} ms')
        ..writeln('  E merge two 20k sorted lists         ${_ms(eMicros)} ms')
        ..writeln('  H getUses(count:100)                 ${_ms(hMicros)} ms')
        ..writeln('  H2 getUses(roomId, since 100 events) ${_ms(h2Micros)} ms')
        ..writeln('  I getConstructUses(500 ids)          ${_ms(iMicros)} ms')
        ..writeln(
          '  H2c same, cold box cache              ${_ms(h2ColdMicros)} ms',
        )
        ..writeln(
          '  Ic  same, cold box cache              ${_ms(iColdMicros)} ms',
        )
        ..writeln(
          '  J  init merge table, full read       ${_ms(jOldMicros)} ms',
        )
        ..writeln(
          '  J2 init merge table, ids only        ${_ms(jNewMicros)} ms',
        )
        ..writeln('  F fromJson all aggregates            ${_ms(fMicros)} ms')
        ..writeln('  G construct from parsed uses (sort)  ${_ms(gMicros)} ms');
      // ignore: avoid_print
      print(report);

      await db.database?.close();
      await events.dispose();
    },
    skip: enabled ? false : 'set ANALYTICS_BENCH=1 to run',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
