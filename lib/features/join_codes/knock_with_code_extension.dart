import 'dart:convert';

import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

extension on Api {
  Future<KnockSpaceResponse> knockSpace(String code) async {
    final requestUri = Uri(path: '_synapse/client/pangea/v1/knock_with_code');
    final request = Request('POST', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    request.bodyBytes = utf8.encode(jsonEncode({'access_code': code}));
    final response = await httpClient.send(request);
    // Read the body up front — the stream can only be consumed once, and the
    // error path now needs it too (to detect the banned-from-every-room 403).
    final responseString = utf8.decode(await response.stream.toBytes());
    if (response.statusCode != 200) {
      // A valid code where the user is banned from every matched room comes
      // back as 403 ORG.PANGEA.BANNED_FROM_ROOM: surface it as a typed
      // exception so the join flow can show a ban-specific message instead of
      // the generic "code not found" (#7592). Anything else keeps throwing the
      // raw response (downstream 429 handling still reads its statusCode).
      final banned = BannedFromRoomException.fromErrorBody(responseString);
      if (banned != null) throw banned;
      throw response;
    }

    return KnockSpaceResponse.fromJson(jsonDecode(responseString));
  }
}

extension KnockSpaceExtension on Client {
  Future<KnockSpaceResponse> knockWithCode(String code) => knockSpace(code);
}

class KnockSpaceResponse {
  final List<String> roomIds;
  final List<String> alreadyJoined;

  /// Rooms the code matched but the user is banned from — present on a mixed
  /// 200 outcome alongside [roomIds] / [alreadyJoined] (#7592).
  final List<String> banned;

  KnockSpaceResponse({
    required this.roomIds,
    required this.alreadyJoined,
    this.banned = const [],
  });

  factory KnockSpaceResponse.fromJson(Map<String, dynamic> json) {
    return KnockSpaceResponse(
      roomIds: List<String>.from(json['rooms'] ?? []),
      alreadyJoined: List<String>.from(json['already_joined'] ?? []),
      banned: List<String>.from(json['banned'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rooms': roomIds,
      'already_joined': alreadyJoined,
      'banned': banned,
    };
  }
}

/// Thrown when `/knock_with_code` reports the code is valid but the user is
/// banned from every matched room (403 `ORG.PANGEA.BANNED_FROM_ROOM`). The join
/// flow maps this to a ban-specific message rather than "code not found"
/// (#7592).
class BannedFromRoomException implements Exception {
  /// The room ids the user is banned from, from the error body's `banned` list.
  final List<String> banned;

  BannedFromRoomException({this.banned = const []});

  /// The server errcode that signals this case.
  static const String errcode = 'ORG.PANGEA.BANNED_FROM_ROOM';

  /// Parse a non-200 `/knock_with_code` body: returns a [BannedFromRoomException]
  /// when the body carries [errcode], else null (the caller then falls back to
  /// throwing the raw response). Never throws — a non-JSON or unexpected body
  /// yields null. Pure, so it can be unit-tested directly.
  static BannedFromRoomException? fromErrorBody(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic> && json['errcode'] == errcode) {
        return BannedFromRoomException(
          banned: List<String>.from(json['banned'] ?? const []),
        );
      }
    } catch (_) {
      // Non-JSON or unexpected shape — fall through to the raw-response path.
    }
    return null;
  }

  @override
  String toString() => 'BannedFromRoomException(banned: $banned)';
}
