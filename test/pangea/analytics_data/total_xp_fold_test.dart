import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/construct_merge_table.dart';
import 'analytics_fixtures.dart';

/// [AnalyticsDataService.foldTotalXP] must equal what the pre-#8418 recompute
/// computed: `Σ ConstructUses.points` over the service-level
/// `getAggregatedConstructs` (merge-table canonicalisation, blocked/invalid
/// canonical dropped, per-construct cap).
void main() {
  ConstructIdentifier vocab(String lemma, [String cat = 'noun']) =>
      ConstructIdentifier(
        lemma: lemma,
        type: ConstructTypeEnum.vocab,
        category: cat,
      );
  ConstructIdentifier morph(String tag, [String feat = 'tense']) =>
      ConstructIdentifier(
        lemma: tag,
        type: ConstructTypeEnum.morph,
        category: feat,
      );

  /// The old computation, reproduced verbatim from
  /// AnalyticsDataService.getAggregatedConstructs + _recomputeTotalXP.
  int legacyTotal(
    List<ConstructUses> rows,
    ConstructMergeTable table,
    Set<ConstructIdentifier> blocked,
  ) {
    final cleaned = <ConstructIdentifier, ConstructUses>{};
    for (final entry in rows) {
      final canonical = table.resolve(entry.id);
      final existing = cleaned[canonical];
      if (existing != null) {
        existing.merge(entry);
      } else if (!blocked.contains(canonical) && !canonical.isInvalid) {
        cleaned[canonical] = entry;
      }
    }
    return cleaned.values.fold(0, (t, c) => t + c.points);
  }

  ({ConstructIdentifier id, int xp}) rowOf(ConstructUses c) =>
      (id: c.id, xp: c.uses.fold(0, (t, u) => t + u.xp));

  test('caps per construct, drops blocked and invalid, sums the rest', () {
    final rows = <({ConstructIdentifier id, int xp})>[
      (id: vocab('casa'), xp: 150), // → 100
      (id: vocab('perro'), xp: -5), // negatives kept
      (id: vocab('gato'), xp: 40),
      (id: vocab('bloqueado'), xp: 60), // blocked
      (id: vocab('raro', ''), xp: 60), // category other → invalid
      (id: morph('Pres'), xp: 30),
      (id: morph('Weird', 'notafeature'), xp: 30), // unknown feature → invalid
    ];
    final total = AnalyticsDataService.foldTotalXP(
      rows,
      resolve: (id) => id,
      blocked: {vocab('bloqueado')},
    );
    expect(total, 100 - 5 + 40 + 30);
  });

  test('rows resolving to one canonical share a single cap', () {
    final table = ConstructMergeTable();
    table.addConstructsByUses([
      ...usesFor('Casa', count: 1),
      ...usesFor('casa', count: 1),
    ], {});
    // Both variants exist; whichever is canonical, the pair must cap once.
    final rows = <({ConstructIdentifier id, int xp})>[
      (id: vocab('Casa'), xp: 70),
      (id: vocab('casa'), xp: 70),
      (id: vocab('casa'), xp: 10), // a local row for the same key
    ];
    expect(
      AnalyticsDataService.foldTotalXP(
        rows,
        resolve: table.resolve,
        blocked: {},
      ),
      AnalyticsConstants.xpForFlower,
    );
  });

  test('a blocked canonical drops its variants too', () {
    final table = ConstructMergeTable();
    table.addConstructsByUses([
      ...usesFor('Casa', count: 1),
      ...usesFor('casa', count: 1),
    ], {});
    final canonical = table.resolve(vocab('Casa'));
    final rows = <({ConstructIdentifier id, int xp})>[
      (id: vocab('Casa'), xp: 20),
      (id: vocab('casa'), xp: 20),
      (id: vocab('otro'), xp: 5),
    ];
    expect(
      AnalyticsDataService.foldTotalXP(
        rows,
        resolve: table.resolve,
        blocked: {canonical},
      ),
      5,
    );
  });

  /// The service's getAggregatedConstructIds algorithm, inline.
  Set<ConstructIdentifier> idsOnlyKeys(
    Iterable<ConstructIdentifier> rowIds,
    ConstructMergeTable table,
    Set<ConstructIdentifier> blocked,
  ) {
    final out = <ConstructIdentifier>{};
    for (final id in rowIds) {
      final canonical = table.resolve(id);
      if (blocked.contains(canonical) || canonical.isInvalid) continue;
      out.add(canonical);
    }
    return out;
  }

  /// The pre-#8433 distractor input: getAggregatedConstructs(...).keys.
  Set<ConstructIdentifier> legacyKeys(
    List<ConstructUses> rows,
    ConstructMergeTable table,
    Set<ConstructIdentifier> blocked,
  ) {
    final cleaned = <ConstructIdentifier, ConstructUses>{};
    for (final entry in rows) {
      final canonical = table.resolve(entry.id);
      final existing = cleaned[canonical];
      if (existing != null) {
        existing.merge(entry);
      } else if (!blocked.contains(canonical) && !canonical.isInvalid) {
        cleaned[canonical] = entry;
      }
    }
    return cleaned.keys.toSet();
  }

  test('property: ids-only canonical set == legacy aggregated keys', () {
    final rng = Random(77);
    for (var trial = 0; trial < 60; trial++) {
      final rows = <ConstructUses>[];
      final allUses = <OneConstructUse>[];
      for (var i = 0; i < 1 + rng.nextInt(12); i++) {
        final base = 'w${rng.nextInt(6)}';
        final lemma = rng.nextBool() ? base : base.toUpperCase();
        final cat = rng.nextInt(7) == 0
            ? ''
            : (rng.nextBool() ? 'noun' : 'verb');
        final uses = List.generate(
          1 + rng.nextInt(5),
          (k) => use(lemma: lemma, category: cat, ts: at(k), xp: 5),
        );
        allUses.addAll(uses);
        rows.add(constructUses(lemma, category: cat, uses: uses));
      }
      final blocked = <ConstructIdentifier>{
        for (final r in rows)
          if (rng.nextInt(5) == 0) r.id,
      };
      final table = ConstructMergeTable()
        ..addConstructsByUses(allUses, blocked);
      final legacyRows = rows
          .map((c) => ConstructUses.fromJson(c.toJson()))
          .toList();
      expect(
        idsOnlyKeys(rows.map((r) => r.id), table, blocked),
        legacyKeys(legacyRows, table, blocked),
        reason: 'trial $trial',
      );
    }
  });

  test('property: equals the legacy Σ points fold over random corpora', () {
    final rng = Random(2026);
    for (var trial = 0; trial < 60; trial++) {
      final lemmas = List.generate(1 + rng.nextInt(12), (i) => 'w$i');
      final rows = <ConstructUses>[];
      final allUses = <OneConstructUse>[];
      for (final lemma in lemmas) {
        // 1–3 storage rows per lemma: case variants and/or server+local dupes
        final variants = rng.nextInt(3) + 1;
        for (var v = 0; v < variants; v++) {
          final l = v == 1 ? lemma.toUpperCase() : lemma;
          final cat = rng.nextInt(8) == 0
              ? ''
              : (rng.nextBool() ? 'noun' : 'verb');
          final uses = List.generate(
            rng.nextInt(30),
            (k) => use(
              lemma: l,
              category: cat,
              ts: at(rng.nextInt(500)),
              xp: rng.nextInt(40) - 10,
            ),
          );
          allUses.addAll(uses);
          rows.add(constructUses(l, category: cat, uses: uses));
        }
      }
      // a few morphs, some with an unknown feature
      for (var m = 0; m < rng.nextInt(4); m++) {
        final feat = rng.nextInt(4) == 0 ? 'bogus' : 'tense';
        final uses = List.generate(
          rng.nextInt(50),
          (k) => use(
            lemma: 't$m',
            category: feat,
            type: ConstructTypeEnum.morph,
            ts: at(rng.nextInt(500)),
            xp: rng.nextInt(20) - 4,
          ),
        );
        allUses.addAll(uses);
        rows.add(
          constructUses(
            't$m',
            category: feat,
            type: ConstructTypeEnum.morph,
            uses: uses,
          ),
        );
      }

      final blocked = <ConstructIdentifier>{};
      for (final r in rows) {
        if (rng.nextInt(6) == 0) blocked.add(r.id);
      }
      final table = ConstructMergeTable();
      table.addConstructsByUses(allUses, blocked);

      // legacy mutates via merge → give it deep copies
      final legacyRows = rows
          .map((c) => ConstructUses.fromJson(c.toJson()))
          .toList();
      final expected = legacyTotal(legacyRows, table, blocked);
      final actual = AnalyticsDataService.foldTotalXP(
        rows.map(rowOf),
        resolve: table.resolve,
        blocked: blocked,
      );
      expect(actual, expected, reason: 'trial $trial');
    }
  });
}
