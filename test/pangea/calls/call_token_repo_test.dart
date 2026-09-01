import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';

/// A JWT carrying [payload], shaped exactly as one on the wire is.
///
/// Unsigned, because nothing here verifies a signature: the payload is plain
/// base64url JSON and reading it is all the client does. The third segment is
/// present because a real token has one and a reader that silently depended on
/// its absence would pass this suite and fail on every real token.
String jwtWith(Map<String, Object?> payload) {
  String seg(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(payload)}.c2ln';
}

/// The video grant our own lk-jwt-service actually mints, as decoded from a
/// token minted by the running service: room access and media, and NOTHING that
/// lets a device publish its own attributes.
const _grantAsShipped = {
  'room': '!r:pangea.localhost',
  'roomJoin': true,
  'canPublish': true,
  'canSubscribe': true,
};

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

  /// The permission the recorder election runs on, and the one nothing checked.
  ///
  /// A device tells its siblings what it can do and what it is holding by
  /// publishing participant attributes, and the SFU refuses that write unless
  /// the token said it could. Our own service has never minted the claim, so
  /// every one of those writes has failed for the life of the feature — and
  /// from the roster's side a refusal is the same thrown error as an SFU that
  /// stopped answering, so it read as an ordinary flake.
  ///
  /// These pin the reading rather than the fix. The claim is the token
  /// service's to add; what the client owes is to know, and to have known
  /// before it shipped.
  group('reading the token grant', () {
    test('the grant our service actually mints is read as ABSENT', () {
      expect(
        CallToken.readMetadataGrant(jwtWith({'video': _grantAsShipped})),
        MetadataGrant.absent,
      );
    });

    test('a grant carrying the claim is read as granted', () {
      expect(
        CallToken.readMetadataGrant(
          jwtWith({
            'video': {..._grantAsShipped, 'canUpdateOwnMetadata': true},
          }),
        ),
        MetadataGrant.granted,
      );
    });

    test('an explicit false is absent, like the claim being missing', () {
      // LiveKit omits the claim when it is false, so both shapes describe the
      // same refusal and must read the same way.
      expect(
        CallToken.readMetadataGrant(
          jwtWith({
            'video': {..._grantAsShipped, 'canUpdateOwnMetadata': false},
          }),
        ),
        MetadataGrant.absent,
      );
    });

    test('a token carrying no video grant is UNKNOWN, not absent', () {
      // An authorization service that shapes its claims differently has not
      // withheld anything. Reading it as a refusal would report a false alarm
      // on every such deployment, forever — and this is the whole back-compat
      // story, since it is the shape an older or third-party service arrives
      // in.
      expect(
        CallToken.readMetadataGrant(jwtWith({'sub': 'device', 'exp': 1})),
        MetadataGrant.unknown,
      );
    });

    test('an opaque token is unknown rather than an exception', () {
      // A call is worth more than knowing this. Every unreadable shape has to
      // come back as an answer, because the alternative is a throw on the path
      // that starts calls.
      for (final token in const [
        '',
        'not-a-jwt',
        'a.b',
        'a.!!!not-base64!!!.c',
        // Valid base64url that is not JSON, and JSON that is not an object.
        'a.bm90IGpzb24.c',
        'a.WyJhbiIsImFycmF5Il0.c',
      ]) {
        expect(
          CallToken.readMetadataGrant(token),
          MetadataGrant.unknown,
          reason: 'reading "$token" must answer, not throw',
        );
      }
    });

    test('a video grant that is not an object is unknown', () {
      expect(
        CallToken.readMetadataGrant(jwtWith({'video': 'roomJoin'})),
        MetadataGrant.unknown,
      );
    });
  });

  group('reporting a token that cannot publish attributes', () {
    setUp(ErrorHandler.resetReportedOnceKeysForTest);
    tearDown(ErrorHandler.resetReportedOnceKeysForTest);

    /// Whether the missing-grant key is still unspent.
    ///
    /// The report is fire-and-forget at the call site, so this is the seam that
    /// observes it: [ErrorHandler.logErrorOnce] spends its key synchronously,
    /// and answers false once it has been spent. Sentry is uninitialised here,
    /// so nothing leaves the test.
    Future<bool> keyUnspent() => ErrorHandler.logErrorOnce(
      key: CallTokenRepo.missingMetadataGrantKey,
      e: Exception('probe'),
      data: const {},
    );

    Future<CallToken> tokenFrom(String jwt) =>
        CallTokenRepo(
          httpClient: respondWith(200, {'url': 'ws://sfu', 'jwt': jwt}),
        ).requestTokenWithOpenId(
          openIdAccessToken: 'tok',
          openIdTokenType: 'Bearer',
          matrixServerName: 'pangea.localhost',
          deviceId: 'DEV',
          roomId: '!r:pangea.localhost',
          focusServiceUrl: 'http://localhost:7980',
        );

    test('is reported at the moment the token is issued', () async {
      await tokenFrom(jwtWith({'video': _grantAsShipped}));
      expect(
        await keyUnspent(),
        isFalse,
        reason: 'issuing the token should have spent the report',
      );
    });

    test('is reported once, however many calls are placed', () async {
      // Tokens are minted per call and every one from a deployment is shaped
      // the same way, so the second report onwards is volume. What carries the
      // size of it is Sentry's affected-user count, not the event count.
      await tokenFrom(jwtWith({'video': _grantAsShipped}));
      await tokenFrom(jwtWith({'video': _grantAsShipped}));
      await tokenFrom(jwtWith({'video': _grantAsShipped}));
      expect(await keyUnspent(), isFalse);
    });

    test('a token that HAS the claim reports nothing', () async {
      await tokenFrom(
        jwtWith({
          'video': {..._grantAsShipped, 'canUpdateOwnMetadata': true},
        }),
      );
      expect(await keyUnspent(), isTrue, reason: 'nothing was reported');
    });

    test('a token that could not be read reports nothing', () async {
      // The back-compat half. An older or differently-shaped authorization
      // service must not fire this every session on a permission it may well
      // grant under another name.
      await tokenFrom('opaque-token');
      expect(await keyUnspent(), isTrue, reason: 'unknown is not a refusal');
    });

    test('the grant is still returned to the caller either way', () async {
      // Reported, never thrown: the token joins the call perfectly well
      // without the claim, and what it loses is coordination between an
      // account's own devices.
      final token = await tokenFrom(jwtWith({'video': _grantAsShipped}));
      expect(token.url, 'ws://sfu');
      expect(token.metadataGrant, MetadataGrant.absent);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
