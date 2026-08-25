import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../endpoint_test_env.dart';

/// Live-SDK harness for the Synapse contract suite.
///
/// Builds a real matrix-dart-sdk [Client] — in-memory database, real HTTP —
/// pointed at the Synapse from `client/.env`, so tests call the client's own
/// extension methods and the bytes on the wire are exactly what the app
/// sends. See testing.instructions.md § Contract tests.
///
/// Accounts: on the local stack (open registration) [loggedIn] registers the
/// deterministic persona idempotently, so the suite is self-seeding. Against
/// staging (registration closed) it falls back to `TEST_MATRIX_*` from `.env`
/// for the primary persona; multi-account tests skip there.
class ContractHarness {
  static const String personaPassword = 'contract-test-pass-1';

  /// Deterministic personas. One account each on the target homeserver.
  static const String learnerA = 'contract-learner-a';
  static const String learnerB = 'contract-learner-b';
  static const String teacher = 'contract-teacher';

  static int _clientCounter = 0;
  static bool _ffiInitialized = false;

  /// A fresh unauthenticated [Client] with an in-memory database (the same
  /// recipe the SDK's own tests use), homeserver already resolved.
  static Future<Client> newClient() async {
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      _ffiInitialized = true;
    }
    final n = _clientCounter++;
    final database = await MatrixSdkDatabase.init(
      'contract_test_${DateTime.now().millisecondsSinceEpoch}_$n',
      database: await databaseFactoryFfi.openDatabase(
        ':memory:',
        options: OpenDatabaseOptions(singleInstance: false),
      ),
      sqfliteFactory: databaseFactoryFfi,
    );
    final client = Client('contract-test-$n', database: database);
    await client.checkHomeserver(Uri.parse(EndpointTestEnv.synapseUrl));
    return client;
  }

  /// A logged-in client for [persona], creating the account when the
  /// homeserver allows it. First sync completed before returning, so
  /// extension methods that wait on sync echoes work.
  static Future<Client> loggedIn(String persona) async {
    final client = await newClient();
    final registered = await _tryRegister(client, persona);
    if (!registered) {
      var username = persona;
      var password = personaPassword;
      if (!await _loginWorks(client, username, password)) {
        // Registration closed and no persona account: staging fallback.
        final envUser = EndpointTestEnv.testUsername;
        final envPass = EndpointTestEnv.testPassword;
        if (envUser == null || envPass == null) {
          throw StateError(
            'Cannot provision "$persona": registration is closed on '
            '${EndpointTestEnv.synapseUrl} and no TEST_MATRIX_* fallback '
            'credentials are set in client/.env',
          );
        }
        username = envUser;
        password = envPass;
        await client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(user: username),
          password: password,
          initialDeviceDisplayName: 'synapse-contract-suite',
        );
      }
    }
    await client.roomsLoading;
    await client.oneShotSync();
    return client;
  }

  /// Registers [username], completing the m.login.dummy UIA stage the local
  /// stack offers. Returns true when the client is now logged in via
  /// registration; false when the account already exists or registration is
  /// closed (callers log in instead).
  static Future<bool> _tryRegister(Client client, String username) async {
    try {
      await client.register(
        username: username,
        password: personaPassword,
        initialDeviceDisplayName: 'synapse-contract-suite',
      );
      return true;
    } on MatrixException catch (e) {
      // Order matters: a UIA challenge (401, no errcode) must be inspected
      // before errcode classification — the SDK maps a missing errcode to a
      // generic error that would read as "registration closed".
      final session = e.session;
      if (e.requireAdditionalAuthentication && session != null) {
        try {
          await client.register(
            username: username,
            password: personaPassword,
            initialDeviceDisplayName: 'synapse-contract-suite',
            auth: AuthenticationData(
              type: AuthenticationTypes.dummy,
              session: session,
            ),
          );
          return true;
        } on MatrixException catch (e2) {
          if (e2.error == MatrixError.M_USER_IN_USE ||
              e2.error == MatrixError.M_FORBIDDEN) {
            return false;
          }
          rethrow;
        }
      }
      if (e.error == MatrixError.M_USER_IN_USE ||
          e.error == MatrixError.M_FORBIDDEN) {
        return false;
      }
      rethrow;
    }
  }

  static Future<bool> _loginWorks(
    Client client,
    String username,
    String password,
  ) async {
    try {
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
        initialDeviceDisplayName: 'synapse-contract-suite',
      );
      return true;
    } on MatrixException catch (e) {
      if (e.error == MatrixError.M_FORBIDDEN) return false;
      rethrow;
    }
  }

  /// The room's current state straight from the server, as
  /// type → state_key → content. Deliberately bypasses the SDK's local cache:
  /// read-back against the server catches silent normalization that a 200 on
  /// the write hides.
  static Future<Map<String, Map<String, Map<String, Object?>>>> serverState(
    Client client,
    String roomId,
  ) async {
    final events = await client.getRoomState(roomId);
    final state = <String, Map<String, Map<String, Object?>>>{};
    for (final event in events) {
      state.putIfAbsent(event.type, () => {})[event.stateKey ?? ''] =
          event.content;
    }
    return state;
  }

  /// Tear down a client created by [loggedIn]. Keeps the account (personas
  /// are reused across runs) but releases the device and the database.
  static Future<void> dispose(Client client) async {
    try {
      await client.logout();
    } catch (_) {
      // A test may already have invalidated the token (e.g. deactivation
      // contracts); disposal must not mask the test result.
    }
    await client.dispose(closeDatabase: true);
  }
}
