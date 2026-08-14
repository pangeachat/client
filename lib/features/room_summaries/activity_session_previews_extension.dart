import 'dart:convert';

import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

/// Consumer of the Synapse `activity_session_previews` module — space-scoped
/// activity-session discovery. Given course-space ids, the server enumerates
/// each space's children, keeps only the activity-session rooms (optionally one
/// activity's), and returns their previews in the exact `room_preview` shape,
/// so parsing reuses [RoomSummariesResponse] unchanged. The caller must be a
/// joined member of each space; spaces the caller is not in are silently
/// dropped server-side. Contract: activity-session-previews.instructions.md
/// (synapse-pangea-chat).
///
/// Not yet wired into discovery — the world map and activity start page still
/// resolve sessions via the client-side hierarchy walk in
/// activity_session_discovery.dart until the adoption lands.
extension ActivitySessionPreviewsApi on Api {
  Future<RoomSummariesResponse> getActivitySessionPreviews(
    List<String> spaceIds, {
    String? activityId,
    required String? l1Code,
  }) async {
    final requestUri = Uri(
      path: '/_synapse/client/pangea/v1/activity_session_previews',
      queryParameters: {'rooms': spaceIds.join(","), 'activity': ?activityId},
    );
    final request = Request('GET', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    final responseString = utf8.decode(responseBody);
    if (response.statusCode != 200) {
      throw PangeaHttpException.fromStreamedResponse(
        request,
        response,
        responseBody,
      );
    }
    final json = jsonDecode(responseString);
    return RoomSummariesResponse.fromJson(json, l1Code: l1Code);
  }
}

extension ActivitySessionPreviewsRequest on Client {
  /// Previews of the activity-session rooms under [spaceIds] (the learner's
  /// joined course spaces), keyed by room id — one request per batch of 50
  /// spaces, mirroring [RoomSummaryRequest.loadRoomSummaries]. A session shared
  /// into several requested courses comes back in each space's batch; the
  /// map merge deduplicates it by room id.
  Future<Map<String, RoomSummaryResponse>> loadActivitySessionPreviews(
    List<String> spaceIds, {
    String? activityId,
    required String? l1Code,
  }) async {
    final batches = _batchSpaceIdRequests(spaceIds);
    final responses = await Future.wait(
      batches.map(
        (b) => getActivitySessionPreviews(
          b,
          activityId: activityId,
          l1Code: l1Code,
        ),
      ),
    );
    return {for (final r in responses) ...r.summaries};
  }

  List<List<String>> _batchSpaceIdRequests(List<String> spaceIds) {
    const int batchSize = 50;
    return [
      for (var i = 0; i < spaceIds.length; i += batchSize)
        spaceIds.sublist(i, (i + batchSize).clamp(0, spaceIds.length)),
    ];
  }
}
