// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';

const _profileFieldRoute =
    '/client/unstable/uk.tcpip.msc4133/profile/'
    '%40test%3AfakeServer.notExisting/${PangeaEventTypes.profileAnalytics}';

/// Records every public-profile PUT and holds each one open until released, so
/// a test can have two writes genuinely in flight at once.
class _GatedProfileApi extends FakeMatrixApi {
  final List<Map<String, dynamic>> puts = [];
  int inFlight = 0;
  int maxConcurrent = 0;
  Completer<void>? gate;

  @override
  FutureOr<http.Response> mockIntercept(http.Request request) async {
    final isProfilePut =
        request.method == 'PUT' &&
        request.url.path.endsWith(_profileFieldRoute);
    if (isProfilePut) {
      inFlight++;
      if (inFlight > maxConcurrent) maxConcurrent = inFlight;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      puts.add(body[PangeaEventTypes.profileAnalytics] as Map<String, dynamic>);
      if (gate != null) await gate!.future;
      inFlight--;
    }
    return super.mockIntercept(request);
  }
}

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);
  final Client _client;
  @override
  Client get client => _client;
}

/// #8611 — the public profile goes up as one blob, from four call sites,
/// several of which do not await. Concurrent PUTs are last-write-wins on the
/// wire, so overlapping them let an older blob land after a newer one and
/// silently undo it. Publishes are serialized, and coalesced: a save already
/// waiting carries the later caller's change too, so its payload is built when
/// its turn comes rather than snapshotted when it was queued.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late _GatedProfileApi api;
  late Client client;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('profile_serialize');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          for (final l in ['es', 'fr', 'nl', 'de'])
            {'language_code': l, 'language_name': l, 'l2_support': 'full'},
        ],
      }),
    });
    await PLanguageStore.initialize();
  });

  setUp(() async {
    api = _GatedProfileApi();
    api.api['GET']!['/.well-known/matrix/client'] = (_) => {};
    api.api['PUT']![_profileFieldRoute] = (_) => {};

    client = Client(
      'Profile serialization test',
      httpClient: api,
      database: await MatrixSdkDatabase.init(
        'test',
        database: await databaseFactoryFfi.openDatabase(
          ':memory:',
          options: OpenDatabaseOptions(singleInstance: false),
        ),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    await client.checkHomeserver(Uri.parse('https://fakeserver.notexisting'));
    await client.login(
      LoginType.mLoginToken,
      identifier: AuthenticationUserIdentifier(user: 'test'),
      password: '1234',
    );

    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
    MatrixState.pangeaController.userController.setPublicProfile(
      PublicProfileModel(analytics: AnalyticsProfileModel()),
      userId: client.userID,
    );
  });

  Map<String, dynamic> levels(Map<String, dynamic> put) =>
      (put[AnalyticsConstants.analytics] as Map).map(
        (k, v) => MapEntry(k as String, v[AnalyticsConstants.level]),
      );

  test('concurrent publishes never overlap on the wire', () async {
    final user = MatrixState.pangeaController.userController;
    api.gate = Completer<void>();

    final writes = [
      user.updateAnalyticsProfile(languageCode: 'es', level: 2),
      user.updateAnalyticsProfile(languageCode: 'fr', level: 3),
      user.updateAnalyticsProfile(languageCode: 'nl', level: 4),
      user.updateAnalyticsProfile(languageCode: 'de', level: 5),
    ];

    // Let the first PUT reach the wire and stay there.
    await Future.delayed(const Duration(milliseconds: 50));
    expect(api.inFlight, 1, reason: 'only one publish may be in flight');

    api.gate!.complete();
    await Future.wait(writes);

    expect(api.maxConcurrent, 1);
  });

  test(
    'a coalesced publish sends the state as of its turn, not when queued',
    () async {
      final user = MatrixState.pangeaController.userController;
      api.gate = Completer<void>();

      final first = user.updateAnalyticsProfile(languageCode: 'es', level: 2);
      await Future.delayed(const Duration(milliseconds: 50));

      // Queued while the first PUT is held open. Both must reach the server, and
      // the follow-up must carry BOTH languages — a payload snapshotted at queue
      // time would be missing whichever change came after it.
      final second = user.updateAnalyticsProfile(languageCode: 'fr', level: 3);
      final third = user.updateAnalyticsProfile(languageCode: 'nl', level: 4);

      api.gate!.complete();
      await Future.wait([first, second, third]);

      expect(levels(api.puts.first), {'es': 2});
      expect(
        levels(api.puts.last),
        {'es': 2, 'fr': 3, 'nl': 4},
        reason: 'the last publish must carry every change made before it',
      );
      // Three callers, but the two that queued together share one publish.
      expect(api.puts.length, 2);
    },
  );

  group('reconciliation', () {
    test('publishes a language the profile has never carried', () async {
      final user = MatrixState.pangeaController.userController;

      await user.reconcileAnalyticsLevels({'fr': 13, 'nl': 4});

      expect(levels(api.puts.single), {'fr': 13, 'nl': 4});
    });

    test('raises a level that has fallen behind the local data', () async {
      final user = MatrixState.pangeaController.userController;
      await user.updateAnalyticsProfile(languageCode: 'fr', level: 2);

      // The reported symptom: French really is 13, but the published entry has
      // been stuck at 2 since the learner last switched away from it.
      await user.reconcileAnalyticsLevels({'fr': 13});

      expect(levels(api.puts.last), {'fr': 13});
    });

    test(
      'never lowers a level, because a stale partition under-reports',
      () async {
        final user = MatrixState.pangeaController.userController;
        await user.updateAnalyticsProfile(languageCode: 'fr', level: 13);
        final before = api.puts.length;

        // This device has only part of French's history — another device holds
        // the rest. Missing events can only make the local level too LOW, so a
        // lower number is never evidence the published one is wrong.
        await user.reconcileAnalyticsLevels({'fr': 2});

        expect(api.puts.length, before, reason: 'nothing to publish');
      },
    );

    test('an equal level publishes nothing', () async {
      final user = MatrixState.pangeaController.userController;
      await user.updateAnalyticsProfile(languageCode: 'fr', level: 7);
      final before = api.puts.length;

      await user.reconcileAnalyticsLevels({'fr': 7});

      expect(api.puts.length, before);
    });

    test('the whole map goes up in one publish', () async {
      final user = MatrixState.pangeaController.userController;

      await user.reconcileAnalyticsLevels({'es': 2, 'fr': 3, 'nl': 4, 'de': 5});

      expect(api.puts.length, 1);
      expect(levels(api.puts.single), {'es': 2, 'fr': 3, 'nl': 4, 'de': 5});
    });

    test('a regional variant reconciles onto its language', () async {
      final user = MatrixState.pangeaController.userController;

      await user.reconcileAnalyticsLevels({'fr-CA': 13});

      expect(levels(api.puts.single), {'fr': 13});
    });
  });

  test('a failed publish does not wedge the ones queued behind it', () async {
    final user = MatrixState.pangeaController.userController;
    api.api['PUT']![_profileFieldRoute] = (_) => throw Exception('boom');

    await user.updateAnalyticsProfile(languageCode: 'es', level: 2);

    api.api['PUT']![_profileFieldRoute] = (_) => {};
    await user.updateAnalyticsProfile(languageCode: 'fr', level: 3);

    expect(levels(api.puts.last), {'es': 2, 'fr': 3});
  });
}
