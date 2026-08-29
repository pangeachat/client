import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:app_links/app_links.dart';
import 'package:collection/collection.dart';
import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_auto_save_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/languages/locale_provider.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/dev_login.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_session.dart' as call_ui;
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_repo.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/uia_request_manager.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/screen_size_warning_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import '../config/setting_keys.dart';
import '../routes/settings/settings_device/key_verification_dialog.dart';
import '../utils/account_bundles.dart';
import '../utils/background_push.dart';
import 'local_notifications_extension.dart';

// #Pangea
// Pangea#

// import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Matrix extends StatefulWidget {
  final Widget? child;

  final List<Client> clients;

  final Map<String, String>? queryParameters;

  final SharedPreferences store;

  const Matrix({
    this.child,
    required this.clients,
    required this.store,
    this.queryParameters,
    super.key,
  });

  @override
  MatrixState createState() => MatrixState();

  /// Returns the (nearest) Client instance of your application.
  static MatrixState of(BuildContext context) =>
      Provider.of<MatrixState>(context, listen: false);
}

class MatrixState extends State<Matrix> with WidgetsBindingObserver {
  int _activeClient = -1;
  String? activeBundle;
  // #Pangea
  static late PangeaController pangeaController;

  /// Whether [pangeaController] has been assigned yet.
  ///
  /// It is assigned in [initState], after `initMatrix()`, but widgets build —
  /// and repos are reached from `build()` — before that runs. Reading the
  /// field first throws `LateInitializationError`, which escapes any caller
  /// that is not already inside a try/catch.
  ///
  /// Dart exposes no initialization check for a `late` field, so the read is
  /// the test. Caught untyped on purpose: the error the runtime throws is
  /// `LateError` from `dart:_internal`, which application code cannot name.
  static bool get isPangeaControllerInitialized {
    try {
      pangeaController;
      return true;
    } catch (_) {
      return false;
    }
  }

  static PangeaAnyState pAnyState = PangeaAnyState();

  /// Not `late`: [dispose] cancels it unconditionally, so an [initState] that
  /// never reached its assignment would crash teardown with a
  /// LateInitializationError that buries whatever actually failed.
  StreamSubscription? _uriListener;

  final Map<String, AnalyticsDataService> _analyticsServices = {};
  final Map<String, ActivityAutoSaveService> _activityAutoSaveServices = {};
  final Map<String, CallService> _callServices = {};

  /// Accounts whose services are being torn down, mapped to the in-flight
  /// disposal. Concurrent teardowns coalesce onto ONE disposal (no double-
  /// dispose), and [analyticsDataService] refuses to resurrect a service while
  /// its account is closing — the entries stay in their maps until disposal
  /// finishes, so a queued rebuild reads the closing service rather than
  /// creating a fresh one that would outlive the account and leak.
  final Map<String, Future<void>> _disposingServices = {};

  /// Client names currently unwinding from a `loggedOut` event: from the
  /// moment the state change is observed until the client has been removed
  /// from [Matrix.clients] and its subscriptions cancelled ([_registerSubs]'s
  /// `loggedOut` branch below). That teardown awaits unrelated async work
  /// (e.g. the analytics update in `handleLoginStateChange`) before it even
  /// starts, so `client.isLogged() == false` alone does not prove the client
  /// is safe to hand back to a new login — [getLoginClient] must never reuse
  /// one still in this set, or the new login silently loses its
  /// `onLoginStateChanged` listener and the login dialog never closes
  /// (#8514).
  final Set<String> _clientsTearingDown = {};
  // Pangea#
  SharedPreferences get store => widget.store;

  XFile? loginAvatar;
  String? loginUsername;
  bool? loginRegistrationSupported;

  BackgroundPush? backgroundPush;
  // #Pangea
  ValueNotifier<int> notifPermissionNotifier = ValueNotifier(0);
  // Pangea#

  // #Pangea
  /// The account [client] last resolved, retained so the getter keeps its
  /// non-null contract while [Matrix.clients] holds none.
  ///
  /// Single-account logout empties that list (the `loggedOut` branch of
  /// [_registerSubs]) and routes straight to `/home`, so every widget building
  /// that route — auth guards, presence builders, the lifecycle observer —
  /// reads [client] against an empty list. Handing back the account that just
  /// logged out is truthful rather than silent: `isLogged()` is false, so
  /// callers gate to the login screen exactly as they would for any signed-out
  /// account, instead of the getter throwing `Bad state: No element` (#8368).
  ///
  /// Only ever a last resort — a live account in [Matrix.clients] always wins,
  /// so the next login is never shadowed by the account it replaced.
  Client? _lastResolvedClient;
  // Pangea#

  Client get client {
    if (_activeClient < 0 || _activeClient >= widget.clients.length) {
      // #Pangea
      final fallback = currentBundle?.firstOrNull ?? _lastResolvedClient;
      if (fallback == null) {
        // Unreachable via ClientManager.getClients, which always yields at
        // least one client. Named loudly so it can never read as the empty
        // bundle above.
        throw StateError('MatrixState.client read before any client existed');
      }
      fallback.homeserver = AppConfig.defaultHomeserverUri;
      return _lastResolvedClient = fallback;
      // Pangea#
    }

    // #Pangea
    final activeClient = widget.clients[_activeClient];
    activeClient.homeserver = AppConfig.defaultHomeserverUri;
    return _lastResolvedClient = activeClient;
    // Pangea#
  }

