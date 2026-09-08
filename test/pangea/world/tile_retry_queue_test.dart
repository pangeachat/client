import 'dart:async';

import 'package:flutter/painting.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/tile_retry_queue.dart';
import 'package:fluffychat/routes/world/world_map_constants.dart';

/// A tile that counts load attempts instead of fetching anything. [onLoad]
/// stands in for the outcome: re-scheduling itself from there is a load that
/// failed again, leaving it unset is one that succeeded.
class _CountingTile extends TileImage {
  int loads = 0;
  void Function(TileImage tile)? onLoad;

  _CountingTile()
    : super(
        vsync: const TestVSync(),
        coordinates: const TileCoordinates(0, 0, 0),
        imageProvider: MemoryImage(TileProvider.transparentImage),
        onLoadComplete: (_) {},
        onLoadError: (_, _, _) {},
        tileDisplay: const TileDisplay.instantaneous(),
        errorImage: null,
        cancelLoading: Completer<void>(),
      );

  @override
  void load() {
    loads++;
    onLoad?.call(this);
  }
}

void main() {
  const base = WorldMapConstants.tileRetryBaseDelay;
  const max = WorldMapConstants.tileRetryMaxDelay;
  const tick = Duration(milliseconds: 1);

  // #8844 — a tile that failed offline stays a hole for as long as it is on
  // screen, because flutter_map only ever loads tiles it has never tried. The
  // queue re-issues load() on those tiles with a backoff, so a returning
  // network fills the holes in place instead of after an app restart.
  group('TileRetryQueue (#8844)', () {
    late TileRetryQueue queue;

    // Disposed at the end of each body, not in tearDown: the test binding
    // rejects a still-pending timer before tearDown runs.
    setUp(() => queue = TileRetryQueue());

    testWidgets('retries after the base delay, doubling while it keeps failing '
        'and never waiting longer than the max delay', (tester) async {
      final tile = _CountingTile()..onLoad = queue.schedule;
      queue.schedule(tile);

      await tester.pump(base - tick);
      expect(tile.loads, 0);
      await tester.pump(tick);
      expect(tile.loads, 1);

      await tester.pump(base * 2 - tick);
      expect(tile.loads, 1, reason: 'the second retry waits twice as long');
      await tester.pump(tick);
      expect(tile.loads, 2);

      await tester.pump(base * 4);
      expect(tile.loads, 3);

      // base * 8 is past the ceiling, so from here every round is max apart.
      await tester.pump(max - tick);
      expect(tile.loads, 3, reason: 'the delay grows up to the max');
      await tester.pump(tick);
      expect(tile.loads, 4);
      await tester.pump(max);
      expect(tile.loads, 5, reason: 'the delay never exceeds the max');
      queue.dispose();
    });

    testWidgets('a clean round ends the episode: the next failure waits only '
        'the base delay again', (tester) async {
      final tile = _CountingTile()..onLoad = queue.schedule;
      queue.schedule(tile);
      await tester.pump(base);
      await tester.pump(base * 2);
      expect(tile.loads, 2);

      // The network is back: this round's load succeeds and nothing re-queues.
      tile.onLoad = null;
      await tester.pump(base * 4);
      expect(tile.loads, 3);
      await tester.pump(max);
      expect(tile.loads, 3);

      // A later outage starts a fresh episode at the base delay.
      queue.schedule(tile);
      await tester.pump(base);
      expect(tile.loads, 4);
      queue.dispose();
    });

    testWidgets('retryNow retries at once and restarts the backoff', (
      tester,
    ) async {
      queue.retryNow(); // Nothing queued: a no-op.

      final tile = _CountingTile()..onLoad = queue.schedule;
      queue.schedule(tile);
      await tester.pump(base);
      await tester.pump(base * 2);
      expect(tile.loads, 2);

      queue.retryNow();
      expect(tile.loads, 3, reason: 'no wait on resume');

      // Backoff restarted: the follow-up round is the second step, not the
      // fourth the episode had reached.
      await tester.pump(base * 2 - tick);
      expect(tile.loads, 3);
      await tester.pump(tick);
      expect(tile.loads, 4);
      queue.dispose();
    });

    testWidgets('queued tiles share one round', (tester) async {
      final first = _CountingTile();
      final second = _CountingTile();
      queue.schedule(first);
      await tester.pump(base ~/ 2);
      queue.schedule(second);
      await tester.pump(base ~/ 2);
      expect(first.loads, 1);
      expect(second.loads, 1, reason: 'rides the pending round');
      queue.dispose();
    });

    testWidgets('a pruned tile is dropped, and a fresh tile at the same '
        'coordinates is still retried', (tester) async {
      final pruned = _CountingTile();
      queue.schedule(pruned);
      pruned.dispose();
      final fresh = _CountingTile();
      queue.schedule(fresh);

      await tester.pump(base);
      expect(pruned.loads, 0);
      expect(fresh.loads, 1);
      queue.dispose();
    });

    testWidgets('dispose cancels the pending round', (tester) async {
      final tile = _CountingTile();
      queue.schedule(tile);
      queue.dispose();
      await tester.pump(max);
      expect(tile.loads, 0);
      queue.dispose();
    });
  });
}
