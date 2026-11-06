import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart' show Client, Membership;

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Consumer of synapse-pangea-chat's `discussion_room` endpoint (#9647). The
/// server picks a discussion's room and writes the learner's seat, so two
/// learners arriving at once never overfill a room, and the learner is never
/// asked to pick one.
///
/// - `GET ?course_id=&activity_id=` previews the placement without joining:
///   `students` is how many students (never course admins or the bot) are in
///   the room opening it would put the learner in now; 0 for a new room.
/// - `POST {course_id, activity_id, version_id?}` places and joins the
///   learner, and answers the room's `room_id`. A new room pins
///   `version_id`, the plan version the learner was shown, as a roleplay
///   session does, so later edits never change its questions; the server
///   takes the room's image from the activity.
/// - `POST {room_id, action: end | continue}` ends or reopens the caller's
///   own seat in a discussion room: the server sets or clears its
///   `finished_at` and `archived_at` under the discussion's lock, so no
///   other seat can be lost. 403 when the caller has no seat there.
///
/// The first two answer 404 when the activity is not a discussion that
/// course's Missions list. Rooms are per course: two courses sharing a
/// discussion never share a room.
abstract class DiscussionRoomRepo {
  static const String _path = '/_synapse/client/pangea/v1/discussion_room';

  /// How long one request may take before it counts as failed, so a stalled
  /// server ends the Join wait with an error rather than leaving it open.
  static const Duration _requestTimeout = Duration(seconds: 20);

  /// How long Join waits for the room to reach this client after the server
  /// placed the learner. Running out is sync lag, not a failed join: the
  /// learner is placed, and the room opens once it lands.
  static const Duration _syncTimeout = Duration(seconds: 10);

  /// How many classmates are in the room Join would put the learner in. Null
  /// when [courseId] doesn't list [activityId] as a discussion: an answer, so not
  /// reported. A start page polls this, so a failure is reported once per
  /// session.
  static Future<Result<int?>> previewStudents(
    Client client, {
    required String courseId,
    required String activityId,
  }) async {
    try {
      final Map<String, Object?> json;
      try {
        json = await _send(
          client,
          'GET',
          queryParameters: {'course_id': courseId, 'activity_id': activityId},
        );
      } on PangeaHttpException catch (e) {
        // silent-ok: 404 is "this course doesn't list that discussion", an answer
        if (e.statusCode == 404) return Result.value(null);
        rethrow;
      }
      final students = json['students'];
      if (students is! int) {
        throw const FormatException('discussion_room preview without students');
      }
      return Result.value(students);
    } catch (e, s) {
      ErrorHandler.logErrorOnce(
        key: 'discussion_room_preview',
        e: e,
        s: s,
        data: {'courseId': courseId, 'activityId': activityId},
      );
      return Result.error(e, s);
    }
  }

  /// Places the learner in a room for [activityId] in [courseId] and returns
  /// its id once their join has reached this client. The room keeps the
  /// default notifications: a learner in a discussion hears every message
  /// until they end it.
  static Future<Result<String>> join(
    Client client, {
    required String courseId,
    required String activityId,
    String? versionId,
  }) async {
    try {
      final json = await _send(
        client,
        'POST',
        body: {
          'course_id': courseId,
          'activity_id': activityId,
          'version_id': ?versionId,
        },
      );
      final roomId = json['room_id'];
      if (roomId is! String) {
        throw const FormatException('discussion_room answered without room_id');
      }
      // The server can answer with a room the learner is already in (their
      // own, when this client didn't know it yet); it then writes nothing,
      // so no sync would come to wait for.
      if (client.getRoomById(roomId)?.membership != Membership.join) {
        try {
          await client
              .waitForRoomInSync(roomId, join: true)
              .timeout(_syncTimeout);
        } on TimeoutException {
          // silent-ok: sync lag after a successful placement; the room opens
          // once it lands
        }
      }
      return Result.value(roomId);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'courseId': courseId, 'activityId': activityId},
      );
      return Result.error(e, s);
    }
  }

  /// Ends ([ended]) or reopens the learner's own seat in discussion room
  /// [roomId]. Mutes and Chats follow in the caller.
  static Future<Result<void>> setSeatEnded(
    Client client, {
    required String roomId,
    required bool ended,
  }) async {
    try {
      await _send(
        client,
        'POST',
        body: {'room_id': roomId, 'action': ended ? 'end' : 'continue'},
      );
      return Result.value(null);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomId, 'ended': ended},
      );
      return Result.error(e, s);
    }
  }

  /// This call bypasses `Requests` (a Synapse endpoint, on the Matrix
  /// client's own session), so it raises the typed failure itself
  /// (repos-and-error-handling.instructions.md).
  static Future<Map<String, Object?>> _send(
    Client client,
    String method, {
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
  }) async {
    final homeserver = client.homeserver;
    final token = client.accessToken;
    if (homeserver == null || token == null) {
      throw StateError('discussion_room called without a session');
    }
    final request = Request(
      method,
      homeserver.resolveUri(Uri(path: _path, queryParameters: queryParameters)),
    );
    request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await client.httpClient
        .send(request)
        .then(Response.fromStream)
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw PangeaHttpException.fromResponse(response);
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, Object?>) {
      throw const FormatException('discussion_room answered a non-object');
    }
    return json;
  }
}