  // #Pangea
  AnalyticsDataService get analyticsDataService {
    final name = client.clientName;
    // A service being torn down stays in its map until disposal finishes (see
    // [disposeAccountServices]), so an access mid-teardown returns the SAME
    // closing service — never a fresh one that would boot a DB, wait forever for
    // a login that isn't coming, and outlive the account. Only create when the
    // account is genuinely present and NOT closing.
    final existing = _analyticsServices[name];
    if (existing != null) return existing;
    Logs().w(
      'Tried to access AnalyticsDataService for client $name, but it does not exist.',
    );
    final created = AnalyticsDataService(client);
    _analyticsServices[name] = created;
    return created;
  }

  /// The EXISTING analytics service for a SPECIFIC account (or null), without the
  /// active-client getter's create-on-miss. Callers that captured one account up
  /// front (e.g. the logout path) use this so they save/flush that account's
  /// analytics even if the active client switched mid-flow — never the wrong
  /// account's, and never resurrecting a service for a closing one.
  AnalyticsDataService? analyticsServiceFor(String clientName) =>
      _analyticsServices[clientName];

  /// This account's calling service.
  ///
  /// One per account and never rebuilt while the account lives: the SDK's [VoIP]
  /// is per-client and identifies our membership by instance, so a second one
  /// would lose track of a call the first is still in. The service itself is
  /// inert until something asks it to call — it holds no media and constructs
  /// no [VoIP] on creation.
  CallService get callService => callServiceFor(client.clientName);

  /// The calling service for a SPECIFIC account, created on first use.
  ///
  /// Unlike [analyticsDataService] this needs no closing-account guard:
  /// [disposeAccountServices] removes the entry, and a service created after
  /// that point owns nothing that could outlive the account.
  CallService callServiceFor(String clientName) =>
      _callServices[clientName] ??= CallService(
        // The same last-resort the [client] getter keeps: a single-account
        // logout empties `clients` while widgets are still building against
        // it, and a service that throws `Bad state: No element` from a
        // rebuild takes the whole route down. An account on its way out
        // resolves to itself; every live account still wins on name.
        widget.clients.firstWhere(
          (c) => c.clientName == clientName,
          orElse: () => client,
        ),
      );

  // #Pangea
  /// The calling service for a SPECIFIC client OBJECT.
  ///
  /// [callServiceFor] resolves by name and, on a miss, falls back to the
  /// ACTIVE account. That is right for what it was written for — a rebuild
  /// during a single-account logout, where throwing would take the route down
  /// — and wrong for anything scoped to one call, where guessing means acting
  /// as somebody else's account. A call to a second account being declined,
  /// answered or watched as the first is the bug this exists to make
  /// impossible.
  ///
  /// So the account is named by identity, and a cached service is handed back
  /// only if it is really this client's. Names cannot collide between two LIVE
  /// accounts — `ClientManager` stamps each login with a millisecond timestamp
  /// — so a mismatch can only be a leftover from an account that has gone, and
  /// the live client's own service replaces it rather than the caller being
  /// refused for ever. [disposeAccountServices] evicts only the entry it
  /// actually disposed, so that replacement cannot be undone by a teardown
  /// finishing afterwards.
  CallService callServiceForClient(Client client) {
    final existing = _callServices[client.clientName];
    if (existing != null && identical(existing.client, client)) return existing;
    return _callServices[client.clientName] = CallService(client);
  }
  // Pangea#

  /// The one call this app is in, if any. Panels and tiles listen here; the
  /// session itself owns the call's lifecycle, so navigation never touches it.
  final ValueNotifier<call_ui.CallSession?> activeCall = ValueNotifier(null);

  /// The standing offer to return to a call a reload interrupted.
  ///
  /// App-level state like [activeCall], NOT banner-widget state: the banner
  /// can be re-instantiated around it (theme, locale, lock-screen rebuilds),
  /// and an offer held in one instance's setState died invisible while
  /// another instance rendered. One notifier, read by whichever is live.
  final ValueNotifier<RejoinOffer?> rejoinOffer = ValueNotifier(null);

  /// Bumped whenever the account context changes: an account added by a login,
  /// removed by a logout, or a different one made active.
  ///
  /// [Matrix.clients] is a plain list with no change signal of its own, and
  /// [build] hands the SAME child widget back on every rebuild, so a `setState`
  /// here does not rebuild the subtree — nothing below could learn that an
  /// account had arrived or left. That is invisible for most widgets, which
  /// read the active account on their next build anyway, and fatal for the
  /// incoming-call banner: it holds a subscription per account, and an account
  /// whose ring stream is never subscribed is an account that never rings.
  ///
  /// Covers two different things on purpose. The three mutations of
  /// [Matrix.clients] change WHICH ACCOUNTS RING; [setActiveClient] changes
  /// only which account the rejoin offer belongs to. Listeners reconcile both
  /// and are written to be idempotent, so an active-only change costs a pass
  /// that finds every subscription already in place.
  final ValueNotifier<int> accounts = ValueNotifier(0);

  /// Says the account context changed. Never assigns a meaningful value — the
  /// count is a tick, and listeners re-read [Matrix.clients] themselves.
  void _accountsChanged() => accounts.value++;

