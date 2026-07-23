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

/// A data service whose reported mxid can be flipped to null — mirroring the
/// Matrix SDK nulling userID in `clear()` BEFORE it emits `loggedOut`, so the
/// non-injected teardown must dispose by the mxid PINNED at start(), not the
/// (now null) live read.
class _MutableUserIdDataService implements AnalyticsDataService {
  _MutableUserIdDataService(this.userId);
  String? userId;
  @override
  String? get accountUserId => userId;
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
    DosageEngagementTracker.debugResetAccounts();
  });

  tearDown(DosageEngagementTracker.debugResetAccounts);

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

  test(
    'start() pins the mxid so teardown disposes it after the SDK nulls userID',
    () async {
      const mxid = '@u:example.org';
      // A real registry tracker for the account, with an open span to flush.
      final reqs = <http.Request>[];
      var clock = DateTime.utc(2026, 1, 1, 12);
      final tracker = DosageEngagementTracker(
        now: () => clock,
        httpClient: MockClient((r) async {
          reqs.add(r);
          return http.Response('', 202);
        }),
      );
      DosageEngagementTracker.debugPutAccount(mxid, tracker);
      tracker.recordActivity(
        userId: mxid,
        deviceId: 'DEVICE-A',
        accessToken: 'token-A',
      );
      clock = clock.add(const Duration(minutes: 1));

      // NON-injected service: dispose() resolves the tracker via the registry
      // using the account mxid, exactly the teardown path that broke.
      final dataService = _MutableUserIdDataService(mxid);
      final svc = AnalyticsUpdateService(dataService);
      svc.start(); // pins the mxid while "logged in"

      // The SDK clears userID before emitting loggedOut — the live read is now
      // null, so ONLY the start()-pinned id can key the disposal.
      dataService.userId = null;

      await svc.dispose();

      expect(
        reqs,
        hasLength(1),
        reason:
            'the pinned account is still flushed on teardown after the SDK '
            'nulled userID — not disposeAccount(\'\') which would leak it',
      );
      expect(
        DosageEngagementTracker.forAccount(mxid),
        isNot(same(tracker)),
        reason: 'the pinned account tracker was removed from the registry',
      );
    },
  );
}
