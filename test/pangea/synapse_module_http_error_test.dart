import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/features/join_codes/request_room_code_extension.dart';
import 'package:fluffychat/features/room_summaries/activity_session_previews_extension.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';

/// The four `Api` extensions that call Synapse Pangea modules directly (Matrix
/// bearer token, `httpClient.send`, bypassing [Requests]) each threw a bare
/// `Exception` interpolating the whole response body — untyped in Sentry, and
/// carrying content the exception must never hold
/// (repos-and-error-handling.instructions.md § What `Requests` throws).
///
/// #8369 / CLIENT-E4Z. These tests pin the typed throw, the diagnosable title,
/// the absence of the body, and the severity the failure resolves to.
void main() {
  /// An [Api] whose every call answers [status] with [body].
  Api api(int status, String body) => Api(
    httpClient: MockClient((_) async => Response(body, status)),
    baseUri: Uri.parse('https://matrix.staging.pangea.chat'),
    bearerToken: 'syt_test_token',
  );

  /// What Synapse answers with when the access token has aged out — the shape
  /// behind CLIENT-E4Z's `401 M_UNAUTHORIZED`. `error` is the free-text half
  /// that must not reach Sentry.
  const unauthorized =
      '{"errcode":"M_UNAUTHORIZED","error":"Invalid access token passed."}';

  /// Each site, as (name, method, path, call).
  final sites = <String, (String, String, Future<void> Function(Api))>{
    'room_preview': (
      'GET',
      '/_synapse/client/unstable/org.pangea/room_preview',
      (a) => a.getRoomSummaries(['!r:server'], l1Code: 'en'),
    ),
    'activity_session_previews': (
      'GET',
      '/_synapse/client/pangea/v1/activity_session_previews',
      (a) => a.getActivitySessionPreviews(['!s:server'], l1Code: 'en'),
    ),
    'request_room_code': (
      'GET',
      '/_synapse/client/pangea/v1/request_room_code',
      (a) => a.getSpaceCode(),
    ),
    'public_courses': (
      'GET',
      '/_synapse/client/unstable/org.pangea/public_courses',
      (a) => a.getPublicCourses(),
    ),
    'knock_with_code': (
      'POST',
      '/_synapse/client/pangea/v1/knock_with_code',
      (a) => a.knockSpace('vldcde1'),
    ),
  };

  sites.forEach((name, site) {
    final (method, path, call) = site;

    group('$name — 401', () {
      Future<PangeaHttpException> thrown() async {
        try {
          await call(api(401, unauthorized));
        } on PangeaHttpException catch (e) {
          return e;
        }
        fail('expected a PangeaHttpException');
      }

      test(
        'throws a typed PangeaHttpException, not a bare Exception',
        () async {
          await expectLater(
            call(api(401, unauthorized)),
            throwsA(isA<PangeaHttpException>()),
          );
        },
      );

      test(
        'toString renders status, method, and the normalized path',
        () async {
          final e = await thrown();
          expect(e.statusCode, 401);
          expect(
            e.toString(),
            'PangeaHttpException: 401 $method $path — M_UNAUTHORIZED',
          );
        },
      );

      test('carries the errcode as detail, never the response body', () async {
        final e = await thrown();
        expect(e.detail, 'M_UNAUTHORIZED');
        expect(e.toString(), isNot(contains('Invalid access token')));
      });

      test('resolves to warning — token lifecycle is routine', () async {
        expect(
          PangeaHttpException.severityOf(await thrown()),
          SentryLevel.warning,
        );
      });
    });

    test('$name — a 403 stays an error', () async {
      try {
        await call(api(403, '{"errcode":"M_FORBIDDEN","error":"nope"}'));
        fail('expected a PangeaHttpException');
      } on PangeaHttpException catch (e) {
        expect(e.statusCode, 403);
        expect(PangeaHttpException.severityOf(e), SentryLevel.error);
      }
    });

    test('$name — a 502 with an unparseable body carries no detail', () async {
      try {
        await call(api(502, '<html>Bad Gateway</html>'));
        fail('expected a PangeaHttpException');
      } on PangeaHttpException catch (e) {
        expect(e.detail, isNull);
        expect(e.toString(), 'PangeaHttpException: 502 $method $path');
        expect(PangeaHttpException.severityOf(e), SentryLevel.error);
      }
    });
  });

  group('knock_with_code — code-not-found and rate limiting (#8693)', () {
    const path = '/_synapse/client/pangea/v1/knock_with_code';

    test('404 CODE_NOT_FOUND is typed, titled, and a warning', () async {
      try {
        await api(
          404,
          '{"errcode":"ORG.PANGEA.CODE_NOT_FOUND",'
          '"error":"No rooms found with the access code: vldcde1"}',
        ).knockSpace('vldcde1');
        fail('expected a PangeaHttpException');
      } on PangeaHttpException catch (e) {
        expect(e.statusCode, 404);
        expect(
          e.toString(),
          'PangeaHttpException: 404 POST $path — ORG.PANGEA.CODE_NOT_FOUND',
        );
        // A wrong code is an expected user mistake — but it stays reported,
        // so a legitimately-distributed code that stops matching is visible.
        expect(PangeaHttpException.severityOf(e), SentryLevel.warning);
      }
    });

    test('a pre-errcode server 400 is typed with no detail', () async {
      // Servers predating the 404/errcode split answer a bare 400 whose only
      // content is free text, which detail never carries.
      try {
        await api(
          400,
          '{"error":"No rooms found with the access code: vldcde1"}',
        ).knockSpace('vldcde1');
        fail('expected a PangeaHttpException');
      } on PangeaHttpException catch (e) {
        expect(e.statusCode, 400);
        expect(e.detail, isNull);
        expect(e.toString(), isNot(contains('vldcde1')));
      }
    });

    test('429 is readable via statusCodeOf — the retry-dialog test', () async {
      try {
        await api(429, '{"error":"Rate limited"}').knockSpace('vldcde1');
        fail('expected a PangeaHttpException');
      } on PangeaHttpException catch (e) {
        expect(PangeaHttpException.statusCodeOf(e), 429);
        expect(PangeaHttpException.severityOf(e), SentryLevel.warning);
      }
    });

    test('the banned 403 still maps to BannedFromRoomException', () async {
      await expectLater(
        api(
          403,
          '{"errcode":"ORG.PANGEA.BANNED_FROM_ROOM","error":"banned",'
          '"banned":["!r:server"]}',
        ).knockSpace('vldcde1'),
        throwsA(isA<BannedFromRoomException>()),
      );
    });
  });

  group('PangeaHttpException.detailFromResponse — Matrix errcode', () {
    test('prefers the choreo detail field when both are present', () {
      expect(
        PangeaHttpException.detailFromResponse(
          Response('{"detail":"from choreo","errcode":"M_UNKNOWN"}', 400),
        ),
        'from choreo',
      );
    });

    test('falls back to the Matrix errcode', () {
      expect(
        PangeaHttpException.detailFromResponse(
          Response('{"errcode":"M_UNKNOWN_TOKEN","error":"soft logout"}', 401),
        ),
        'M_UNKNOWN_TOKEN',
      );
    });

    test('never reads the free-text error field', () {
      expect(
        PangeaHttpException.detailFromResponse(
          Response('{"error":"learner typed this"}', 400),
        ),
        isNull,
      );
    });
  });
}
