import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';

import 'endpoint_test_env.dart';

/// Synapse endpoint tests — exercise the client's real calls to the Matrix
/// homeserver (`Requests` + the client's `KnockSpaceResponse` model) against the
/// live Synapse at `EndpointTestEnv.synapseUrl` (the `SYNAPSE_URL` from
/// `client/.env`; keep it pointed at the same environment as choreo/cms).
///
/// Unlike `choreo_endpoint_test.dart`, these hit an **internal** service with no
/// paid third-party API, so there is no `mock: true` — the calls run for real.
/// Still integration-tier (internal real, nothing paid). Needs a running Synapse,
/// so it is local-only, not a PR gate — see testing.instructions.md.
///
/// Doubles as a local seeding tool. To put several learners into a course so you
/// can see a multi-user course locally, set in `client/.env`:
///   TEST_MATRIX_USERNAME / TEST_MATRIX_PASSWORD   (an existing account, for login)
///   TEST_COURSE_CODE=c5g1pza                       (the course's access code)
///   SEED_USERS=sofia,mateo                         (accounts to join; comma-sep)
///   SEED_USER_PASSWORD=learnerpass                 (their password; default learnerpass)
/// then run: flutter test test/pangea/synapse_endpoint_test.dart
/// Tests that lack their required env vars skip rather than fail.
void main() {
  late String synapse;

  setUpAll(() {
    EndpointTestEnv.load();
    synapse = EndpointTestEnv.synapseUrl;
  });

  Future<({String token, String userId})> login(
    String user,
    String password,
  ) async {
    final res = await Requests().post(
      url: '$synapse/_matrix/client/v3/login',
      body: {
        'type': 'm.login.password',
        'identifier': {'type': 'm.id.user', 'user': user},
        'password': password,
      },
    );
    expect(res.statusCode, 200, reason: 'login failed for $user');
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (token: json['access_token'] as String, userId: json['user_id'] as String);
  }

  /// Best-effort registration via the dummy flow. Swallows all errors: the
  /// account may already exist, or the homeserver may disable open registration
  /// (it returns 4xx and `Requests` throws). Callers fall back to login, so a
  /// pre-existing account still seeds; brand-new accounts must be created via the
  /// operator path (`register_new_matrix_user`) when open registration is off.
  Future<void> tryRegister(String user, String password) async {
    try {
      await Requests().post(
        url: '$synapse/_matrix/client/v3/register',
        body: {
          'username': user,
          'password': password,
          'auth': {'type': 'm.login.dummy'},
        },
      );
    } catch (_) {
      // ignore — see doc comment above
    }
  }

  /// The client's join-by-code call: validate the code and server-invite the
  /// caller to the matching course (parsed with the client's response model).
  Future<KnockSpaceResponse> knockWithCode(String token, String code) async {
    final res = await Requests(accessToken: token).post(
      url: '$synapse/_synapse/client/pangea/v1/knock_with_code',
      body: {'access_code': code},
    );
    expect(res.statusCode, 200, reason: 'knock_with_code failed');
    return KnockSpaceResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> acceptInvite(String token, String roomId) async {
    final res = await Requests(accessToken: token).post(
      url: '$synapse/_matrix/client/v3/rooms/$roomId/join',
      body: {},
    );
    expect(res.statusCode, 200, reason: 'join $roomId failed');
  }

  group('Synapse endpoint tests', () {
    test('login returns an access token', () async {
      final user = EndpointTestEnv.testUsername;
      final password = EndpointTestEnv.testPassword;
      if (user == null || password == null) {
        markTestSkipped('Set TEST_MATRIX_USERNAME / TEST_MATRIX_PASSWORD');
        return;
      }
      final session = await login(user, password);
      expect(session.token, isNotEmpty);
      expect(session.userId, isNotEmpty);
    });

    test('knock_with_code joins the test user to a course by code', () async {
      final code = dotenv.env['TEST_COURSE_CODE'];
      final user = EndpointTestEnv.testUsername;
      final password = EndpointTestEnv.testPassword;
      if (code == null || user == null || password == null) {
        markTestSkipped('Set TEST_COURSE_CODE + TEST_MATRIX_USERNAME/PASSWORD');
        return;
      }
      final session = await login(user, password);
      final response = await knockWithCode(session.token, code);
      final rooms = [...response.roomIds, ...response.alreadyJoined];
      expect(rooms, isNotEmpty, reason: 'no room matched code $code');
      for (final room in response.roomIds) {
        await acceptInvite(session.token, room);
      }
    });

    test('seed multiple learners into a course (SEED_USERS)', () async {
      final code = dotenv.env['TEST_COURSE_CODE'];
      final usersCsv = dotenv.env['SEED_USERS'];
      final password = dotenv.env['SEED_USER_PASSWORD'] ?? 'learnerpass';
      if (code == null || usersCsv == null || usersCsv.trim().isEmpty) {
        markTestSkipped('Set SEED_USERS (comma-separated) + TEST_COURSE_CODE');
        return;
      }
      final users = usersCsv
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      for (final user in users) {
        await tryRegister(user, password);
        final session = await login(user, password);
        final response = await knockWithCode(session.token, code);
        for (final room in response.roomIds) {
          await acceptInvite(session.token, room);
        }
      }
    });
  });
}
