import 'dart:async';
import 'dart:convert';

import 'package:matrix/matrix.dart';

/// Shared sign-in with the teacher dashboard (admin-dash#235), the pure half;
/// routing.instructions.md § Signing in from the dashboard.
///
/// The side that signs in asks, and uses a single-use Matrix login token only
/// from an answer to its own request, so a token pushed at it (login CSRF)
/// signs nobody in. Each side keeps a "signed in here" flag cookie on the
/// parent domain the two share, naming its own origin (never a credential),
/// and the other side asks only when it sees one. The browser side effects
/// live in shared_signin_web.dart.

/// Set by this app while signed in; its value is this app's origin.
const String appSignedInFlag = 'pangea_app_signed_in';

/// Set by the dashboard while signed in; its value is the dashboard's origin.
const String dashboardSignedInFlag = 'pangea_dashboard_signed_in';

/// How long the dashboard's API may take before the normal sign-in stays.
const Duration dashboardAskTimeout = Duration(seconds: 5);

final RegExp _requestFormat = RegExp(r'^state=([0-9a-f]{32})$');

/// The configured dashboard (`DASHBOARD_URL`) as an origin, or null when it is
/// unset or not a plain https origin (plain http only on this machine). The
/// app only ever sends a token here.
Uri? dashboardBase(String? raw) {
  final uri = Uri.tryParse(raw?.trim() ?? '');
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
  final localHttp =
      uri.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
  if (uri.scheme != 'https' && !localHttp) return null;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );
}

/// The cookie Domain two hosts share: '' for one host (a host-only cookie, as
/// on localhost, where ports share cookies), their common parent of two or
/// more labels, or null when they share no site (no flag can be seen).
String? sharedCookieDomain(String a, String b) {
  if (a == b) return '';
  final x = a.split('.').reversed.toList();
  final y = b.split('.').reversed.toList();
  var n = 0;
  while (n < x.length && n < y.length && x[n] == y[n]) {
    n++;
  }
  return n >= 2 ? x.take(n).toList().reversed.join('.') : null;
}

/// The `document.cookie` assignment for a cookie on the domain [app] and
/// [dashboard] share ([value] null removes it); null when they share no site.
String? sharedCookie({
  required String name,
  required String? value,
  required int maxAge,
  required Uri app,
  required Uri dashboard,
}) {
  final domain = sharedCookieDomain(app.host, dashboard.host);
  if (domain == null) return null;
  return [
    '$name=${value ?? ''}',
    'Path=/',
    'SameSite=Lax',
    // An expiry in the past removes it.
    value != null ? 'Max-Age=$maxAge' : 'Expires=Thu, 01 Jan 1970 00:00:00 GMT',
    if (domain.isNotEmpty) 'Domain=$domain',
    if (app.scheme == 'https') 'Secure',
  ].join('; ');
}

/// The `document.cookie` assignment that marks (or unmarks) this browser as
/// signed in to [app], for [dashboard]; null when the two share no site.
String? appFlagCookie({
  required bool signedIn,
  required Uri app,
  required Uri dashboard,
}) => sharedCookie(
  name: appSignedInFlag,
  value: signedIn ? Uri.encodeComponent(app.origin) : null,
  maxAge: 2592000,
  app: app,
  dashboard: dashboard,
);

/// Every value of cookie [name] in a `document.cookie` string. A parent
/// domain's cookie (prod's `Domain=pangea.chat`) reaches staging hosts too,
/// under the same name, so a check looks for its own value among all of them.
List<String> cookieValues(String? cookies, String name) => [
  for (final part in (cookies ?? '').split('; '))
    if (part.indexOf('=') > 0 && part.substring(0, part.indexOf('=')) == name)
      Uri.decodeComponent(part.substring(part.indexOf('=') + 1)),
];

/// The dashboard's state in a `/handoff/dashboard#state=…` request, else null.
String? dashboardRequestState(String? fragment) =>
    _requestFormat.firstMatch(fragment ?? '')?.group(1);

/// Where the app answers the dashboard: a token when signed in, else none.
String dashboardAnswerUrl(Uri dashboard, String state, {String? loginToken}) {
  final answer = loginToken == null
      ? 'handoff=none'
      : 'loginToken=${Uri.encodeQueryComponent(loginToken)}';
  return '$dashboard/auth/handoff/#$answer&state=$state';
}

/// A signed-out app asks the dashboard's API for this browser's sign-in, with
/// [post] (a credentialed POST that returns the response body). The login
/// token, or null when there is nothing to ask for, the dashboard has no
/// session to share, or the API is down or slow (routine: [onRoutine]) or
/// answers nonsense (an error: [onError]): the normal sign-in stays.
Future<String?> askDashboardForLoginToken({
  required bool hasSession,
  required String? cookies,
  required Uri? dashboard,
  required String teacherBffApi,
  required Future<String?> Function(Uri url) post,
  required void Function(Object error, StackTrace stackTrace) onError,
  required void Function(String message, Object? error) onRoutine,
  Duration timeout = dashboardAskTimeout,
}) async {
  if (hasSession || dashboard == null || teacherBffApi.isEmpty) return null;
  if (!dashboardSignedIn(cookies, dashboard)) return null;
  final String? body;
  try {
    body = await post(
      Uri.parse('$teacherBffApi/api/auth/handoff/app'),
    ).timeout(timeout);
  } catch (e) {
    // A down or slow API is no worse than no hand-off.
    onRoutine('the dashboard could not be asked', e);
    return null;
  }
  try {
    final token = (jsonDecode(body ?? '') as Map)['login_token'];
    return token is String && token.isNotEmpty ? token : null;
  } catch (e, s) {
    onError(e, s);
    return null;
  }
}

