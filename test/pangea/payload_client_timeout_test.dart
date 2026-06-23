import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/course_plans/payload_client/payload_client.dart';

void main() {
  // A stalled CMS read (connection opened but the response never arrives) must
  // time out and throw, not hang the caller forever. Un-timed reads here left
  // the activity/course resolvers spinning with no error and no activity
  // (#7085, #7159, #7080). A tiny readTimeout keeps the test fast.
  group('PayloadClient bounds a stalled read', () {
    PayloadClient clientThatNeverResponds() => PayloadClient(
      baseUrl: 'https://cms.example.test',
      accessToken: 'token',
      // Never completes the response — simulates an open-but-stalled connection.
      httpClient: MockClient((_) => Completer<http.Response>().future),
      readTimeout: const Duration(milliseconds: 50),
    );

    test('findById throws TimeoutException instead of hanging', () {
      expect(
        clientThatNeverResponds().findById<Map<String, dynamic>>(
          'quests',
          'missing',
          (j) => j,
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('find throws TimeoutException instead of hanging', () {
      expect(
        clientThatNeverResponds().find<Map<String, dynamic>>(
          'quests',
          (j) => j,
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
