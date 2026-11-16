import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/shared_signin/shared_signin.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/home/store_login_method_repo.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Shared sign-in with the teacher dashboard (admin-dash#235), the browser
/// half: it reads and writes cookies, asks over the network and navigates;
/// every decision is a pure function in shared_signin.dart.
///
/// Types from universal_html are read into nullable locals: off the web (the
/// test VM) the same getters are nullable, and a non-null use compiles on the
/// web only.
abstract class SharedSignIn {
  /// The dashboard's state when this page load is its `/handoff/dashboard`
  /// request, read at boot before the router rewrites the address.
  static String? _requestState;

  /// The fragment of a `/handoff/signout` page load, read at boot.
  static String? _signOutFragment;

  /// Called first thing at boot: keeps the dashboard's request, if any.
  static void readRequest() {
    if (!kIsWeb) return;
    if (Uri.base.path == '/handoff/dashboard') {
      _requestState = dashboardRequestState(Uri.base.fragment);
    } else if (Uri.base.path == '/handoff/signout') {
      _signOutFragment = Uri.base.fragment;
    }
  }

  /// Marks (or unmarks) this browser as signed in to the app, for the
  /// dashboard. Nothing is written without a dashboard sharing this site.
  static void markSignedIn(bool signedIn) {
    final dashboard = Environment.dashboardUrl;
    if (!kIsWeb || dashboard == null) return;
    final cookie = appFlagCookie(
      signedIn: signedIn,
      app: Uri.base,
      dashboard: dashboard,
    );
    if (cookie != null) html.document.cookie = cookie;
  }

  /// Once the stored session has settled: publishes whether this browser is
  /// signed in, and, signed out with the dashboard's flag present, asks the
  /// dashboard's API for this browser's sign-in. A token signs in as the same
  /// teacher, then `/` opens the kept link (or onboarding). Anything else
  /// leaves the normal sign-in where it is.
  static Future<void> signInFromDashboard(MatrixState matrix) async {
    if (!kIsWeb) return;
    await _restoreSettled(matrix.client);
    bool hasSession() => matrix.widget.clients.any((c) => c.isLogged());
    markSignedIn(hasSession());
    final String? cookies = html.document.cookie;
    final token = await askDashboardForLoginToken(
      hasSession: hasSession(),
      cookies: cookies,
      dashboard: Environment.dashboardUrl,
      teacherBffApi: Environment.teacherBffApi,
      post: _credentialedPost,
      onError: (e, s) =>
          Logs().w('[handoff] the dashboard could not be asked', e, s),
    );
    if (token == null || hasSession()) return;
    GoogleAnalytics.prepareLogin('dashboard');
    try {
      final loginClient = await matrix.getLoginClient();
      // The method of the dashboard's own sign-in is unknown here, so the
      // previous hint is cleared rather than replaced with a guess.
      await LoginMethodRepo.clearStoredLoginMethod();
      await loginClient.login(
        LoginType.mLoginToken,
        token: token,
        initialDeviceDisplayName: PlatformInfos.clientName,
      );
      // The sign-in can land before the boot's own redirect to the sign-in
      // page does, and the login listener only moves a visitor already on it.
      FluffyChatApp.router.go(PRoutes.world);
    } catch (e, s) {
      GoogleAnalytics.cancelPendingLogin();
      // An expired or used token: the normal sign-in, with the link kept.
      ErrorHandler.logError(e: e, s: s, data: {'flow': 'dashboard-handoff'});
    }
  }

  static Future<String?> _credentialedPost(Uri url) async {
    final request = await html.HttpRequest.request(
      url.toString(),
      method: 'POST',
      withCredentials: true,
    );
    final String? body = request.responseText;
    return body;
  }

  /// `/handoff/dashboard`: answers the dashboard's request with a token when
  /// this browser is signed in, otherwise none, only ever to `DASHBOARD_URL`.
  /// False when there is nothing to answer, so the page moves into the app.
  static Future<bool> answerDashboard(MatrixState matrix) async {
    if (!kIsWeb) return false;
    final state = _requestState;
    _requestState = null;
    final dashboard = Environment.dashboardUrl;
    if (state == null || dashboard == null) return false;
    await _restoreSettled(matrix.client);
    final client = matrix.client;
    String? token;
    if (client.isLogged()) {
      try {
        token = (await client.generateLoginToken()).loginToken;
      } catch (e, s) {
        // Signed in but no token (Synapse allows one a minute): the dashboard
        // shows its own sign-in.
        ErrorHandler.logError(e: e, s: s, data: {'flow': 'dashboard-handoff'});
      }
    }
    html.window.location.replace(
      dashboardAnswerUrl(dashboard, state, loginToken: token),
    );
    return true;
  }

  static Future<void> _restoreSettled(Client client) => Future.wait<void>([
    client.roomsLoading?.then<void>((_) {}, onError: (_) {}) ??
        Future<void>.value(),
    client.accountDataLoading?.then<void>((_) {}, onError: (_) {}) ??
        Future<void>.value(),
  ]);

  /// After this app's own sign-out by hand: through the dashboard's sign-out
  /// page when the dashboard is signed in here and answering (it returns to
  /// this app's sign-in), so this browser is signed out of both. Otherwise
  /// the visitor stays on this app's sign-in.
  static Future<void> leaveAfterSignOut() async {
    if (!kIsWeb) return;
    final dashboard = Environment.dashboardUrl;
    final String? cookies = html.document.cookie;
    if (!dashboardSignedIn(cookies, dashboard)) return;
    if (!await _reachable(dashboard!)) return;
    final nonce = newNonce();
    final cookie = sharedCookie(
      name: signOutCookie,
      value: nonce,
      maxAge: 120,
      app: Uri.base,
      dashboard: dashboard,
    );
    if (cookie == null) return;
    html.document.cookie = cookie;
    html.window.location.assign(dashboardSignOutUrl(dashboard, nonce));
  }

  /// `/handoff/signout`: the dashboard signed out and asks this app to sign
  /// this browser out too. Only a request carrying the nonce the dashboard put
  /// in the shared cookie is honoured; the cookie is cleared either way. Then
  /// back to the dashboard's sign-in. False when there was no such request, so
  /// the page moves into the app.
  static Future<bool> answerSignOut(MatrixState matrix) async {
    if (!kIsWeb) return false;
    final fragment = _signOutFragment;
    _signOutFragment = null;
    final dashboard = Environment.dashboardUrl;
    final String? cookies = html.document.cookie;
    final requested = signOutRequested(fragment, cookies);
    if (dashboard != null) {
      final clear = sharedCookie(
        name: signOutCookie,
        value: null,
        maxAge: 0,
        app: Uri.base,
        dashboard: dashboard,
      );
      if (clear != null) html.document.cookie = clear;
    }
    if (!requested || dashboard == null) return false;
    await _restoreSettled(matrix.client);
    for (final client in matrix.widget.clients.where((c) => c.isLogged())) {
      try {
        // This device only: never the account's other sessions.
        await client.logout();
      } catch (e, s) {
        ErrorHandler.logError(e: e, s: s, data: {'flow': 'shared-signout'});
      }
    }
    html.window.location.replace('$dashboard/login/');
    return true;
  }

  /// Whether [site] answers at all, by loading its icon: an image loads from
  /// any origin without CORS. A failure or a slow answer is no.
  static Future<bool> _reachable(Uri site) async {
    final done = Completer<bool>();
    final probe = html.ImageElement();
    probe.onLoad.first.then((_) {
      if (!done.isCompleted) done.complete(true);
    });
    probe.onError.first.then((_) {
      if (!done.isCompleted) done.complete(false);
    });
    probe.src =
        '$site/favicon.ico?probe=${DateTime.now().millisecondsSinceEpoch}';
    return done.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => false,
    );
  }
}
