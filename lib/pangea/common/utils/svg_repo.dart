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
/// Successes persist for a day; failures are remembered for the session only,
/// so a moment offline doesn't blank an icon until tomorrow.
class SvgRepo {
  static final GetStorage _storage = GetStorage('svg_cache');

  /// In-flight and settled fetches, keyed by URL. Deduping here is what keeps
  /// a list of ~100 flags on a dead connection to one fetch and one report per
  /// URL instead of one per widget per rebuild (#8338).
  static final Map<String, Future<Result<String>>> _cache = {};

  static Future<Result<String>> get(String url) async {
    if (_cache.containsKey(url)) {
      return _cache[url]!;
    }

    final future = _fetch(url);
    _cache[url] = future;
    return future;
  }

  static Future<Result<String>> _fetch(String url) async {
    try {
      final cached = await _getCached(url);
      if (cached?.svg != null) return Result.value(cached!.svg!);

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        ErrorHandler.logError(
          e: Exception('Failed to load SVG: ${response.statusCode}'),
          data: {"url": url},
          level: SentryLevel.warning,
        );
        return Result.error(Exception('Failed to load SVG at $url'));
      }

      final String svgContent = response.body;

      await _setCached(url, svgContent);
      return Result.value(svgContent);
    } catch (e, stack) {
      ErrorHandler.logError(
        e: Exception('Error fetching SVG: $e'),
        data: {"url": url},
        s: stack,
        // A transport failure — offline, dropped connection, a blocked
        // request — is transient and the caller renders a fallback. Anything
        // else here is a bug in how we asked for the file.
        level: e is http.ClientException
            ? SentryLevel.warning
            : SentryLevel.error,
      );
      return Result.error(Exception('Failed to load SVG at $url'));
    }
  }

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