  /// Places or answers a call in [room], or brings the existing one back up.
  ///
  /// One call at a time is already the service's rule ([AlreadyInACall]); this
  /// keeps the UI consistent with it: a second ask while a call is up expands
  /// the call rather than failing, and a failed call still on screen is
  /// dismissed to make way for the new one.
  void startCall(
    Room room, {
    required bool video,
    String? notificationEventId,
    String? rejoinMembershipEventId,
    DateTime? rejoinSince,
    String? callerMembershipEventId,

    /// Whether the call covers the whole app from its first frame, rather than
    /// waiting to be presented inside its own chat. Only a call answered on an
    /// account that is not the active one asks for this: its room belongs to
    /// another account, so there is no chat pane it could be shown in. See
    /// [call_ui.CallSession.fullscreen].
    bool fullscreen = false,
  }) {
    final existing = activeCall.value;
    if (existing != null) {
      if (existing.isFailed) {
        existing.dismissFailed();
      } else if (existing.isOver) {
        // Between the outcome latch and the deferred handover there is a
        // one-microtask window in which a FINISHED session is still held here.
        // It renders nothing, so expanding it would swallow the new call with
        // no error anywhere. It is stepped over -- but NOT disposed: this
        // branch can run from inside the old call's own notification, and its
        // pending release microtask is the one place its disposal is safe.
        activeCall.value = null;
      } else if (existing.room.client != room.client ||
          existing.room.id != room.id) {
        // A live call somewhere ELSE -- another account, or another room on
        // this one. Expanding it and returning answered nothing and declined
        // nothing: the prompt had already been dismissed, so the caller rang
        // out and wrote a missed call while this learner sat looking at an
        // unrelated call. One call at a time is right; silently swallowing
        // the second one is not, and the callers differ on what to do about
        // it -- answering declines as busy, pressing Call just brings the
        // live call forward -- so this says what happened and lets them
        // decide.
        Logs().w(
          'Refusing a call in ${room.id}: already on one in ${existing.room.id}',
        );
        existing.expand();
        throw const AlreadyInACall();
      } else {
        existing.expand();
        return;
      }
    }
    // The services this call will use, resolved from the call's OWN account
    // rather than from whichever account happens to be active later.
    final accountName = room.client.clientName;
    final callAccount = analyticsServiceFor(accountName);
    // The SAME rule for the languages this call is transcribed against, and
    // for the same reason. A call has no language of its own: it has two
    // halves, each recorded from one device's own microphone and published
    // under one account, and the pair belongs to whichever account publishes
    // the half. Read through `pangeaController.userController` these came from
    // whichever account was FOREGROUNDED when the call started -- and the
    // target language picks the provider chain server-side, so the wrong one
    // does not return an approximation, it returns nothing
    // (pangeachat/.github#410).
    final languages = UserController.languageCodesFor(room.client);
    activeCall.value = call_ui.CallSession.start(
      room: room,
      video: video,
      notificationEventId: notificationEventId,
      rejoinAnchor: rejoinMembershipEventId,
      rejoinSince: rejoinSince,
      callerMembershipEventId: callerMembershipEventId,
      // By the room's client OBJECT, not its name: the name-keyed getter
      // falls back to the ACTIVE account, and this is the call's own service
      // for its whole life. Resolving it the same way the incoming-call
      // banner does also guarantees they hold the SAME instance -- the SDK's
      // VoIP is per instance, and two would lose track of each other's call.
      callService: callServiceForClient(room.client),
      // Passed into the constructor, NOT toggled afterwards: the assignment
      // to `activeCall` below is what makes GlobalCallTile build, so a session
      // that becomes fullscreen after it would show one frame of the
      // control-less mini tile first.
      fullscreen: fullscreen,
      // The two strings Android renders for the ongoing call. They can only
      // come from here: the plugin has no translations, and the session has
      // no context.
      platformLabels: (
        mute: L10n.of(context).callMute,
        channel: L10n.of(context).callOngoingChannel,
      ),
      // The repo answers with a Result; the sink's contract is a value or a
      // throw, and it already treats a throw as "this chunk's words are lost".
      transcribe: (request) async {
        final result = await SpeechToTextRepo.instance.get(request);
        final value = result.asValue;
        if (value == null) {
          throw result.asError?.error ?? StateError('speech-to-text failed');
        }
        return value.value;
      },
      userL1: languages.l1 ?? LanguageKeys.unknownLanguage,
      userL2: languages.l2 ?? LanguageKeys.unknownLanguage,
      // Bound to the account that OWNS this call, captured now. Both of
      // these used to be read through the active-account getters at the
      // moment the recording finished, which is minutes later and after the
      // learner may have switched accounts -- so one learner's spoken words
      // could be credited to another's analytics. The call's own room names
      // its account; nothing about that changes while the call runs.
      analytics: (eventId, uses, language) async {
        // Null once that account has been disposed -- logged out mid-call, or
        // torn down while the transcription was still landing. Its analytics
        // have nowhere to go, and the ACTIVE account's service is the one
        // place they must not go.
        final service = callAccount ?? analyticsServiceFor(accountName);
        if (service == null) {
          Logs().w(
            'No analytics service left for $accountName; call speech '
            'from that account is not being credited anywhere',
          );
          return;
        }
        try {
          await service.updateService.addAnalytics(eventId, uses, language);
        } on AnalyticsNotStoredException catch (e) {
          // Said in the call's own terms, so the record knows this one is
          // safe to try again and every other failure is not.
          throw CallAnalyticsNotStored(e.cause);
        }
      },
      onReleased: (session) {
        if (activeCall.value == session) activeCall.value = null;
        session.dispose();
      },
    );
  }
  // Pangea#

