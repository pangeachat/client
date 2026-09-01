import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// What a call token says about this device's permission to publish its own
/// participant attributes.
///
/// The attributes are how one of an account's devices tells its siblings what
/// it can do and what it is doing, which is the whole input to the recorder
/// election. A token without the permission makes every one of those writes
/// fail, and the failure is invisible from the SFU's side: the siblings simply
/// never hear anything, which reads exactly like a device that has nothing to
/// say.
enum MetadataGrant {
  /// The video grant carries `canUpdateOwnMetadata`.
  granted,

  /// The video grant was read, and does not carry it.
  absent,

  /// Nothing could be read — the token is not a decodable JWT, or it carries no
  /// video grant object at all.
  ///
  /// DELIBERATELY NOT [absent]. An authorization service that shapes its claims
  /// differently, or a token this build cannot parse, is not evidence that a
  /// permission was withheld; reporting it as one would fire on every such
  /// deployment forever. Absence is asserted only when the object it would have
  /// been in was actually read.
  unknown,
}

/// A LiveKit connection grant: where to dial, and the token to dial it with.
class CallToken {
  /// WebSocket URL of the SFU, as returned by the authorization service. Dialled by
  /// the client directly, so it must be reachable from the device — not from the
  /// server that issued it.
  final String url;

  /// Short-lived LiveKit JWT scoped to one room and one identity.
  final String jwt;

  const CallToken({required this.url, required this.jwt});

  /// What [jwt] permits this device to say about itself.
  ///
  /// Derived rather than stored, so it cannot disagree with the token it
  /// describes: a field would let a caller construct a grant that says one thing
  /// and a token that says another.
  MetadataGrant get metadataGrant => readMetadataGrant(jwt);

  /// The claim a device needs to publish its own participant attributes.
  static const ownMetadataClaim = 'canUpdateOwnMetadata';

  /// Reads [ownMetadataClaim] out of a LiveKit JWT's video grant.
  ///
  /// A JWT payload is plain base64url JSON — no signature check is possible or
  /// wanted here, because this is not authenticating anything. It is reading
  /// what we were handed, so that a permission the feature depends on is
  /// checked at the moment it is issued rather than discovered as a silent
  /// write failure several seconds into a call.
  ///
  /// NEVER THROWS. Every way this can fail — a token that is not three
  /// segments, base64 that will not decode, JSON that is not an object —
  /// returns [MetadataGrant.unknown]. A call is worth more than knowing this,
  /// and a token that cannot be read is still a token that works.
  static MetadataGrant readMetadataGrant(String jwt) {
    try {
      final segments = jwt.split('.');
      // Header and payload; a signature may or may not follow, and this does
      // not care either way.
      if (segments.length < 2) return MetadataGrant.unknown;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      if (payload is! Map) return MetadataGrant.unknown;
      final video = payload['video'];
      // No video grant to read is UNKNOWN, not absent. See the enum.
      if (video is! Map) return MetadataGrant.unknown;
      return video[ownMetadataClaim] == true
          ? MetadataGrant.granted
          : MetadataGrant.absent;
    } catch (_) {
      return MetadataGrant.unknown;
    }
  }
}

class CallTokenException implements Exception {
  final String message;
  final int? statusCode;
  const CallTokenException(this.message, {this.statusCode});
  @override
  String toString() =>
      'CallTokenException($message${statusCode == null ? '' : ', status $statusCode'})';
}

/// Exchanges a Matrix identity for permission to join a call's media session.
///
/// Three hops, none of which the SDK performs: ask Synapse for an OpenID token, hand
/// that to the MatrixRTC authorization service, receive a LiveKit JWT. The SDK stores
/// the service URL and never calls it, so this is app code by necessity rather than
/// by choice.
class CallTokenRepo {
  /// The session-throttle key the missing-grant report is filed under.
  ///
  /// Named rather than inlined so the report and the test that pins its budget
  /// spend the same string. A key that drifted between the two would leave the
  /// test asserting a throttle nothing uses.
  static const missingMetadataGrantKey = 'call_token.no_own_metadata_grant';

  final http.Client _http;
  final bool _ownsHttp;

