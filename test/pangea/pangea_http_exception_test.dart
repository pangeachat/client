import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

/// The typed HTTP failure behind #8094: every ≥400 response used to be thrown
/// as a raw [Response], whose missing `toString()` collapsed 66 distinct
/// Sentry issues into one title, `Instance of 'Response'`. These tests pin the
/// three things the exception exists for: a diagnosable `toString()`, path
/// normalization so titles group per endpoint, and the one severity table.
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