  bool get isMultiAccount => widget.clients.length > 1;

  int getClientIndexByMatrixId(String matrixId) =>
      widget.clients.indexWhere((client) => client.userID == matrixId);

  late String currentClientSecret;
  RequestTokenResponse? currentThreepidCreds;
  // #Pangea
  String? currentRegistrationEmail;
  String? currentRegisrationUsername;
  int currentSendAttempt = 0;
  // Pangea#

  void setActiveClient(Client? cl) {
    final i = widget.clients.indexWhere((c) => c == cl);
    if (i != -1) {
      _activeClient = i;
      // #Pangea
      // Nothing below this widget rebuilds on an active-account change (see
      // [accounts]), so anything holding per-account state has to be told.
      _accountsChanged();
      // Pangea#
    } else {
      Logs().w('Tried to set an unknown client ${cl!.userID} as active');
    }
  }

  List<Client?>? get currentBundle {
    if (!hasComplexBundles) {
      return List.from(widget.clients);
    }
    final bundles = accountBundles;
    if (bundles.containsKey(activeBundle)) {
      return bundles[activeBundle];
    }
    return bundles.values.first;
  }

  Map<String?, List<Client?>> get accountBundles {
    final resBundles = <String?, List<_AccountBundleWithClient>>{};
    for (var i = 0; i < widget.clients.length; i++) {
      final bundles = widget.clients[i].accountBundles;
      for (final bundle in bundles) {
        if (bundle.name == null) {
          continue;
        }
        resBundles[bundle.name] ??= [];
        resBundles[bundle.name]!.add(
          _AccountBundleWithClient(client: widget.clients[i], bundle: bundle),
        );
      }
    }
    for (final b in resBundles.values) {
      b.sort(
        (a, b) => a.bundle!.priority == null
            ? 1
            : b.bundle!.priority == null
            ? -1
            : a.bundle!.priority!.compareTo(b.bundle!.priority!),
      );
    }
    return resBundles.map(
      (k, v) => MapEntry(k, v.map((vv) => vv.client).toList()),
    );
  }

  bool get hasComplexBundles => accountBundles.values.any((v) => v.length > 1);

  Client? _loginClientCandidate;

  AudioPlayer? audioPlayer;
  final ValueNotifier<String?> voiceMessageEventId = ValueNotifier(null);

  /// Whether [getLoginClient] would hand back the current [client] instead
  /// of creating a fresh login candidate. Exposed for tests; see
  /// [_clientsTearingDown].
  @visibleForTesting
  bool get canReuseClientForLogin =>
      widget.clients.isNotEmpty &&
      !client.isLogged() &&
      !_clientsTearingDown.contains(client.clientName);

  /// Whether [account] is unwinding a logout.
  ///
  /// Set the moment `loggedOut` arrives and cleared only once the whole unwind
  /// is done -- which is BEFORE the account leaves [widget.clients], because
  /// that removal waits for the teardown to finish. Anything that must not act
  /// for a departing account has to ask this as well as the client list: in
  /// between, the list still contains it.
  bool isSigningOut(Client account) =>
      _clientsTearingDown.contains(account.clientName);

  /// Test-only: marks [clientName] as unwinding a `loggedOut` event, exactly
  /// as the listener installed by [_registerSubs] does before its async
  /// teardown — lets tests exercise the [getLoginClient] race guard without
  /// a live `loggedOut` stream event (#8514).
  @visibleForTesting
  void markClientTearingDownForTest(String clientName) =>
      _clientsTearingDown.add(clientName);

  Future<Client> getLoginClient() async {
    if (canReuseClientForLogin) {
      return client;
    }
    final candidate = _loginClientCandidate ??=
        await ClientManager.createClient(
            '${AppSettings.applicationName.value}-${DateTime.now().millisecondsSinceEpoch}',
            store,
          )
          ..onLoginStateChanged.stream
              .where((l) => l == LoginState.loggedIn)
              .first
              .then((_) async {
                // #Pangea
                // The `client` getter (and anything handleLoginStateChange
                // reads through it, e.g. PangeaController._onLogin) must
                // resolve to THIS candidate before handleLoginStateChange
                // runs — added to Matrix.clients and made active first.
                // Otherwise, on a fresh single-account login, Matrix.clients
                // is still empty at this point and `client` falls back to
                // the previous (already logged-out, torn-down) account, so
                // _onLogin's network calls hang against a dead client and
                // the login dialog never closes (#8514).
                // The bump below is said HERE rather than left to
                // setActiveClient: the list changing and the ACTIVE account
                // changing are two different facts, and only the first decides
                // which accounts ring. A later edit that stopped making a new
                // login active would otherwise stop it ever ringing.
                if (!widget.clients.contains(_loginClientCandidate)) {
                  widget.clients.add(_loginClientCandidate!);
                  _accountsChanged();
                }
                setActiveClient(_loginClientCandidate);
                await MatrixState.pangeaController.handleLoginStateChange(
                  LoginState.loggedIn,
                  _loginClientCandidate!.userID,
                  context,
                );
                // Pangea#
                ClientManager.addClientNameToStore(
                  _loginClientCandidate!.clientName,
                  store,
                );
                _registerSubs(_loginClientCandidate!.clientName);
                // #Pangea
                // Update BackgroundPush with the new client so push
                // notifications work after logout/login without a restart.
                backgroundPush?.client = _loginClientCandidate!;
                backgroundPush?.setupPush();
                // Pangea#
                _loginClientCandidate = null;
                // #Pangea
                // FluffyChatApp.router.go('/backup');
                final isL2Set =
                    await pangeaController.userController.isUserL2Set;
                if (!isL2Set) {
                  // A new user's onboarding joins with any code cached across
                  // the login bounce and clears it at completion
                  // (user_type_onboarding_step.dart).
                  FluffyChatApp.router.go('/registration');
                } else {
                  // A join code cached across the login bounce is consumed by
                  // the world route's auth guard on this landing
                  // (PAuthGaurd._consumeCachedJoinCode) — the one consumption
                  // point shared with logins that never pass through this
                  // listener (web SSO's full-reload return, a restored
                  // session).
                  FluffyChatApp.router.go(PRoutes.world);
                }
                // Pangea#
              });
    // #Pangea
    candidate.homeserver = AppConfig.defaultHomeserverUri;

    // This listener is not set for the new login client until the user is logged in,
    // but if the user tries to sign up without this listener set, the signup UIA request
    // will hang. So set the listener here.
    onUiaRequest[candidate.clientName] ??= candidate.onUiaRequest.stream.listen(
      uiaRequestHandler,
    );
    // Pangea#
    // #Pangea
    if (widget.clients.isEmpty) {
      widget.clients.add(candidate);
      _accountsChanged();
    }
    // Pangea#
    return candidate;
  }

