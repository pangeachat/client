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

  test(
    'opens on activity, extends, flushes a UUIDv4 span on heartbeat',
    () async {
      final tracker = buildTracker();
      tracker.recordActivity(deviceId: deviceId, accessToken: token);
      clock = base.add(const Duration(minutes: 3));
      tracker.recordActivity(deviceId: deviceId, accessToken: token);
      clock = base.add(const Duration(minutes: 3, seconds: 30));
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
      // Active at flush => the span ends at the flush time.
      expect(spanStartOf(span), base);
      expect(
        spanEndOf(span),
        base.add(const Duration(minutes: 3, seconds: 30)),
      );
    },
  );

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

  test('rolls over before exceeding the 30-minute server cap', () async {
    final tracker = buildTracker();
    tracker.recordActivity(deviceId: deviceId, accessToken: token);
    clock = base.add(const Duration(minutes: 31));
    tracker.recordActivity(deviceId: deviceId, accessToken: token);
    await settle();

    expect(
      requests,
      hasLength(1),
      reason: 'the capped span flushed on rollover',
    );
    expect(
      spanEndOf(postedSpans().single),
      base.add(const Duration(minutes: 30)),
    );

    clock = base.add(const Duration(minutes: 32));
    tracker.flushOpenSpan();
    await settle();
    expect(requests, hasLength(2));
    expect(
      spanStartOf(postedSpans()[1]),
      base.add(const Duration(minutes: 31)),
    );
  });

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
}
