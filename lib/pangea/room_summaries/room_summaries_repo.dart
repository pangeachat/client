import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/room_summaries/room_summary_extension.dart';

class RoomSummariesRepo {
  final Client client;
  RoomSummariesRepo(this.client);

  static const int _batchSize = 50;

  Future<Map<String, RoomSummaryResponse>> loadRoomSummaries(
    List<String> roomIds,
  ) async {
    final batches = _batchRoomIdRequests(roomIds);
    final responses = await Future.wait(
      batches.map((b) => client.requestRoomSummaries(b)),
    );
    return {for (final r in responses) ...r.summaries};
  }

  List<List<String>> _batchRoomIdRequests(List<String> roomIds) => [
    for (var i = 0; i < roomIds.length; i += _batchSize)
      roomIds.sublist(i, (i + _batchSize).clamp(0, roomIds.length)),
  ];
}