  Client? getClientByName(String name) =>
      widget.clients.firstWhereOrNull((c) => c.clientName == name);

  final onRoomKeyRequestSub = <String, StreamSubscription>{};
  final onKeyVerificationRequestSub = <String, StreamSubscription>{};
  final onNotification = <String, StreamSubscription>{};
  final onLoginStateChanged = <String, StreamSubscription<LoginState>>{};
  final onUiaRequest = <String, StreamSubscription<UiaRequest>>{};

  String? _cachedPassword;
  Timer? _cachedPasswordClearTimer;

  String? get cachedPassword => _cachedPassword;

  set cachedPassword(String? p) {
    Logs().d('Password cached');
    _cachedPasswordClearTimer?.cancel();
    _cachedPassword = p;
    _cachedPasswordClearTimer = Timer(const Duration(minutes: 10), () {
      _cachedPassword = null;
      Logs().d('Cached Password cleared');
    });
  }

  String? get activeRoomId {
    final route = FluffyChatApp.router.routeInformationProvider.value.uri.path;
    // #Pangea
    // world_v2: open chats also live under /courses/:spaceid/:roomid and
    // /analytics/activities/:roomid.
    if (!route.startsWith('/rooms/') &&
        !route.startsWith('/courses/') &&
        !route.startsWith('/analytics/activities/')) {
      return null;
    }
    // if (!route.startsWith('/rooms/')) return null;
    // Pangea#
    // #Pangea
    // return route.split('/')[2];
    // world_v2 URLs carry a bare localpart; re-attach the home server_name so
    // this matches full event room ids (e.g. notification suppression).
    final roomId = FluffyChatApp.router.state.pathParameters['roomid'];
    if (roomId == null || roomId.contains(':')) return roomId;
    final userId = client.userID;
    final sep = userId?.indexOf(':') ?? -1;
    return sep == -1 ? roomId : '$roomId:${userId!.substring(sep + 1)}';
    // Pangea#
  }

