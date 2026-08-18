// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/user/own_profile_client_extension.dart';

const _userId = '@test:fakeServer.notExisting';
const _profileRoute = '/client/v3/profile/%40test%3AfakeServer.notExisting';

/// A logged-in client over [FakeMatrixApi] whose GET /profile answers with
/// whatever [served] holds, plus a record of every own-profile announcement.
class _ProfileHarness {
  final FakeMatrixApi api = FakeMatrixApi();
  final List<String> announced = [];
  late final Client client;
  Map<String, dynamic> served = {
    'avatar_url': 'mxc://server/first',
    'displayname': 'First',
  };
  int profileGets = 0;

  Future<void> setUp() async {
    final gets = api.api['GET']!;
    gets['/.well-known/matrix/client'] = (_) => {};
    gets[_profileRoute] = (_) {
      profileGets++;
      return served;
    };
    api.api['PUT']!['$_profileRoute/displayname'] = (_) => {};

    client = Client(
      'Own profile test',
      httpClient: api,
      database: await MatrixSdkDatabase.init(
        'test',
        // sqflite hands the same open instance back per path, so without
        // this every test would share (and inherit the cache of) one DB.
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
      identifier: AuthenticationUserIdentifier(user: '@alice:example.invalid'),
      password: '1234',
    );

    // Warm the SDK's profile cache so a stale answer is what's on offer.
    final cached = await client.fetchOwnProfile();
    expect(cached.avatarUrl.toString(), 'mxc://server/first');
    client.onUserProfileUpdate.stream.listen(announced.add);
  }

  /// The write was announced for the own user, and a fetch now bypasses the
  /// stale cache to bring back what the server holds.
  Future<void> expectAnnouncedAndRefetched({
    required String avatarUrl,
    required String displayName,
  }) async {
    await pumpEventQueue();
    expect(announced, [_userId]);
    final gets = profileGets;
    final refetched = await client.fetchOwnProfile();
    expect(profileGets, gets + 1, reason: 'stale cache must not answer');
    expect(refetched.avatarUrl.toString(), avatarUrl);
    expect(refetched.displayName, displayName);
  }
}

/// #8330 — an own-profile write must not leave listeners waiting on the sync
/// round-trip: right after the server accepts it, the cached profile is stale
/// and the update stream has announced the change, so `fetchOwnProfile`
/// callers go back to the server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ProfileHarness harness;

  setUp(() async {
    harness = _ProfileHarness();
    await harness.setUp();
  });

  test(
    'setOwnAvatarUrl announces and invalidates the cached profile',
    () async {
      harness.served = {
        'avatar_url': 'mxc://server/second',
        'displayname': 'First',
      };
      await harness.client.setOwnAvatarUrl(Uri.parse('mxc://server/second'));
      await harness.expectAnnouncedAndRefetched(
        avatarUrl: 'mxc://server/second',
        displayName: 'First',
      );
    },
  );

  test(
    'setOwnAvatar(null) announces and invalidates the cached profile',
    () async {
      harness.served = {'displayname': 'First'};
      await harness.client.setOwnAvatar(null);
      await harness.expectAnnouncedAndRefetched(
        avatarUrl: 'null',
        displayName: 'First',
      );
    },
  );

  test(
    'setOwnDisplayName announces and invalidates the cached profile',
    () async {
      harness.served = {
        'avatar_url': 'mxc://server/first',
        'displayname': 'Second',
      };
      await harness.client.setOwnDisplayName('Second');
      await harness.expectAnnouncedAndRefetched(
        avatarUrl: 'mxc://server/first',
        displayName: 'Second',
      );
    },
  );

  test('a rejected write announces nothing and keeps the cache', () async {
    harness.api.api['PUT']!['$_profileRoute/displayname'] = (_) => {
      'errcode': 'M_FORBIDDEN',
      'error': 'nope',
    };
    await expectLater(
      harness.client.setOwnDisplayName('Second'),
      throwsA(isA<MatrixException>()),
    );
    await pumpEventQueue();
    expect(harness.announced, isEmpty);
    // Cache untouched: the (still current) first profile is served from it,
    // without a round-trip.
    final gets = harness.profileGets;
    final still = await harness.client.fetchOwnProfile();
    expect(still.displayName, 'First');
    expect(harness.profileGets, gets);
  });
}
