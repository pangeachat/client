import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/quests/repo/activity_map_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';

/// #8398 — the bbox request carries the resolved display language as `l1`, so
/// card text (title/description/learning objective) comes back localized and
/// map search matches what the learner sees. Omitting it keeps the canonical
/// response — the server contract (choreo #3037).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // GetStorage needs path_provider; stub the channel to a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('bbox_l1_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    // Served entirely by MockClient — `.invalid` never resolves, so a
    // regression that bypassed the mock fails loudly (see
    // bbox_pins_containment_test.dart).
    dotenv.testLoad(fileInput: 'CHOREO_API=https://api.test.invalid/choreo');
    MatrixState.pangeaController = FakePangeaController(accessToken: 'token');
  });

  final bounds = LatLngBounds(const LatLng(0, 0), const LatLng(1, 1));

  /// The query parameters of the one request [body] issues.
  Future<Map<String, String>> requestedParams({String? l1}) async {
    Uri? requested;
    await http.runWithClient(
      () => ActivityMapRepo.bboxPins(bounds: bounds, l2: 'es', l1: l1),
      () => MockClient((request) async {
        requested = request.url;
        return http.Response('[]', 200);
      }),
    );
    expect(requested, isNotNull, reason: 'the request was never issued');
    return requested!.queryParameters;
  }

  group('ActivityMapRepo.bboxPins display language', () {
    test('carries the resolved display language as l1', () async {
      final params = await requestedParams(l1: 'fr');
      expect(params['l1'], 'fr');
      expect(params['l2'], 'es');
    });

    test('omits l1 when none is resolved — canonical response', () async {
      final params = await requestedParams();
      expect(params.containsKey('l1'), isFalse);
    });
  });
}
