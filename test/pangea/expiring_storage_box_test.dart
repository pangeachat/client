import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/utils/expiring_storage_box.dart';

/// [ExpiringStorageBox] backs the practice caches that sit on the message
/// toolbar hot path. What's pinned here: entries expire exactly at their TTL,
/// the expiry decision never deserializes any payload (an entry with a
/// payload nobody could parse survives a sweep untouched and is handed back
/// verbatim), and the full sweep runs once up front and then no more than once
/// per interval — not on every read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const box = 'expiring_storage_box_test';
  const payloadKey = 'payload';
  const ttl = Duration(minutes: 1);

  late DateTime clock;
  late ExpiringStorageBox cache;
  late GetStorage raw;

  setUpAll(() async {
    // GetStorage needs path_provider; stub the channel to a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('expiring_box_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init(box);
  });

  setUp(() async {
    raw = GetStorage(box);
    await raw.erase();
    clock = DateTime(2026, 8, 17, 12);
    cache = ExpiringStorageBox(
      box,
      ttl: ttl,
      payloadKey: payloadKey,
      now: () => clock,
    );
  });

  /// Writes an entry in the on-disk shape directly, bypassing [cache], so a
  /// test can plant entries with arbitrary timestamps and payloads.
  Future<void> plant(String key, DateTime at, dynamic payload) =>
      raw.write(key, {
        ExpiringStorageBox.timestampKey: at.toIso8601String(),
        payloadKey: payload,
      });

  group('expiry', () {
    test('an entry written now reads back until the TTL elapses', () async {
      await cache.write('k', {'v': 1});
      expect(cache.read('k'), {'v': 1});

      clock = clock.add(ttl);
      expect(cache.read('k'), {'v': 1}, reason: 'exactly at TTL is still live');

      clock = clock.add(const Duration(seconds: 1));
      expect(cache.read('k'), isNull, reason: 'past TTL is expired');
      expect(raw.hasData('k'), isFalse, reason: 'expired read drops the entry');
    });

    test('a missing key is a miss and leaves the box alone', () async {
      await cache.write('other', {'v': 1});
      expect(cache.read('nope'), isNull);
      expect(raw.getKeys<Iterable<String>>(), ['other']);
    });

    test('a malformed entry is a miss and is removed', () async {
      await raw.write('no-timestamp', {payloadKey: {}});
      await raw.write('bad-timestamp', {
        ExpiringStorageBox.timestampKey: 'yesterday-ish',
        payloadKey: {},
      });
      await raw.write('not-a-map', 42);
      await plant('payload-not-a-map', clock, 'nope');

      for (final key in [
        'no-timestamp',
        'bad-timestamp',
        'not-a-map',
        'payload-not-a-map',
      ]) {
        expect(cache.read(key), isNull, reason: key);
        expect(raw.hasData(key), isFalse, reason: '$key removed');
      }
    });

    test('remove and erase drop entries', () async {
      await cache.write('a', {});
      await cache.write('b', {});
      await cache.remove('a');
      expect(raw.hasData('a'), isFalse);
      expect(raw.hasData('b'), isTrue);
      await cache.erase();
      expect(raw.getKeys<Iterable<String>>(), isEmpty);
    });
  });

  group('no payload parse', () {
    test('sweep and read decide on the timestamp alone', () async {
      // Payloads that any real model's fromJson would choke on. If the expiry
      // path deserialized payloads, these entries would be treated as
      // malformed and dropped; instead the live one must survive verbatim.
      await plant('live-garbage', clock, {'definitely': 'not a model'});
      await plant(
        'stale-garbage',
        clock.subtract(ttl + const Duration(seconds: 1)),
        {'definitely': 'not a model'},
      );

      await cache.sweep();

      expect(raw.hasData('stale-garbage'), isFalse);
      expect(raw.hasData('live-garbage'), isTrue);
      expect(cache.read('live-garbage'), {'definitely': 'not a model'});
    });

    test('read returns the stored payload map without copying it', () async {
      await cache.write('k', {
        'nested': {'deep': 1},
      });
      final first = cache.read('k');
      final second = cache.read('k');
      expect(identical(first, second), isTrue);
      expect(identical(first, raw.read('k')[payloadKey]), isTrue);
    });
  });

  group('sweep cadence', () {
    test('first access sweeps, then at most once per interval', () async {
      final stale = clock.subtract(ttl + const Duration(seconds: 1));
      await plant('stale-1', stale, {});
      await plant('live', clock, {});

      // First access: full sweep runs.
      cache.read('live');
      await pumpEventQueue();
      expect(raw.hasData('stale-1'), isFalse);

      // Within the interval: an entry that goes stale is NOT swept on read of
      // an unrelated key.
      clock = clock.add(const Duration(seconds: 30));
      await plant('stale-2', stale, {});
      cache.read('live');
      await pumpEventQueue();
      expect(
        raw.hasData('stale-2'),
        isTrue,
        reason: 'no sweep inside interval',
      );

      // Reading the stale key itself still drops it (per-key expiry check).
      expect(cache.read('stale-2'), isNull);
      expect(raw.hasData('stale-2'), isFalse);

      // Once the interval has elapsed, the next access sweeps again.
      await plant('stale-3', stale, {});
      clock = clock.add(const Duration(seconds: 31));
      cache.read('live');
      await pumpEventQueue();
      expect(raw.hasData('stale-3'), isFalse, reason: 'sweep after interval');
    });

    test('sweep interval can be longer than the TTL', () async {
      final longSweep = ExpiringStorageBox(
        box,
        ttl: ttl,
        payloadKey: payloadKey,
        sweepInterval: const Duration(days: 1),
        now: () => clock,
      );
      await longSweep.write('k', {});
      await pumpEventQueue();

      clock = clock.add(ttl * 2);
      await plant('stale', clock.subtract(ttl * 2), {});
      longSweep.read('other');
      await pumpEventQueue();
      expect(raw.hasData('stale'), isTrue, reason: 'still inside interval');

      clock = clock.add(const Duration(days: 1));
      longSweep.read('other');
      await pumpEventQueue();
      expect(raw.hasData('stale'), isFalse);
    });

    test('a sweep clears every stale entry and keeps the live ones', () async {
      final stale = clock.subtract(ttl + const Duration(seconds: 1));
      for (var i = 0; i < 50; i++) {
        await plant('stale-$i', stale, {'i': i});
      }
      await plant('live', clock, {});

      await cache.sweep();

      expect(raw.getKeys<Iterable<String>>().toList(), ['live']);
    });
  });
}
