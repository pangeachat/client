import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class _SvgCacheEntry {
  final int timestamp;
  final String? svg;

  _SvgCacheEntry(this.svg, this.timestamp);

  Map<String, dynamic> toJson() => {'svg': svg, 'timestamp': timestamp};

  factory _SvgCacheEntry.fromJson(Map<String, dynamic> json) {
    return _SvgCacheEntry(json['svg'] as String?, json['timestamp'] as int);
  }

  static const Duration cacheDuration = Duration(days: 1);

  bool get isExpired => DateTime.fromMillisecondsSinceEpoch(
    timestamp,
  ).isBefore(DateTime.now().subtract(cacheDuration));
}

/// Fetches SVG assets and owns their failures, per the repo contract in
/// repos-and-error-handling.instructions.md: nothing escapes to the caller as a
/// thrown exception, and each failure is reported to Sentry exactly once.
///
/// Successes persist for a day; a failure is held only briefly
/// ([_retryFailedAfter]), so a moment offline doesn't blank an icon until
/// tomorrow — or, as it did, for the rest of the session (#9080).
///
/// Fetches share one pooled client and run under a concurrency cap, because the
/// language lists ask for every row at once.
class SvgRepo {
  static final GetStorage _storage = GetStorage('svg_cache');

  /// One client for every SVG fetch. The top-level `http.get` wraps each call
  /// in a `Client` of its own and closes it again, so nothing was ever pooled:
  /// a screen of flags paid for a DNS resolution and a TLS handshake per asset
  /// (#9080).
  static http.Client? _client;

  /// The zone [_client] was built in. `http.Client()` resolves through
  /// `runWithClient`'s zone-local factory, so a pooled client is only valid
  /// inside the zone that supplied it — keeping one past that boundary would
  /// hand one test's mock to the next. The app runs in a single zone, so this
  /// costs one comparison and still pools for the life of the session.
  static Zone? _clientZone;

  static http.Client get _pooled {
    if (_client == null || _clientZone != Zone.current) {
      _client = http.Client();
      _clientZone = Zone.current;
    }
    return _client!;
  }

  /// How many fetches may be in flight at once. A language list asks for every
  /// row in a single frame — up to 67 URLs — and unbounded that is 67
  /// simultaneous connections to one host, which a phone surfaces as DNS
  /// failures, connection resets and 504s rather than as slowness (#9080).
  static const int _maxConcurrent = 6;
  static int _inFlight = 0;
  static final List<Completer<void>> _waiting = [];

  /// How long a failed URL is left alone before another caller may retry it.
  /// Without a retry, one bad moment leaves the fallback in place until the app
  /// restarts; without the delay, a list rebuilding while offline would refetch
  /// on every frame — the storm #8338 fixed. The Sentry report stays once per
  /// URL per session regardless, so a retry cannot reopen that either.
  static const Duration _retryFailedAfter = Duration(seconds: 30);
  static final Map<String, DateTime> _failedAt = {};

  /// Ages every recorded failure past [_retryFailedAfter], so a test can assert
  /// the retry without sleeping through the cooldown.
  @visibleForTesting
  static void expireFailuresForTest() {
    final aged = DateTime.now().subtract(_retryFailedAfter);
    for (final url in _failedAt.keys.toList()) {
      _failedAt[url] = aged;
    }
  }

  /// In-flight and settled fetches, keyed by URL. Deduping here is what keeps
  /// a list of ~100 flags on a dead connection to one fetch and one report per
  /// URL instead of one per widget per rebuild (#8338).
  static final Map<String, Future<Result<String>>> _cache = {};

  /// The settled half of [_cache]. A widget that lays itself out differently
  /// for a missing asset needs the answer while it builds, not a frame later.
  static final Map<String, Result<String>> _settled = {};

  /// The outcome of this session's fetch of [url], or null if it hasn't been
  /// fetched yet or is still in flight.
  static Result<String>? peek(String url) => _settled[url];