/// Whether the dashboard marked this browser as signed in to it.
bool dashboardSignedIn(String? cookies, Uri? dashboard) =>
    dashboard != null &&
    cookieValues(cookies, dashboardSignedInFlag).contains(dashboard.origin);

// --- Signing out of both (owner, 2026-11-16) --------------------------------
// One "signed out" marker on the shared parent domain, naming the dashboard
// (so environments never read each other's). Either side sets it on its own
// sign-out; while it is set neither side hands off, and each side that still
// finds a session of its own ends it at its next visit. A sign-in by hand
// clears it. Neither side needs the other to be up at the moment of sign-out.

/// The shared-domain cookie a sign-out on either side sets.
const String signedOutMarker = 'pangea_signed_out';

/// Whether this browser signed out of this app and dashboard (either side).
bool signedOutOfBoth(String? cookies, Uri? dashboard) =>
    dashboard != null &&
    cookieValues(cookies, signedOutMarker).contains(dashboard.origin);

// --- The flows, behind a host the browser half implements -------------------

/// What the flows need from the browser and the Matrix session; the web half
/// implements it, tests fake it.
abstract class SharedSignInHost {
  /// This app's own address.
  Uri get app;

  /// The configured dashboard (`DASHBOARD_URL`), or null.
  Uri? get dashboard;

  /// The dashboard's API (`TEACHER_BFF_API`), or empty.
  String get teacherBffApi;

  String? readCookies();
  void writeCookie(String cookie);

  /// Whether any account is signed in on this device.
  bool hasSession();

  /// Completes once the stored session has been restored.
  Future<void> settled();

  /// A POST with this browser's cookies; the response body. Throws on a
  /// failure or a non-2xx answer.
  Future<String?> credentialedPost(Uri url);

  Future<void> loginWithToken(String loginToken);
  Future<String> mintLoginToken();

  /// Signs every signed-in account out of this device, the app's normal way.
  Future<void> signOutHere();

  void goToWorld();
  void leaveFor(String url);

  /// A real failure (reported).
  void onError(Object error, StackTrace stackTrace);

  /// An expected outcome worth a log line, not a report.
  void onRoutine(String message, Object? error);
}

/// Marks (or unmarks) this browser as signed in to the app, for the dashboard.
void markAppSignedIn(SharedSignInHost host, bool signedIn) {
  final dashboard = host.dashboard;
  if (dashboard == null) return;
  final cookie = appFlagCookie(
    signedIn: signedIn,
    app: host.app,
    dashboard: dashboard,
  );
  if (cookie != null) host.writeCookie(cookie);
}

/// Sets (the app's own sign-out) or clears (a sign-in by hand) the
/// signed-out marker.
void markSignedOutOfBoth(SharedSignInHost host, bool signedOut) {
  final dashboard = host.dashboard;
  if (dashboard == null) return;
  final cookie = sharedCookie(
    name: signedOutMarker,
    value: signedOut ? Uri.encodeComponent(dashboard.origin) : null,
    maxAge: 31536000,
    app: host.app,
    dashboard: dashboard,
  );
  if (cookie != null) host.writeCookie(cookie);
}

/// Synapse's one-token-a-minute limit, or a login token already used or
/// expired: expected, not a failure.
bool _routine(Object e) =>
    e is MatrixException &&
    (e.error == MatrixError.M_LIMIT_EXCEEDED ||
        e.error == MatrixError.M_FORBIDDEN);

/// At boot, once the stored session settled. With the signed-out marker set
/// (this browser signed out of the dashboard since), a session still here is
/// signed out the normal way and nothing is asked. Otherwise publishes whether
/// this browser is signed in and, signed out with the dashboard's flag
/// present, asks the dashboard's API for a sign-in. True when it signed in
/// (then `/` opens the kept link, or onboarding).
Future<bool> signInFromDashboard(SharedSignInHost host) async {
  await host.settled();
  if (signedOutOfBoth(host.readCookies(), host.dashboard)) {
    if (host.hasSession()) {
      try {
        await host.signOutHere();
      } catch (e, s) {
        host.onError(e, s);
      }
    }
    markAppSignedIn(host, false);
    return false;
  }
  markAppSignedIn(host, host.hasSession());
  final token = await askDashboardForLoginToken(
    hasSession: host.hasSession(),
    cookies: host.readCookies(),
    dashboard: host.dashboard,
    teacherBffApi: host.teacherBffApi,
    post: host.credentialedPost,
    onError: host.onError,
    onRoutine: host.onRoutine,
  );
  if (token == null || host.hasSession()) return false;
  try {
    await host.loginWithToken(token);
  } catch (e, s) {
    // The normal sign-in, with the link kept.
    _routine(e)
        ? host.onRoutine('the dashboard\'s login token was refused', e)
        : host.onError(e, s);
    return false;
  }
  // The sign-in can land before the boot's own redirect to the sign-in page
  // does, and the login listener only moves a visitor already on it.
  host.goToWorld();
  return true;
}

/// `/handoff/dashboard`: answers the dashboard's request ([state]) with a
/// token when signed in (and not signed out of both since), else none, only
/// ever to `DASHBOARD_URL`. False when there is nothing to answer.
Future<bool> answerDashboard(SharedSignInHost host, String? state) async {
  final dashboard = host.dashboard;
  if (state == null || dashboard == null) return false;
  await host.settled();
  String? token;
  if (host.hasSession() && !signedOutOfBoth(host.readCookies(), dashboard)) {
    try {
      token = await host.mintLoginToken();
    } catch (e, s) {
      // The dashboard shows its own sign-in.
      _routine(e)
          ? host.onRoutine('no login token for the dashboard', e)
          : host.onError(e, s);
    }
  }
  host.leaveFor(dashboardAnswerUrl(dashboard, state, loginToken: token));
  return true;
}
