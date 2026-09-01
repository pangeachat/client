import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics_access/grant_analytics_access_extension.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'sentry_capture_harness.dart';

/// The grant call is the one live raw-`Response` throw site of #8362: it
/// bypasses `Requests` entirely (Synapse endpoint, Matrix SDK client and
/// token), so nothing upstream types its failures for it. Thrown raw, every
/// grant failure arrived in Sentry titled `Instance of 'Response'`.
///
/// These tests pin the contract the doc actually asks for
/// (repos-and-error-handling.instructions.md): the failure is a
/// `PangeaHttpException`, its `toString()` names the endpoint, and it maps onto
/// the one severity table.
void main() {
  const courseRoomId = '!course:staging.pangea.chat';
  const analyticsRoomId = '!analytics:staging.pangea.chat';
  const grantPath =
      '/_synapse/client/pangea/v1/grant_instructor_analytics_access';

  Api apiReturning(int status, {String body = ''}) => Api(
    baseUri: Uri.parse('https://matrix.staging.pangea.chat'),
    bearerToken: 'syt_test_token',
    httpClient: MockClient(
      (request) async => Response(body, status, request: request),
    ),
  );

  /// The thrown object, or null when the call succeeded.
  Future<Object?> grantFailure(Api api) async {
    try {
      await api.grantInstructorAnalyticsAccess(courseRoomId, analyticsRoomId);
      return null;
    } catch (e) {
      return e;
    }
  }

  group('grantInstructorAnalyticsAccess', () {
    test('a 200 completes without throwing', () async {
      expect(
        await grantFailure(apiReturning(200, body: '{"errors":[]}')),
        isNull,
      );
    });

    test('throws the typed exception, never the response', () async {
      final error = await grantFailure(apiReturning(403));

      expect(error, isA<PangeaHttpException>());
      // The regression itself: a thrown response has no toString() override.
      expect(error, isNot(isA<BaseResponse>()));
      expect(error.toString(), isNot(contains('Instance of')));
    });

    test('toString carries status, method, and the endpoint path', () async {
      expect(
        (await grantFailure(apiReturning(502))).toString(),
        'PangeaHttpException: 502 POST $grantPath',
      );
    });

    test('reports the status the server actually sent', () async {
      for (final status in [400, 403, 404, 429, 500]) {
        expect(
          PangeaHttpException.statusCodeOf(
            await grantFailure(apiReturning(status)),
          ),
          status,
        );
      }
    });

    test('the failure lands on the shared severity table', () async {
      // The two callers in join_room_analytics_access_extension.dart report
      // with exactly this level, so a routine 404 stops paging as an error.
      for (final status in [401, 404, 410, 429]) {
        expect(
          PangeaHttpException.severityOf(
            await grantFailure(apiReturning(status)),
          ),
          SentryLevel.warning,
          reason: '$status is routine — the resource is gone or will retry',
        );
      }
      for (final status in [400, 403, 500, 502]) {
        expect(
          PangeaHttpException.severityOf(
            await grantFailure(apiReturning(status)),
          ),
          SentryLevel.error,
          reason: '$status is a code bug or a backend regression',
        );
      }
    });

    test('names an instructor only when the caller consented to one', () async {
      // The field picks which gate the server applies: absent, it demands the
      // course toggle; present, it demands a knock from that instructor.
      // Sending it when nobody was named would silently switch the
      // required-course grant onto the consent gate.
      final bodies = <Map<String, dynamic>>[];
      final api = Api(
        baseUri: Uri.parse('https://matrix.staging.pangea.chat'),
        bearerToken: 'syt_test_token',
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return Response('', 200, request: request);
        }),
      );

      await api.grantInstructorAnalyticsAccess(courseRoomId, analyticsRoomId);
      await api.grantInstructorAnalyticsAccess(
        courseRoomId,
        analyticsRoomId,
        instructorId: '@teacher:staging.pangea.chat',
      );

      expect(bodies.first.containsKey('mx_instructor_id'), isFalse);
      expect(bodies.last['mx_instructor_id'], '@teacher:staging.pangea.chat');
      for (final body in bodies) {
        expect(body['mx_course_id'], courseRoomId);
        expect(body['mx_analytics_room_id'], analyticsRoomId);
      }
    });

    test('never carries the response body', () async {
      // Bodies carry learner content; only the parsed `detail` may travel.
      final error =
          await grantFailure(
                apiReturning(500, body: '{"error":"secret learner text"}'),
              )
              as PangeaHttpException;

      expect(error.detail, isNull);
      expect(error.toString(), isNot(contains('secret learner text')));
    });
  });

  group('grantInstructorAnalyticsAccess partial failure', () {
    // #8695: the endpoint answers 200 with per-instructor failures in `errors`.
    // Reading only the status code left an instructor absent from a student's
    // analytics room with nothing reported anywhere.
    const partialBody =
        '{"instructors_joined":[],'
        '"errors":[{"user_id":"@teacher:staging.pangea.chat",'
        '"error":"duplicate key value violates unique constraint"}]}';

    late SentryCaptureHarness harness;

    setUp(() async {
      harness = SentryCaptureHarness();
      await harness.init();
    });

    tearDown(() => harness.close());

    test('reports a 200 that carries per-instructor errors', () async {
      final event = await harness.capture(() {
        apiReturning(
          200,
          body: partialBody,
        ).grantInstructorAnalyticsAccess(courseRoomId, analyticsRoomId);
      });

      expect(
        event.throwable.toString(),
        contains('returned per-instructor errors'),
      );
      // Silent data loss, not a routine status — this has to page.
      expect(event.level, SentryLevel.error);
    });

    test('a partial failure still does not throw', () async {
      // The instructors that were granted still are. Turning that into a total
      // failure would change what all three call sites do.
      expect(await grantFailure(apiReturning(200, body: partialBody)), isNull);
    });

    test('an empty errors array reports nothing', () async {
      var reported = false;
      await Sentry.close();
      await Sentry.init((options) {
        options.dsn = 'https://public@sentry.invalid/1';
        options.beforeSend = (event, hint) {
          reported = true;
          return null;
        };
      });

      await apiReturning(
        200,
        body:
            '{"instructors_joined":[{"user_id":"@t:x","action":"joined"}],'
            '"errors":[]}',
      ).grantInstructorAnalyticsAccess(courseRoomId, analyticsRoomId);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(reported, isFalse);
    });

    test('a body that will not parse is reported too', () async {
      // Not a failed grant, but we can no longer tell a granted instructor from
      // an ungranted one — the same silence, one layer up.
      final event = await harness.capture(() {
        apiReturning(
          200,
          body: 'not json',
        ).grantInstructorAnalyticsAccess(courseRoomId, analyticsRoomId);
      });

      expect(event.throwable.toString(), contains('unreadable body'));
    });

    test('never carries instructor identities', () async {
      // Server-side reasons are diagnosable; MXIDs are PII we do not ship.
      final event = await harness.capture(() {
        apiReturning(
          200,
          body: partialBody,
        ).grantInstructorAnalyticsAccess(courseRoomId, analyticsRoomId);
      });

      expect(event.toJson().toString(), isNot(contains('@teacher:')));
    });
  });
}
