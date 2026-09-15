import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics_data/analytics_database.dart';
import 'analytics_fixtures.dart';

/// Golden tests for [AnalyticsDatabase] read/write paths on an in-memory
/// sqflite database. Pins current behavior so later performance stages
/// (batched reads, cheaper XP recompute) can be proven behavior-preserving.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AnalyticsDatabase db;
  late ServerEventFactory events;

  setUpAll(() async {
    events = await ServerEventFactory.create();
  });

  setUp(() async {
    db = await freshDatabase();
  });

  tearDown(() async {
    await db.database?.close();
  });

  tearDownAll(() => events.dispose());

  ConstructIdentifier vocabId(String lemma, [String cat = 'noun']) =>
      ConstructIdentifier(
        lemma: lemma,
        type: ConstructTypeEnum.vocab,
        category: cat,
      );

  group('server analytics writes', () {
    test(
      'updateServerAnalytics stores raw uses and aggregates by construct',
      () async {
        await db.updateServerAnalytics([
          events.event([
            ...usesFor('casa', count: 3, xpEach: 5),
            ...usesFor(
              'Tense',
              count: 2,
              xpEach: 5,
              type: ConstructTypeEnum.morph,
              category: 'tense',
            ),
          ], ts: at(10)),
        ], testLang);

        final vocab = await db.getAggregatedConstructs(
          ConstructTypeEnum.vocab,
          testLang,
        );
        expect(vocab.length, 1);
        expect(vocab.single.lemma, 'casa');
        expect(vocab.single.points, 15);
        expect(vocab.single.numTotalUses, 3);

        final morph = await db.getAggregatedConstructs(
          ConstructTypeEnum.morph,
          testLang,
        );
        expect(morph.length, 1);
        expect(morph.single.category, 'tense');
        expect(morph.single.points, 10);

        expect(await db.getLastEventTimestamp(testLang), at(10));
        expect(await db.getLastUpdated(testLang), isNotNull);
      },
    );

    test(
      'a second event for the same construct merges into the aggregate',
      () async {
        await db.updateServerAnalytics([
          events.event(usesFor('casa', count: 2, xpEach: 5), ts: at(10)),
        ], testLang);
        await db.updateServerAnalytics([
          events.event(
            usesFor('casa', count: 2, xpEach: 5, startMinute: 20),
            ts: at(20),
          ),
        ], testLang);

        final vocab = await db.getAggregatedConstructs(
          ConstructTypeEnum.vocab,
          testLang,
        );
        expect(vocab.single.numTotalUses, 4);
        expect(vocab.single.points, 20);
        expect(vocab.single.uses.first.timeStamp, at(0));
        expect(vocab.single.uses.last.timeStamp, at(21));
        expect(await db.getLastEventTimestamp(testLang), at(20));
      },
    );

    test('an already-stored eventId is ignored', () async {
      final e = events.event(usesFor('casa', count: 2, xpEach: 5), ts: at(10));
      await db.updateServerAnalytics([e], testLang);
      await db.updateServerAnalytics([e], testLang);
      final vocab = await db.getAggregatedConstructs(
        ConstructTypeEnum.vocab,
        testLang,
      );
      expect(vocab.single.numTotalUses, 2);
    });

    test('an event older than the last event timestamp is skipped', () async {
      await db.updateServerAnalytics([
        events.event(usesFor('casa', count: 1), ts: at(10)),
      ], testLang);
      await db.updateServerAnalytics([
        events.event(usesFor('perro', count: 1), ts: at(5)),
      ], testLang);
      final vocab = await db.getAggregatedConstructs(
        ConstructTypeEnum.vocab,
        testLang,
      );
      expect(vocab.map((c) => c.lemma), ['casa']);
    });

    test('languages are isolated', () async {
      await db.updateServerAnalytics([
        events.event(usesFor('casa', count: 1), ts: at(10)),
      ], 'es');
      await db.updateServerAnalytics([
        events.event(usesFor('house', count: 1), ts: at(10)),
      ], 'en');
      expect(
        (await db.getAggregatedConstructs(
          ConstructTypeEnum.vocab,
          'es',
        )).map((c) => c.lemma),
        ['casa'],
      );
      expect(
        (await db.getAggregatedConstructs(
          ConstructTypeEnum.vocab,
          'en',
        )).map((c) => c.lemma),
        ['house'],
      );
    });

    test('case variants are separate storage keys', () async {
      await db.updateServerAnalytics([
        events.event([
          ...usesFor('Casa', count: 1),
          ...usesFor('casa', count: 1),
        ], ts: at(10)),
      ], testLang);
      final vocab = await db.getAggregatedConstructs(
        ConstructTypeEnum.vocab,
        testLang,
      );
      expect(vocab.length, 2);
    });
  });

  group('local analytics writes', () {
    test('updateLocalAnalytics stores raw uses and local aggregates', () async {
      await db.updateLocalAnalytics(
        usesFor('casa', count: 3, xpEach: 5),
        testLang,
      );
      final local = await db.getLocalUses(testLang);
      expect(local.length, 3);
      expect(await db.getLocalConstructCount(testLang), 1);

      final vocab = await db.getAggregatedConstructs(
        ConstructTypeEnum.vocab,
        testLang,
      );
      expect(vocab.single.points, 15);
    });

    test('server + local aggregates for the same key are merged', () async {
      await db.updateServerAnalytics([
        events.event(usesFor('casa', count: 2, xpEach: 5), ts: at(10)),
      ], testLang);
      await db.updateLocalAnalytics(
        usesFor('casa', count: 2, xpEach: 5, startMinute: 30),
        testLang,
      );
      final vocab = await db.getAggregatedConstructs(
        ConstructTypeEnum.vocab,
        testLang,
      );
      expect(vocab.single.numTotalUses, 4);
      expect(vocab.single.points, 20);
      expect(vocab.single.uses.last.timeStamp, at(31));
    });

    test(
      'clearLocalConstructData removes local uses and aggregates only',
      () async {
        await db.updateServerAnalytics([
          events.event(usesFor('casa', count: 2, xpEach: 5), ts: at(10)),
        ], testLang);
        await db.updateLocalAnalytics(usesFor('perro', count: 2), testLang);
        await db.clearLocalConstructData(testLang);

        expect(await db.getLocalUses(testLang), isEmpty);
        final vocab = await db.getAggregatedConstructs(
          ConstructTypeEnum.vocab,
          testLang,
        );
        expect(vocab.map((c) => c.lemma), ['casa']);
      },
    );
  });

  group('getConstructUse(s)', () {
    test(
      'merges server + local for one id and returns empty for unknown',
      () async {
        await db.updateServerAnalytics([
          events.event(usesFor('casa', count: 2, xpEach: 5), ts: at(10)),
        ], testLang);
        await db.updateLocalAnalytics(
          usesFor('casa', count: 1, xpEach: 5, startMinute: 30),
          testLang,
        );

        final c = await db.getConstructUse([vocabId('casa')], testLang);
        expect(c.numTotalUses, 3);
        expect(c.points, 15);

        final none = await db.getConstructUse([vocabId('nada')], testLang);
        expect(none.numTotalUses, 0);
        expect(none.lemma, 'nada');
        expect(none.category, 'noun');
      },
    );

    test('grouped ids (case variants) merge into one construct', () async {
      await db.updateServerAnalytics([
        events.event([
          ...usesFor('Casa', count: 1, xpEach: 5),
          ...usesFor('casa', count: 1, xpEach: 5, startMinute: 5),
        ], ts: at(10)),
      ], testLang);
      final c = await db.getConstructUse([
        vocabId('Casa'),
        vocabId('casa'),
      ], testLang);
      expect(c.numTotalUses, 2);
      expect(c.lemma, 'Casa');
      expect(c.points, 10);
    });

    test(
      'getConstructUses: an empty group yields an empty construct for the key',
      () async {
        final result = await db.getConstructUses({
          vocabId('nada'): [],
        }, testLang);
        expect(result[vocabId('nada')]!.numTotalUses, 0);
        expect(result[vocabId('nada')]!.lemma, 'nada');
      },
    );

    test(
      'getConstructUses handles a large batch (> the 1000-key sql limit)',
      () async {
        final ids = List.generate(1200, (i) => vocabId('w$i'));
        await db.updateServerAnalytics([
          events.event([
            for (var i = 0; i < 1200; i += 3)
              ...usesFor('w$i', count: 1, xpEach: 5),
          ], ts: at(10)),
        ], testLang);
        final result = await db.getConstructUses({
          for (final id in ids) id: [id],
        }, testLang);
        expect(result.length, 1200);
        expect(result[vocabId('w0')]!.points, 5);
        expect(result[vocabId('w1')]!.points, 0);
        expect(result[vocabId('w1197')]!.points, 5);
      },
    );

    test('getConstructUses returns one entry per requested key', () async {
      await db.updateServerAnalytics([
        events.event([
          ...usesFor('casa', count: 2, xpEach: 5),
          ...usesFor('perro', count: 1, xpEach: 5),
        ], ts: at(10)),
      ], testLang);
      final result = await db.getConstructUses({
        vocabId('casa'): [vocabId('casa')],
        vocabId('perro'): [vocabId('perro')],
        vocabId('gato'): [vocabId('gato')],
      }, testLang);
      expect(result.length, 3);
      expect(result[vocabId('casa')]!.points, 10);
      expect(result[vocabId('perro')]!.points, 5);
      expect(result[vocabId('gato')]!.points, 0);
    });
  });

  group('getUses', () {
    Future<void> seed() async {
      // server: two events, oldest first
      await db.updateServerAnalytics([
        events.event(
          usesFor('casa', count: 3, xpEach: 5, roomId: '!a'),
          ts: at(10),
        ),
      ], testLang);
      await db.updateServerAnalytics([
        events.event(
          usesFor(
            'perro',
            count: 3,
            xpEach: 5,
            startMinute: 20,
            roomId: '!b',
            useType: ConstructUseTypeEnum.wa,
          ),
          ts: at(25),
        ),
      ], testLang);
      // local: newest
      await db.updateLocalAnalytics(
        usesFor('gato', count: 2, xpEach: 5, startMinute: 40, roomId: '!a'),
        testLang,
      );
    }

    test(
      'returns local uses first, then server uses newest event first',
      () async {
        await seed();
        final uses = await db.getUses(testLang);
        expect(uses.map((u) => u.lemma).toList(), [
          'gato', 'gato', // local, newest first
          'perro', 'perro', 'perro', // newest server event
          'casa', 'casa', 'casa',
        ]);
        expect(uses[0].timeStamp, at(41));
        expect(uses[2].timeStamp, at(22));
      },
    );

    test('count truncates', () async {
      await seed();
      final uses = await db.getUses(testLang, count: 4);
      expect(uses.length, 4);
      expect(uses.map((u) => u.lemma).toList(), [
        'gato',
        'gato',
        'perro',
        'perro',
      ]);
    });

    test('roomId filters', () async {
      await seed();
      final uses = await db.getUses(testLang, roomId: '!a');
      expect(uses.map((u) => u.lemma).toSet(), {'gato', 'casa'});
      expect(uses.length, 5);
    });

    test('types filters', () async {
      await seed();
      final uses = await db.getUses(testLang, types: [ConstructUseTypeEnum.wa]);
      expect(uses.map((u) => u.lemma).toSet(), {'perro'});
    });

    test('since excludes older uses', () async {
      await seed();
      final uses = await db.getUses(testLang, since: at(21));
      // gato (40,41), perro (21,22) — casa (0..2) and perro@20 excluded
      expect(uses.map((u) => u.timeStamp).toList(), [
        at(41),
        at(40),
        at(22),
        at(21),
      ]);
    });

    test('since at epoch returns everything', () async {
      await seed();
      final uses = await db.getUses(
        testLang,
        since: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(uses.length, 8);
    });

    test('count across many server events stops at the right use', () async {
      // 150 one-use events > the 64-key read chunk; newest event first.
      for (var i = 0; i < 150; i++) {
        await db.updateServerAnalytics([
          events.event(usesFor('w$i', count: 1, startMinute: i), ts: at(i)),
        ], testLang);
      }
      final uses = await db.getUses(testLang, count: 70);
      expect(uses.length, 70);
      expect(uses.first.lemma, 'w149');
      expect(uses.last.lemma, 'w80');
      expect(
        uses.map((u) => u.timeStamp).toList(),
        List.generate(70, (i) => at(149 - i)),
      );

      final all = await db.getUses(testLang);
      expect(all.length, 150);
      expect(all.last.lemma, 'w0');
    });

    test('since keeps uses in an event whose server timestamp trails them '
        '(client clock ahead) inside the skew allowance', () async {
      // Event stamped at minute 0 by the server, but the client-stamped uses
      // inside it are at minute 30 and 31.
      await db.updateServerAnalytics([
        events.event(
          usesFor('adelantado', count: 2, startMinute: 30),
          ts: at(0),
        ),
      ], testLang);
      // A genuinely old event, well outside the allowance.
      await db.updateServerAnalytics([
        events.event(
          usesFor('viejo', count: 1, startMinute: 0),
          ts: at(60 * 24 * 3),
        ),
      ], testLang);
      final uses = await db.getUses(testLang, since: at(31));
      expect(uses.map((u) => u.lemma).toList(), ['adelantado']);
      expect(uses.single.timeStamp, at(31));

      // Far beyond the allowance: an event 2 days older than `since` is not
      // read at all, so its uses can never appear.
      final later = await db.getUses(testLang, since: at(60 * 24 * 2 + 30));
      expect(later, isEmpty);
    });

    test(
      'roomId / types filters give the same result as filtering afterwards',
      () async {
        await seed();
        final all = await db.getUses(testLang);
        final expected = all
            .where(
              (u) =>
                  u.metadata.roomId == '!a' &&
                  u.useType == ConstructUseTypeEnum.corPA,
            )
            .toList();
        final filtered = await db.getUses(
          testLang,
          roomId: '!a',
          types: [ConstructUseTypeEnum.corPA],
        );
        expect(
          filtered.map((u) => u.timeStamp),
          expected.map((u) => u.timeStamp),
        );
        expect(filtered, isNotEmpty);
      },
    );

    test('empty database returns empty', () async {
      expect(await db.getUses(testLang), isEmpty);
      expect(await db.getUses(testLang, count: 5, roomId: '!x'), isEmpty);
    });
  });

  group('derived stats', () {
    test('defaults, totalXP and offset', () async {
      final initial = await db.getDerivedStats(testLang);
      expect(initial.totalXP, 0);
      expect(initial.level, 1);

      await db.updateTotalXP(1000, testLang);
      expect((await db.getDerivedStats(testLang)).totalXP, 1000);

      await db.updateXPOffset(50, testLang);
      final s = await db.getDerivedStats(testLang);
      expect(s.totalXP, 1050);
      expect(s.offset, 50);

      // total update keeps offset
      await db.updateTotalXP(10, testLang);
      expect((await db.getDerivedStats(testLang)).totalXP, 60);
    });

    test('metadata keys round-trip', () async {
      await db.updateUserID(testUserId);
      await db.updateCurrentLanguage('es');
      await db.updateAnalyticsRoomId('!room');
      expect(await db.getUserID(), testUserId);
      expect(await db.getCurrentLanguage(), 'es');
      expect(await db.getAnalyticsRoomId(), '!room');
    });
  });

  group('getAggregateXPSums', () {
    /// The reference: uncapped per-row xp via full deserialization.
    Future<Map<String, int>> referenceSums(ConstructTypeEnum type) async {
      final out = <String, int>{};
      for (final c in await db.getAggregatedConstructs(type, testLang)) {
        out[c.id.storageKey] =
            (out[c.id.storageKey] ?? 0) + c.uses.fold(0, (t, u) => t + u.xp);
      }
      return out;
    }

    Map<String, int> byKey(List<({ConstructIdentifier id, int xp})> rows) {
      final out = <String, int>{};
      for (final r in rows) {
        out[r.id.storageKey] = (out[r.id.storageKey] ?? 0) + r.xp;
      }
      return out;
    }

    test('empty database yields no rows', () async {
      expect(
        await db.getAggregateXPSums(ConstructTypeEnum.vocab, testLang),
        isEmpty,
      );
    });

    test('matches full deserialization: negatives, over-cap, server+local, '
        'case variants, morphs, other language', () async {
      await db.updateServerAnalytics([
        events.event([
          ...usesFor('casa', count: 30, xpEach: 5), // 150 uncapped
          ...usesFor('Casa', count: 2, xpEach: 5), // case variant row
          ...usesFor('perro', count: 3, xpEach: 5),
          use(lemma: 'perro', ts: at(50), xp: -20), // negative
          ...usesFor(
            'Pres',
            count: 4,
            xpEach: 5,
            type: ConstructTypeEnum.morph,
            category: 'tense',
          ),
          use(
            lemma: 'Past',
            ts: at(1),
            xp: -3,
            type: ConstructTypeEnum.morph,
            category: 'tense',
          ),
        ], ts: at(60)),
      ], testLang);
      // local rows for an existing and a new key
      await db.updateLocalAnalytics([
        ...usesFor('casa', count: 2, xpEach: 5, startMinute: 100),
        ...usesFor('gato', count: 1, xpEach: 7, startMinute: 100),
      ], testLang);
      // another language must not leak in
      await db.updateServerAnalytics([
        events.event(usesFor('house', count: 4), ts: at(60)),
      ], 'en');

      for (final type in ConstructTypeEnum.values) {
        final rows = await db.getAggregateXPSums(type, testLang);
        expect(byKey(rows), await referenceSums(type), reason: type.name);
      }

      // spot-check the raw values themselves
      final vocab = byKey(
        await db.getAggregateXPSums(ConstructTypeEnum.vocab, testLang),
      );
      expect(vocab[vocabId('casa').storageKey], 160); // 150 server + 10 local
      expect(vocab[vocabId('Casa').storageKey], 10);
      expect(vocab[vocabId('perro').storageKey], -5);
      expect(vocab[vocabId('gato').storageKey], 7);
      expect(vocab.containsKey(vocabId('house').storageKey), isFalse);
      // server and local rows for casa are separate rows
      final casaRows = (await db.getAggregateXPSums(
        ConstructTypeEnum.vocab,
        testLang,
      )).where((r) => r.id.storageKey == vocabId('casa').storageKey);
      expect(casaRows.length, 2);
    });
  });

  group('getAggregateIds', () {
    /// Reference: identifiers of the rows getAggregatedConstructs yields, in
    /// its order, keeping only rows with uses.
    Future<List<ConstructIdentifier>> reference(ConstructTypeEnum type) async =>
        [
          for (final c in await db.getAggregatedConstructs(type, testLang))
            if (c.numTotalUses > 0) c.id,
        ];

    test('empty database yields nothing', () async {
      expect(
        await db.getAggregateIds(ConstructTypeEnum.vocab, testLang),
        isEmpty,
      );
    });

    test('same ids, same order as the full read; server+local collapse; '
        'local-only appended; other language excluded', () async {
      await db.updateServerAnalytics([
        events.event([
          ...usesFor('casa', count: 2),
          ...usesFor('Casa', count: 1),
          ...usesFor('perro', count: 1),
          ...usesFor(
            'Pres',
            count: 2,
            type: ConstructTypeEnum.morph,
            category: 'tense',
          ),
        ], ts: at(10)),
      ], testLang);
      await db.updateLocalAnalytics([
        ...usesFor('casa', count: 1, startMinute: 50), // also on server
        ...usesFor('gato', count: 1, startMinute: 50), // local only
      ], testLang);
      await db.updateServerAnalytics([
        events.event(usesFor('house', count: 1), ts: at(10)),
      ], 'en');

      for (final type in ConstructTypeEnum.values) {
        final ids = await db.getAggregateIds(type, testLang);
        expect(ids, await reference(type), reason: type.name);
      }
      final vocab = await db.getAggregateIds(ConstructTypeEnum.vocab, testLang);
      expect(vocab.map((i) => i.lemma).toSet(), {
        'casa',
        'Casa',
        'perro',
        'gato',
      });
      expect(
        vocab.last.lemma,
        'gato',
      ); // local-only rows come after server rows
      expect(vocab.where((i) => i.lemma == 'casa').length, 1);
    });
  });

  group('recompute-equivalent fold', () {
    test('sum of capped points across aggregates', () async {
      await db.updateServerAnalytics([
        events.event([
          ...usesFor('casa', count: 30, xpEach: 5), // capped → 100
          ...usesFor('perro', count: 3, xpEach: 5), // 15
          ...usesFor(
            'Pres',
            count: 4,
            xpEach: 5,
            type: ConstructTypeEnum.morph,
            category: 'tense',
          ), // 20
        ], ts: at(60)),
      ], testLang);
      final vocab = await db.getAggregatedConstructs(
        ConstructTypeEnum.vocab,
        testLang,
      );
      final morph = await db.getAggregatedConstructs(
        ConstructTypeEnum.morph,
        testLang,
      );
      final total = [...vocab, ...morph].fold(0, (t, c) => t + c.points);
      expect(total, AnalyticsConstants.xpForFlower + 15 + 20);
    });
  });

  /// A raw write that fails must reach the caller. `addAnalytics` credits a
  /// use once and only once, so a write it is told succeeded is never retried
  /// — the uses would be neither uploaded nor recoverable (#8537).
  ///
  /// Each test drops only the raw table, leaving the aggregate tables intact,
  /// so the failure is isolated to the raw write. The preceding successful
  /// call warms the box key cache, which keeps the drop off the read path.
  group('raw write failures surface to the caller', () {
    test('updateLocalAnalytics rethrows a failed raw local write', () async {
      await db.updateLocalAnalytics(usesFor('casa', count: 1), testLang);

      await db.database!.execute('DROP TABLE box_local_constructs');

      await expectLater(
        db.updateLocalAnalytics(usesFor('perro', count: 1), testLang),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('updateServerAnalytics rethrows a failed raw server write', () async {
      await db.updateServerAnalytics([
        events.event(usesFor('casa', count: 1), ts: at(10)),
      ], testLang);

      await db.database!.execute('DROP TABLE box_server_constructs');

      await expectLater(
        db.updateServerAnalytics([
          events.event(usesFor('perro', count: 1), ts: at(20)),
        ], testLang),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