  static Future<Result<String>> get(String url) async {
    final failedAt = _failedAt[url];
    if (failedAt != null &&
        DateTime.now().difference(failedAt) >= _retryFailedAfter) {
      _failedAt.remove(url);
      _cache.remove(url);
      _settled.remove(url);
    }

    if (_cache.containsKey(url)) {
      return _cache[url]!;
    }

    final future = _fetch(url).then((result) {
      _settled[url] = result;
      if (result.isError) _failedAt[url] = DateTime.now();
      return result;
    });
    _cache[url] = future;
    return future;
  }

  /// [url] fetched over the pooled client, under [_maxConcurrent].
  static Future<http.Response> _send(String url) async {
    await _acquire();
    try {
      return await _pooled.get(Uri.parse(url));
    } finally {
      _release();
    }
  }

  static Future<void> _acquire() {
    if (_inFlight < _maxConcurrent) {
      _inFlight++;
      return Future.value();
    }
    final slot = Completer<void>();
    _waiting.add(slot);
    return slot.future;
  }

  static void _release() {
    // The slot is handed straight to the next waiter rather than given up and
    // retaken, so the cap stays saturated while anything is still queued.
    if (_waiting.isEmpty) {
      _inFlight--;
      return;
    }
    _waiting.removeAt(0).complete();
  }

  static Future<Result<String>> _fetch(String url) async {
    try {
      final cached = await _getCached(url);
      if (cached?.svg != null) return Result.value(cached!.svg!);

      final response = await _send(url);
      if (response.statusCode != 200) {
        // The url is in the message, not only in `data`: it is the title and
        // the searchable text in Sentry, and a status alone names no asset
        // (CLIENT-ECE). Grouping is by stack, so per-url text stays one issue.
        ErrorHandler.logErrorOnce(
          key: _reportKey(url),
          e: Exception('Failed to load SVG: ${response.statusCode} $url'),
          data: {"url": url},
          level: SentryLevel.warning,
        );
        return Result.error(Exception('Failed to load SVG at $url'));
      }

      final String svgContent = response.body;

      await _setCached(url, svgContent);
      return Result.value(svgContent);
    } catch (e, stack) {
      ErrorHandler.logErrorOnce(
        key: _reportKey(url),
        // A ClientException — offline, dropped connection, a blocked request —
        // keeps its type so the sink recognises a request that never reached a
        // server (severity table, no-response row: warning, once per session).
        // The real clients attach the uri; one that arrives without it is
        // given the url, since the title must always name the asset (#8733).
        // Anything else is a bug in how we asked for the file: wrapped so it
        // names the url too, and the table's default (error) stands.
        e: e is http.ClientException
            ? (e.uri == null
                  ? http.ClientException(e.message, Uri.parse(url))
                  : e)
            : Exception('Error fetching SVG $url: $e'),
        data: {"url": url},
        s: stack,
      );
      return Result.error(Exception('Failed to load SVG at $url'));
    }
  }

  /// One report per URL per session, so [_retryFailedAfter] buys a second
  /// attempt without buying a second Sentry event (#8338).
  static String _reportKey(String url) => 'svg-repo:$url';

  static Future<_SvgCacheEntry?> _getCached(String url) async {
    await GetStorage.init('svg_cache');
    final entry = _storage.read(url);
    if (entry == null) return null;

    try {
      final svg = _SvgCacheEntry.fromJson(entry);
      // A null body is a failure written by an older build; failures are no
      // longer persisted, so treat it as a miss and drop it.
      if (svg.isExpired || svg.svg == null) {
        await _storage.remove(url);
        return null;
      }
      return svg;
    } catch (_) {
      await _storage.remove(url);
      return null;
    }
  }

  static Future<void> _setCached(String url, String svg) async {
    if (svg.length > 5200000) {
      Logs().w('SVG content is very large, skipping cache for $url');
      return;
    }
    final entry = _SvgCacheEntry(svg, DateTime.now().millisecondsSinceEpoch);
    await _storage.write(url, entry.toJson());
  }
}
