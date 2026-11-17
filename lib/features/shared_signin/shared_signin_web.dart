import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/features/authentication/p_logout.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/shared_signin/shared_signin.dart' as flows;
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/home/store_login_method_repo.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Shared sign-in with the teacher dashboard (admin-dash#235), the browser
/// half: [_BrowserHost] reads and writes cookies and storage, talks to the
/// network, the Matrix session and the router; every decision is a flow in
/// shared_signin.dart, tested there against a fake host.
///
/// Values from universal_html are read into nullable locals: off the web (the
/// test VM) those getters are nullable, and a non-null use compiles on the web
/// only.
abstract class SharedSignIn {
  static String? _requestState;

  /// Accounts being signed out because this browser signed out (on either
  /// side) after they signed in. The guards treat them as signed out at once,
  /// so the sign-in shows without waiting for the logout to finish.
  static final Set<String> _signingOut = {};

  static bool _watching = false;

  /// Whether [client] is signed in and not being signed out.
  static bool isLive(Client client) =>
      client.isLogged() && !_signingOut.contains(client.clientName);

  /// Called first thing at boot: keeps the dashboard's request, if any,
  /// before the router rewrites the address.
  static void readRequest() {
    if (!kIsWeb || Uri.base.path != '/handoff/dashboard') return;
    _requestState = flows.dashboardRequestState(Uri.base.fragment);
  }

  /// Right after the stored sessions are restored, before anything shows:
  /// sessions that began before this browser's latest sign-out are marked for
  /// signing out, so the first screen is already the sign-in.
  static void checkAtStart(List<Client> clients) {
    if (!kIsWeb) return;
    _signingOut.addAll(flows.accountsToSignOut(_BrowserHost(null, clients)));
  }

  /// After any sign-in or sign-out on this device.
  static void onSessionChange(List<Client> clients) {
    if (!kIsWeb) return;
    flows.onSessionChange(_BrowserHost(null, clients));
  }

  /// The app's own sign-out: this browser signs out of the dashboard too, at
  /// the dashboard's next visit (the signed-out time).
  static void markSignedOutOfBoth() {
    if (!kIsWeb) return;
    flows.markSignedOutOfBoth(_BrowserHost(null, const []));
  }

  /// Boot, once the app is up: ends the sessions marked at start, then signs
  /// in from the dashboard when it can. Open tabs check again whenever they
  /// come back into view.
  static Future<void> start(MatrixState matrix) async {
    if (!kIsWeb) return;
    _watch(matrix);
    final host = _BrowserHost(matrix, matrix.widget.clients);
    await flows.honourSignOut(host, Set.of(_signingOut));
    await flows.signInFromDashboard(host);
  }

  static void _watch(MatrixState matrix) {
    if (_watching) return;
    _watching = true;
    Future<void> recheck(_) async {
      if (html.document.visibilityState == 'hidden') return;
      final host = _BrowserHost(matrix, matrix.widget.clients);
      final accounts = flows.accountsToSignOut(host);
      if (accounts.isEmpty) return;
      _signingOut.addAll(accounts);
      await flows.honourSignOut(host, accounts);
    }

    html.document.onVisibilityChange.listen(recheck);
    html.window.onFocus.listen(recheck);
  }

  /// `/handoff/dashboard`.
  static Future<bool> answerDashboard(MatrixState matrix) async {
    if (!kIsWeb) return false;
    final state = _requestState;
    _requestState = null;
    return flows.answerDashboard(
      _BrowserHost(matrix, matrix.widget.clients),
      state,
    );
  }
}

class _BrowserHost implements flows.SharedSignInHost {
  final MatrixState? matrix;
  final List<Client> clients;

  _BrowserHost(this.matrix, this.clients);

  static const _sessionStartedKey = 'pangea-app-session-started';

  @override
  Uri get app => Uri.base;

  @override
  Uri? get dashboard => Environment.dashboardUrl;

  @override
  String get teacherBffApi => Environment.teacherBffApi;

  @override
  String? readCookies() {
    final String? cookies = html.document.cookie;
    return cookies;
  }

  @override
  void writeCookie(String cookie) => html.document.cookie = cookie;

  @override
  int? readSessionStart() {
    try {
      final String? raw = html.window.localStorage[_sessionStartedKey];
      return raw == null ? null : int.tryParse(raw);
    } catch (e) {
      // silent-ok: unknown reads as "began before any sign-out", the safe side.
      Logs().w('[handoff] when this session began could not be read', e);
      return null;
    }
  }

  @override
  void writeSessionStart(int? ms) {
    try {
      if (ms == null) {
        html.window.localStorage.remove(_sessionStartedKey);
      } else {
        html.window.localStorage[_sessionStartedKey] = '$ms';
      }
    } catch (e) {
      Logs().w('[handoff] when this session began could not be kept', e);
    }
  }

  @override
  int now() => DateTime.now().millisecondsSinceEpoch;

  @override
  List<String> liveAccounts() =>
      clients.where(SharedSignIn.isLive).map((c) => c.clientName).toList();

  @override
  Future<void> signOut(Set<String> accounts) async {
    final m = matrix!;
    // A snapshot: each logout removes its client from the live list.
    final targets = m.widget.clients
        .where((c) => c.isLogged() && accounts.contains(c.clientName))
        .toList();
    try {
      for (final client in targets) {
        // The app's normal logout for this device: never other sessions.
        await logoutAccount(m, client);
      }
    } finally {
      SharedSignIn._signingOut.removeAll(accounts);
    }
  }

  @override
  Future<String?> credentialedPost(Uri url) async {
    final request = await html.HttpRequest.request(
      url.toString(),
      method: 'POST',
      withCredentials: true,
    );
    final String? body = request.responseText;
    return body;
  }

  @override
  Future<void> loginWithToken(String loginToken) async {
    final loginClient = await matrix!.getLoginClient();
    GoogleAnalytics.prepareLogin('dashboard');
    try {
      // The method of the dashboard's own sign-in is unknown here, so the
      // previous hint is cleared rather than replaced with a guess.
      await LoginMethodRepo.clearStoredLoginMethod();
      await loginClient.login(
        LoginType.mLoginToken,
        token: loginToken,
        initialDeviceDisplayName: PlatformInfos.clientName,
      );
    } catch (_) {
      GoogleAnalytics.cancelPendingLogin();
      rethrow;
    }
  }

  @override
  Future<String> mintLoginToken() async =>
      (await matrix!.client.generateLoginToken()).loginToken;

  @override
  String? keptDestination() => SpaceCodeRepo.destination;

  @override
  void goTo(String location) {
    // Going straight there: the kept link is spent.
    if (location == SpaceCodeRepo.destination) {
      SpaceCodeRepo.clearDestination();
    }
    FluffyChatApp.router.go(location);
  }

  @override
  void goToSignIn() => FluffyChatApp.router.go('/home');

  @override
  void leaveFor(String url) => html.window.location.replace(url);

  @override
  void onError(Object error, StackTrace stackTrace) => ErrorHandler.logError(
    e: error,
    s: stackTrace,
    data: {'flow': 'dashboard-handoff'},
  );

  @override
  void onRoutine(String message, Object? error) =>
      Logs().i('[handoff] $message', error);
}