  final linuxNotifications = PlatformInfos.isLinux
      ? NotificationsClient()
      : null;
  final Map<String, int> linuxNotificationIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initMatrix();
    // #Pangea
    Sentry.configureScope(
      (scope) =>
          scope.setUser(SentryUser(id: client.userID, name: client.userID)),
    );
    pangeaController = PangeaController(matrixState: this);
    pangeaController.initControllers(client.userID);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setAppLanguage();
      _setLanguageListener();
      _checkScreenSize();
      // Debug-only: `?devlogin=1` signs the local build into the test account,
      // bypassing the canvas login form. No-op without the param. See
      // dev_login.dart / matrix-auth.instructions.md.
      maybeDevLogin(this);
    });
    _uriListener = AppLinks().uriLinkStream.listen(_processIncomingUris);
    // Pangea#
  }

  // #Pangea
  final ScreenSizeWarning _screenSizeWarning = ScreenSizeWarning();
  Timer? _screenSizeTimer;

  @override
  void didChangeMetrics() {
    // Debounced: a resize (or an on-screen keyboard opening/closing) fires a
    // burst of metrics changes, and only the size it settles on is meaningful.
    _screenSizeTimer?.cancel();
    _screenSizeTimer = Timer(kScreenSizeSettleDelay, _checkScreenSize);
    super.didChangeMetrics();
  }

  void _checkScreenSize() {
    if (!kIsWeb || !mounted) return;

    // The navigator may not be mounted yet on the initial frame — retry next
    // frame, but only while the window is short enough to warrant a warning.
    final navigatorContext =
        FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
    if (navigatorContext == null && screenIsTooShort(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkScreenSize());
      return;
    }

    _screenSizeWarning.onWindowHeight(windowHeight(context), navigatorContext);
  }

  StreamSubscription? _languageListener;
  StreamSubscription? _appLanguageSettingsListener;
  Future<void> _setLanguageListener() async {
    await pangeaController.userController.initialize();
    // The initState call to _setAppLanguage ran before initialize() resolved,
    // so it read Profile.emptyProfile and never saw the real user settings.
    // Re-apply now that the actual profile (and the toggle) are loaded.
    _setAppLanguage();
    GrammarConstructsProvider.fetchFeaturesAndTags();

    _languageListener?.cancel();
    _languageListener = pangeaController.userController.languageStream.stream
        .listen((update) {
          _setAppLanguage();
          analyticsDataService.updateService.onUpdateLanguages(update);
          GrammarConstructsProvider.fetchFeaturesAndTags();
        });

    // Non-language settings changes (e.g. the app-copy-language immersion
    // toggle) emit here, not on languageStream — re-apply the locale so the
    // toggle takes effect.
    _appLanguageSettingsListener?.cancel();
    _appLanguageSettingsListener = pangeaController
        .userController
        .settingsUpdateStream
        .stream
        .listen((_) => _setAppLanguage());
  }

  void _setAppLanguage() {
    try {
      final settings = pangeaController.userController.profile.userSettings;
      // Immersion: show the app in the target language when the user opts in,
      // otherwise their source/native language. Falls back to source (then
      // system) if the target isn't set.
      final appLanguage = settings.appLanguageIsTarget
          ? (settings.targetLanguage ?? settings.sourceLanguage)
          : settings.sourceLanguage;
      Provider.of<LocaleProvider>(
        context,
        listen: false,
      ).setLocale(appLanguage);
    } catch (e, s) {
      Logs().e('Error setting app language', e);
      ErrorHandler.logError(e: e, s: s, data: {});
    }
  }
  // Pangea#

  void _registerSubs(String name) {
    final c = getClientByName(name);
    if (c == null) {
      Logs().w(
        'Attempted to register subscriptions for non-existing client $name',
      );
      return;
    }
    onRoomKeyRequestSub[name] ??= c.onRoomKeyRequest.stream.listen((
      RoomKeyRequest request,
    ) async {
      if (widget.clients.any(
        ((cl) =>
            cl.userID == request.requestingDevice.userId &&
            cl.identityKey == request.requestingDevice.curve25519Key),
      )) {
        Logs().i(
          '[Key Request] Request is from one of our own clients, forwarding the key...',
        );
        await request.forwardKey();
      }
    });
    onKeyVerificationRequestSub[name] ??= c.onKeyVerificationRequest.stream
        .listen((KeyVerification request) async {
          var hidPopup = false;
          request.onUpdate = () {
            if (!hidPopup &&
                {
                  KeyVerificationState.done,
                  KeyVerificationState.error,
                }.contains(request.state)) {
              FluffyChatApp.router.pop('dialog');
            }
            hidPopup = true;
          };
          request.onUpdate = null;
          hidPopup = true;
          await KeyVerificationDialog(request: request).show(
            FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
                context,
          );
        });
    onLoginStateChanged[name] ??= c.onLoginStateChanged.stream.listen((
      state,
    ) async {
      // #Pangea
      // Mark BEFORE the handleLoginStateChange await below, which can take a
      // while (e.g. the analytics update) — getLoginClient must refuse to
      // reuse this client for the whole unwind, not just once teardown
      // itself starts (#8514).
      if (state == LoginState.loggedOut) {
        _clientsTearingDown.add(c.clientName);
      }
      // A failure reporting the state change (e.g. Firebase analytics) must NOT
      // skip the loggedOut teardown below — otherwise the account's services +
      // subscriptions (and its dosage tracker) leak on logout.
      try {
        await MatrixState.pangeaController.handleLoginStateChange(
          state,
          c.userID,
          context,
        );
      } catch (e, s) {
        Logs().e('handleLoginStateChange failed', e, s);
      }
      // Pangea#
      final loggedInWithMultipleClients = widget.clients.length > 1;
      if (state == LoginState.loggedOut) {
        // #Pangea
        // In a `finally`, because the mark is what makes `getLoginClient`
        // refuse to reuse this slot. A throw anywhere in the unwind -- a
        // service `dispose()` that fails, a subscription that will not cancel
        // -- used to skip the clear, and the account then stayed marked for
        // the life of the app: signing in again could never reuse the client,
        // with nothing on screen to say why. The clear belongs to reaching the
        // END of the unwind, not to reaching it successfully.
        // Pangea#
        try {
          await _cancelSubs(c.clientName);
          widget.clients.remove(c);
          ClientManager.removeClientNameFromStore(c.clientName, store);
        } finally {
          // #Pangea
          // InitWithRestoreExtension.deleteSessionBackup(name);
          _clientsTearingDown.remove(c.clientName);
        }
        // #Pangea
        // Said AFTER the account is out of the list, so a listener that
        // re-reads it sees the account gone rather than half-gone. The
        // incoming-call banner uses this to drop that account's ring
        // subscriptions and put away a prompt nobody can answer any more.
        _accountsChanged();
        // Pangea#
      }
      if (loggedInWithMultipleClients && state != LoginState.loggedIn) {
        // #Pangea
        ScaffoldMessenger.of(
          FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
              context,
        ).showSnackBarAnnounced(
          SnackBar(content: Text(L10n.of(context).oneClientLoggedOut)),
        );
        // Pangea#

        if (state != LoginState.loggedIn) {
          FluffyChatApp.router.go(PRoutes.world);
        }
      } else {
        // #Pangea
        // FluffyChatApp.router.go(
        //   state == LoginState.loggedIn ? '/backup' : '/home',
        // );
        if (state == LoginState.loggedIn) {
          final isL2Set = await pangeaController.userController.isUserL2Set;
          // Not unconditionally the world map. This state also means "the
          // session finished restoring", which on a cold start lands AFTER the
          // app has resolved the URL the user opened — and going to the map
          // then throws that URL away. See [PAuthGaurd.loggedInLanding].
          final landing = PAuthGaurd.loggedInLanding(
            current: FluffyChatApp.router.routeInformationProvider.value.uri,
            isL2Set: isL2Set,
          );
          if (landing != null) FluffyChatApp.router.go(landing);
        } else {
          FluffyChatApp.router.go('/home');
        }
        // Pangea#
      }
    });
    onUiaRequest[name] ??= c.onUiaRequest.stream.listen(uiaRequestHandler);
    if (PlatformInfos.isWeb || PlatformInfos.isLinux) {
      c.onSync.stream.first.then((s) {
        html.Notification.requestPermission();
        onNotification[name] ??= c.onNotification.stream.listen(
          showLocalNotification,
        );
      });
    }
    // #Pangea
    _analyticsServices[name] ??= AnalyticsDataService(c);
    if (_activityAutoSaveServices[name] == null) {
      _activityAutoSaveServices[name] = ActivityAutoSaveService(
        client: c,
        analyticsService: _analyticsServices[name]!,
      );
      _activityAutoSaveServices[name]!.start();
    }
    // Pangea#
  }

  Future<void> _cancelSubs(String name) async {
    onRoomKeyRequestSub[name]?.cancel();
    onRoomKeyRequestSub.remove(name);
    onKeyVerificationRequestSub[name]?.cancel();
    onKeyVerificationRequestSub.remove(name);
    onLoginStateChanged[name]?.cancel();
    onLoginStateChanged.remove(name);
    onNotification[name]?.cancel();
    onNotification.remove(name);
    // #Pangea
    onUiaRequest[name]?.cancel();
    onUiaRequest.remove(name);
    await disposeAccountServices(name);
    // Pangea#
  }

  /// Best-effort, bounded, NON-destructive flush of an account's open engagement
  /// span. Called BEFORE `client.logout()` so the final POST uses a still-valid
  /// bearer WITHOUT tearing the services down — if logout then fails, they are
  /// intact and the `loggedOut` listener disposes them once logout is confirmed.
  /// Never throws or blocks the logout.
  Future<void> flushAccountTelemetry(String clientName) async {
    try {
      final service = _analyticsServices[clientName];
      final userId = service?.accountUserId;
      if (userId == null || userId.isEmpty) return;
      // Tombstoned, non-destructive flush: KEEPS the tracker (so a failed logout
      // leaves it live) but blocks a new span from opening during the awaited
      // POST — which would otherwise flush only after logout kills the bearer.
      //
      // The audio buffer gets the same treatment and, unlike the span, it is
      // handed the bearer explicitly: a listening observation has no Matrix
      // artefact to re-derive it from, so this is the last moment it can be
      // delivered at all. Both are bounded and independent — one timing out must
      // not cost the other its flush.
      await Future.wait([
        DosageEngagementTracker.flushForLogout(
          userId,
        ).timeout(const Duration(seconds: 5)).catchError((_) {}),
        DosageAudioBuffer.flushForLogout(
          userId,
          accessToken: service?.accountAccessToken,
        ).timeout(const Duration(seconds: 5)).catchError((_) {}),
      ]);
    } catch (_) {
      // Telemetry is best-effort; a flush failure must never block logout.
    }
  }

  /// DISPOSES THIS account's dosage/analytics services (awaited). The final span
  /// is flushed by [flushAccountTelemetry] BEFORE logout; this destructive
  /// teardown runs on the `loggedOut` listener ([_cancelSubs]) and widget
  /// [dispose]. Concurrent teardowns for the same account COALESCE onto one
  /// disposal (a second caller awaits the first, never double-disposing the
  /// service/database), and the map entries are removed only AFTER disposal
  /// completes — so [analyticsDataService] returns the still-closing service
  /// mid-teardown instead of resurrecting a fresh one for a logged-out account.
  Future<void> disposeAccountServices(String clientName) {
    return _disposingServices[clientName] ??= () async {
      // #Pangea
      // Captured BEFORE any await, so the entry evicted in `finally` is the
      // one this teardown actually disposed and not whatever occupies the key
      // by the time it finishes.
      final disposingCall = _callServices[clientName];
      final disposingAnalytics = _analyticsServices[clientName];
      // Pangea#
      try {
        _activityAutoSaveServices[clientName]?.dispose();
        // The CALL first, and not just the service. Disposing the service
        // retracts this account's MatrixRTC membership, which is bookkeeping;
        // the LiveKit connection, the microphone, the recorder and Android's
        // ongoing-call notification all belong to the session. Logging out
        // while on a call left every one of them running -- the other person
        // could still hear a learner who had signed out, and the phone still
        // showed a call in progress for an account that was gone.
        final live = activeCall.value;
        // By the client OBJECT when we have one. Matching on the name alone
        // would let a departing account end the SUCCESSOR's call, for the same
        // reused-name reason described above.
        if (live != null && live.room.client.clientName == clientName) {
          activeCall.value = null;
          live.dispose();
        }
        await disposingCall?.dispose();
        await disposingAnalytics?.dispose();
      } finally {
        _activityAutoSaveServices.remove(clientName);
        // #Pangea
        // Only if it is still the service this teardown disposed. Disposal
        // awaits network work, and a new account can claim the same name in
        // the meantime ([callServiceForClient] installs its own service on a
        // mismatch). Removing unconditionally would strip the LIVE account's
        // service and leave the incoming-call banner subscribed to a service
        // nothing else can find — an account that silently stops ringing.
        if (identical(_callServices[clientName], disposingCall)) {
          _callServices.remove(clientName);
        }
        // Pangea#
        // On the same terms as the call service above: only if it is still
        // the one this teardown disposed.
        if (identical(_analyticsServices[clientName], disposingAnalytics)) {
          _analyticsServices.remove(clientName);
        }
        _disposingServices.remove(clientName);
      }
    }();
  }

  void initMatrix() {
    for (final c in widget.clients) {
      _registerSubs(c.clientName);
    }

    if (PlatformInfos.isMobile) {
      backgroundPush = BackgroundPush(
        this,
        onFcmError: (errorMsg, {Uri? link}) async {
          final result = await showOkCancelAlertDialog(
            context:
                FluffyChatApp
                    .router
                    .routerDelegate
                    .navigatorKey
                    .currentContext ??
                context,
            title: L10n.of(context).pushNotificationsNotAvailable,
            message: errorMsg,
            okLabel: link == null
                ? L10n.of(context).ok
                : L10n.of(context).learnMore,
            cancelLabel: L10n.of(context).doNotShowAgain,
          );
          if (result == OkCancelResult.ok && link != null) {
            launchUrlString(
              link.toString(),
              mode: LaunchMode.externalApplication,
            );
          }
          if (result == OkCancelResult.cancel) {
            await AppSettings.showNoGoogle.setItem(true);
          }
        },
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground =
        state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused;
    for (final client in widget.clients) {
      client.syncPresence = state == AppLifecycleState.resumed
          ? null
          : PresenceType.unavailable;
      if (PlatformInfos.isMobile) {
        client.backgroundSync = foreground;
        client.requestHistoryOnLimitedTimeline = !foreground;
        Logs().v('Set background sync to', foreground);
      }
    }

    if (state == AppLifecycleState.resumed) {
      pangeaController.subscriptionController.refreshOnAppResume(client.userID);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // #Pangea
    // A call must never outlive the account UI that owns it. Disposing the
    // session hangs up (idempotent) and still writes the record.
    activeCall.value?.dispose();
    activeCall.value = null;
    // Pangea#

    onRoomKeyRequestSub.values.map((s) => s.cancel());
    onKeyVerificationRequestSub.values.map((s) => s.cancel());
    onLoginStateChanged.values.map((s) => s.cancel());
    onNotification.values.map((s) => s.cancel());
    client.httpClient.close();

    linuxNotifications?.close();
    // #Pangea
    // Flush + dispose every account's dosage/analytics on widget teardown so the
    // last open engagement span isn't dropped. dispose() can't be async; the
    // teardown is awaited internally and each flush POSTs on its own client, and
    // the bearer isn't invalidated by widget teardown.
    for (final name in {
      ..._analyticsServices.keys,
      ..._activityAutoSaveServices.keys,
      ..._callServices.keys,
    }) {
      unawaited(disposeAccountServices(name));
    }
    _languageListener?.cancel();
    _appLanguageSettingsListener?.cancel();
    _uriListener?.cancel();
    _screenSizeTimer?.cancel();
    notifPermissionNotifier.dispose();
    accounts.dispose();
    // Pangea#

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(create: (_) => this, child: widget.child);
  }

  // #Pangea
  /// The in-app location an OS-delivered link maps to — pure and unit-tested
  /// (incoming_uri_path_test.dart): a bare `/<code>` course join link and the
  /// `/<uuid>` activity link flow straight through to the router's
  /// LegacyRedirects, which folds them into their tokens — no per-shape
  /// rewrite here.
  static String incomingUriToPath(Uri uri) {
    if (uri.fragment.isNotEmpty) {
      return uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}';
    }
    final query = uri.queryParameters;
    final queryString = query.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    var path = '/${uri.pathSegments.join('/')}';
    if (queryString.isNotEmpty) {
      path = '$path?$queryString';
    }
    return path;
  }

  /// Whether an `app_links` emission should be navigated to.
  ///
  /// Only OS-delivered links are real inbound navigations. On **web** the
  /// plugin has no OS channel: its stream is a single value captured at
  /// construction — the URL the page was LOADED with — so every emission is a
  /// replay of the boot location the router already consumed (path URL
  /// strategy, see main.dart). Acting on that replay re-navigates the user
  /// back to the link they may already have moved on from: it arrives one
  /// post-frame AFTER the app's first frame, so closing a deep-linked
  /// activity or course in that window snapped straight back into it — the
  /// "uncloseable activity" trap (#7821). Pure, so it is unit-tested.
  static bool shouldNavigateToIncomingUri({required bool isWeb}) => !isWeb;

  Future<void> _processIncomingUris(Uri? uri) async {
    if (uri == null) return;
    if (!shouldNavigateToIncomingUri(isWeb: kIsWeb)) return;
    final path = incomingUriToPath(uri);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FluffyChatApp.router.go(path);
    });
  }

  // Pangea#
}

class _AccountBundleWithClient {
  final Client? client;
  final AccountBundle? bundle;

  _AccountBundleWithClient({this.client, this.bundle});
}
