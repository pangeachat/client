import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
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
        // client before opening the room. It keeps the default notifications:
        // a learner in a discussion hears every message until they end it.
        await client.waitForRoomInSync(roomId, join: true);
        return roomId;
      },
    );
    return resp.result;
  }

  /// Where opening [activityId] would put the learner now, without joining:
  /// the server's own placement rule, so the count is the room they land in.
  /// Throws on a failed read; the caller shows no count.
  static Future<DiscussionPlacement> preview(
    Client client, {
    required String courseId,
    required String activityId,
  }) async {
    final request = Request(
      'GET',
      client.homeserver!.resolveUri(
        Uri(
          path: '/_synapse/client/pangea/v1/discussion_room',
          queryParameters: {'course_id': courseId, 'activity_id': activityId},
        ),
      ),
    );
    request.headers['authorization'] = 'Bearer ${client.accessToken!}';
    final response = await client.httpClient.send(request);
    final body = await response.stream.toBytes();
    if (response.statusCode != 200) {
      throw PangeaHttpException.fromStreamedResponse(request, response, body);
    }
    final json = jsonDecode(utf8.decode(body));
    final students = json is Map ? json['students'] : null;
    if (students is! int) {
      throw Exception('discussion_room preview answered without students');
    }
    return DiscussionPlacement(
      roomId: json['room_id'] as String?,
      students: students,
      joined: json['joined'] == true,
    );
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
}

/// Where opening a discussion would put the learner: [roomId] (null for a new
/// room), its [students] (course admins and the bot never count), and whether
/// it is the learner's own room already.
class DiscussionPlacement {
  final String? roomId;
  final int students;
  final bool joined;

  const DiscussionPlacement({
    required this.roomId,
    required this.students,
    required this.joined,
  });
}