  CallTokenRepo({http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null;

  /// Releases the HTTP client, but only if this repo created it.
  ///
  /// A caller that passed one in owns it and may still be using it — closing
  /// another object's client is how a shared client dies mid-request.
  void close() {
    if (_ownsHttp) _http.close();
  }

  /// Requests a grant for [roomId] on behalf of the logged-in user.
  ///
  /// [focusServiceUrl] is the authorization service base URL, from [RtcFocus].
  Future<CallToken> requestToken({
    required Client client,
    required String roomId,
    required String focusServiceUrl,
  }) async {
    final deviceId = client.deviceID;
    final userId = client.userID;
    if (deviceId == null || userId == null) {
      throw const CallTokenException('no device id; client is not logged in');
    }

    // The OpenID token is what proves Matrix identity to a service that is not the
    // homeserver. It is short-lived and single-purpose.
    final OpenIdCredentials openId;
    try {
      openId = await client.requestOpenIdToken(userId, {});
    } catch (e) {
      throw CallTokenException('could not obtain an OpenID token: $e');
    }

    return requestTokenWithOpenId(
      openIdAccessToken: openId.accessToken,
      openIdTokenType: openId.tokenType,
      matrixServerName: openId.matrixServerName,
      deviceId: deviceId,
      roomId: roomId,
      focusServiceUrl: focusServiceUrl,
    );
  }

  /// The exchange itself, with the homeserver round-trip already done.
  ///
  /// Split out so it can be tested without a logged-in SDK [Client] — constructing
  /// one needs a native database, which is a lot of apparatus to prove that a 403 is
  /// reported differently from an outage.
  Future<CallToken> requestTokenWithOpenId({
    required String openIdAccessToken,
    required String openIdTokenType,
    required String matrixServerName,
    required String deviceId,
    required String roomId,
    required String focusServiceUrl,
  }) async {
    final endpoint = Uri.parse(
      '${focusServiceUrl.replaceAll(RegExp(r'/+$'), '')}/sfu/get',
    );

    final http.Response res;
    try {
      res = await _http.post(
        endpoint,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'room': roomId,
          'openid_token': {
            'access_token': openIdAccessToken,
            'token_type': openIdTokenType,
            'matrix_server_name': matrixServerName,
          },
          'device_id': deviceId,
        }),
      );
    } catch (e) {
      throw CallTokenException(
        'could not reach the RTC service at $endpoint: $e',
      );
    }

    if (res.statusCode != 200) {
      // The service reports refusals as Matrix-shaped errors; surface the code so a
      // caller can tell "you may not create a room here" from "the SFU is down".
      String detail = res.body;
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['error'] is String) {
          detail = '${body['errcode'] ?? 'error'}: ${body['error']}';
        }
      } catch (_) {}
      throw CallTokenException(detail, statusCode: res.statusCode);
    }

    final body = jsonDecode(res.body);
    if (body is! Map || body['jwt'] is! String || body['url'] is! String) {
      throw const CallTokenException('RTC service returned no usable grant');
    }
    final token = CallToken(
      url: body['url'] as String,
      jwt: body['jwt'] as String,
    );
    _reportMissingMetadataGrant(token);
    return token;
  }

  /// Says once, per app session, that this deployment's tokens cannot publish
  /// attributes.
  ///
  /// Here rather than at the write that fails, because this is the only place
  /// that can tell WHY it will fail. From the roster's side a refused write and
  /// an unreachable SFU are the same thrown error, and only one of them is a
  /// deployment we have to change.
  ///
  /// Reported, never thrown. The token joins the call perfectly well without
  /// this claim; what it loses is the coordination between an account's own
  /// devices, and a call is worth more than that.
  ///
  /// One event per session, not one per token: tokens are minted per call and
  /// every one from a given deployment is shaped the same way, so the second
  /// report onwards is volume rather than signal. Sentry's affected-user count
  /// is what carries the size of it.
  ///
  /// Severity is left to [ErrorHandler]'s table, which reads this as an error.
  /// That is the right reading: nothing here is transient, and it stays true
  /// until the authorization service is changed.
  void _reportMissingMetadataGrant(CallToken token) {
    if (token.metadataGrant != MetadataGrant.absent) return;
    ErrorHandler.logErrorOnce(
      key: missingMetadataGrantKey,
      m:
          'The call token carries no ${CallToken.ownMetadataClaim} grant; this '
          "account's devices cannot tell each other what they are recording",
      // Claim NAMES only. They are fixed strings from the token service, and
      // the values beside them are not: a room grant carries the room.
      data: {'videoGrantClaims': _videoGrantClaims(token.jwt)},
    );
  }

  /// The claim names the video grant actually carries, for triage. Empty when
  /// the token could not be read, which is the case this never reports on.
  static List<String> _videoGrantClaims(String jwt) {
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(jwt.split('.')[1]))),
      );
      final video = (payload as Map)['video'];
      return (video as Map).keys.map((k) => k.toString()).toList()..sort();
    } catch (_) {
      return const [];
    }
  }
}
