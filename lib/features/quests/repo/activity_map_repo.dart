import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// World-map pins for a viewport, via the choreographer bbox endpoint
/// (`GET /v2/activities/bbox`). Always viewport-bounded — never the whole
/// library. CEFR band, completion, and free-text search are applied client-side
/// over the returned set in v1. See world-map-search.instructions.md.
class ActivityMapRepo {
  /// Thin pins whose coordinates fall within [bounds], optionally scoped to a
  /// target language [l2]. [l1] is passed only for pin-text localization.
  /// Returns up to [limit] placed activities; an empty list on any error so the
  /// map stays usable.
  static Future<List<QuestActivityCard>> bboxPins({
    required LatLngBounds bounds,
    String? l2,
    String? l1,
    int limit = 200,
  }) async {
    final params = <String, String>{
      'min_lat': '${bounds.south}',
      'min_lng': '${bounds.west}',
      'max_lat': '${bounds.north}',
      'max_lng': '${bounds.east}',
      if (l2 != null && l2.isNotEmpty) 'l2': l2,
      if (l1 != null && l1.isNotEmpty) 'l1': l1,
      'limit': '$limit',
    };
    final uri = Uri.parse(
      PApiUrls.activitiesBbox,
    ).replace(queryParameters: params);

    final response = await Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    ).get(url: uri.toString());
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
