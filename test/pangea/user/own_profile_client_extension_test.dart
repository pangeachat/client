// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/user/own_profile_client_extension.dart';

const _userId = '@test:fakeServer.notExisting';
const _profileRoute = '/client/v3/profile/%40test%3AfakeServer.notExisting';

/// [FakeMatrixApi] whose profile PUTs can be held open (never answering until
/// released) or failed at the transport — the shapes a large account's write
/// takes when the homeserver's in-request propagation outlives the proxy.
class _ProfileApi extends FakeMatrixApi {
  /// While set, every profile PUT waits on this before being answered.
  Completer<void>? holdProfilePuts;

  /// While set, every profile PUT throws this instead of being answered.
  Object? failProfilePutsWith;

  int profilePuts = 0;

  bool _isProfilePut(http.Request request) =>
      request.method == 'PUT' &&
      request.url.path.contains('/_matrix$_profileRoute/');

  @override
  FutureOr<http.Response> mockIntercept(http.Request request) async {
    if (_isProfilePut(request)) {
      profilePuts++;
      final hold = holdProfilePuts;
      if (hold != null) await hold.future;
      final failure = failProfilePutsWith;
      if (failure != null) throw failure;
    }
    return super.mockIntercept(request);
  }
}

/// A logged-in client over [_ProfileApi] whose GET /profile answers with
/// whatever [served] holds, plus a record of every own-profile announcement.
class _ProfileHarness {
  final _ProfileApi api = _ProfileApi();
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
    api.api['PUT']!['$_profileRoute/avatar_url'] = (_) => {};
    api.api['POST']!['/media/v3/upload?filename=avatar.png'] = (_) => {
      'content_uri': 'mxc://server/uploaded',
    };

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

  /// What the sync loop raises when a member event for the own user lands:
  /// the first of a large account's burst arrives long before its PUT returns.
  void raiseSyncSignal() => client.onUserProfileUpdate.add(_userId);

