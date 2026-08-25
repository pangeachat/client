import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../endpoint_test_env.dart';

/// Live-SDK harness for the Synapse contract suite.
///
/// Builds a real matrix-dart-sdk [Client] — in-memory database, real HTTP —
/// pointed at the Synapse from `client/.env`, so tests call the client's own
/// extension methods and the bytes on the wire are exactly what the app
/// sends. See testing.instructions.md § Contract tests.
///
/// LOCAL-ONLY BY CONSTRUCTION: the suite creates, publishes, bans, and
/// deletes rooms and schedules account deletions. [initTestEnvironment]
/// refuses any non-localhost `SYNAPSE_URL` unless
/// `CONTRACT_SUITE_ALLOW_REMOTE=1` is set in the process environment. There
/// is deliberately NO fallback to shared credentials: personas must be
/// registrable (open local registration), or the suite fails loudly instead
/// of silently collapsing distinct personas into one account.
///
/// Homeserver preconditions (all true on the stock local stack): open
/// registration with the m.login.dummy flow; a non-zero
/// `delete_room_purge_delay_seconds` (the delete tests read leave-time
/// state); rate limits at the local inventory's values. On Synapse >=1.159
/// the new `rc_room_creation` limiter (default 1 room/min) must be raised
/// for the suite's room churn, mirroring the deployment override.
class ContractHarness {
  static const String personaPassword = 'contract-test-pass-1';

  static int _clientCounter = 0;
  static bool _ffiInitialized = false;
  static bool _environmentInitialized = false;
  static final Map<Client, List<String>> _trackedRooms = {};

  /// `SYNAPSE_URL` with a scheme (a bare host would die opaquely inside the
  /// SDK's homeserver discovery).
  static Uri get synapseUri {
    final raw = EndpointTestEnv.synapseUrl;
    return Uri.parse(raw.contains('://') ? raw : 'http://$raw');
  }

