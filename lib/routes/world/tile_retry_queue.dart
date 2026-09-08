import 'dart:async';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/routes/world/world_map_constants.dart';

/// Re-fetches map tiles that failed on the learner's own connectivity, in
/// place, once the network is back (#8844).
///
/// flutter_map never retries a failed tile that stays on screen: its
/// `TileImageManager` only starts tiles that have never loaded, and an
/// `evictErrorTileStrategy` can only drop error tiles that sit outside the
/// pruning margin (`keepBuffer`) or at another zoom level. A tile that failed
/// offline therefore stays a hole for as long as it is in view — until the
/// app restarts. This queue re-issues `TileImage.load()` on those tiles, the
/// same call flutter_map's own `reloadImages` makes; the failed fetch already
/// evicted its image-cache entry (every failure path of
/// `NetworkTileImageProvider` does), so the call is a fresh request.
///
/// One timer serves the whole queue, doubling its delay from
/// [WorldMapConstants.tileRetryBaseDelay] to
/// [WorldMapConstants.tileRetryMaxDelay] while retries keep failing. Offline,
/// a retry fails on the device and never reaches the tile provider; on a
/// broken-but-connected network the backoff keeps the doomed requests sparse.
/// A round whose tiles all load ends the episode: the next tick finds nothing
/// queued and the delay resets. [retryNow] skips the wait for the moment the
/// network is most likely back — the app resuming.
///
/// Only connectivity failures belong here. An HTTP error status is the
/// provider's answer (world-map-tiles.instructions.md, "Blocking detection"),
/// and retrying it would hammer a provider that is saying no; the caller
/// leaves those to the eviction strategy.
class TileRetryQueue {
  /// By identity: `TileImage` compares by coordinates, and a tile flutter_map
  /// pruned and re-created at the same coordinates must not be mistaken for
  /// the disposed one already queued.
  final Set<TileImage> _failed = Set.identity();
  Timer? _timer;
  Duration _delay = WorldMapConstants.tileRetryBaseDelay;

  /// Queue [tile] for the next retry round. A pending round picks it up;
  /// otherwise one is scheduled at the current backoff delay.
  void schedule(TileImage tile) {
    _failed.add(tile);
    _timer ??= Timer(_delay, _retry);
  }

  /// Retry everything queued right now and restart the backoff from its base.
  void retryNow() {
    _timer?.cancel();
    _delay = WorldMapConstants.tileRetryBaseDelay;
    _retry();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _failed.clear();
  }

  void _retry() {
    _timer = null;
    if (_failed.isEmpty) {
      // The previous round came back clean: the episode is over.
      _delay = WorldMapConstants.tileRetryBaseDelay;
      return;
    }
    final round = _failed.toList();
    _failed.clear();
    // Re-arm before loading: a tile that fails again lands back in the queue
    // for this timer; if none does, it fires empty and resets the delay.
    _delay = _delay * 2 > WorldMapConstants.tileRetryMaxDelay
        ? WorldMapConstants.tileRetryMaxDelay
        : _delay * 2;
    _timer = Timer(_delay, _retry);
    for (final tile in round) {
      // A tile flutter_map pruned meanwhile is disposed (its cancelLoading
      // completed) and is created afresh if it comes back into view.
      if (!tile.cancelLoading.isCompleted) tile.load();
    }
  }
}
