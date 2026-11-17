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
/// signed in to [app], for [dashboard], with when its session [began] (epoch
/// ms); null when the two share no site.
String? appFlagCookie({
  required bool signedIn,
  required Uri app,
  required Uri dashboard,
  int began = 0,
}) => sharedCookie(
  name: appSignedInFlag,
  value: signedIn ? Uri.encodeComponent('${app.origin}|$began') : null,
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

/// The latest time stamped under [name] for [origin] (`<origin>|<ms>`),
/// among every cookie of that name. Null when none names [origin].
int? latestStamp(String? cookies, String name, String origin) {
  int? latest;
  for (final value in cookieValues(cookies, name)) {
    final bar = value.lastIndexOf('|');
    if (bar < 0 || value.substring(0, bar) != origin) continue;
    final ms = int.tryParse(value.substring(bar + 1));
    if (ms != null && (latest == null || ms > latest)) latest = ms;
  }
  return latest;
}

/// Whether a session that [began] (epoch ms, null when unknown) must end
/// because this browser signed out at [signedOutAt] after it began.
bool sessionCondemned(int? began, int? signedOutAt) =>
    signedOutAt != null && (began ?? 0) <= signedOutAt;

/// Whether the dashboard has a session here that began after this browser's
/// latest sign-out, so asking it for a sign-in is wanted.
bool dashboardSignedIn(String? cookies, Uri? dashboard) {
  if (dashboard == null) return false;
  final began = latestStamp(cookies, dashboardSignedInFlag, dashboard.origin);
  return began != null &&
      !sessionCondemned(began, signedOutAt(cookies, dashboard));
}

// --- Signing out of both (owner, 2026-11-16) --------------------------------
// One "signed out" cookie on the shared parent domain: "<dashboard
// origin>|<when>" (so environments never read each other's). Either side
// writes it on its own sign-out. Each side ends any session of its own that
// began before that time, at its next start or when an open tab comes back
// into view, and never hands off to one; a session begun after it (a sign-in
// by hand) is untouched. Nothing clears it. Neither side needs the other up.

/// The shared-domain cookie a sign-out on either side writes.
const String signedOutMarker = 'pangea_signed_out';

/// When this browser last signed out of this app or its dashboard, or null.
int? signedOutAt(String? cookies, Uri? dashboard) => dashboard == null
    ? null
    : latestStamp(cookies, signedOutMarker, dashboard.origin);

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

  /// When this device's app session began (epoch ms), or null.
  int? readSessionStart();
  void writeSessionStart(int? ms);
  int now();

  /// The signed-in accounts here that are not already being signed out.
  List<String> liveAccounts();

  /// Signs these accounts out of this device, the app's normal way.
  Future<void> signOut(Set<String> accounts);

  /// A POST with this browser's cookies; the response body. Throws on a
  /// failure or a non-2xx answer.
  Future<String?> credentialedPost(Uri url);

  Future<void> loginWithToken(String loginToken);
  Future<String> mintLoginToken();

  /// The link a signed-out visitor opened, kept for after the sign-in.
  String? keptDestination();
  void goTo(String location);
  void goToSignIn();
  void leaveFor(String url);

  /// A real failure (reported).
  void onError(Object error, StackTrace stackTrace);

  /// An expected outcome worth a log line, not a report.
  void onRoutine(String message, Object? error);
}

/// Publishes whether this browser is signed in to the app, and when that
/// session began, for the dashboard.
void markAppSignedIn(SharedSignInHost host, bool signedIn) {
  final dashboard = host.dashboard;
  if (dashboard == null) return;
  final cookie = appFlagCookie(
    signedIn: signedIn,
    app: host.app,
    dashboard: dashboard,
    began: host.readSessionStart() ?? 0,
  );
  if (cookie != null) host.writeCookie(cookie);
}

