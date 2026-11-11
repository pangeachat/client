import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/authentication/module_token_renewal_client.dart';
import 'package:fluffychat/features/authentication/token_renewal_extension.dart';
import 'package:fluffychat/features/join_codes/request_room_code_extension.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';

const _profileWriteRoute =
    '/client/unstable/uk.tcpip.msc4133/profile/'
    '%40test%3AfakeServer.notExisting/${PangeaEventTypes.profileAnalytics}';

const _roomCodeRoute = '/_synapse/client/pangea/v1/request_room_code';

/// [FakeMatrixApi] that answers a profile write and a call to the homeserver's
/// Pangea module, and records the bearer each one carried.
class _RecordingApi extends FakeMatrixApi {
  final List<String?> profileWrites = [];
  final List<String?> moduleCalls = [];

  _RecordingApi() {
    api['PUT']![_profileWriteRoute] = (_) => {};
    api['GET']![_roomCodeRoute] = (_) => {'access_code': 'abc123'};
  }

  @override
  FutureOr<http.Response> mockIntercept(http.Request request) {
    final bearer = request.headers['authorization'];
    if (request.url.path.endsWith(_profileWriteRoute)) {
      profileWrites.add(bearer);
    }
    if (request.url.path == _roomCodeRoute) moduleCalls.add(bearer);
    return super.mockIntercept(request);
  }
}

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// Just enough controller for a real [UserController], which reaches the
/// client through `MatrixState.pangeaController.matrixState`.
class _Controller implements PangeaController {
  _Controller(Client client) : matrixState = _FakeMatrixState(client);

  @override
  final MatrixState matrixState;

  @override
  UserController userController = UserController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Req extends BaseRequest {
  _Req(this.id);

  final String id;

  @override
  String get storageKey => id;

  @override
  Map<String, dynamic> toJson() => const {};
}

class _Resp extends BaseResponse {
  @override
  Map<String, dynamic> toJson() => const {};
}

/// A choreo read built the way every [BaseRepo] builds one: its carrier and
/// token come from the real [BaseRepo.createRequests].
class _ChoreoRepo extends BaseRepo<_Req, _Resp> {
  _ChoreoRepo()
    : super(
        cache: MemoryRepoCache<_Resp>(),
        responseFromJson: (_) => _Resp(),
        cacheDuration: Duration.zero,
      );

