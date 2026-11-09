import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' show Client, LoginState;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/connection_status/filtered_network_controller.dart';
import 'package:fluffychat/features/connection_status/network_help_repo.dart';
import 'package:fluffychat/features/connection_status/network_help_request.dart';
import 'package:fluffychat/features/connection_status/network_host_category.dart';
import 'package:fluffychat/features/connection_status/network_type.dart';
import 'package:fluffychat/features/languages/locale_provider.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/test_client.dart';
import '../sentry_capture_harness.dart';

/// #9434 — "Ask Pangea for help": a CMS form submission the team is emailed,
/// held on the device until the CMS can be reached, one a day.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final request = NetworkHelpRequest(
    email: 'teacher@school.example',
    accountId: '@teacher:pangea.chat',
    blockedCategories: const [
      NetworkHostCategory.pangeaApi,
      NetworkHostCategory.video,
    ],
    platform: 'web',
    networkType: NetworkType.wifi,
    firstBlockedAt: DateTime.utc(2026, 10, 8, 14, 30),
  );

  late List<http.Request> posts;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'network_help_repo_test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://api.example.test'});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NetworkHelpRepo.resetForTest();
    FilteredNetworkController.instance.onNetworkChanged = () =>
        const Stream<List<ConnectivityResult>>.empty();
    posts = [];
  });

  tearDown(() {
    FilteredNetworkController.instance.resetForTest();
    ErrorHandler.resetReportedOnceKeysForTest();
  });

  /// Runs [work] with every request answered by [answer].
  Future<void> withCms(
    Future<http.Response> Function(http.Request) answer,
    Future<void> Function() work,
  ) => http.runWithClient(
    work,
    () => MockClient((request) {
      // A failed send also starts the network check, whose probes are HEADs.
      if (request.method == 'POST') posts.add(request);
      return answer(request);
    }),
  );

  Future<http.Response> created(http.Request _) async =>
      http.Response('{}', 201);

  test('a request reaches the CMS as a network-help form submission', () async {
    await withCms(created, () => NetworkHelpRepo.submit(request));

    expect(NetworkHelpRepo.status.value, NetworkHelpStatus.sent);
    expect(posts, hasLength(1));
    expect(posts.single.url.path, '/cms/api/form-submissions');
    final body = jsonDecode(posts.single.body) as Map<String, dynamic>;
    expect(body['formType'], 'network-help');
    expect(body['name'], '@teacher:pangea.chat');
    expect(body['email'], 'teacher@school.example');
    expect(body['data'], {
      'accountId': '@teacher:pangea.chat',
      'blockedCategories': ['pangeaApi', 'video'],
      'platform': 'web',
      'networkType': 'wifi',
      'firstBlockedAt': '2026-10-08T14:30:00.000Z',
    });
  });

  test('a signed-out user is named by their email', () {
    final signedOut = NetworkHelpRequest.fromJson({
      ...request.toJson(),
      'accountId': null,
    });
    expect(signedOut.toFormSubmission()['name'], 'teacher@school.example');
  });

  test('an account sends one request a day', () async {
    await withCms(created, () => NetworkHelpRepo.submit(request));
    NetworkHelpRepo.resetForTest();
    await withCms(created, () => NetworkHelpRepo.submit(request));

    expect(posts, hasLength(1));
    expect(NetworkHelpRepo.status.value, NetworkHelpStatus.sent);
  });

  test(
    'a request with no response waits, and goes out on the next good connection',
    () async {
      await withCms(
        (r) => throw http.ClientException('Failed to fetch', r.url),
        () => NetworkHelpRepo.submit(request),
      );
      expect(NetworkHelpRepo.status.value, NetworkHelpStatus.waiting);
      // Nothing is blocked, but the waiting request alone keeps the app
      // listening for a better network.
      expect(FilteredNetworkController.instance.blocked.value, isEmpty);
      expect(FilteredNetworkController.instance.isWatchingNetwork, isTrue);

      // A new session reads the waiting request back from the device.
      NetworkHelpRepo.resetForTest();
      await NetworkHelpRepo.refreshStatus();
      expect(NetworkHelpRepo.status.value, NetworkHelpStatus.waiting);

      await withCms(created, NetworkHelpRepo.flush);
      expect(NetworkHelpRepo.status.value, NetworkHelpStatus.sent);
      expect(posts, hasLength(2));
      expect(FilteredNetworkController.instance.isWatchingNetwork, isFalse);
    },
  );

  /// #9592 — the limit is per account: the next account on a shared device
  /// gets the form, and never sees "Sent" for a request it did not make.
  group('signing out', () {
    late Client client;

    setUpAll(() async => client = await prepareTestClient());

    tearDownAll(() => client.dispose());

    test('lets the next account send its own request', () async {
      await withCms(created, () => NetworkHelpRepo.submit(request));
      await NetworkHelpRepo.onSignOut();
      expect(NetworkHelpRepo.status.value, NetworkHelpStatus.none);

      await withCms(created, () => NetworkHelpRepo.submit(request));
      expect(posts, hasLength(2));
      expect(NetworkHelpRepo.status.value, NetworkHelpStatus.sent);
    });

    test('keeps a waiting request, which goes out on the next good '
        'connection', () async {
      await withCms(
        (r) => throw http.ClientException('Failed to fetch', r.url),
        () => NetworkHelpRepo.submit(request),
      );
      await NetworkHelpRepo.onSignOut();
      expect(NetworkHelpRepo.status.value, NetworkHelpStatus.waiting);

      await withCms(created, NetworkHelpRepo.flush);
      expect(posts, hasLength(2));
      expect(NetworkHelpRepo.status.value, NetworkHelpStatus.sent);
    });

    testWidgets('clears the mark when the app signs an account out', (
      tester,
    ) async {
      // A cached language list, so the controller fetches none.
      SharedPreferences.setMockInitialValues({
        PrefKey.lastFetched: DateTime.now().toIso8601String(),
        PrefKey.languagesKey: jsonEncode({
          PrefKey.languagesKey: [
            {
              'language_code': 'es',
              'language_name': 'Spanish',
              'l2_support': 'full',
            },
          ],
        }),
      });
      late BuildContext context;
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleProvider(),
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final controller = PangeaController(
        matrixState: _FakeMatrixState(client),
      );

      await tester.runAsync(() async {
        await withCms(created, () => NetworkHelpRepo.submit(request));
        expect(NetworkHelpRepo.status.value, NetworkHelpStatus.sent);
        await controller.handleLoginStateChange(
          LoginState.loggedOut,
          null,
          context,
        );
        // The sign-out does not wait for the mark to clear.
        await Future<void>.delayed(Duration.zero);
      });

      expect(NetworkHelpRepo.status.value, NetworkHelpStatus.none);
    });
  });

  group('a request the CMS refuses', () {
    late SentryCaptureHarness harness;

    setUp(() async {
      harness = SentryCaptureHarness();
      await harness.init();
    });

    tearDown(() => harness.close());

    test('is reported, and not resent for the rest of the session', () async {
      final event = await harness.capture(
        () => withCms(
          (_) async => http.Response('{"errors":[]}', 400),
          () => NetworkHelpRepo.submit(request),
        ),
      );
      expect(event.throwable.toString(), contains('400'));
      expect(NetworkHelpRepo.status.value, NetworkHelpStatus.refused);

      await withCms(created, NetworkHelpRepo.flush);
      expect(posts, hasLength(1));
    });
  });
}

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}
