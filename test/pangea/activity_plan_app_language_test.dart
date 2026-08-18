import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// #8397 — activity content follows the display language, not the fixed L1.
///
/// The plan read (`GET /v2/activity/{id}?l1=`) is where activity titles,
/// descriptions, and goals get localized. Before this, the repo defaulted `l1`
/// to the learner's L1 no matter what the "App in target language" toggle said,
/// so flipping the app into L2 left every activity in L1. What is pinned here:
/// the repo's default `l1` is [UserController.appLanguageCode] — and because
/// the cache keys on `l1`, a display-language change is a cache miss, not a
/// stale L1 plan served from disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Registered synchronously, BEFORE `ActivityPlanRepo.instance` is touched:
  // the singleton's `PersistentRepoCache` builds a `GetStorage` container on
  // construction, which reaches for path_provider immediately.
  final tempDir = Directory.systemTemp.createTempSync('plan_app_language_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  final repo = ActivityPlanRepo.instance;

  setUpAll(() async {
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://choreo.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('activity_plan_storage');
  });

  setUp(repo.resetBackoff);

  /// Runs [body] with every top-level `http` call answered by a transient 503
  /// (so nothing is cached or confirmed-removed between calls) and returns the
  /// `l1` query each request carried, in order.
  Future<List<String?>> requestedL1s(Future<void> Function() body) async {
    final l1s = <String?>[];
    await http.runWithClient(body, () {
      return MockClient((request) async {
        l1s.add(request.url.queryParameters['l1']);
        return http.Response('{"detail":"upstream down"}', 503);
      });
    });
    return l1s;
  }

  test('the plan read sends the display language as l1, not the L1', () async {
    MatrixState.pangeaController = FakePangeaController(
      userL1Code: 'en',
      appLanguageCode: 'es',
      accessToken: 'test-token',
    );
    final l1s = await requestedL1s(() => repo.getPlan('activity-1'));
    expect(l1s, ['es']);
  });

  test('toggle off: the display language is the L1, as before', () async {
    MatrixState.pangeaController = FakePangeaController(
      userL1Code: 'en',
      accessToken: 'test-token',
    );
    final l1s = await requestedL1s(() => repo.getPlan('activity-2'));
    expect(l1s, ['en']);
  });

  test('a display-language change re-keys the read (cache miss)', () async {
    MatrixState.pangeaController = FakePangeaController(
      userL1Code: 'en',
      appLanguageCode: 'en',
      accessToken: 'test-token',
    );
    final before = await requestedL1s(() => repo.getPlan('activity-3'));
    MatrixState.pangeaController = FakePangeaController(
      userL1Code: 'en',
      appLanguageCode: 'fr',
      accessToken: 'test-token',
    );
    final after = await requestedL1s(() => repo.getPlan('activity-3'));
    expect([...before, ...after], ['en', 'fr']);
  });

  test('an explicit l1 still wins over the display language', () async {
    MatrixState.pangeaController = FakePangeaController(
      userL1Code: 'en',
      appLanguageCode: 'es',
      accessToken: 'test-token',
    );
    final l1s = await requestedL1s(() => repo.getPlan('activity-4', l1: 'de'));
    expect(l1s, ['de']);
  });
}
