import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/utils/custom_http_client.dart';
import 'package:fluffychat/utils/init_with_restore.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';

abstract class ClientManager {
  static const String clientNamespace = 'im.fluffychat.store.clients';

  static Future<List<Client>> getClients({
    bool initialize = true,
    required SharedPreferences store,
  }) async {
    final clientNames = <String>{};
    try {
      final clientNamesList = store.getStringList(clientNamespace) ?? [];
      Logs().i('Found client names in store: $clientNamesList');
      clientNames.addAll(clientNamesList);
    } catch (e, s) {
      Logs().w('Client names in store are corrupted', e, s);
      await store.remove(clientNamespace);
    }
    if (clientNames.isEmpty) {
      Logs().i(
        'No client names found, adding default client name ${PlatformInfos.clientName}',
      );
      clientNames.add(PlatformInfos.clientName);
      await store.setStringList(clientNamespace, clientNames.toList());
    }
    final clients = await Future.wait(
      clientNames.map((name) => createClient(name, store)),
    );
    if (initialize) {
      await Future.wait(
        clients.map(
          (client) => client
              .initWithRestore(
                onMigration: () async {
                  // #Pangea
                  // final l10n = await lookupL10n(
                  //   PlatformDispatcher.instance.locale,
                  // );
                  // sendInitNotification(
                  //   l10n.databaseMigrationTitle,
                  //   l10n.databaseMigrationBody,
                  // );
                  // Pangea#
                },
              )
              .then((_) => renewExpiredToken(client))
              .catchError(
                (e, s) => Logs().e('Unable to initialize client', e, s),
              ),
        ),
      );
    }
    if (clients.length > 1 && clients.any((c) => !c.isLogged())) {
      final loggedOutClients = signedOutClientsToForget(clients);
      for (final client in loggedOutClients) {
        Logs().w(
          'Multi account is enabled but client ${client.userID} is not logged in. Removing...',
        );
        clientNames.remove(client.clientName);
        clients.remove(client);
      }
      await store.setStringList(clientNamespace, clientNames.toList());
    }
    return clients;
  }

  /// How long startup waits for an expired access token to be renewed before
  /// carrying on without it (session-lifetime.instructions.md).
  static const Duration tokenRenewalWait = Duration(seconds: 10);

