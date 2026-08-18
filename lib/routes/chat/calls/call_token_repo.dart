import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// A LiveKit connection grant: where to dial, and the token to dial it with.
class CallToken {
  /// WebSocket URL of the SFU, as returned by the authorization service. Dialled by
  /// the client directly, so it must be reachable from the device — not from the
  /// server that issued it.
  final String url;

  /// Short-lived LiveKit JWT scoped to one room and one identity.
  final String jwt;

  const CallToken({required this.url, required this.jwt});
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
    return CallToken(url: body['url'] as String, jwt: body['jwt'] as String);
  }
}
