import 'package:flutter/foundation.dart';

import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/widgets/matrix.dart';

/// Persisted negative cache of resource ids a backend confirmed gone (404),
/// with when — `{id: confirmedAt}` under one reserved key in a [GetStorage]
/// box.
///
/// In-session suppression of a confirmed 404 (`ActivityPlanRepo`'s removed
/// gate, `QuestRepo`'s outline memo) caps the loop at one fetch + one report
/// per id per app session — but every NEW session re-fetches and re-reports
/// every known-dead id, which is where the residual Sentry volume lives
/// (CLIENT-EB0, CLIENT-EFH, CLIENT-CY3; #8691). This class is the shared
/// cross-session half of the gate.
///
/// Retention ([retention]) is checked only at [load]: a verdict never lapses
/// mid-session, but the next session past the window re-checks, so a repaired
/// resource comes back without every user hard-refreshing. [clear] is the
/// explicit-refresh escape hatch, and a registered box is erased on logout and
/// language change ([MatrixState.pangeaController]'s storage-key registry).
///
/// A failed [load] or write degrades to in-session-only suppression — it must
/// never wedge the read path it gates.
class ConfirmedRemovedCache {
  ConfirmedRemovedCache({
    required this.boxName,
    required this.storageKey,
    required this.retention,
    required this.now,
  });

  final String boxName;

  /// Reserved key for the verdict map. When the box is shared with a repo's
  /// response cache, pick a name its response keys cannot collide with.
  final String storageKey;

  final Duration retention;

  /// Clock seam: retention is wall-clock, so tests would otherwise need real
  /// delays. Callers pass an indirection to their own settable seam.
  final DateTime Function() now;

  final Map<String, DateTime> _ids = {};

  /// Set by [clear]. Guards [_load]'s merge: an explicit refresh that runs
  /// before the load completes (a cold-start refresh) must not have the
  /// verdicts it just dropped resurrected by the load and re-persisted.
  bool _cleared = false;

  /// Loads the persisted verdicts once; awaited by [contains] so the fetch
  /// path a prior session's verdict must gate cannot race it.
  late final Future<void> load = _load();

  Future<void> _load() async {
    _register();
    try {
      await GetStorage.init(boxName);
      final raw = GetStorage(boxName).read(storageKey);
      if (raw is! Map || _cleared) return;
      final cutoff = now().subtract(retention);
      var lapsed = false;
      for (final entry in raw.entries) {
        final id = entry.key;
        final millis = entry.value;
        if (id is! String || millis is! int) continue;
        final confirmedAt = DateTime.fromMillisecondsSinceEpoch(millis);
        if (confirmedAt.isAfter(cutoff)) {
          // putIfAbsent: an id confirmed by THIS session before the load
          // finished keeps its fresher timestamp.
          _ids.putIfAbsent(id, () => confirmedAt);
        } else {
          lapsed = true;
        }
      }
      if (lapsed) _persist();
    } catch (_) {
      // Degrade to in-session suppression.
    }
  }

  /// Registers the box so logout / language change erase the verdicts with
  /// every other per-account box. Guarded: [load] can run before
  /// `MatrixState.pangeaController` exists (the gate deliberately does not
  /// depend on the controller), and an unguarded read would throw a
  /// `LateInitializationError` into the memoized [load] future — permanently,
  /// the trap documented on `ActivityPlanRepo._request` (CLIENT-D43). Re-run
  /// from [_persist], by which point the controller exists (a verdict is only
  /// marked after an authenticated fetch), so registration is never lost to an
  /// early load. Idempotent set-add.
  void _register() {
    if (MatrixState.isPangeaControllerInitialized) {
      MatrixState.pangeaController.registerStorageKey(boxName);
    }
  }

  /// Fire-and-forget write-through; suppression must never wait on disk.
  /// Sequenced behind [load] so a write cannot race the initial read.
  void _persist() {
    _register();
    load.whenComplete(() {
      GetStorage(boxName)
          .write(storageKey, {
            for (final entry in _ids.entries)
              entry.key: entry.value.millisecondsSinceEpoch,
          })
          .catchError((_) {});
    });
  }

  /// Whether [id] is confirmed gone — this session, or a prior one within
  /// [retention].
  Future<bool> contains(String id) async {
    await load;
    return _ids.containsKey(id);
  }

  /// [contains] without awaiting [load] — for synchronous gates reached from
  /// `build()`. On a cold start it cannot see not-yet-loaded verdicts; the
  /// async read path those gates drain into must call [contains].
  bool containsSync(String id) => _ids.containsKey(id);

  /// Records the backend's 404 verdict for [id].
  void mark(String id) {
    _ids[id] = now();
    _persist();
  }

  /// Drops the verdict for [id] — a successful fetch disproved it.
  void unmark(String id) {
    if (_ids.remove(id) != null) _persist();
  }

  /// Drops every verdict, persisted included — the explicit-refresh seam,
  /// which must never be suppressed.
  void clear() {
    _cleared = true;
    _ids.clear();
    _persist();
  }

  @visibleForTesting
  int get lengthForTesting => _ids.length;
}