  /// Renews [client]'s access token when it has expired or is about to, so
  /// the app's first requests don't go out with a token the server refuses.
  /// Tokens last 24 hours, so a learner who opens the app less than daily
  /// restores an expired one; the SDK otherwise renews it only from its sync
  /// loop, racing every startup request (#9304). Offline the renewal cannot
  /// finish: after [wait] startup carries on and the SDK retries it on the
  /// next sync.
  @visibleForTesting
  static Future<void> renewExpiredToken(
    Client client, {
    Duration wait = tokenRenewalWait,
  }) async {
    if (!client.isLogged()) return;
    try {
      await client.ensureNotSoftLoggedOut().timeout(wait);
    } on TimeoutException {
      // silent-ok: offline or slow network; the SDK retries on the next sync.
      Logs().w('Token renewal took over ${wait.inSeconds}s; starting without');
    } on MatrixException catch (e, s) {
      // The homeserver rejected the session and the SDK has signed out, so
      // the app starts on the signed-out screen.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'client_name': client.clientName},
        level: SentryLevel.warning,
      );
    }
  }

  /// The signed-out clients [getClients] forgets — never all of them. A
  /// store holding two signed-out names (the build's client name changed
  /// under a stored account, or a login candidate outlived its session) used
  /// to yield an empty list, and an app with no client at all cannot boot:
  /// `MatrixState.client` has nothing to resolve (#9018). Keeps the one named
  /// [PlatformInfos.clientName] when present — the name this build would
  /// otherwise create fresh — else the most recently stored.
  @visibleForTesting
  static List<Client> signedOutClientsToForget(List<Client> clients) {
    final loggedOut = clients.where((c) => !c.isLogged()).toList();
    if (loggedOut.length == clients.length) {
      loggedOut.remove(
        loggedOut.firstWhere(
          (c) => c.clientName == PlatformInfos.clientName,
          orElse: () => loggedOut.last,
        ),
      );
    }
    return loggedOut;
  }

  static Future<void> addClientNameToStore(
    String clientName,
    SharedPreferences store,
  ) async {
    Logs().i('Adding client name $clientName to store');
    final clientNamesList = store.getStringList(clientNamespace) ?? [];
    clientNamesList.add(clientName);
    await store.setStringList(clientNamespace, clientNamesList);
  }

  static Future<void> removeClientNameFromStore(
    String clientName,
    SharedPreferences store,
  ) async {
    final clientNamesList = store.getStringList(clientNamespace) ?? [];
    clientNamesList.remove(clientName);
    await store.setStringList(clientNamespace, clientNamesList);
  }

  static NativeImplementations get nativeImplementations => kIsWeb
      ? NativeImplementationsWebWorker(
          Uri.parse('native_executor.js'),
          timeout: const Duration(minutes: 1),
        )
      : NativeImplementationsIsolate(
          compute,
          vodozemacInit: () => vod.init(wasmPath: './assets/assets/vodozemac/'),
        );

  static Future<Client> createClient(
    String clientName,
    SharedPreferences store,
  ) async {
    final shareKeysWith = AppSettings.shareKeysWith.value;
    final enableSoftLogout = AppSettings.enableSoftLogout.value;

    final client = Client(
      clientName,
      httpClient: CustomHttpClient.createHTTPClient(),
      verificationMethods: {
        KeyVerificationMethod.numbers,
        if (kIsWeb || PlatformInfos.isMobile || PlatformInfos.isLinux)
          KeyVerificationMethod.emoji,
      },
      importantStateEvents: <String>{
        // To make room emotes work
        'im.ponies.room_emotes',
        // #Pangea
        // The things in this list will be loaded in the first sync, without having
        // to postLoad to confirm that these state events are completely loaded
        EventTypes.RoomPowerLevels,
        EventTypes.RoomJoinRules,
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
        // Who is in a call. An incoming call can be for ANY room, so this has
        // to be known without that room having been opened — a ring is decided
        // against it, and a room left partial would read as nobody being in
        // the call at all.
        EventTypes.GroupCallMember,
        // Pangea#
      },
      logLevel: kReleaseMode ? Level.warning : Level.verbose,
      database: await flutterMatrixSdkDatabaseBuilder(clientName),
      supportedLoginTypes: {
        AuthenticationTypes.password,
        AuthenticationTypes.sso,
      },
      nativeImplementations: nativeImplementations,
      defaultNetworkRequestTimeout: const Duration(minutes: 30),
      enableDehydratedDevices: true,
      shareKeysWith:
          ShareKeysWith.values.singleWhereOrNull(
            (share) => share.name == shareKeysWith,
          ) ??
          ShareKeysWith.all,
      convertLinebreaksInFormatting: false,
      onSoftLogout: enableSoftLogout
          ? (client) => client.refreshAccessToken()
          : null,
      // #Pangea
      shouldReplaceRoomLastEvent: (current, event) =>
          event.isVisibleLastEvent &&
          // Two genuine cards for one call must not leave the chat list
          // describing a different one than the conversation draws.
          callCardMayTakeTheChatListLine(current, event),
      enableLastEventRefresh: false,
      roomPreviewLastEvents: {
        PangeaEventTypes.activityPlan,
        PangeaEventTypes.activitySummary,
        EventTypes.RoomMember,
        // A finished call is the newest thing that happened in that room, and
        // the chat list should say so. Without this the card can never become
        // the room's last event: hiding the membership plumbing stopped the
        // list reading "sent a com.famedly.call.member event", but left
        // "No messages yet" on a room where two people had just talked. The
        // card carries a plain body -- "Voice call (0:13)", "Missed call",
        // "Call declined" -- written for exactly this line.
        PangeaEventTypes.call,
      },
      // Pangea#
    );
    // Covers init, a fresh login and every token refresh, each of which ends
    // in loggedIn. See [InitWithRestoreExtension.storeSessionBackup].
    client.onLoginStateChanged.stream
        .where((state) => state == LoginState.loggedIn)
        .listen((_) => client.storeSessionBackup());
    return client;
  }
}
