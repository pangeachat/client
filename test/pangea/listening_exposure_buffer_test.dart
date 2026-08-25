import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/listening_exposure_buffer.dart';

/// Bucketing is what keeps listening exposure from banking one near-empty row
/// per word heard on a list nothing ever prunes, and the shape of a bucket is
/// load-bearing downstream: the count is authoritative, the timestamp has to be
/// a real instant inside the bucket (engagement spans corroborate against it),
/// and no identifier may travel.
void main() {
  ConstructIdentifier id(String lemma, [String pos = 'verb']) =>
      ConstructIdentifier(
        lemma: lemma,
        type: ConstructTypeEnum.vocab,
        category: pos,
      );

  late DateTime clock;
  ListeningExposureBuffer build() => ListeningExposureBuffer(now: () => clock);

  setUp(() {
    clock = DateTime.utc(2026, 8, 24, 9);
    ListeningExposureBuffer.debugResetAccounts();
  });

  group('bucketing', () {
    test('repeats of one lemma collapse into a single counted row', () {
      final buffer = build();

      buffer.record([id('hablar')], langCode: 'es');
      buffer.record([id('hablar')], langCode: 'es');
      buffer.record([id('hablar')], langCode: 'es');

      final drained = buffer.drain('es');

      expect(drained, hasLength(1));
      expect(drained.single.lemma, 'hablar');
      expect(drained.single.count, 3);
    });

    test('distinct lemmas get a row each', () {
      final buffer = build();

      buffer.record([id('hablar'), id('comer')], langCode: 'es');
      buffer.record([id('hablar')], langCode: 'es');

      final drained = buffer.drain('es');

      expect(drained, hasLength(2));
      expect(
        {for (final use in drained) use.lemma: use.count},
        {'hablar': 2, 'comer': 1},
      );
    });

    test('the same lemma under a different POS is a different construct', () {
      final buffer = build();

      buffer.record([id('bank', 'noun')], langCode: 'es');
      buffer.record([id('bank', 'verb')], langCode: 'es');

      expect(buffer.drain('es'), hasLength(2));
    });

    test('counts occurrences, not rows', () {
      final buffer = build();

      buffer.record([id('hablar'), id('comer')], langCode: 'es');
      buffer.record([id('hablar')], langCode: 'es');

      expect(buffer.pendingExposures, 3);
    });
  });

  group('the emitted row', () {
    test('is worth no XP', () {
      final buffer = build()..record([id('hablar')], langCode: 'es');

      final use = buffer.drain('es').single;

      expect(use.useType, ConstructUseTypeEnum.hrd);
      expect(use.xp, 0);
    });

    test('carries no room id and no event id', () {
      // Not incidental: the listening lane drops both at collection because a
      // per-student record of which peers a learner attends to is a
      // third-party fact. A regression here is a privacy regression.
      final buffer = build()..record([id('hablar')], langCode: 'es');

      final use = buffer.drain('es').single;

      expect(use.metadata.roomId, isNull);
      expect(use.metadata.eventId, isNull);
    });

    test('carries no form, because a bucket spans several', () {
      final buffer = build()..record([id('hablar')], langCode: 'es');

      expect(buffer.drain('es').single.form, isNull);
    });

    test('is stamped with the last exposure in the bucket', () {
      // Engagement spans corroborate against construct-use timestamps within
      // ±10 minutes, so the stamp must be an instant the learner was really
      // active at — never a synthetic window boundary.
      final buffer = build();

      buffer.record([id('hablar')], langCode: 'es');
      clock = clock.add(const Duration(minutes: 2));
      buffer.record([id('hablar')], langCode: 'es');

      expect(
        buffer.drain('es').single.metadata.timeStamp,
        DateTime.utc(2026, 8, 24, 9, 2),
      );
    });
  });

  group('the window', () {
    test('keeps one bucket open while it has not elapsed', () {
      final buffer = build();

      buffer.record([id('hablar')], langCode: 'es');
      clock = clock.add(
        ListeningExposureBuffer.window - const Duration(seconds: 1),
      );
      buffer.record([id('hablar')], langCode: 'es');

      expect(buffer.drain('es'), hasLength(1));
    });

    test('closes the open bucket once it has elapsed', () {
      // The heartbeat normally closes a window by draining it. This bound is
      // what holds the ±10 minute invariant when the heartbeat is not running
      // — a suspended timer in the background.
      final buffer = build();

      buffer.record([id('hablar')], langCode: 'es');
      final firstStamp = clock;
      clock = clock.add(ListeningExposureBuffer.window);
      buffer.record([id('hablar')], langCode: 'es');

      final drained = buffer.drain('es');

      expect(drained, hasLength(2), reason: 'two windows, two rows');
      expect(drained.first.metadata.timeStamp, firstStamp);
      expect(drained.last.metadata.timeStamp, clock);
      expect(drained.map((u) => u.count), everyElement(1));
    });
  });

  group('draining', () {
    test('empties the buffer, so a window is never counted twice', () {
      final buffer = build()..record([id('hablar')], langCode: 'es');

      expect(buffer.drain('es'), hasLength(1));
      expect(buffer.drain('es'), isEmpty);
      expect(buffer.isEmpty, isTrue);
    });

    test('a buffer that heard nothing drains nothing', () {
      expect(build().drain('es'), isEmpty);
    });
  });

  group('a failed write', () {
    test('is retried, not lost', () {
      // `drain` empties the buffer, so a store error between the drain and the
      // write would silently lose the window rather than retry it.
      final buffer = build()..record([id('hablar')], langCode: 'es');
      final drained = buffer.drain('es');

      buffer.restore('es', drained);

      expect(buffer.drain('es').single.count, 1);
    });

    test('restored rows stay older than anything recorded since', () {
      final buffer = build()..record([id('hablar')], langCode: 'es');
      final drained = buffer.drain('es');
      clock = clock.add(const Duration(minutes: 1));
      buffer.record([id('comer')], langCode: 'es');

      buffer.restore('es', drained);

      expect(buffer.drain('es').map((u) => u.lemma), ['hablar', 'comer']);
    });

    test('cannot grow without bound while the store stays down', () {
      // Otherwise an outage grows this on the device until it is killed.
      final buffer = build();
      for (var i = 0; i < ListeningExposureBuffer.maxHeldRows + 50; i++) {
        buffer.record([id('lemma$i')], langCode: 'es');
      }

      buffer.restore('es', buffer.drain('es'));

      expect(
        buffer.drain('es'),
        hasLength(ListeningExposureBuffer.maxHeldRows),
      );
    });

    test('drops the OLDEST rows when it has to drop some', () {
      final buffer = build();
      for (var i = 0; i < ListeningExposureBuffer.maxHeldRows + 1; i++) {
        buffer.record([id('lemma$i')], langCode: 'es');
      }

      buffer.restore('es', buffer.drain('es'));

      expect(
        buffer.drain('es').first.lemma,
        'lemma1',
        reason: 'lemma0 was the oldest and is the one dropped',
      );
    });
  });

  group('language', () {
    test('a drain returns only the language it asked for', () {
      // The whole point. A stored use carries no language of its own, so a
      // French hearing handed to a Spanish drain is filed as Spanish vocabulary
      // and nothing downstream can tell it apart again.
      final buffer = build();

      buffer.record([id('hablar')], langCode: 'es');
      buffer.record([id('parler')], langCode: 'fr');

      expect(buffer.drain('es').map((u) => u.lemma), ['hablar']);
      expect(buffer.drain('fr').map((u) => u.lemma), ['parler']);
    });

    test('a language nobody drains is held, never handed to another', () {
      final buffer = build()..record([id('parler')], langCode: 'fr');

      expect(buffer.drain('es'), isEmpty);
      expect(buffer.pendingExposuresFor('fr'), 1);
    });

    test('the same lemma in two languages stays two rows', () {
      // "bank" is a word in several languages and means different things in
      // each. Merging them on lemma alone would blend two learners' worth of
      // vocabulary into one.
      final buffer = build();

      buffer.record([id('bank')], langCode: 'en');
      buffer.record([id('bank')], langCode: 'nl');

      expect(buffer.drain('en').single.count, 1);
      expect(buffer.drain('nl').single.count, 1);
    });

    test('a regional variant is the same language as its base', () {
      // Analytics partitions by language, not by locale: es-MX and es are one
      // room, so they must be one bucket.
      final buffer = build();

      buffer.record([id('hablar')], langCode: 'es-MX');
      buffer.record([id('hablar')], langCode: 'es');

      expect(buffer.drain('es-ES').single.count, 2);
    });

    test('an empty language records nothing rather than guessing', () {
      final buffer = build()..record([id('hablar')], langCode: '');

      expect(buffer.pendingExposures, 0);
    });

    test('languages heard long ago are evicted rather than held forever', () {
      // Exposure in a language that never becomes the L2 is never drained by
      // anyone, so without a ceiling a multilingual room accumulates a bucket
      // set per language for the life of the session.
      final buffer = build();
      for (var i = 0; i < ListeningExposureBuffer.maxLanguages + 3; i++) {
        buffer.record([id('word$i')], langCode: 'l$i');
      }

      expect(
        buffer.heldLanguages,
        hasLength(ListeningExposureBuffer.maxLanguages),
      );
      expect(
        buffer.pendingExposuresFor('l0'),
        0,
        reason: 'the least recently heard language is the one dropped',
      );
      expect(buffer.pendingExposuresFor('l10'), 1);
    });

    test('re-hearing a language keeps it from being evicted', () {
      final buffer = build();
      buffer.record([id('word0')], langCode: 'l0');
      for (var i = 1; i < ListeningExposureBuffer.maxLanguages; i++) {
        buffer.record([id('word$i')], langCode: 'l$i');
      }
      buffer.record([id('again')], langCode: 'l0');
      buffer.record([id('newest')], langCode: 'zz');

      expect(
        buffer.pendingExposuresFor('l0'),
        2,
        reason: 'touched most recently',
      );
      expect(buffer.pendingExposuresFor('l1'), 0, reason: 'now the oldest');
    });

    test('a language that is never drained still cannot grow unbounded', () {
      final buffer = build();
      for (var i = 0; i < ListeningExposureBuffer.maxHeldRows + 20; i++) {
        buffer.record([id('lemma$i')], langCode: 'fr');
        clock = clock.add(ListeningExposureBuffer.window);
      }

      // The cap bounds CLOSED rows; the window still open on top of it is
      // bounded by how many distinct lemmas one five-minute window can hold,
      // which is speech, not storage. What matters is that 5020 recordings do
      // not leave 5020 rows held.
      expect(
        buffer.pendingExposuresFor('fr'),
        lessThanOrEqualTo(ListeningExposureBuffer.maxHeldRows + 1),
      );
    });
  });

  group('restoring after a failed write', () {
    test('moves the restored language to the front of the eviction queue', () {
      // A restore is evidence this language IS the one being drained — the
      // learner's L2. Left at its original position it is the OLDEST entry, so
      // the next new language evicts it: the buffer drops the one language
      // somebody is about to ask for and keeps the ones nobody will.
      final buffer = build()..record([id('hablar')], langCode: 'es');
      for (var i = 0; i < ListeningExposureBuffer.maxLanguages - 1; i++) {
        buffer.record([id('word$i')], langCode: 'l$i');
      }

      buffer.restore('es', buffer.drain('es'));
      buffer.record([id('neu')], langCode: 'de');

      expect(buffer.heldLanguages, contains('es'));
      expect(buffer.pendingExposuresFor('es'), 1);
      expect(
        buffer.heldLanguages,
        isNot(contains('l0')),
        reason: 'the genuinely oldest language is the one evicted',
      );
    });

    test('does not push the buffer past the language cap', () {
      final buffer = build()..record([id('hablar')], langCode: 'es');
      final drained = buffer.drain('es');
      for (var i = 0; i < ListeningExposureBuffer.maxLanguages; i++) {
        buffer.record([id('word$i')], langCode: 'l$i');
      }

      buffer.restore('es', drained);

      expect(
        buffer.heldLanguages,
        hasLength(ListeningExposureBuffer.maxLanguages),
      );
      expect(buffer.pendingExposuresFor('es'), 1);
    });
  });

  group('per-account registry', () {
    test('keeps accounts apart', () {
      ListeningExposureBuffer.forAccount(
        '@a:server',
      )!.record([id('hablar')], langCode: 'es');

      expect(
        ListeningExposureBuffer.forAccount('@b:server')!.pendingExposures,
        0,
      );
      expect(
        ListeningExposureBuffer.forAccount('@a:server')!.pendingExposures,
        1,
      );
    });

    test('an unknown account has no buffer, so nothing is misattributed', () {
      expect(ListeningExposureBuffer.forAccount(''), isNull);
    });

    test('disposing an account drops its buffer', () {
      ListeningExposureBuffer.forAccount(
        '@a:server',
      )!.record([id('hablar')], langCode: 'es');
      ListeningExposureBuffer.disposeAccount('@a:server');

      expect(
        ListeningExposureBuffer.forAccount('@a:server')!.pendingExposures,
        0,
      );
    });
  });
}