  @override
  Future<http.Response> fetch(Requests req, _Req request) =>
      req.get(url: 'https://choreo.test/choreo/v2/activity/${request.id}');
}

/// Renewal of an expired access token, at startup (#9304) and before every
/// Pangea request after it, such as the first ones after the app resumes
/// (#9835). See session-lifetime.instructions.md. Tokens last 24 hours, so a
/// learner who opens the app less than daily restores a session whose token
/// has already expired, and one who leaves it in the background for a day
/// resumes with one; every request sent before the renewal lands is refused.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  /// A session restored from storage the way the app restores one at
  /// startup, with an access token that expired an hour ago, sending through
  /// the HTTP client `ClientManager.createClient` gives it.
  Future<Client> restoredWithExpiredToken(
    Future<void> Function(Client) onSoftLogout, {
    FakeMatrixApi? api,
  }) async {
    late final Client client;
    client = Client(
      'renewal-test',
      httpClient: ModuleTokenRenewalClient(
        api ?? FakeMatrixApi(),
        () => client,
      ),
      database: await MatrixSdkDatabase.init(
        'renewal-test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
      onSoftLogout: onSoftLogout,
    );
    await client.checkHomeserver(
      Uri.parse('https://fakeServer.notExisting'),
      checkWellKnown: false,
    );
    await client.init(
      newToken: 'abcd',
      newRefreshToken: 'refresh_abcd',
      newTokenExpiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      newUserID: '@test:fakeServer.notExisting',
      newHomeserver: client.homeserver,
      newDeviceName: 'Test',
      newDeviceID: 'GHTYAJCE',
      waitForFirstSync: false,
    );
    return client;
  }

  /// A session whose renewal is held until [release] completes, then lands
  /// with the token [FakeMatrixApi] hands out, `a_new_token`. Returning before
  /// then is exactly the race these tests guard against: the SDK's own sync
  /// loop renews too, so checking only the final token would pass without the
  /// wait.
  Future<Client> heldUntil(Completer<void> release, {FakeMatrixApi? api}) =>
      restoredWithExpiredToken((client) async {
        await release.future;
        await client.refreshAccessToken();
      }, api: api);

  test('startup waits for the renewal to land before carrying on', () async {
    final release = Completer<void>();
    final client = await heldUntil(release);
    addTearDown(client.dispose);

    var returned = false;
    final renewal = client.renewExpiredToken().then((_) => returned = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(returned, isFalse);

    release.complete();
    await renewal;
    expect(returned, isTrue);
    expect(client.accessToken, 'a_new_token');
    expect(client.isLogged(), true);
  });

  test(
    'startup carries on after the wait when renewal cannot finish',
    () async {
      // A renewal that never answers, as when the device is offline.
      final never = Completer<void>();
      final client = await restoredWithExpiredToken((_) => never.future);
      addTearDown(client.dispose);

      await client.renewExpiredToken(wait: const Duration(milliseconds: 50));

      expect(client.isLogged(), true);
    },
  );

  test(
    'a session the server rejects starts signed out, without throwing',
    () async {
      final client = await restoredWithExpiredToken((_) async {
        throw MatrixException.fromJson({
          'errcode': 'M_UNKNOWN_TOKEN',
          'error': 'Invalid refresh token',
        });
      });
      addTearDown(client.dispose);

      await client.renewExpiredToken();

      expect(client.isLogged(), false);
    },
  );

  group('a request sent with an expired token', () {
    /// Serves every top-level `http` call made by [body] and records the
    /// bearer each one carried. Pangea service requests go out this way.
    Future<List<String?>> pangeaServiceBearers(
      Future<void> Function(List<String?> bearers) body,
    ) async {
      final bearers = <String?>[];
      await http.runWithClient(
        () => body(bearers),
        () => MockClient((request) async {
          bearers.add(request.headers['authorization']);
          return http.Response('{}', 200);
        }),
      );
      return bearers;
    }

    test(
      'to a Pangea service waits for the renewal and sends the new token',
      () async {
        final release = Completer<void>();
        final client = await heldUntil(release);
        addTearDown(client.dispose);
        MatrixState.pangeaController = _Controller(client);

        final bearers = await pangeaServiceBearers((bearers) async {
          final read = _ChoreoRepo().get(_Req('1'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          // Nothing has gone out with the token the server would refuse.
          expect(bearers, isEmpty);

          release.complete();
          expect((await read).isValue, isTrue);
        });

        expect(bearers, ['Bearer a_new_token']);
      },
    );

    test(
      'to the homeserver Pangea module waits for the renewal and sends the new token',
      () async {
        final release = Completer<void>();
        final api = _RecordingApi();
        final client = await heldUntil(release, api: api);
        addTearDown(client.dispose);

        final call = client.requestSpaceCode();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(api.moduleCalls, isEmpty);

        release.complete();
        expect(await call, 'abc123');
        expect(api.moduleCalls, ['Bearer a_new_token']);
      },
    );

    test(
      'as a profile write waits for the renewal and sends the new token',
      () async {
        final release = Completer<void>();
        final api = _RecordingApi();
        final client = await heldUntil(release, api: api);
        addTearDown(client.dispose);
        final controller = _Controller(client);
        MatrixState.pangeaController = controller;
        controller.userController.setPublicProfile(
          PublicProfileModel(analytics: AnalyticsProfileModel(), about: 'Hola'),
          userId: client.userID,
        );

        final write = controller.userController.updatePublicProfile();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(api.profileWrites, isEmpty);

        release.complete();
        await write;
        expect(api.profileWrites, ['Bearer a_new_token']);
      },
    );

    test('shares one renewal with the requests sent alongside it', () async {
      final release = Completer<void>();
      final api = _RecordingApi();
      var renewals = 0;
      final client = await restoredWithExpiredToken((client) async {
        renewals++;
        await release.future;
        await client.refreshAccessToken();
      }, api: api);
      addTearDown(client.dispose);
      MatrixState.pangeaController = _Controller(client);

      final bearers = await pangeaServiceBearers((bearers) async {
        final requests = [
          _ChoreoRepo().get(_Req('1')),
          _ChoreoRepo().get(_Req('2')),
          client.requestSpaceCode(),
        ];
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(bearers, isEmpty);
        expect(api.moduleCalls, isEmpty);

        release.complete();
        await Future.wait(requests);
      });

      expect(bearers, ['Bearer a_new_token', 'Bearer a_new_token']);
      expect(api.moduleCalls, ['Bearer a_new_token']);
      expect(renewals, 1);
    });

    test(
      'goes out after the wait, still signed in, when renewal cannot finish',
      () async {
        // A renewal that never answers, as when the device is offline.
        final never = Completer<void>();
        final client = await restoredWithExpiredToken((_) => never.future);
        addTearDown(client.dispose);
        MatrixState.pangeaController = _Controller(client);

        final bearers = <String?>[];
        var answered = false;
        fakeAsync((async) {
          http.runWithClient(
            () => _ChoreoRepo().get(_Req('1')).then((_) => answered = true),
            () => MockClient((request) async {
              bearers.add(request.headers['authorization']);
              return http.Response('{}', 200);
            }),
          );
          const tick = Duration(milliseconds: 1);
          async.elapse(TokenRenewalExtension.tokenRenewalWait - tick);
          // Still waiting for the renewal just before the wait runs out.
          expect(answered, isFalse);
          async.elapse(tick);
        });

        expect(answered, isTrue);
        expect(bearers, ['Bearer abcd']);
        expect(client.isLogged(), isTrue);
      },
    );
  });
}
