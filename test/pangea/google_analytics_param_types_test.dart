import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';

/// Captures what the wrapper hands to firebase_analytics. Only [logEvent] is
/// real; nothing else is reachable from these tests.
class _CapturingAnalytics implements FirebaseAnalytics {
  final events = <String, Map<String, Object>?>{};

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
    AnalyticsCallOptions? callOptions,
  }) async {
    events[name] = parameters;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// firebase_analytics asserts `value is String || value is num` on every
/// parameter (CLIENT-EK9: a bare bool `version_pin_honored` tripped it).
void expectFirebaseSafe(Map<String, Object>? params) {
  expect(params, isNotNull);
  for (final entry in params!.entries) {
    expect(
      entry.value,
      anyOf(isA<String>(), isA<num>()),
      reason: '${entry.key} is a ${entry.value.runtimeType}',
    );
  }
}

void main() {
  late _CapturingAnalytics analytics;

  setUp(() {
    analytics = _CapturingAnalytics();
    GoogleAnalytics.analytics = analytics;
  });

  tearDown(() => GoogleAnalytics.analytics = null);

  test('start_activity encodes version_pin_honored as a string', () {
    GoogleAnalytics.startActivity('act', 'room', versionPinHonored: true);
    final params = analytics.events['start_activity'];
    expectFirebaseSafe(params);
    expect(params!['version_pin_honored'], 'true');
    expect(params.containsKey('fallback_cause'), isFalse);
  });

  test('complete_activity encodes version_pin_honored as a string', () {
    GoogleAnalytics.completeActivity(
      'act',
      'room',
      versionPinHonored: false,
      fallbackCause: 'version_evicted',
    );
    final params = analytics.events['complete_activity'];
    expectFirebaseSafe(params);
    expect(params!['version_pin_honored'], 'false');
    expect(params['fallback_cause'], 'version_evicted');
  });

  test('activity events omit the pin params when the caller has none', () {
    GoogleAnalytics.completeActivity('act', 'room');
    final params = analytics.events['complete_activity'];
    expectFirebaseSafe(params);
    expect(params, {'activity_id': 'act', 'room_id': 'room'});
  });
}
