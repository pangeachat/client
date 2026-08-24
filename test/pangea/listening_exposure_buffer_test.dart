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

      buffer.record([id('hablar')]);
      buffer.record([id('hablar')]);
      buffer.record([id('hablar')]);

      final drained = buffer.drain();

      expect(drained, hasLength(1));
      expect(drained.single.lemma, 'hablar');
      expect(drained.single.count, 3);
    });

    test('distinct lemmas get a row each', () {
      final buffer = build();

      buffer.record([id('hablar'), id('comer')]);
      buffer.record([id('hablar')]);

      final drained = buffer.drain();

      expect(drained, hasLength(2));
      expect(
        {for (final use in drained) use.lemma: use.count},
        {'hablar': 2, 'comer': 1},
      );
    });

    test('the same lemma under a different POS is a different construct', () {
      final buffer = build();

      buffer.record([id('bank', 'noun')]);
      buffer.record([id('bank', 'verb')]);

      expect(buffer.drain(), hasLength(2));
    });

    test('counts occurrences, not rows', () {
      final buffer = build();

      buffer.record([id('hablar'), id('comer')]);
      buffer.record([id('hablar')]);

      expect(buffer.pendingExposures, 3);
    });
  });

  group('the emitted row', () {
    test('is worth no XP', () {
      final buffer = build()..record([id('hablar')]);

      final use = buffer.drain().single;

      expect(use.useType, ConstructUseTypeEnum.hrd);
      expect(use.xp, 0);
    });

    test('carries no room id and no event id', () {
      // Not incidental: the listening lane drops both at collection because a
      // per-student record of which peers a learner attends to is a
      // third-party fact. A regression here is a privacy regression.
      final buffer = build()..record([id('hablar')]);

      final use = buffer.drain().single;

      expect(use.metadata.roomId, isNull);
      expect(use.metadata.eventId, isNull);
    });

    test('carries no form, because a bucket spans several', () {
      final buffer = build()..record([id('hablar')]);

      expect(buffer.drain().single.form, isNull);
    });

    test('is stamped with the last exposure in the bucket', () {
      // Engagement spans corroborate against construct-use timestamps within
      // ±10 minutes, so the stamp must be an instant the learner was really
      // active at — never a synthetic window boundary.
      final buffer = build();

      buffer.record([id('hablar')]);
      clock = clock.add(const Duration(minutes: 2));
      buffer.record([id('hablar')]);

      expect(
        buffer.drain().single.metadata.timeStamp,
        DateTime.utc(2026, 8, 24, 9, 2),
      );
    });
  });

  group('the window', () {
    test('keeps one bucket open while it has not elapsed', () {
      final buffer = build();

      buffer.record([id('hablar')]);
      clock = clock.add(
        ListeningExposureBuffer.window - const Duration(seconds: 1),
      );
      buffer.record([id('hablar')]);

      expect(buffer.drain(), hasLength(1));
    });

    test('closes the open bucket once it has elapsed', () {
      // The heartbeat normally closes a window by draining it. This bound is
      // what holds the ±10 minute invariant when the heartbeat is not running
      // — a suspended timer in the background.
      final buffer = build();

      buffer.record([id('hablar')]);
      final firstStamp = clock;
      clock = clock.add(ListeningExposureBuffer.window);
      buffer.record([id('hablar')]);

      final drained = buffer.drain();

      expect(drained, hasLength(2), reason: 'two windows, two rows');
      expect(drained.first.metadata.timeStamp, firstStamp);
      expect(drained.last.metadata.timeStamp, clock);
      expect(drained.map((u) => u.count), everyElement(1));
    });
  });

  group('draining', () {
    test('empties the buffer, so a window is never counted twice', () {
      final buffer = build()..record([id('hablar')]);

      expect(buffer.drain(), hasLength(1));
      expect(buffer.drain(), isEmpty);
      expect(buffer.isEmpty, isTrue);
    });

    test('a buffer that heard nothing drains nothing', () {
      expect(build().drain(), isEmpty);
    });
  });

  group('a failed write', () {
    test('is retried, not lost', () {
      // `drain` empties the buffer, so a store error between the drain and the
      // write would silently lose the window rather than retry it.
      final buffer = build()..record([id('hablar')]);
      final drained = buffer.drain();

      buffer.restore(drained);

      expect(buffer.drain().single.count, 1);
    });

    test('restored rows stay older than anything recorded since', () {
      final buffer = build()..record([id('hablar')]);
      final drained = buffer.drain();
      clock = clock.add(const Duration(minutes: 1));
      buffer.record([id('comer')]);

      buffer.restore(drained);

      expect(buffer.drain().map((u) => u.lemma), ['hablar', 'comer']);
    });

    test('cannot grow without bound while the store stays down', () {
      // Otherwise an outage grows this on the device until it is killed.
      final buffer = build();
      for (var i = 0; i < ListeningExposureBuffer.maxHeldRows + 50; i++) {
        buffer.record([id('lemma$i')]);
      }

      buffer.restore(buffer.drain());

      expect(buffer.drain(), hasLength(ListeningExposureBuffer.maxHeldRows));
    });

    test('drops the OLDEST rows when it has to drop some', () {
      final buffer = build();
      for (var i = 0; i < ListeningExposureBuffer.maxHeldRows + 1; i++) {
        buffer.record([id('lemma$i')]);
      }

      buffer.restore(buffer.drain());

      expect(
        buffer.drain().first.lemma,
        'lemma1',
        reason: 'lemma0 was the oldest and is the one dropped',
      );
    });
  });

  group('per-account registry', () {
    test('keeps accounts apart', () {
      ListeningExposureBuffer.forAccount('@a:server')!.record([id('hablar')]);

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
      ListeningExposureBuffer.forAccount('@a:server')!.record([id('hablar')]);
      ListeningExposureBuffer.disposeAccount('@a:server');

      expect(
        ListeningExposureBuffer.forAccount('@a:server')!.pendingExposures,
        0,
      );
    });
  });
}
