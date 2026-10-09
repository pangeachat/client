import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/network_filter/filtered_network_controller.dart';
import 'package:fluffychat/features/network_filter/network_host_category.dart';
import 'package:fluffychat/features/network_filter/network_probe.dart';
import 'package:fluffychat/features/network_filter/network_type.dart';
import 'package:fluffychat/features/network_filter/network_verdict.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import '../sentry_capture_harness.dart';

/// #9434 — which host categories the network blocks, and when the app checks.
void main() {
  const chatHost = 'matrix.example.test';
  const apiHost = 'api.example.test';
  const cmsHost = 'cms.example.test';
  final neutralHosts = NetworkProbe.neutralUrls.map((url) => url.host).toSet();

  final controller = FilteredNetworkController.instance;
  late Map<String, NetworkProbeResult> answers;
  late List<String> probedHosts;
  late StreamController<List<ConnectivityResult>> networkChanges;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Environment.appConfigOverride reads a GetStorage('env_override') box that
    // needs path_provider; stub the channel to a temp dir so init is silent.
    final tempDir = await Directory.systemTemp.createTemp(
      'filtered_network_controller_test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'SYNAPSE_URL': 'https://$chatHost',
        'CHOREO_API': 'https://$apiHost',
        'CMS_API': 'https://$cmsHost',
      },
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    answers = {
      for (final host in neutralHosts) host: NetworkProbeResult.answered,
    };
    probedHosts = [];
    networkChanges = StreamController.broadcast();
    controller.probe = (url) async {
      probedHosts.add(url.host);
      return answers[url.host] ?? NetworkProbeResult.answered;
    };
    controller.onNetworkChanged = () => networkChanges.stream;
    controller.currentNetworkType = () async => NetworkType.wifi;
  });

  tearDown(() async {
    controller.resetForTest();
    ErrorHandler.resetReportedOnceKeysForTest();
    unawaited(networkChanges.close());
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'a refused host with the neutral hosts answering is filtered, and reported once',
    () async {
      answers[chatHost] = NetworkProbeResult.refused;

      expect(
        await controller.check(NetworkHostCategory.chatServer),
        NetworkVerdict.filtered,
      );
      expect(
        await controller.check(NetworkHostCategory.chatServer),
        NetworkVerdict.filtered,
      );
      await settle();

      expect(controller.blocked.value, {NetworkHostCategory.chatServer});
      expect(controller.firstBlockedAt, isNotNull);
      expect(
        ErrorHandler.reportedOnceKeysForTest,
        contains('filtered-network-chatServer'),
      );
    },
  );

  test('a host that answers costs one request and blocks nothing', () async {
    expect(
      await controller.check(NetworkHostCategory.pangeaApi),
      NetworkVerdict.reachable,
    );

    expect(probedHosts, [apiHost]);
    expect(controller.blocked.value, isEmpty);
  });

  test('our own outage is not a block', () async {
    answers[apiHost] = NetworkProbeResult.slow;

    expect(
      await controller.check(NetworkHostCategory.pangeaApi),
      NetworkVerdict.reachable,
    );
    expect(controller.blocked.value, isEmpty);
  });

  test('an offline device is never reported as filtered', () async {
    controller.probe = (url) async => NetworkProbeResult.refused;

    expect(
      await controller.check(NetworkHostCategory.chatServer),
      NetworkVerdict.offline,
    );
    await settle();

    expect(controller.blocked.value, isEmpty);
    expect(ErrorHandler.reportedOnceKeysForTest, isEmpty);
  });

  test('going offline leaves a block already seen in place', () async {
    answers[chatHost] = NetworkProbeResult.refused;
    await controller.check(NetworkHostCategory.chatServer);
    for (final host in neutralHosts) {
      answers[host] = NetworkProbeResult.refused;
    }

    expect(
      await controller.check(NetworkHostCategory.chatServer),
      NetworkVerdict.offline,
    );
    expect(controller.blocked.value, {NetworkHostCategory.chatServer});
  });

  test('a request that reaches a blocked host clears the block', () async {
    answers[chatHost] = NetworkProbeResult.refused;
    await controller.check(NetworkHostCategory.chatServer);

    controller.onRequestSucceeded(
      Uri.https(chatHost, '/_matrix/client/v3/sync'),
    );

    expect(controller.blocked.value, isEmpty);
  });

  test(
    'a failed request checks its host once however many fail at once',
    () async {
      final url = Uri.https(apiHost, '/choreo/tokenize');
      for (var i = 0; i < 3; i++) {
        controller.onRequestFailed(url);
      }
      await settle();
      controller.onRequestFailed(url);
      await settle();

      expect(probedHosts, [apiHost]);
    },
  );

  test(
    'a failed request to a host the app does not watch checks nothing',
    () async {
      controller.onRequestFailed(Uri.https('example.com', '/image.png'));
      await settle();

      expect(probedHosts, isEmpty);
    },
  );

  test('a network change re-checks what was blocked', () async {
    answers[NetworkHostCategory.video.probeUrl.host] =
        NetworkProbeResult.refused;
    await controller.check(NetworkHostCategory.video);
    expect(controller.blocked.value, {NetworkHostCategory.video});

    answers[NetworkHostCategory.video.probeUrl.host] =
        NetworkProbeResult.answered;
    networkChanges.add([ConnectivityResult.mobile]);
    await settle();

    expect(controller.blocked.value, isEmpty);
  });

  test(
    'observe passes a request with no response on, and checks its host',
    () async {
      final url = Uri.https(apiHost, '/choreo/tokenize');
      answers[apiHost] = NetworkProbeResult.refused;

      await expectLater(
        controller.observe(
          url,
          Future<void>.error(http.ClientException('Failed to fetch', url)),
        ),
        throwsA(isA<http.ClientException>()),
      );
      await settle();

      expect(controller.blocked.value, {NetworkHostCategory.pangeaApi});
    },
  );

  test(
    'a TLS failure, which package:http does not wrap, also starts a check',
    () async {
      final url = Uri.https(apiHost, '/choreo/tokenize');
      answers[apiHost] = NetworkProbeResult.refused;

      await expectLater(
        controller.observe(
          url,
          Future<void>.error(
            const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
          ),
        ),
        throwsA(isA<HandshakeException>()),
      );
      await settle();

      expect(controller.blocked.value, {NetworkHostCategory.pangeaApi});
    },
  );

  test('any other error passes through without a check', () async {
    final url = Uri.https(apiHost, '/choreo/tokenize');

    await expectLater(
      controller.observe(
        url,
        Future<void>.error(const FormatException('bad json')),
      ),
      throwsA(isA<FormatException>()),
    );
    await settle();

    expect(probedHosts, isEmpty);
  });

  group('the report', () {
    late SentryCaptureHarness harness;

    setUp(() async {
      harness = SentryCaptureHarness();
      await harness.init();
    });

    tearDown(() => harness.close());

    test(
      'is an error tagged with the category, platform and network type',
      () async {
        answers[apiHost] = NetworkProbeResult.refused;

        final event = await harness.capture(
          () => controller.check(NetworkHostCategory.pangeaApi),
        );

        expect(event.level, SentryLevel.error);
        expect(event.tags, containsPair('blocked_host_category', 'pangeaApi'));
        expect(event.tags, containsPair('network_type', 'wifi'));
        expect(
          event.tags,
          containsPair('app_platform', FilteredNetworkController.platformName),
        );
      },
    );
  });

  test('the IT list names every host the app needs', () {
    final domains = NetworkHostCategory.allAllowlistDomains;
    expect(domains, contains(cmsHost));
    for (final category in NetworkHostCategory.values) {
      expect(
        domains,
        contains(category.probeUrl.host.replaceFirst('www.', '')),
      );
    }
  });
}
