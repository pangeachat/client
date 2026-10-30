import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// What a discussion card or pin opens (#9647): the learner's own room for the
/// discussion, else a room with space, else a new one. The server picks the
/// room and writes the learner's seat, so two learners arriving at once never
/// overfill a room (synapse-pangea-chat `discussion_room`). The learner is
/// never asked to pick one.
class DiscussionRoomService {
  const DiscussionRoomService._();

  /// The room id to open for [activityId] in [course], behind a loading
  /// dialog; null if that failed (the dialog shows why).
  static Future<String?> open(
    BuildContext context, {
    required Room course,
    required String activityId,
    Uri? imageUrl,
  }) async {
    final client = course.client;
    final own = client.discussionRoomsFor(activityId).firstOrNull;
    if (own != null) return own.id;
    final resp = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final roomId = await _requestRoom(
          client,
          courseId: course.id,
          activityId: activityId,
          imageUrl: imageUrl,
        );
        // The server joined the learner; wait for that join to reach this
        // client before opening the room.
        await client.waitForRoomInSync(roomId, join: true);
        await _mentionsOnly(client, roomId);
        return roomId;
      },
    );
    return resp.result;
  }

  static Future<String> _requestRoom(
    Client client, {
    required String courseId,
    required String activityId,
    Uri? imageUrl,
  }) async {
    final request = Request(
      'POST',
      client.homeserver!.resolveUri(
        Uri(path: '/_synapse/client/pangea/v1/discussion_room'),
      ),
    );
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${client.accessToken!}';
    request.body = jsonEncode({
      'course_id': courseId,
      'activity_id': activityId,
      if (imageUrl != null) 'avatar_url': imageUrl.toString(),
    });
    final response = await client.httpClient.send(request);
    final body = await response.stream.toBytes();
    if (response.statusCode != 200) {
      throw PangeaHttpException.fromStreamedResponse(request, response, body);
    }
    final json = jsonDecode(utf8.decode(body));
    final roomId = json is Map ? json['room_id'] : null;
    if (roomId is! String) {
      throw Exception('discussion_room answered without a room_id');
    }
    return roomId;
  }

  /// A discussion notifies the learner only when someone mentions them: they
  /// may have said their piece already.
  static Future<void> _mentionsOnly(Client client, String roomId) async {
    final room = client.getRoomById(roomId);
    if (room == null || room.pushRuleState == PushRuleState.mentionsOnly) {
      return;
    }
    try {
      await room.setPushRuleState(PushRuleState.mentionsOnly);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomId},
        level: SentryLevel.warning,
      );
    }
  }
}
