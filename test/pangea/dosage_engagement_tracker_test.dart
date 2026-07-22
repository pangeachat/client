import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';

/// Unit tests for the engagement span lifecycle ([DosageEngagementTracker]).
/// The tracker takes an injectable clock + HTTP client, so span open / extend /
/// idle-close / cap-rollover / flush are all driven deterministically with no
/// Matrix boot — the POSTed spans are read back off a [MockClient].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bffUrl = 'https://bff.test.example';
  const token = 'syt_token';
  const deviceId = 'DEVICE-A';
  final base = DateTime.utc(2026, 1, 1, 12);

  late List<http.Request> requests;
  late http.Client mock;
  late DateTime clock;

  DosageEngagementTracker buildTracker() =>
      DosageEngagementTracker(now: () => clock, httpClient: mock);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  List<Map<String, dynamic>> postedSpans() => requests
      .expand(
        (r) =>
            (jsonDecode(r.body)['spans'] as List).cast<Map<String, dynamic>>(),
      )
      .toList();

  DateTime spanEndOf(Map<String, dynamic> span) =>
      DateTime.parse(span['span_end'] as String).toUtc();
  DateTime spanStartOf(Map<String, dynamic> span) =>
      DateTime.parse(span['span_start'] as String).toUtc();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('dosage_track_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': bffUrl,
      },
    );
    requests = [];
    mock = MockClient((req) async {
      requests.add(req);
      return http.Response('', 202);
    });
    clock = base;
  });

  test('opens on activity, extends, flushes a UUIDv4 span on heartbeat', () async {
    final tracker = buildTracker();
    tracker.recordActivity(deviceId: deviceId, accessToken: token);
    // A second activity WITHIN the idle gap extends the same span.
    clock = base.add(const Duration(seconds: 90));
    tracker.recordActivity(deviceId: deviceId, accessToken: token);
    clock = base.add(const Duration(minutes: 2));
    tracker.flushOpenSpan();
    await settle();

    expect(requests, hasLength(1));
    final span = postedSpans().single;
    expect(span['device_id'], deviceId);
    expect(span['platform'], isNotEmpty);
    expect(
      span['span_id'] as String,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    // Active at flush (last activity 30s ago, within the idle gap) => the span
    // ends at the flush time.
    expect(spanStartOf(span), base);
    expect(spanEndOf(span), base.add(const Duration(minutes: 2)));
  });

  test('is dark: opens no span and posts nothing when a gate is off', () async {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'false',
        'TEACHER_BFF_API': bffUrl,
      },
    );
    final tracker = buildTracker();
    tracker.recordActivity(deviceId: deviceId, accessToken: token);
    clock = base.add(const Duration(minutes: 5));
    tracker.flushOpenSpan();
    await settle();
    expect(requests, isEmpty);
  });

  test(
    'an empty device id opens no span (activity is not silently lost)',
    () async {
      final tracker = buildTracker();
      tracker.recordActivity(deviceId: '', accessToken: token);
      clock = base.add(const Duration(minutes: 5));
      tracker.flushOpenSpan();
      await settle();
      expect(requests, isEmpty, reason: 'no span may open without a device id');

      // A later activity with a known device id still opens a span.
      tracker.recordActivity(deviceId: deviceId, accessToken: token);
      clock = base.add(const Duration(minutes: 6));
      tracker.flushOpenSpan();
      await settle();
      expect(requests, hasLength(1));
    },
  );

  test(
    'idle gap closes the span at the last activity, not the flush time',
    () async {
      final tracker = buildTracker();
      tracker.recordActivity(deviceId: deviceId, accessToken: token);
      clock = base.add(const Duration(minutes: 1));
      tracker.recordActivity(deviceId: deviceId, accessToken: token);
      clock = base.add(const Duration(minutes: 6)); // idle since 12:01
      tracker.flushOpenSpan();
      await settle();

      expect(
        spanEndOf(postedSpans().single),
        base.add(const Duration(minutes: 1)),
      );
    },
  );

  test(
    'a single-message span is floored to minEngagement, never dropped',
    () async {
      final tracker = buildTracker();
      tracker.recordActivity(deviceId: deviceId, accessToken: token);
      clock = base.add(const Duration(minutes: 5));
      tracker.flushOpenSpan();
      await settle();

      expect(requests, hasLength(1));
      expect(
        spanEndOf(postedSpans().single),
        base.add(DosageEngagementTracker.minEngagement),
      );
    },
  );

  test('a continuously active span rolls over at the 30-minute cap', () async {
    final tracker = buildTracker();
    // Activity every 90s (inside the 2-min idle gap) keeps ONE span open and
    // accumulating; at 30 minutes it hits the server cap and flushes there.
    for (var i = 0; i <= 20; i++) {
      clock = base.add(Duration(seconds: 90 * i)); // 0 .. 1800s (30 min)
      tracker.recordActivity(deviceId: deviceId, accessToken: token);
    }
    await settle();

    expect(
      requests,
      hasLength(1),
      reason: 'the capped span flushed on rollover',
    );
    final capped = postedSpans().single;
    expect(spanStartOf(capped), base);
    expect(spanEndOf(capped), base.add(const Duration(minutes: 30)));

    // The rollover opened a fresh span at the cap moment; a later flush reports
    // only post-cap time, never a second counted 30 minutes.
    clock = base.add(const Duration(minutes: 31));
    tracker.flushOpenSpan();
    await settle();
    expect(requests, hasLength(2));
    expect(
      spanStartOf(postedSpans()[1]),
      base.add(const Duration(minutes: 30)),
    );
  });

  test(
    'a gap beyond the idle threshold rolls the span over instead of bridging',
    () async {
      final tracker = buildTracker();
      tracker.recordActivity(deviceId: deviceId, accessToken: token); // 12:00
      clock = base.add(const Duration(minutes: 1));
      tracker.recordActivity(deviceId: deviceId, accessToken: token); // 12:01
      // 10 minutes of silence (>> the 2-min idle gap), then a new message.
      clock = base.add(const Duration(minutes: 11));
      tracker.recordActivity(deviceId: deviceId, accessToken: token); // 12:11
      await settle();

      // The prior span closed at its last real activity (12:01): the idle gap is
      // NOT bridged into it.
      expect(
        requests,
        hasLength(1),
        reason: 'the idle gap rolled the prior span over on the new activity',
      );
      final first = postedSpans().single;
      expect(spanStartOf(first), base);
      expect(spanEndOf(first), base.add(const Duration(minutes: 1)));

      // The new message opened a fresh span; flushing it counts only post-gap
      // time, never the idle minutes.
      clock = base.add(const Duration(minutes: 12));
      tracker.flushOpenSpan();
      await settle();
      expect(requests, hasLength(2));
      final second = postedSpans()[1];
      expect(spanStartOf(second), base.add(const Duration(minutes: 11)));
      expect(spanEndOf(second), base.add(const Duration(minutes: 12)));
    },
  );

  test(
    'a lone activity then one far later reports a short span, not a capped 30 '
    'minutes',
    () async {
      final tracker = buildTracker();
      tracker.recordActivity(deviceId: deviceId, accessToken: token); // 12:00
      // A single message, then silence past the cap distance, then one more: the
      // gap is idle, not a 30-minute engaged span.
      clock = base.add(const Duration(minutes: 31));
      tracker.recordActivity(deviceId: deviceId, accessToken: token); // 12:31
      await settle();

      expect(requests, hasLength(1));
      final first = postedSpans().single;
      expect(spanStartOf(first), base);
      // Floored to minEngagement — NOT the 30-minute cap the old cap-first path
      // would have reported.
      expect(spanEndOf(first), base.add(DosageEngagementTracker.minEngagement));
    },
  );

  test('flushing with no open span, or twice, sends nothing extra', () async {
    final tracker = buildTracker();
    tracker.flushOpenSpan();
    await settle();
    expect(requests, isEmpty);

    tracker.recordActivity(deviceId: deviceId, accessToken: token);
    clock = base.add(const Duration(minutes: 1));
    tracker.flushOpenSpan();
    tracker.flushOpenSpan(); // span already reset — no double send
    await settle();
    expect(requests, hasLength(1));
  });

  test(
    'switching accounts mid-window rolls over — no cross-account attribution',
    () async {
      String authOf(http.Request r) => r.headers['Authorization'] ?? '';

      final tracker = buildTracker();
      // Account A activity.
      tracker.recordActivity(deviceId: 'DEVICE-A', accessToken: 'token-A');
      clock = base.add(const Duration(seconds: 30));
      // Account B activity WITHIN A's idle window. The app-isolate-global tracker
      // used to only update _lastActivity, so B's activity extended A's span and
      // later flushed under A's device + bearer.
      tracker.recordActivity(deviceId: 'DEVICE-B', accessToken: 'token-B');
      await settle();

      // The device switch closed A's span, flushed under A's OWN identity.
      expect(requests, hasLength(1), reason: 'the account switch closed A');
      expect(authOf(requests.single), 'Bearer token-A');
      expect(postedSpans().single['device_id'], 'DEVICE-A');

      // B's span reports under B's identity, never A's.
      clock = base.add(const Duration(minutes: 1));
      tracker.flushOpenSpan();
      await settle();
      expect(requests, hasLength(2));
      expect(authOf(requests[1]), 'Bearer token-B');
      expect(postedSpans()[1]['device_id'], 'DEVICE-B');
    },
  );

  test(
    'flushOpenSpan awaits the span POST so a final flush is not dropped',
    () async {
      final gate = Completer<http.Response>();
      final gatedMock = MockClient((req) {
        requests.add(req);
        return gate.future;
      });
      final tracker = DosageEngagementTracker(
        now: () => clock,
        httpClient: gatedMock,
      );
      tracker.recordActivity(deviceId: deviceId, accessToken: token);
      clock = base.add(const Duration(minutes: 1));

      var flushed = false;
      final flush = tracker.flushOpenSpan().then((_) => flushed = true);
      await pumpEventQueue();
      // The POST fired, but the flush future must NOT resolve until it lands —
      // so teardown that awaits it cannot drop the final span.
      expect(requests, hasLength(1), reason: 'the flush actually POSTed');
      expect(
        flushed,
        isFalse,
        reason: 'the flush future must await the POST, not fire-and-forget it',
      );

      gate.complete(http.Response('', 202));
      await flush;
      expect(flushed, isTrue);
    },
  );
}
