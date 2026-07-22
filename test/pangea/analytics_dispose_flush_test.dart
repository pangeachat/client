import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_service.dart';
import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';

/// AnalyticsUpdateService.dispose() only touches WidgetsBinding, its timer, and
/// the injected tracker — never dataService — so a noSuchMethod fake avoids
/// booting a real DB/client.
class _FakeDataService implements AnalyticsDataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The teardown chain (matrix `_cancelSubs` → AnalyticsDataService.dispose →
/// AnalyticsUpdateService.dispose → tracker flush) must AWAIT the final
/// engagement-span flush so the last span is actually POSTed on logout, not
/// dropped. This drives the REAL AnalyticsUpdateService.dispose entry point.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('analytics_dispose');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
  });

  test('dispose awaits the final flush POST before resolving', () async {
    final gate = Completer<http.Response>();
    var posted = false;
    var clock = DateTime.utc(2026, 1, 1, 12);
    final gatedTracker = DosageEngagementTracker(
      now: () => clock,
      httpClient: MockClient((req) {
        posted = true;
        return gate.future;
      }),
    );
    final svc = AnalyticsUpdateService(
      _FakeDataService(),
      tracker: gatedTracker,
    );

    // Open a span, then advance the clock so it has positive length to flush.
    gatedTracker.recordActivity(
      userId: '@u:example.org',
      deviceId: 'DEVICE-A',
      accessToken: 'token-A',
    );
    clock = clock.add(const Duration(minutes: 1));

    var disposed = false;
    final dispose = svc.dispose().then((_) => disposed = true);
    await pumpEventQueue();

    // The flush POST fired, but dispose must NOT resolve until it lands.
    expect(posted, isTrue, reason: 'dispose flushed the open span');
    expect(
      disposed,
      isFalse,
      reason: 'teardown must await the final flush POST, not drop it',
    );

    gate.complete(http.Response('', 202));
    await dispose;
    expect(disposed, isTrue);
  });
}
