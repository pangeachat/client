import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
/// session to share, or the API fails or is slow ([onError] is told): the
/// normal sign-in stays.
Future<String?> askDashboardForLoginToken({
  required bool hasSession,
  required String? cookies,
  required Uri? dashboard,
  required String teacherBffApi,
  required Future<String?> Function(Uri url) post,
  required void Function(Object error, StackTrace stackTrace) onError,
  Duration timeout = dashboardAskTimeout,
}) async {
  if (hasSession || dashboard == null || teacherBffApi.isEmpty) return null;
  if (!dashboardSignedIn(cookies, dashboard)) return null;
  try {
    final body = await post(
      Uri.parse('$teacherBffApi/api/auth/handoff/app'),
    ).timeout(timeout);
    final token = (jsonDecode(body ?? '') as Map)['login_token'];
    return token is String && token.isNotEmpty ? token : null;
  } catch (e, s) {
    // A down, slow or confused API is no worse than no hand-off.
    onError(e, s);
    return null;
  }
}

// --- Signing out of both (owner, 2026-11-16) --------------------------------
// A sign-out on either side signs this browser out of the other too. The
// dashboard's comes through `/handoff/signout`, which signs out only for a
// request whose nonce also sits in a short-lived cookie on the shared parent
// domain, so a link from a site outside it signs nobody out. The app's ends
// the dashboard session through admin-dash-api directly.

/// The shared-domain cookie holding a sign-out request's nonce.
const String signOutCookie = 'pangea_signout';

final RegExp _nonceFormat = RegExp(r'^nonce=([0-9a-f]{32})$');

/// A fresh 128-bit nonce, as 32 hex characters.
String newNonce([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// The dashboard's sign-out page, asked to sign this browser out too.
String dashboardSignOutUrl(Uri dashboard, String nonce) =>
    '$dashboard/auth/signout/#nonce=$nonce';

/// Whether `/handoff/signout`'s request is the dashboard's: its nonce is the
/// one in the shared cookie.
bool signOutRequested(String? fragment, String? cookies) {
  final nonce = _nonceFormat.firstMatch(fragment ?? '')?.group(1);
  return nonce != null && cookieValues(cookies, signOutCookie).contains(nonce);
}

/// Whether the dashboard marked this browser as signed in to it.
bool dashboardSignedIn(String? cookies, Uri? dashboard) =>
    dashboard != null &&
    cookieValues(cookies, dashboardSignedInFlag).contains(dashboard.origin);

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
  void onError(Object error, StackTrace stackTrace);
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

/// At boot: publishes whether this browser is signed in, and, signed out with
/// the dashboard's flag present, asks the dashboard's API for a sign-in. True
/// when it signed in (then `/` opens the kept link, or onboarding).
Future<bool> signInFromDashboard(SharedSignInHost host) async {
  await host.settled();
  markAppSignedIn(host, host.hasSession());
  final token = await askDashboardForLoginToken(
    hasSession: host.hasSession(),
    cookies: host.readCookies(),
    dashboard: host.dashboard,
    teacherBffApi: host.teacherBffApi,
    post: host.credentialedPost,
    onError: host.onError,
  );
  if (token == null || host.hasSession()) return false;
  try {
    await host.loginWithToken(token);
  } catch (e, s) {
    // An expired or used token: the normal sign-in, with the link kept.
    host.onError(e, s);
    return false;
  }
  // The sign-in can land before the boot's own redirect to the sign-in page
  // does, and the login listener only moves a visitor already on it.
  host.goToWorld();
  return true;
}

/// `/handoff/dashboard`: answers the dashboard's request ([state]) with a
/// token when signed in, else none, only ever to `DASHBOARD_URL`. False when
/// there is nothing to answer.
Future<bool> answerDashboard(SharedSignInHost host, String? state) async {
  final dashboard = host.dashboard;
  if (state == null || dashboard == null) return false;
  await host.settled();
  String? token;
  if (host.hasSession()) {
    try {
      token = await host.mintLoginToken();
    } catch (e, s) {
      // Signed in but no token (Synapse allows one a minute): the dashboard
      // shows its own sign-in.
      host.onError(e, s);
    }
  }
  host.leaveFor(dashboardAnswerUrl(dashboard, state, loginToken: token));
  return true;
}

/// After this app's own sign-out: ends this browser's dashboard session
/// through the dashboard's API, never depending on the dashboard's pages, and
/// removes its signed-in flag so no later visit here signs back in from it.
Future<void> signOutDashboardToo(SharedSignInHost host) async {
  final dashboard = host.dashboard;
  if (!dashboardSignedIn(host.readCookies(), dashboard)) return;
  final flag = sharedCookie(
    name: dashboardSignedInFlag,
    value: null,
    maxAge: 0,
    app: host.app,
    dashboard: dashboard!,
  );
  if (flag != null) host.writeCookie(flag);
  if (host.teacherBffApi.isEmpty) return;
  try {
    await host
        .credentialedPost(Uri.parse('${host.teacherBffApi}/api/auth/logout'))
        .timeout(dashboardAskTimeout);
  } catch (e, s) {
    host.onError(e, s);
  }
}

/// `/handoff/signout`: the dashboard signed out and asks this app to sign
/// this browser out too ([fragment] carries its nonce). Honoured only when the
/// nonce is in the shared cookie, which is cleared either way; then back to
/// the dashboard's sign-in. False when there was no such request.
Future<bool> answerSignOut(SharedSignInHost host, String? fragment) async {
  final dashboard = host.dashboard;
  if (dashboard == null) return false;
  final requested = signOutRequested(fragment, host.readCookies());
  final clear = sharedCookie(
    name: signOutCookie,
    value: null,
    maxAge: 0,
    app: host.app,
    dashboard: dashboard,
  );
  if (clear != null) host.writeCookie(clear);
  if (!requested) return false;
  await host.settled();
  try {
    await host.signOutHere();
  } catch (e, s) {
    host.onError(e, s);
  }
  markAppSignedIn(host, false);
  host.leaveFor('$dashboard/login/');
  return true;
}