  /// The write was announced for the own user, and a fetch now bypasses the
  /// stale cache to bring back what the server holds.
  Future<void> expectAnnouncedAndRefetched({
    required String avatarUrl,
    required String displayName,
    int announcements = 1,
  }) async {
    await pumpEventQueue();
    expect(announced, List.filled(announcements, _userId));
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
/// callers go back to the server. And the write is judged by what the server
/// holds, not by whether the request came back: on Synapse before 1.150 the
/// PUT propagates to every joined room before answering, so a large account's
/// write can outlive the proxy after the server already applied it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ProfileHarness harness;

  setUp(() async {
    harness = _ProfileHarness();
    await harness.setUp();
  });

  group('the request completes', () {
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

    test('setOwnAvatar(file) uploads, then points the profile at it', () async {
      harness.served = {
        'avatar_url': 'mxc://server/uploaded',
        'displayname': 'First',
      };
      await harness.client.setOwnAvatar(
        MatrixFile(bytes: Uint8List.fromList([1, 2, 3]), name: 'avatar.png'),
      );
      expect(
        FakeMatrixApi.calledEndpoints.keys,
        contains('/media/v3/upload?filename=avatar.png'),
      );
      expect(
        FakeMatrixApi.calledEndpoints['$_profileRoute/avatar_url']!.single,
        '{"avatar_url":"mxc://server/uploaded"}',
      );
      await harness.expectAnnouncedAndRefetched(
        avatarUrl: 'mxc://server/uploaded',
        displayName: 'First',
      );
    });

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
  });

  group('the request fails after the server applied the value', () {
    // The proxy gives up on the long PUT: the browser sees a transport error,
    // yet GET /profile already returns the new value.
    setUp(() {
      harness.api.failProfilePutsWith = http.ClientException(
        'XMLHttpRequest error.',
      );
    });

    test('setOwnAvatarUrl resolves and announces', () async {
      harness.served = {
        'avatar_url': 'mxc://server/second',
        'displayname': 'First',
      };
      await harness.client.setOwnAvatarUrl(Uri.parse('mxc://server/second'));
      await harness.expectAnnouncedAndRefetched(
        avatarUrl: 'mxc://server/second',
        displayName: 'First',
      );
    });

    test(
      'setOwnAvatar(null) resolves when the server serves no avatar',
      () async {
        harness.served = {'displayname': 'First'};
        await harness.client.setOwnAvatar(null);
        await harness.expectAnnouncedAndRefetched(
          avatarUrl: 'null',
          displayName: 'First',
        );
      },
    );

    test('setOwnDisplayName resolves and announces', () async {
      harness.served = {
        'avatar_url': 'mxc://server/first',
        'displayname': 'Second',
      };
      await harness.client.setOwnDisplayName('Second');
      await harness.expectAnnouncedAndRefetched(
        avatarUrl: 'mxc://server/first',
        displayName: 'Second',
      );
    });

    test(
      'the failure surfaces when the server does not hold the value',
      () async {
        // Server still has the old name: a genuine failure, reported as such.
        await expectLater(
          harness.client.setOwnDisplayName('Second'),
          throwsA(isA<http.ClientException>()),
        );
        await pumpEventQueue();
        expect(harness.announced, isEmpty);
      },
    );

    test(
      'the failure surfaces when the server cannot be read either',
      () async {
        harness.api.api['GET']![_profileRoute] = (_) =>
            throw http.ClientException('offline');
        await expectLater(
          harness.client.setOwnDisplayName('Second'),
          throwsA(isA<http.ClientException>()),
        );
        await pumpEventQueue();
        expect(harness.announced, isEmpty);
      },
    );
  });

  group('the request is still in flight', () {
    late Completer<void> release;

    setUp(() {
      release = harness.api.holdProfilePuts = Completer<void>();
    });

    test(
      'a sync signal with the server holding the value resolves the write',
      () async {
        harness.served = {
          'avatar_url': 'mxc://server/second',
          'displayname': 'First',
        };
        final write = harness.client.setOwnAvatarUrl(
          Uri.parse('mxc://server/second'),
        );
        await pumpEventQueue();
        expect(harness.api.profilePuts, 1, reason: 'the PUT went out');
        expect(harness.announced, isEmpty, reason: 'nothing to announce yet');

        harness.raiseSyncSignal();
        await write.timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('the write must not wait on the held PUT'),
        );
        // One announcement from the sync signal itself, one from the write.
        await harness.expectAnnouncedAndRefetched(
          avatarUrl: 'mxc://server/second',
          displayName: 'First',
          announcements: 2,
        );
        release.complete();
      },
    );

    test('a sync signal without the server holding the value keeps waiting, '
        'and later signals are not re-checked', () async {
      // A straggler from an earlier burst: the server still has the old
      // picture, so the write waits for its own request — and the rest of
      // the burst (one event per joined room) must not cost a read each.
      var settled = false;
      final write = harness.client
          .setOwnAvatarUrl(Uri.parse('mxc://server/second'))
          .then((_) => settled = true);
      await pumpEventQueue();
      final gets = harness.profileGets;
      for (var i = 0; i < 20; i++) {
        harness.raiseSyncSignal();
        await pumpEventQueue();
      }
      expect(settled, isFalse);
      expect(harness.profileGets, gets + 1, reason: 'one read per write');

      harness.served = {
        'avatar_url': 'mxc://server/second',
        'displayname': 'First',
      };
      release.complete();
      await write;
      expect(settled, isTrue);
      await harness.expectAnnouncedAndRefetched(
        avatarUrl: 'mxc://server/second',
        displayName: 'First',
        announcements: 21,
      );
    });

    test(
      'a display name the server stores stripped still counts as applied',
      () async {
        // Synapse strips surrounding whitespace before storing.
        harness.served = {
          'avatar_url': 'mxc://server/first',
          'displayname': 'Second',
        };
        final write = harness.client.setOwnDisplayName('  Second ');
        await pumpEventQueue();
        harness.raiseSyncSignal();
        await write.timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('the write must not wait on the held PUT'),
        );
        release.complete();
      },
    );

    test(
      'a write resolved early tolerates its request failing afterwards',
      () async {
        harness.served = {
          'avatar_url': 'mxc://server/first',
          'displayname': 'Second',
        };
        final write = harness.client.setOwnDisplayName('Second');
        await pumpEventQueue();
        harness.raiseSyncSignal();
        await write;

        // The held PUT now dies at the proxy — nothing for the caller to see.
        harness.api.failProfilePutsWith = http.ClientException('late 504');
        release.complete();
        await pumpEventQueue();
        await harness.expectAnnouncedAndRefetched(
          avatarUrl: 'mxc://server/first',
          displayName: 'Second',
          announcements: 2,
        );
      },
    );
  });
}
