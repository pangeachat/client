import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';

/// Exercises the request this builds and the failures it has to distinguish.
///
/// The happy path is separately proven end to end against the running local stack
/// (Synapse -> lk-jwt-service -> LiveKit CreateRoom). What matters here is that a
/// refusal, an outage and a malformed grant stay distinguishable, since a caller has
/// to react differently to each and they all arrive as "no token".
void main() {
  late Uri captured;
  late Map<String, dynamic> sentBody;

  http.Client respondWith(int status, Object body) => MockClient((req) async {
    captured = req.url;
    sentBody = jsonDecode(req.body) as Map<String, dynamic>;
    return http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );
  });

  group('CallTokenRepo error handling', () {
    test('a refusal surfaces the service errcode, not a bare status', () async {
      final repo = CallTokenRepo(
        httpClient: respondWith(403, {
          'errcode': 'M_FORBIDDEN',
          'error': 'not permitted to create a room here',
        }),
      );

      await expectLater(
        () => repo.requestTokenWithOpenId(
          openIdAccessToken: 'tok',
          openIdTokenType: 'Bearer',
          matrixServerName: 'pangea.localhost',
          deviceId: 'DEV',
          roomId: '!r:pangea.localhost',
          focusServiceUrl: 'http://localhost:7980',
        ),
        throwsA(
          isA<CallTokenException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('M_FORBIDDEN')),
        ),
      );
    });

    test('an unreachable service is reported as unreachable', () async {
      final repo = CallTokenRepo(
        httpClient: MockClient((_) async => throw const SocketExceptionStub()),
      );

      await expectLater(
        () => repo.requestTokenWithOpenId(
          openIdAccessToken: 'tok',
          openIdTokenType: 'Bearer',
          matrixServerName: 'pangea.localhost',
          deviceId: 'DEV',
          roomId: '!r:pangea.localhost',
          focusServiceUrl: 'http://localhost:7980',
        ),
        throwsA(
          isA<CallTokenException>().having(
            (e) => e.message,
            'message',
            contains('could not reach'),
          ),
        ),
      );
    });

    test(
      'a 200 carrying no usable grant is rejected, not half-accepted',
      () async {
        final repo = CallTokenRepo(
          httpClient: respondWith(200, {"url": "ws://x"}),
        );

        await expectLater(
          () => repo.requestTokenWithOpenId(
            openIdAccessToken: 'tok',
            openIdTokenType: 'Bearer',
            matrixServerName: 'pangea.localhost',
            deviceId: 'DEV',
            roomId: '!r:pangea.localhost',
            focusServiceUrl: 'http://localhost:7980',
          ),
          throwsA(isA<CallTokenException>()),
        );
      },
    );
  });

  group('CallTokenRepo request shape', () {
    test(
      'posts the openid token and device to /sfu/get, trimming the base url',
      () async {
        final repo = CallTokenRepo(
          httpClient: respondWith(200, {
            'url': 'ws://livekit.localhost:7880',
            'jwt': 'j.w.t',
          }),
        );

        final grant = await repo.requestTokenWithOpenId(
          openIdAccessToken: 'tok',
          openIdTokenType: 'Bearer',
          matrixServerName: 'pangea.localhost',
          deviceId: 'DEV',
          roomId: '!r:pangea.localhost',
          // trailing slashes are easy to introduce via config; they must not double up
          focusServiceUrl: 'http://localhost:7980///',
        );

        expect(captured.toString(), 'http://localhost:7980/sfu/get');
        expect(sentBody['room'], '!r:pangea.localhost');
        expect(sentBody['device_id'], 'DEV');
        expect(
          sentBody['openid_token']['matrix_server_name'],
          'pangea.localhost',
        );
        expect(grant.url, 'ws://livekit.localhost:7880');
        expect(grant.jwt, 'j.w.t');
      },
    );
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
