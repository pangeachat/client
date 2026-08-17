import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics_data/construct_merge_table.dart';
import 'analytics_fixtures.dart';

/// [ConstructMergeTable.addIdentifiers] fed one identifier per aggregate row
/// (what `_initMergeTable` now does) must build the same table as feeding it
/// every capped use of every row (what it did before): same canonical per
/// variant, same groups, same counts.
void main() {
  ConstructIdentifier vocab(String lemma, [String cat = 'noun']) =>
      ConstructIdentifier(
        lemma: lemma,
        type: ConstructTypeEnum.vocab,
        category: cat,
      );

  test('last variant seen becomes canonical for the group', () {
    final t = ConstructMergeTable();
    t.addIdentifiers([vocab('Casa'), vocab('casa'), vocab('CASA')], {});
    expect(t.resolve(vocab('Casa')), vocab('CASA'));
    expect(t.resolve(vocab('casa')), vocab('CASA'));
    expect(t.resolve(vocab('CASA')), vocab('CASA'));
    expect(t.uniqueConstructsByType(ConstructTypeEnum.vocab), 1);
    expect(t.groupedIds(vocab('Casa'), {}), [vocab('Casa'), vocab('CASA')]);
  });

  test('a later call can move the canonical, as live uses always could', () {
    final t = ConstructMergeTable();
    t.addIdentifiers([vocab('Casa'), vocab('casa')], {});
    expect(t.resolve(vocab('Casa')), vocab('casa'));
    t.addIdentifiers([vocab('Casa')], {});
    expect(t.resolve(vocab('casa')), vocab('Casa'));
  });

  test('excluded and invalid identifiers are skipped', () {
    final t = ConstructMergeTable();
    t.addIdentifiers(
      [vocab('casa'), vocab('perro'), vocab('raro', '')],
      {vocab('perro')},
    );
    expect(t.constructUsed(vocab('casa')), isTrue);
    expect(t.constructUsed(vocab('perro')), isFalse);
    expect(t.constructUsed(vocab('raro', '')), isFalse);
    expect(t.uniqueConstructsByType(ConstructTypeEnum.vocab), 1);
  });

  test('different categories are separate constructs, not variants', () {
    final t = ConstructMergeTable();
    t.addIdentifiers([vocab('bank', 'noun'), vocab('bank', 'verb')], {});
    expect(t.resolve(vocab('bank', 'noun')), vocab('bank', 'noun'));
    expect(t.uniqueConstructsByType(ConstructTypeEnum.vocab), 2);
  });

  test('property: one id per row == every capped use of every row', () {
    final rng = Random(99);
    for (var trial = 0; trial < 80; trial++) {
      final rows = <ConstructUses>[];
      final n = 1 + rng.nextInt(10);
      for (var i = 0; i < n; i++) {
        final base = 'w${rng.nextInt(5)}';
        final lemma = switch (rng.nextInt(3)) {
          0 => base,
          1 => base.toUpperCase(),
          _ => '${base[0].toUpperCase()}${base.substring(1)}',
        };
        final cat = rng.nextInt(7) == 0
            ? ''
            : (rng.nextBool() ? 'noun' : 'verb');
        final type = rng.nextInt(5) == 0
            ? ConstructTypeEnum.morph
            : ConstructTypeEnum.vocab;
        final catForType = type == ConstructTypeEnum.morph
            ? (rng.nextInt(4) == 0 ? 'bogus' : 'tense')
            : cat;
        // sometimes an empty row (no uses)
        final uses = List.generate(
          rng.nextInt(4) == 0 ? 0 : 1 + rng.nextInt(30),
          (k) => use(
            lemma: lemma,
            category: catForType,
            type: type,
            ts: at(rng.nextInt(100)),
            xp: rng.nextInt(30),
          ),
        );
        rows.add(
          constructUses(lemma, category: catForType, type: type, uses: uses),
        );
      }
      final blocked = <ConstructIdentifier>{
        for (final r in rows)
          if (rng.nextInt(6) == 0) r.id,
      };

      final legacy = ConstructMergeTable()
        ..addConstructsByUses(
          rows.expand((c) => c.cappedUses).toList(),
          blocked,
        );
      final fresh = ConstructMergeTable()
        ..addIdentifiers([
          for (final r in rows)
            if (r.numTotalUses > 0) r.id,
        ], blocked);

      final allIds = {for (final r in rows) r.id};
      for (final id in allIds) {
        expect(
          fresh.resolve(id),
          legacy.resolve(id),
          reason: 'trial $trial resolve $id',
        );
        expect(
          fresh.constructUsed(id),
          legacy.constructUsed(id),
          reason: 'trial $trial used $id',
        );
        expect(
          fresh.groupedIds(id, blocked),
          legacy.groupedIds(id, blocked),
          reason: 'trial $trial grouped $id',
        );
      }
      for (final type in ConstructTypeEnum.values) {
        expect(
          fresh.uniqueConstructsByType(type),
          legacy.uniqueConstructsByType(type),
          reason: 'trial $trial count ${type.name}',
        );
      }
    }
  });
}
