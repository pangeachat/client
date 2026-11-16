import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/features/shared_signin/shared_signin.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Shared sign-in with the teacher dashboard (admin-dash#235), the browser
/// half: it reads and writes this tab's storage and navigates; every decision
/// is a pure function in shared_signin.dart.
abstract class SharedSignIn {
  static HandoffArrival? _arrival;

  /// A token this tab asked for and the state check accepted, waiting for the
  /// stored session to settle ([completePendingLogin]).
  static String? _pendingToken;

  static html.Storage get _tab => html.window.sessionStorage;

  /// Reads the fragment `web/index.html` moved out of the address bar, before
  /// analytics, Sentry or the router start. An answer ends this tab's
  /// hand-offs whatever it says, and its saved state is consumed before it is
  /// compared, so a token is tried once at most.
  static void readArrival() {
    if (!kIsWeb) return;
    try {
      _arrival = parseHandoffArrival(_tab.remove(handoffArrivalStorageKey));
      if (_arrival is! HandoffAnswer) return;
      _tab[handoffTriedStorageKey] = '1';
      _pendingToken = acceptedHandoffToken(
        _arrival,
        _tab.remove(handoffStateStorageKey),
      );
      if ((_arrival as HandoffAnswer).loginToken != null &&
          _pendingToken == null) {
        Logs().w('[handoff] dropped a login token this tab did not ask for');
      }
    } catch (e, s) {
      // No tab storage: nothing can be checked, so nothing is used.
      ErrorHandler.logError(e: e, s: s, data: {'flow': 'dashboard-handoff'});
    }
  }

  /// A signed-out visitor who opened a link from the dashboard: ask the
  /// dashboard's API, once per tab, whether this browser is signed in there.
  /// The link is already kept as the destination, so it opens after either
  /// sign-in. Returns whether the page is leaving.
  static bool maybeAskDashboard({required bool hasSession}) {
    if (!kIsWeb) return false;
    final bff = Environment.teacherBffApi;
    try {
      if (!shouldAskDashboard(
        isWeb: kIsWeb,
        hinted: _arrival is HandoffHint,
        alreadyTried: _tab[handoffTriedStorageKey] != null,
        hasSession: hasSession,
        teacherBffApi: bff,
      )) {
        return false;
      }
      final state = newHandoffState();
      _tab[handoffStateStorageKey] = state;
      _tab[handoffTriedStorageKey] = '1';
      _arrival = null;
      html.window.location.replace(
        dashboardSignInRequestUrl(bff, state, html.window.location.origin),
      );
      return true;
    } catch (e, s) {
      // Without tab storage the answer could never be checked.
      ErrorHandler.logError(e: e, s: s, data: {'flow': 'dashboard-handoff'});
      return false;
    }
  }

  /// Signs in with an accepted token once the stored session has settled. A
  /// session that exists by then (another tab signed in) is kept and the token
  /// dropped, so an account is never swapped. The `/` guard then opens the
  /// kept destination.
  static Future<void> completePendingLogin(MatrixState matrix) async {
    final token = _pendingToken;
    _pendingToken = null;
    if (token == null) return;
    await _restoreSettled(matrix.client);
    if (matrix.widget.clients.any((c) => c.isLogged())) return;
    try {
      final loginClient = await matrix.getLoginClient();
      if (loginClient.isLogged()) return;
      await loginClient.login(
        LoginType.mLoginToken,
        token: token,
        initialDeviceDisplayName: PlatformInfos.clientName,
      );
    } catch (e, s) {
      // An expired or used token: the visitor is on the normal sign-in with
      // the destination kept. The token is never reported.
      ErrorHandler.logError(e: e, s: s, data: {'flow': 'dashboard-handoff'});
    }
  }

  /// `/handoff/dashboard`: answers the dashboard's request with a token when
  /// this browser is signed in, otherwise none, only ever to `DASHBOARD_URL`.
  /// False when there is nothing to answer, so the page moves into the app.
  static Future<bool> answerDashboard(MatrixState matrix) async {
    if (!kIsWeb) return false;
    final request = _arrival;
    _arrival = null;
    final dashboard = Environment.dashboardUrl;
    if (request is! HandoffRequest || dashboard == null) return false;
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
      dashboardAnswerUrl(dashboard, request.state, loginToken: token),
    );
    return true;
  }

  static Future<void> _restoreSettled(Client client) => Future.wait<void>([
    client.roomsLoading?.then<void>((_) {}, onError: (_) {}) ??
        Future<void>.value(),
    client.accountDataLoading?.then<void>((_) {}, onError: (_) {}) ??
        Future<void>.value(),
  ]);
}
