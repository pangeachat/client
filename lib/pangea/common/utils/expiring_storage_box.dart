import 'dart:async';

import 'package:get_storage/get_storage.dart';

/// A [GetStorage] box of TTL-stamped entries, where the expiry check never
/// deserializes the payload.
///
/// Every entry is stored as `{'timestamp': <ISO-8601>, <payloadKey>: <json>}`.
/// [read] and [sweep] look only at `timestamp` before deciding whether an
/// entry is live, and hand the raw payload map back untouched — the caller
/// owns model parsing, so it happens once, for the one key it asked for.
///
/// Expired entries are dropped when [read] hits them. Entries nobody reads
/// again are dropped by [sweep], which runs lazily: on the first access to the
/// box and then at most once per [sweepInterval] (throttled off [read]/[write]
/// rather than a timer, so there's nothing to cancel). Since [GetStorage]
/// rewrites the whole box file on every remove, keeping the sweep off the
/// per-read path matters as much as skipping the parse.
class ExpiringStorageBox {
  ExpiringStorageBox(
    String boxName, {
    required this.ttl,
    required this.payloadKey,
    Duration? sweepInterval,
    DateTime Function()? now,
  }) : _storage = GetStorage(boxName),
       sweepInterval = sweepInterval ?? ttl,
       _now = now ?? DateTime.now;

  static const String timestampKey = 'timestamp';

  final GetStorage _storage;

  /// How long after being written an entry stays live. An entry is expired
  /// once `now - timestamp > ttl`.
  final Duration ttl;

  /// The key the payload is stored under inside each entry.
  final String payloadKey;

  /// Minimum time between two full sweeps of the box.
  final Duration sweepInterval;

  final DateTime Function() _now;
  DateTime? _lastSweep;

  /// The payload written for [key], or null if there is none, it has expired,
  /// or the entry is malformed (the last two are removed from the box).
  ///
  /// Only the entry's timestamp is inspected; the payload is returned as the
  /// raw map it was written as.
  Map<String, dynamic>? read(String key) {
    _maybeSweep();
    final entry = _storage.read(key);
    if (entry == null) return null;

    final ts = _timestampOf(entry);
    if (ts == null || _isExpired(ts)) {
      _storage.remove(key);
      return null;
    }

    final payload = (entry as Map)[payloadKey];
    if (payload is! Map<String, dynamic>) {
      _storage.remove(key);
      return null;
    }
    return payload;
  }

  /// Stores [payload] under [key], stamped with the current time.
  Future<void> write(String key, Map<String, dynamic> payload) {
    _maybeSweep();
    return _storage.write(key, {
      timestampKey: _now().toIso8601String(),
      payloadKey: payload,
    });
  }

  Future<void> remove(String key) => _storage.remove(key);

  Future<void> erase() => _storage.erase();

  /// Removes every expired or malformed entry, inspecting timestamps only.
  Future<void> sweep() async {
    _lastSweep = _now();
    // The box loads its file asynchronously on construction; a sweep that
    // ran before that finished would see nothing and skip a whole interval.
    await _storage.initStorage;
    final expired = List<String>.from(_storage.getKeys()).where((key) {
      final ts = _timestampOf(_storage.read(key));
      return ts == null || _isExpired(ts);
    }).toList();
    // Issue every remove in the same microtask: GetStorage coalesces flushes
    // scheduled together, so the box file is rewritten once, not once per key.
    await Future.wait(expired.map(_storage.remove));
  }

  void _maybeSweep() {
    final last = _lastSweep;
    if (last != null && _now().difference(last) < sweepInterval) return;
    unawaited(sweep());
  }

  bool _isExpired(DateTime timestamp) => _now().difference(timestamp) > ttl;

  /// The entry's timestamp, or null when the entry isn't in the expected
  /// shape. Deliberately never touches [payloadKey].
  static DateTime? _timestampOf(dynamic entry) {
    if (entry is! Map) return null;
    final raw = entry[timestampKey];
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }
}
