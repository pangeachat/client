import 'dart:io';

import 'package:flutter/services.dart';

import 'package:async/async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/repo/activity_map_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// #8473. `ActivityMapRepo.bboxPins` used to rethrow, and nothing above it
/// caught: `WorldMapPinsManager.loadWorldScopedPins` has no catch,
/// `WorldMapController.loadWorldPins` has only a `finally`, and all four of its
/// call sites (`onMapReady`, `_onCameraSettled`, `_loadForContext`, `_setL2`)
/// discard the future. So on web every failed viewport fetch became an
/// unhandled async error — a raw `ClientException: Failed to fetch` reaching
/// the browser's global `onerror` handler, grouped in Sentry on nothing but
/// `Error._throw` and therefore sharing one issue with every other unhandled
/// fetch failure in the app (CLIENT-B01).
///
/// This is the same shape, and the same fix, as the language-flag SVG storm
/// one repo over (#8338 → `SvgRepo`, `network_svg_test.dart`) — a fetch on a
/// future nobody owns has to come back as a value.
///
/// What's pinned here: a transport failure surfaces as `Result.error` and
/// never as a throw; it carries the real cause; and it is distinguishable from
/// both a suppressed read and a genuinely empty viewport.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // GetStorage needs path_provider; stub the channel to a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('bbox_pins_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    // NOT an endpoint test — those are the live-backend suites that resolve a
    // real host through `endpoint_test_env.dart`
    // (testing.instructions.md). Every call here is served by `MockClient`
    // and no socket is opened; `.invalid` is the reserved TLD (RFC 6761) so a
    // regression that bypassed the mock would fail to resolve rather than
    // quietly reach a real service. This only exists because
    // `PApiUrls.activitiesBbox` resolves through `Environment.choreoApi`, and
    // with no host at all the URL never parses, so the request is never
    // attempted and the containment path under test is never reached.
    dotenv.testLoad(fileInput: 'CHOREO_API=https://api.test.invalid/choreo');
    MatrixState.pangeaController = FakePangeaController(accessToken: 'token');
  });

  setUp(QuestRepo.activityReadPause.reset);
  tearDown(QuestRepo.activityReadPause.reset);

  final bounds = LatLngBounds(const LatLng(0, 0), const LatLng(1, 1));

  /// Runs [body] with every top-level `http` call served by [handler].
  Future<T> withClient<T>(
    Future<http.Response> Function(http.Request) handler,
    Future<T> Function() body,
  ) => http.runWithClient(body, () => MockClient(handler));

  Future<Result<List<QuestActivityCard>>> pinsWith(
    Future<http.Response> Function(http.Request) handler,
  ) => withClient(handler, () => ActivityMapRepo.bboxPins(bounds: bounds));

  group('ActivityMapRepo.bboxPins containment', () {
    test(
      'a transport failure returns an error result, it does not throw',
      () async {
        // Verbatim the CLIENT-B01 exception: on dart2js a browser fetch
        // `TypeError` arrives as exactly this (package:http strips the
        // `TypeError: ` prefix). An abort would be a `RequestAbortedException`
        // instead, which is how that hypothesis was ruled out.
        final result = await pinsWith(
          (_) async => throw http.ClientException('Failed to fetch'),
        );

        expect(result.error, isA<http.ClientException>());
      },
    );

    test('a failed read does not read as an empty viewport', () async {
      // The caller keeps the pins it has on an error. An empty list would mean
      // "this viewport genuinely holds no activities" and would blank the map
      // on a transient network blip.
      final result = await pinsWith(
        (_) async => throw http.ClientException('Failed to fetch'),
      );

      expect(result.result, isNull);
      expect(result.result, isNot(const <QuestActivityCard>[]));
    });

    test('a failed read is not the suppressed read', () async {
      // Both leave the map's pins alone, but only one of them means the
      // request was actually issued. Conflating them would let a real outage
      // read as a quiet backoff.
      final result = await pinsWith(
        (_) async => throw http.ClientException('Failed to fetch'),
      );

      expect(result.error, isNot(isA<RateLimitedException>()));
    });

    test('a malformed body is contained too', () async {
      // Decoding and card mapping sit inside the same try as the request on
      // purpose: they run on the same unowned future, so before #8473 a body
      // that failed to parse escaped exactly as far as a failed fetch did.
      final result = await pinsWith(
        (_) async => http.Response('{"not": "a list"', 200),
      );

      expect(result.error, isNotNull);
      expect(result.result, isNull);
    });

    test('a non-429 failure does not arm the shared pause', () async {
      // `RateLimitPause.recordFailure` only arms on a 429 — a statement about
      // our rate. A transport failure says nothing about it, and pausing every
      // activity read on one would let a single bad response mute the map.
      // This is also why the identical bbox URI repeated 90 times in
      // CLIENT-B01: nothing throttles a `ClientException`, so every camera
      // settle re-fires it. Backoff for that case is deliberately still an
      // open design question (#8473) — this pins today's behavior, not a
      // decision.
      await pinsWith(
        (_) async => throw http.ClientException('Failed to fetch'),
      );

      expect(QuestRepo.activityReadPause.isPaused, isFalse);
    });

    test('a good response still parses to pins', () async {
      // The happy path through the Result refactor: a 200 must still come back
      // as a value, not as an error the map would silently hold old pins for.
      final result = await pinsWith((_) async => http.Response('[]', 200));

      expect(result.error, isNull);
      expect(result.result, isEmpty);
    });
  });
}
