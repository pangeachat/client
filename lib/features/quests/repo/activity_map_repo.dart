import 'dart:convert';

import 'package:async/async.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// World-map pins for a viewport, via the choreographer bbox endpoint
/// (`GET /v2/activities/bbox`). Always viewport-bounded — never the whole
/// library. CEFR band, completion, and free-text search are applied client-side
/// over the returned set in v1. See world-map.instructions.md.
class ActivityMapRepo {
  /// Thin pins whose coordinates fall within [bounds], optionally scoped to a
  /// target language [l2]. With [l1] (the resolved display language), each
  /// card's title/description/learning objective comes back localized from
  /// persisted translation rows, falling back to canonical per card where no
  /// row exists yet — so search matches what the learner sees (#8398, choreo
  /// #3037). Omitting [l1] returns canonical text. Returns up to [limit]
  /// placed activities.
  ///
  /// **Never throws.** Every failure comes back as [Result.error], captured to
  /// Sentry here exactly once (repos-and-error-handling.instructions.md). This
  /// read has no owned future — the world map fires it from `onMapReady` and
  /// from each camera settle without awaiting — so anything thrown past this
  /// point is an unhandled async error rather than a caught one. On web that
  /// meant a raw `ClientException: Failed to fetch` reaching the browser's
  /// global `onerror` handler and landing in Sentry unhandled, with only
  /// `Error._throw` to group on, so it shared one issue with every other
  /// unhandled fetch failure in the app (CLIENT-B01, #8473).
  ///
  /// Two errors the caller is expected to tell apart from a *successful* empty
  /// list — which means the viewport genuinely holds no activities:
  ///
  /// - [RateLimitedException] — choreo rate-limited us and
  ///   [RateLimitPause.choreo] is running (#8360), so the read was never
  ///   made. Panning is what fires this read, so a per-viewport backoff would
  ///   be no backoff at all; instead the pause itself reports the
  ///   suppression once per activation via
  ///   [RateLimitPause.reportSuppressionOnce] (client#8507), not once per
  ///   suppressed viewport read.
  /// - anything else — the read was made and failed.
  ///
  /// Either way the caller must keep the pins it already has rather than blank
  /// the map, which is why neither is an empty list.
  static Future<Result<List<QuestActivityCard>>> bboxPins({
    required LatLngBounds bounds,
    String? l2,
    String? l1,
    int limit = 200,
  }) async {
    if (RateLimitPause.choreo.isPaused) {
      RateLimitPause.choreo.reportSuppressionOnce({
        'min_lat': bounds.south,
        'min_lng': bounds.west,
        'max_lat': bounds.north,
        'max_lng': bounds.east,
        if (l2 != null && l2.isNotEmpty) 'l2': l2,
        if (l1 != null && l1.isNotEmpty) 'l1': l1,
      });
      return Result.error(RateLimitedException());
    }
    final params = <String, String>{
      'min_lat': '${bounds.south}',
      'min_lng': '${bounds.west}',
      'max_lat': '${bounds.north}',
      'max_lng': '${bounds.east}',
      if (l2 != null && l2.isNotEmpty) 'l2': l2,
      if (l1 != null && l1.isNotEmpty) 'l1': l1,
      'limit': '$limit',
    };

    try {
      final uri = Uri.parse(
        PApiUrls.activitiesBbox,
      ).replace(queryParameters: params);
      final response = await Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
      ).get(url: uri.toString());
      if (response.statusCode != 200) return Result.value(const []);

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return Result.value(const []);
      return Result.value(
        decoded
            .whereType<Map<String, dynamic>>()
            .map(QuestActivityCard.fromBboxCard)
            .where((card) => card.point != null)
            .toList(),
      );
    } catch (e, s) {
      // Before the report, so the pause is armed even if reporting throws.
      RateLimitPause.choreo.recordFailure(e);
      // Decoding and card mapping sit inside the try with the request on
      // purpose: they run on a future nobody awaits too, so a malformed body
      // escaped exactly as far as a failed fetch did.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: params,
        level: PangeaHttpException.severityOf(e),
      );
      return Result.error(e);
    }
  }
}
