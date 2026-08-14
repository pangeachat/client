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
import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/languages/locale_provider.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/overlay/any_state_holder.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/dev_login.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
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

  /// Accounts whose services are being torn down, mapped to the in-flight
  /// disposal. Concurrent teardowns coalesce onto ONE disposal (no double-
  /// dispose), and [analyticsDataService] refuses to resurrect a service while
  /// its account is closing — the entries stay in their maps until disposal
  /// finishes, so a queued rebuild reads the closing service rather than
  /// creating a fresh one that would outlive the account and leak.
  final Map<String, Future<void>> _disposingServices = {};
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

  Future<Client> getLoginClient() async {
    if (widget.clients.isNotEmpty && !client.isLogged()) {
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
                await MatrixState.pangeaController.handleLoginStateChange(
                  LoginState.loggedIn,
                  _loginClientCandidate!.userID,
                  context,
                );
                // Pangea#
                if (!widget.clients.contains(_loginClientCandidate)) {
                  widget.clients.add(_loginClientCandidate!);
                }
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
    if (widget.clients.isEmpty) widget.clients.add(candidate);
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
        await _cancelSubs(c.clientName);
        widget.clients.remove(c);
        ClientManager.removeClientNameFromStore(c.clientName, store);
        // #Pangea
        // InitWithRestoreExtension.deleteSessionBackup(name);
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
          FluffyChatApp.router.go(isL2Set ? PRoutes.world : '/registration');
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
      final userId = _analyticsServices[clientName]?.accountUserId;
      if (userId == null || userId.isEmpty) return;
      // Tombstoned, non-destructive flush: KEEPS the tracker (so a failed logout
      // leaves it live) but blocks a new span from opening during the awaited
      // POST — which would otherwise flush only after logout kills the bearer.
      await DosageEngagementTracker.flushForLogout(
        userId,
      ).timeout(const Duration(seconds: 5));
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
      try {
        _activityAutoSaveServices[clientName]?.dispose();
        await _analyticsServices[clientName]?.dispose();
      } finally {
        _activityAutoSaveServices.remove(clientName);
        _analyticsServices.remove(clientName);
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
    }) {
      unawaited(disposeAccountServices(name));
    }
    _languageListener?.cancel();
    _appLanguageSettingsListener?.cancel();
    _uriListener?.cancel();
    _screenSizeTimer?.cancel();
    notifPermissionNotifier.dispose();
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