  /// One-time test-process setup: dotenv, the localhost guard, plus the
  /// GetStorage box that `Environment.appConfigOverride` reads (needed by
  /// extensions that consult `Environment`, e.g. `BotName.byEnvironment`).
  /// Same path_provider stub pattern as sentry_build_tags_test.dart.
  /// Ordering is load-bearing: the binding must exist before HttpOverrides
  /// is reset, and both before anything makes a network call.
  static Future<void> initTestEnvironment() async {
    if (_environmentInitialized) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    // The test binding installs a mock HttpClient that 400s every request;
    // this suite exists to make REAL requests — restore the real client.
    HttpOverrides.global = null;
    EndpointTestEnv.load();

    final host = synapseUri.host;
    final allowRemote =
        Platform.environment['CONTRACT_SUITE_ALLOW_REMOTE'] == '1';
    if (!allowRemote && host != 'localhost' && host != '127.0.0.1') {
      throw StateError(
        'The contract suite creates/publishes/bans/deletes rooms and '
        'schedules account deletions — refusing to run against "$host". '
        'Switch client/.env to the local profile (scripts/use-env.sh '
        'local), or set CONTRACT_SUITE_ALLOW_REMOTE=1 if you really mean '
        'it.',
      );
    }

    // The analytics dual-write posts construct batches to the teacher BFF
    // (fire-and-forget). The localhost guard above only covers Synapse, so
    // refuse the combination that would write real analytics remotely.
    final dualWrite =
        dotenv.env['ANALYTICS_DUAL_WRITE_ENABLED']?.toLowerCase() == 'true';
    final bff = dotenv.env['TEACHER_BFF_API'] ?? '';
    if (dualWrite && !bff.contains('localhost') && !bff.contains('127.0.0.1')) {
      throw StateError(
        'ANALYTICS_DUAL_WRITE_ENABLED is on with a non-local '
        'TEACHER_BFF_API ($bff) — the constructs tests would write real '
        'analytics to a remote service.',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp('synapse_contract');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    _environmentInitialized = true;
  }

  /// Register [roomId] for best-effort cleanup when [client] is disposed:
  /// unpublished from the directory and left, so personas' initial syncs and
  /// the public directory stay bounded across runs.
  static void trackRoom(Client client, String roomId) {
    _trackedRooms.putIfAbsent(client, () => []).add(roomId);
  }

  /// Sync-poll until [predicate] holds — for extension methods that read the
  /// LOCAL room state (join rules, space children) right after a server
  /// write. Each sync join is time-boxed so the background long-poll cannot
  /// stretch an iteration far past [timeout].
  static Future<void> waitUntil(
    Client client,
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('waitUntil: condition not met in $timeout');
      }
      try {
        await client.oneShotSync().timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // The joined background long-poll outlived our slice; re-check.
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Whether the homeserver supports creating rooms of [version] (per
  /// /capabilities) — gates the room-v12 canaries, which are meaningless on
  /// a server that cannot create v12 rooms at all.
  static Future<bool> roomVersionSupported(
    Client client,
    String version,
  ) async {
    final capabilities = await client.getCapabilities();
    final available = capabilities.mRoomVersions?.available;
    return available?.containsKey(version) ?? false;
  }

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
    final client = Client(
      'contract-test-$n',
      database: database,
      // Mirrors ClientManager.createClient: without these in the important
      // set the SDK never surfaces join_rules / pangea.* state on the local
      // Room, and every extension that reads local state silently no-ops.
      // m.space.child/parent and m.room.canonical_alias are in the SDK's
      // DEFAULT important set today; listed explicitly because the local
      // waitUntil predicates depend on them and an SDK default change would
      // otherwise turn those waits into silent hangs.
      importantStateEvents: <String>{
        'im.ponies.room_emotes',
        EventTypes.RoomPowerLevels,
        EventTypes.RoomJoinRules,
        EventTypes.SpaceChild,
        EventTypes.SpaceParent,
        EventTypes.RoomCanonicalAlias,
        PangeaEventTypes.botOptions,
        PangeaEventTypes.capacity,
        PangeaEventTypes.userSetLemmaInfo,
        PangeaEventTypes.activityPlan,
        PangeaEventTypes.activityRole,
        PangeaEventTypes.activitySummary,
        PangeaEventTypes.activityRoomIds,
        PangeaEventTypes.analyticsStatus,
        PangeaEventTypes.coursePlan,
        PangeaEventTypes.teacherMode,
        PangeaEventTypes.courseChatList,
        PangeaEventTypes.analyticsSettings,
        PangeaEventTypes.courseSettings,
        PangeaEventTypes.orchestratorAwardedGoals,
        PangeaEventTypes.botParticipant,
      },
    );
    await client.checkHomeserver(synapseUri);
    return client;
  }

  /// A logged-in client for [persona], creating the account when it does not
  /// exist. First sync completed before returning, so extension methods that
  /// wait on sync echoes work. Throws instead of falling back to shared
  /// credentials — persona identity is load-bearing for multi-account tests.
  static Future<Client> loggedIn(String persona) async {
    final client = await newClient();
    final registered = await _tryRegister(client, persona);
    if (!registered && !await _loginWorks(client, persona, personaPassword)) {
      throw StateError(
        'Cannot provision persona "$persona" on ${synapseUri.host}: '
        'registration refused and password login failed. The contract '
        'suite needs open local registration (m.login.dummy).',
      );
    }
    await client.roomsLoading;
    await client.oneShotSync();
    return client;
  }

  /// Registers [username], completing the m.login.dummy UIA stage the local
  /// stack offers. Returns true when the client is now logged in via
  /// registration; false when the account already exists (callers log in).
  /// A non-dummy UIA flow fails loudly — silently treating it as "account
  /// exists" is how personas would collapse into a shared login.
  static Future<bool> _tryRegister(Client client, String username) async {
    Future<void> doRegister({AuthenticationData? auth}) => _withRateLimitRetry(
      () => client.register(
        username: username,
        password: personaPassword,
        initialDeviceDisplayName: 'synapse-contract-suite',
        auth: auth,
      ),
    );

    try {
      await doRegister();
      return true;
    } on MatrixException catch (e) {
      // Order matters: a UIA challenge (401, no errcode) must be inspected
      // before errcode classification — the SDK maps a missing errcode on a
      // 401 to M_FORBIDDEN, which would read as "registration closed".
      final session = e.session;
      if (e.requireAdditionalAuthentication && session != null) {
        try {
          await doRegister(
            auth: AuthenticationData(
              type: AuthenticationTypes.dummy,
              session: session,
            ),
          );
          return true;
        } on MatrixException catch (e2) {
          if (e2.requireAdditionalAuthentication) {
            // The dummy stage was not accepted: this homeserver wants a
            // different flow (token/recaptcha/terms). Say so instead of
            // misreading the errcode-less 401 as "account exists".
            throw StateError(
              'Registration on ${synapseUri.host} requires a UIA flow the '
              'harness does not implement (offered: '
              '${e2.authenticationFlows?.map((f) => f.stages).toList()})',
            );
          }
          if (e2.error == MatrixError.M_USER_IN_USE) return false;
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
      await _withRateLimitRetry(
        () => client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(user: username),
          password: password,
          initialDeviceDisplayName: 'synapse-contract-suite',
        ),
      );
      return true;
    } on MatrixException catch (e) {
      if (e.error == MatrixError.M_FORBIDDEN) return false;
      rethrow;
    }
  }

  /// One bounded retry on M_LIMIT_EXCEEDED, honoring retryAfterMs (capped) —
  /// the suite's register/login bursts can brush Synapse's per-IP defaults,
  /// and a first-run-green / second-run-red gate is the worst signal.
  static Future<T> _withRateLimitRetry<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on MatrixException catch (e) {
      if (e.error != MatrixError.M_LIMIT_EXCEEDED) rethrow;
      final waitMs = (e.retryAfterMs ?? 2000).clamp(500, 15000);
      await Future.delayed(Duration(milliseconds: waitMs));
      return fn();
    }
  }

  /// The room's current state straight from the server, as
  /// type → state_key → content. Deliberately bypasses the SDK's local
  /// cache: read-back against the server catches silent normalization that a
  /// 200 on the write hides. Also works for rooms the user has LEFT (state
  /// as of the leave) — the delete/leave contracts rely on that.
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

  /// One event straight from the server (`/rooms/{id}/event/{id}`),
  /// bypassing the local database. Room.getEventById serves the client's
  /// OWN bytes back (sendEvent fake-syncs the authored content under the
  /// real event id), so it can never detect server-side normalization.
  static Future<MatrixEvent> serverEvent(
    Client client,
    String roomId,
    String eventId,
  ) => client.getOneRoomEvent(roomId, eventId);

  /// Tear down a client created by [loggedIn]. Best-effort cleanup of
  /// tracked rooms (unpublish + leave) keeps the persona's initial sync and
  /// the public directory bounded across runs; the account itself persists.
  static Future<void> dispose(Client client) async {
    // Drain fire-and-forget tails (e.g. getMyAnalyticsRoom's unawaited
    // grant/space-attach calls) before closing the database under them.
    // Also load-bearing: loggedIn always leaves prevBatch non-null, which
    // keeps those tails off the `onSync.stream.first` path that would throw
    // on a closed stream OUTSIDE their try/catch.
    try {
      await client.oneShotSync().timeout(const Duration(seconds: 2));
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 250));
    for (final roomId in _trackedRooms.remove(client) ?? const <String>[]) {
      try {
        await client.setRoomVisibilityOnDirectory(
          roomId,
          visibility: Visibility.private,
        );
      } catch (_) {}
      try {
        await client.leaveRoom(roomId);
      } catch (_) {}
    }
    try {
      await client.logout();
    } catch (e) {
      // A test may already have invalidated the token (e.g. deactivation
      // contracts); disposal must not mask the test result — but don't hide
      // the signal entirely.
      // ignore: avoid_print
      print('contract harness: logout during dispose failed: $e');
    }
    await client.dispose(closeDatabase: true);
  }
}
