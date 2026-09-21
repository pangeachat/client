import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

/// The typed HTTP failure behind #8094: every ≥400 response used to be thrown
/// as a raw [Response], whose missing `toString()` collapsed 66 distinct
/// Sentry issues into one title, `Instance of 'Response'`. These tests pin the
/// four things the exception exists for: a diagnosable `toString()`, path
/// normalization so titles group per endpoint, the one severity table, and
/// the Sentry fingerprint that makes grouping match the title (#8469).
void main() {
  Response response(
    int status, {
    String method = 'GET',
    String url = 'https://api.pangea.chat/choreo/health',
  }) => Response('', status, request: Request(method, Uri.parse(url)));

  group('PangeaHttpException.toString', () {
    test('carries status, method, and normalized path', () {
      final e = PangeaHttpException.fromResponse(
        response(
          404,
          url:
              'https://api.pangea.chat/choreo/quests/123e4567-e89b-12d3-a456-426614174000/activities',
        ),
      );
      expect(
        e.toString(),
        'PangeaHttpException: 404 GET /choreo/quests/{id}/activities',
      );
    });

    test('appends the parsed detail when present', () {
      final e = PangeaHttpException.fromResponse(
        response(504, url: 'https://api.pangea.chat/choreo/v2/activities/bbox'),
        detail: 'upstream timed out',
      );
      expect(
        e.toString(),
        'PangeaHttpException: 504 GET /choreo/v2/activities/bbox'
        ' — upstream timed out',
      );
    });

    test('caps detail length — never a whole body', () {
      final e = PangeaHttpException.fromResponse(
        response(500),
        detail: 'x' * 1000,
      );
      expect(e.detail!.length, PangeaHttpException.maxDetailLength);
    });

    test('survives a response with no request attached', () {
      final e = PangeaHttpException.fromResponse(Response('', 502));
      expect(e.toString(), 'PangeaHttpException: 502 UNKNOWN unknown');
    });
  });

  group('PangeaHttpException.normalizePath', () {
    test('replaces opaque id segments with {id}', () {
      expect(
        // UUID
        PangeaHttpException.normalizePath(
          Uri.parse(
            'https://x/choreo/quests/123e4567-e89b-12d3-a456-426614174000/activities',
          ),
        ),
        '/choreo/quests/{id}/activities',
      );
      expect(
        // CMS (Mongo) ObjectId
        PangeaHttpException.normalizePath(
          Uri.parse('https://x/cms/api/quest-plans/507f1f77bcf86cd799439011'),
        ),
        '/cms/api/quest-plans/{id}',
      );
      expect(
        // numeric id
        PangeaHttpException.normalizePath(Uri.parse('https://x/things/12345')),
        '/things/{id}',
      );
      expect(
        // Matrix room id (percent-encoded in the URL, decoded per segment)
        PangeaHttpException.normalizePath(
          Uri.parse('https://x/rooms/${Uri.encodeComponent('!abc:server')}'),
        ),
        '/rooms/{id}',
      );
    });

    test('keeps ordinary segments and drops the query string', () {
      expect(
        PangeaHttpException.normalizePath(
          Uri.parse('https://x/choreo/v2/activities/bbox?course_room_id=!r:s'),
        ),
        '/choreo/v2/activities/bbox',
      );
    });

    test(
      'templates human-readable content ids, so one endpoint is one issue',
      () {
        // Each of these was its own Sentry grouping (#8713): fourteen issues
        // across two statuses for what is one endpoint.
        for (final id in [
          'sp101-m1-a',
          'sp101-m2-b',
          'sp101-m4-b',
          'germ1-nyc-m1',
          'germ1-nyc-m13',
          'spanish-101-mission-1',
        ]) {
          expect(
            PangeaHttpException.normalizePath(
              Uri.parse('https://x/choreo/v2/activity/$id'),
            ),
            '/choreo/v2/activity/{id}',
            reason: '$id should template',
          );
        }
      },
    );

    test('never renames a real route segment', () {
      // Every hyphenated segment the client can build (urls.dart) plus the
      // shapes a digit-bearing rule could plausibly swallow. A regression here
      // renames an endpoint in every Sentry title it appears in.
      for (final segment in [
        'analytics-events',
        'audio-signals',
        'engagement-spans',
        'message-events',
        'session-outcomes',
        'quest-plans',
        'v2',
        'bbox',
        'text_to_speech',
        'phonetic_transcription_v2',
        'grammar_constructs',
        'activity_session_previews',
        'org.matrix.msc4075.rtc.notification',
      ]) {
        expect(
          PangeaHttpException.normalizePath(Uri.parse('https://x/a/$segment')),
          '/a/$segment',
          reason: '$segment is a route, not a resource',
        );
      }
    });
  });

  group('PangeaHttpException.statusCodeOf', () {
    test('reads a PangeaHttpException', () {
      expect(
        PangeaHttpException.statusCodeOf(
          PangeaHttpException.fromResponse(response(404)),
        ),
        404,
      );
    });

    test('still reads a raw Response from a not-yet-migrated throw site', () {
      expect(PangeaHttpException.statusCodeOf(Response('', 503)), 503);
    });

    test('is null for anything else', () {
      expect(PangeaHttpException.statusCodeOf(Exception('offline')), isNull);
      expect(PangeaHttpException.statusCodeOf(null), isNull);
    });
  });

  group('PangeaHttpException.fingerprintOf — the Sentry grouping key', () {
    test('is status, method, and normalized path under one namespace', () {
      final e = PangeaHttpException.fromResponse(
        response(
          404,
          url:
              'https://api.pangea.chat/choreo/v2/activity/'
              '98881d89-7195-4928-95ad-3aef0ec3228a',
        ),
      );
      expect(PangeaHttpException.fingerprintOf(e), [
        'pangea-http',
        '404',
        'GET',
        '/choreo/v2/activity/{id}',
      ]);
    });

    test('two resources under one endpoint group together', () {
      List<String>? forActivity(String id) => PangeaHttpException.fingerprintOf(
        PangeaHttpException.fromResponse(
          response(404, url: 'https://api.pangea.chat/choreo/v2/activity/$id'),
          detail: "No canonical activity found for activity_id='$id'",
        ),
      );
      // The detail differs per resource, which is exactly why it is not in
      // the fingerprint — including it would mint one issue per activity id.
      expect(
        forActivity('98881d89-7195-4928-95ad-3aef0ec3228a'),
        forActivity('2a3c40b7-8a00-445e-8bea-18d13404fab9'),
      );
    });

    test('status splits — a 5xx never hides inside the 404 group', () {
      const url = 'https://api.pangea.chat/choreo/quests/{id}/activities';
      expect(
        PangeaHttpException.fingerprintOf(
          PangeaHttpException.fromResponse(response(404, url: url)),
        ),
        isNot(
          PangeaHttpException.fingerprintOf(
            PangeaHttpException.fromResponse(response(503, url: url)),
          ),
        ),
      );
    });

    test('method and endpoint split', () {
      final get = PangeaHttpException.fingerprintOf(
        PangeaHttpException.fromResponse(
          response(401, url: 'https://api.pangea.chat/subscription/status'),
        ),
      );
      final post = PangeaHttpException.fingerprintOf(
        PangeaHttpException.fromResponse(
          response(
            401,
            method: 'POST',
            url: 'https://api.pangea.chat/choreo/grammar_constructs',
          ),
        ),
      );
      expect(get, isNot(post));
    });

    test('is null for anything else — Sentry default grouping stands', () {
      expect(PangeaHttpException.fingerprintOf(Response('', 503)), isNull);
      expect(PangeaHttpException.fingerprintOf(Exception('offline')), isNull);
      expect(PangeaHttpException.fingerprintOf(null), isNull);
    });
  });

  group('PangeaHttpException.severityOf — the one severity table', () {
    PangeaHttpException http(int status) =>
        PangeaHttpException.fromResponse(response(status));

    test('timeouts, 401, 404, 410, and 429 are warnings', () {
      expect(
        PangeaHttpException.severityOf(TimeoutException('slow')),
        SentryLevel.warning,
      );
      for (final status in [401, 404, 410, 429]) {
        expect(
          PangeaHttpException.severityOf(http(status)),
          SentryLevel.warning,
        );
      }
    });

    test('other 4xx and all 5xx are errors', () {
      for (final status in [400, 403, 405, 422, 500, 502, 504]) {
        expect(PangeaHttpException.severityOf(http(status)), SentryLevel.error);
      }
    });

    test('non-HTTP failures are errors', () {
      expect(
        PangeaHttpException.severityOf(Exception('parse')),
        SentryLevel.error,
      );
    });
  });
}
