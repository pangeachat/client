import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/features/authentication/p_logout.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/shared_signin/shared_signin.dart' as flows;
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/home/store_login_method_repo.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Shared sign-in with the teacher dashboard (admin-dash#235), the browser
/// half: [_BrowserHost] reads and writes cookies, talks to the network, the
/// Matrix session and the router; every decision is a flow in
/// shared_signin.dart, tested there against a fake host.
///
/// Values from universal_html are read into nullable locals: off the web (the
/// test VM) those getters are nullable, and a non-null use compiles on the web
/// only.
abstract class SharedSignIn {
  static String? _requestState;

  /// Set once the boot's own sign-in step is over: a sign-in after that is
  /// one by hand (or a hand-off, which the marker would have stopped).
  static bool _bootDone = false;

  /// Called first thing at boot: keeps the dashboard's request, if any,
  /// before the router rewrites the address.
  static void readRequest() {
    if (!kIsWeb || Uri.base.path != '/handoff/dashboard') return;
    _requestState = flows.dashboardRequestState(Uri.base.fragment);
  }

  /// Tells the dashboard whether this browser is signed in to the app.
  static void markSignedIn(bool signedIn) {
    if (!kIsWeb) return;
    flows.markAppSignedIn(_BrowserHost(null), signedIn);
  }

  /// The app's own sign-out: this browser signs out of the dashboard too, at
  /// the dashboard's next visit (the signed-out marker).
  static void markSignedOutOfBoth() {
    if (!kIsWeb) return;
    flows.markSignedOutOfBoth(_BrowserHost(null), true);
  }

  /// A sign-in on this device after boot is one by hand: hand-offs are on
  /// again in this browser.
  static void onSignedIn() {
    if (!kIsWeb || !_bootDone) return;
    flows.markSignedOutOfBoth(_BrowserHost(null), false);
  }

  /// Boot: honours the signed-out marker, else signs in from the dashboard
  /// when it can.
  static Future<void> signInFromDashboard(MatrixState matrix) async {
    if (!kIsWeb) return;
    try {
      await flows.signInFromDashboard(_BrowserHost(matrix));
    } finally {
      _bootDone = true;
    }
  }

  /// `/handoff/dashboard`.
  static Future<bool> answerDashboard(MatrixState matrix) async {
    if (!kIsWeb) return false;
    final state = _requestState;
    _requestState = null;
    return flows.answerDashboard(_BrowserHost(matrix), state);
  }
}

class _BrowserHost implements flows.SharedSignInHost {
  final MatrixState? matrix;

  _BrowserHost(this.matrix);

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
  bool hasSession() => matrix?.widget.clients.any((c) => c.isLogged()) ?? false;

  @override
  Future<void> settled() async {
    final client = matrix?.client;
    if (client == null) return;
    await Future.wait<void>([
      client.roomsLoading?.then<void>((_) {}, onError: (_) {}) ??
          Future<void>.value(),
      client.accountDataLoading?.then<void>((_) {}, onError: (_) {}) ??
          Future<void>.value(),
    ]);
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
  Future<void> signOutHere() async {
    final m = matrix!;
    // A snapshot: each logout removes its client from the live list.
    for (final client in m.widget.clients.where((c) => c.isLogged()).toList()) {
      // The app's normal logout for this device: never other sessions.
      await logoutAccount(m, client);
    }
  }

  @override
  void goToWorld() => FluffyChatApp.router.go(PRoutes.world);

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
