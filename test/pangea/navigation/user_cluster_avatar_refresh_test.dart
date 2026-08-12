// ignore_for_file: depend_on_referenced_packages

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
      database: await MatrixSdkDatabase.init(
        'test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
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

    routes[_profileRoute] = (_) => {'avatar_url': 'mxc://server/second'};
    // The sync loop marks the profile outdated before announcing it; without
    // that the client answers from its own cache.
    await client.database.markUserProfileAsOutdated(client.userID!);

    // Someone else's change leaves our circle alone.
    client.onUserProfileUpdate.add('@someone:else.invalid');
    await pumpEventQueue();
    expect(viewModel.avatarUrl.value.toString(), 'mxc://server/first');

    client.onUserProfileUpdate.add(client.userID!);
    await pumpEventQueue();
    expect(viewModel.avatarUrl.value.toString(), 'mxc://server/second');
  });
}
