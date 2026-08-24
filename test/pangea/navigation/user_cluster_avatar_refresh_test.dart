// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model.dart';

/// The view model only reads [updateDispatcher] off the analytics service, so a
/// bare dispatcher stands in for the whole service — no DB, no sync.
class _FakeAnalyticsService implements AnalyticsDataService {
  @override
  late final AnalyticsUpdateDispatcher updateDispatcher =
      AnalyticsUpdateDispatcher(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _profileRoute = '/client/v3/profile/%40test%3AfakeServer.notExisting';
const _userId = '@test:fakeServer.notExisting';

/// Short enough to wait out in a test, long enough to land several signals in.
const _quietPeriod = Duration(milliseconds: 80);

Future<void> _afterQuietPeriod() => Future.delayed(_quietPeriod * 2);

/// One profile fetch the test completes by hand; [fromServer] records whether
/// the view model let the SDK answer from its cache.
class _ManualFetch {
  final Completer<Profile> completer = Completer();
  final bool fromServer;
  _ManualFetch({required this.fromServer});
}

/// A client whose own-profile fetches complete only when the test says so, to
/// pin down what the view model does with signals that land mid-fetch.
class _ManualProfileClient extends Client {
  _ManualProfileClient({required super.database})
    : super('Cluster avatar coalescing test');

  final List<_ManualFetch> fetches = [];

  @override
  String? get userID => _userId;

  // fetchOwnProfile funnels into this, so the override sees every fetch.
  @override
  Future<Profile> getProfileFromUserId(
    String userId, {
    bool? getFromRooms,
    bool? cache,
    Duration timeout = const Duration(seconds: 30),
    Duration maxCacheAge = const Duration(days: 1),
  }) {
    final fetch = _ManualFetch(fromServer: maxCacheAge == Duration.zero);
    fetches.add(fetch);
    return fetch.completer.future;
  }
}

Future<MatrixSdkDatabase> _inMemoryDatabase() async => MatrixSdkDatabase.init(
  'test',
  // sqflite hands the same open instance back per path, so without this
  // every test would share (and inherit the cache of) one DB.
  database: await databaseFactoryFfi.openDatabase(
    ':memory:',
    options: OpenDatabaseOptions(singleInstance: false),
  ),
  sqfliteFactory: databaseFactoryFfi,
);

/// #8330 — a profile picture changed from the settings page must reach the
/// cluster avatar, which stays mounted and so never refetches on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The view model reaches ActivityPlanRepo, whose cache opens GetStorage.
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('cluster_avatar');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
  });

  test('own profile update reloads the cluster avatar', () async {
    final api = FakeMatrixApi();
    final routes = api.api['GET']!;
    routes['/.well-known/matrix/client'] = (_) => {};
    routes[_profileRoute] = (_) => {'avatar_url': 'mxc://server/first'};

    final client = Client(
      'Cluster avatar test',
      httpClient: api,
      database: await _inMemoryDatabase(),
    );
    await client.checkHomeserver(Uri.parse('https://fakeserver.notexisting'));
    await client.login(
      LoginType.mLoginToken,
      identifier: AuthenticationUserIdentifier(user: '@alice:example.invalid'),
      password: '1234',
    );

    final viewModel = WorldUserClusterViewModel(
      analyticsService: _FakeAnalyticsService(),
      client: client,
    );
    addTearDown(viewModel.dispose);

    viewModel.reloadProfile();
    await pumpEventQueue();
    expect(viewModel.avatarUrl.value.toString(), 'mxc://server/first');

    // Only the server has the new picture — the SDK's cache still says first.
    routes[_profileRoute] = (_) => {'avatar_url': 'mxc://server/second'};

    // Someone else's change leaves our circle alone.
    client.onUserProfileUpdate.add('@someone:else.invalid');
    await pumpEventQueue();
    expect(viewModel.avatarUrl.value.toString(), 'mxc://server/first');

    client.onUserProfileUpdate.add(client.userID!);
    await pumpEventQueue();
    expect(viewModel.avatarUrl.value.toString(), 'mxc://server/second');
  });

  // A fetch already in flight may have left before the change reached the
  // server, so signals that land during it can't just be dropped — but a burst
  // of them (one member event per joined room) must not fan out into a fetch
  // apiece either: exactly one follow-up fetch, once the burst goes quiet.
  test('updates during a fetch fold into one follow-up fetch', () async {
    final client = _ManualProfileClient(database: await _inMemoryDatabase());
    final viewModel = WorldUserClusterViewModel(
      analyticsService: _FakeAnalyticsService(),
      client: client,
      profileRefreshQuietPeriod: _quietPeriod,
    );
    addTearDown(viewModel.dispose);

    viewModel.reloadProfile();
    expect(client.fetches, hasLength(1));
    expect(client.fetches[0].fromServer, isFalse, reason: 'first load: cache');

    for (var i = 0; i < 3; i++) {
      client.onUserProfileUpdate.add(_userId);
    }
    await pumpEventQueue();
    expect(client.fetches, hasLength(1), reason: 'burst waits on the fetch');

    client.fetches[0].completer.complete(
      Profile(userId: _userId, avatarUrl: Uri.parse('mxc://server/stale')),
    );
    await pumpEventQueue();
    expect(viewModel.avatarUrl.value.toString(), 'mxc://server/stale');
    expect(client.fetches, hasLength(1), reason: 'burst not yet quiet');

    await _afterQuietPeriod();
    expect(client.fetches, hasLength(2), reason: 'one follow-up for the burst');
    // The SDK just cached the stale answer as fresh; the follow-up must not
    // be served from it.
    expect(client.fetches[1].fromServer, isTrue);

    client.fetches[1].completer.complete(
      Profile(userId: _userId, avatarUrl: Uri.parse('mxc://server/fresh')),
    );
    await _afterQuietPeriod();
    expect(viewModel.avatarUrl.value.toString(), 'mxc://server/fresh');
    expect(client.fetches, hasLength(2), reason: 'nothing pending, no refetch');
  });

  test('a burst of signals costs one leading and one trailing fetch', () async {
    final client = _ManualProfileClient(database: await _inMemoryDatabase());
    final viewModel = WorldUserClusterViewModel(
      analyticsService: _FakeAnalyticsService(),
      client: client,
      profileRefreshQuietPeriod: _quietPeriod,
    );
    addTearDown(viewModel.dispose);

    // The first signal — the profile page's own announcement — fetches at
    // once, from the server, so a local edit shows immediately.
    client.onUserProfileUpdate.add(_userId);
    await pumpEventQueue();
    expect(client.fetches, hasLength(1));
    expect(client.fetches[0].fromServer, isTrue);
    client.fetches[0].completer.complete(
      Profile(userId: _userId, avatarUrl: Uri.parse('mxc://server/new')),
    );
    await pumpEventQueue();
    expect(viewModel.avatarUrl.value.toString(), 'mxc://server/new');

    // The member-event burst — one per joined room, each landing before the
    // stream has been quiet for long — folds into a single trailing fetch.
    for (var i = 0; i < 20; i++) {
      client.onUserProfileUpdate.add(_userId);
      await Future.delayed(_quietPeriod ~/ 4);
    }
    expect(client.fetches, hasLength(1), reason: 'burst still running');
    await _afterQuietPeriod();
    expect(client.fetches, hasLength(2), reason: 'one trailing fetch');
    expect(client.fetches[1].fromServer, isTrue);
    client.fetches[1].completer.complete(
      Profile(userId: _userId, avatarUrl: Uri.parse('mxc://server/new')),
    );
    await _afterQuietPeriod();
    expect(client.fetches, hasLength(2), reason: 'burst fully drained');
  });

  test('a fetch that lands after dispose is dropped', () async {
    final client = _ManualProfileClient(database: await _inMemoryDatabase());
    final viewModel = WorldUserClusterViewModel(
      analyticsService: _FakeAnalyticsService(),
      client: client,
    );

    viewModel.reloadProfile();
    viewModel.dispose();
    client.fetches.single.completer.complete(
      Profile(userId: _userId, avatarUrl: Uri.parse('mxc://server/late')),
    );
    // A disposed ValueNotifier throws on write; reaching here means it wasn't.
    await pumpEventQueue();
  });
}