/// After any sign-in or sign-out here: a session that has just appeared is
/// stamped with when it began (a restored one keeps its stamp); none left
/// forgets it. Then publishes the result. A sign-in ([signedIn]) is stamped
/// now over a stamp from before this browser's sign-out too: that stamp
/// belongs to a session still being signed out (another tab can hold its
/// storage), and keeping it would end the new one at the next check.
void onSessionChange(SharedSignInHost host, {bool signedIn = false}) {
  final live = host.liveAccounts().isNotEmpty;
  final began = host.readSessionStart();
  if (live &&
      (began == null ||
          (signedIn &&
              sessionCondemned(
                began,
                signedOutAt(host.readCookies(), host.dashboard),
              )))) {
    host.writeSessionStart(host.now());
  }
  if (!live) host.writeSessionStart(null);
  markAppSignedIn(host, live);
}

/// The app's own sign-out: records when, for the dashboard (and this app's
/// other tabs), which end their sessions begun before it.
void markSignedOutOfBoth(SharedSignInHost host) {
  final dashboard = host.dashboard;
  if (dashboard == null) return;
  final cookie = sharedCookie(
    name: signedOutMarker,
    value: Uri.encodeComponent('${dashboard.origin}|${host.now()}'),
    maxAge: 31536000,
    app: host.app,
    dashboard: dashboard,
  );
  if (cookie != null) host.writeCookie(cookie);
}

/// The accounts here to sign out because this browser signed out (on either
/// side) after the app's session began; empty otherwise.
Set<String> accountsToSignOut(SharedSignInHost host) =>
    sessionCondemned(
      host.readSessionStart(),
      signedOutAt(host.readCookies(), host.dashboard),
    )
    ? host.liveAccounts().toSet()
    : const {};

/// Signs [accounts] out the normal way; with no session left, forgets when it
/// began, unpublishes it and opens the sign-in.
Future<void> honourSignOut(SharedSignInHost host, Set<String> accounts) async {
  if (accounts.isEmpty) return;
  try {
    await host.signOut(accounts);
  } catch (e, s) {
    host.onError(e, s);
  }
  if (host.liveAccounts().isNotEmpty) return;
  host.writeSessionStart(null);
  markAppSignedIn(host, false);
  host.goToSignIn();
}

/// Synapse's one-token-a-minute limit, or a login token already used or
/// expired: expected, not a failure.
bool _routine(Object e) =>
    e is MatrixException &&
    (e.error == MatrixError.M_LIMIT_EXCEEDED ||
        e.error == MatrixError.M_FORBIDDEN);

/// At start, after [honourSignOut]: publishes whether this browser is signed
/// in and, signed out with the dashboard's flag present (a dashboard session
/// begun after any sign-out), asks the dashboard's API for a sign-in. True
/// when it signed in, then opens the link the visitor came with.
Future<bool> signInFromDashboard(SharedSignInHost host) async {
  final live = host.liveAccounts().isNotEmpty;
  markAppSignedIn(host, live);
  final token = await askDashboardForLoginToken(
    hasSession: live,
    cookies: host.readCookies(),
    dashboard: host.dashboard,
    teacherBffApi: host.teacherBffApi,
    post: host.credentialedPost,
    onError: host.onError,
    onRoutine: host.onRoutine,
  );
  if (token == null || host.liveAccounts().isNotEmpty) return false;
  // Read before the sign-in: the `/` guard consumes it as soon as the
  // sign-in lands, and a later read would find it gone.
  final destination = host.keptDestination();
  try {
    await host.loginWithToken(token);
  } catch (e, s) {
    // The normal sign-in, with the link kept.
    _routine(e)
        ? host.onRoutine('the dashboard\'s login token was refused', e)
        : host.onError(e, s);
    return false;
  }
  host.goTo(destination ?? '/');
  return true;
}

/// `/handoff/dashboard`: answers the dashboard's request ([state]) with a
/// token when signed in, else none, only ever to `DASHBOARD_URL`. False when
/// there is nothing to answer.
Future<bool> answerDashboard(SharedSignInHost host, String? state) async {
  final dashboard = host.dashboard;
  if (state == null || dashboard == null) return false;
  String? token;
  if (host.liveAccounts().isNotEmpty) {
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
