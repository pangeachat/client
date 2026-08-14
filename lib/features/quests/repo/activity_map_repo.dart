import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// World-map pins for a viewport, via the choreographer bbox endpoint
/// (`GET /v2/activities/bbox`). Always viewport-bounded — never the whole
/// library. CEFR band, completion, and free-text search are applied client-side
/// over the returned set in v1. See world-map.instructions.md.
class ActivityMapRepo {
  /// Thin pins whose coordinates fall within [bounds], optionally scoped to a
  /// target language [l2]. Card text is canonical-only — thin lists never
  /// translate (choreo #2736); large-card titles localize via plan hydration.
  /// Returns up to [limit] placed activities.
  ///
  /// **Null means the read was not made** — choreo rate-limited us and
  /// [QuestRepo.activityReadPause] is running (#8360). Distinct from an empty
  /// list, which means the viewport genuinely holds no activities: the caller
  /// must keep the pins it already has rather than blank the map for the whole
  /// pause. Panning is what fires this read, so a per-viewport backoff would
  /// be no backoff at all.
  static Future<List<QuestActivityCard>?> bboxPins({
    required LatLngBounds bounds,
    String? l2,
    int limit = 200,
  }) async {
    if (QuestRepo.activityReadPause.isPaused) return null;
    final params = <String, String>{
      'min_lat': '${bounds.south}',
      'min_lng': '${bounds.west}',
      'max_lat': '${bounds.north}',
      'max_lng': '${bounds.east}',
      if (l2 != null && l2.isNotEmpty) 'l2': l2,
      'limit': '$limit',
    };
    final uri = Uri.parse(
      PApiUrls.activitiesBbox,
    ).replace(queryParameters: params);

    final http.Response response;
    try {
      response = await Requests(
        accessToken: MatrixState.pangeaController.userController.accessToken,
      ).get(url: uri.toString());
    } catch (e) {
      // Arms the shared pause, then lets the failure surface exactly as before
      // — this repo does not own the reporting or the empty-map fallback.
      QuestRepo.activityReadPause.recordFailure(e);
      rethrow;
    }
    if (response.statusCode != 200) return const [];

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(QuestActivityCard.fromBboxCard)
        .where((card) => card.point != null)
        .toList();
  }
}
