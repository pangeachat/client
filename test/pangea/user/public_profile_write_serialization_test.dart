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

  test('a change is announced before its publish reaches the server', () async {
    // Surfaces read the level through this stream because the profile is
    // mutated in place. Announcing from inside the publish instead held every
    // update back for however long the chain ahead of it took — the staleness
    // the stream exists to remove (#8582).
    final user = MatrixState.pangeaController.userController;
    api.gate = Completer<void>();

    // One publish already in flight and held open, so the next change has a
    // chain ahead of it. That is the only arrangement that tells the two
    // placements apart: announcing from inside the publish would make this
    // change wait for the stalled one to return.
    unawaited(user.updateAnalyticsProfile(languageCode: 'es', level: 2));
    await Future.delayed(const Duration(milliseconds: 50));
    expect(api.inFlight, 1);

    final announced = <int?>[];
    final sub = user.publicProfileStream.stream.listen(
      (p) => announced.add(p?.analytics.languageAnalytics?['fr']?.level),
    );

    unawaited(user.updateAnalyticsProfile(languageCode: 'fr', level: 9));
    await Future.delayed(const Duration(milliseconds: 50));

    expect(
      announced,
      contains(9),
      reason: 'announced when the change is made, not when its publish lands',
    );

    api.gate!.complete();
    await sub.cancel();
  });

  test('a logout mid-publish does not start an overlapping write', () async {
    // clear() must not reset the publish chain: reassigning it cannot detach a
    // callback already registered on the old future, and starting a fresh chain
    // while a request is in flight lets the next publish overlap it — the
    // last-write-wins loss the chain exists to prevent.
    final user = MatrixState.pangeaController.userController;
    api.gate = Completer<void>();

    unawaited(user.updateAnalyticsProfile(languageCode: 'es', level: 2));
    await Future.delayed(const Duration(milliseconds: 50));
    expect(api.inFlight, 1);

    user.clear();
    user.setPublicProfile(
      PublicProfileModel(analytics: AnalyticsProfileModel()),
      userId: client.userID,
    );
    unawaited(user.updateAnalyticsProfile(languageCode: 'fr', level: 3));
    await Future.delayed(const Duration(milliseconds: 50));

    expect(
      api.maxConcurrent,
      1,
      reason: 'a logout must not let a second publish overlap the first',
    );

    api.gate!.complete();
    await Future.delayed(const Duration(milliseconds: 50));
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
