import 'dart:async';
import 'dart:convert';

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

/// The `document.cookie` assignment that marks (or unmarks) this browser as
/// signed in to [app], for [dashboard]; null when the two share no site.
String? appFlagCookie({
  required bool signedIn,
  required Uri app,
  required Uri dashboard,
}) {
  final domain = sharedCookieDomain(app.host, dashboard.host);
  if (domain == null) return null;
  return [
    '$appSignedInFlag=${Uri.encodeComponent(app.origin)}',
    'Path=/',
    'SameSite=Lax',
    // An expiry in the past removes it.
    signedIn ? 'Max-Age=2592000' : 'Expires=Thu, 01 Jan 1970 00:00:00 GMT',
    if (domain.isNotEmpty) 'Domain=$domain',
    if (app.scheme == 'https') 'Secure',
  ].join('; ');
}

/// The value of cookie [name] in a `document.cookie` string, else null.
String? readCookie(String? cookies, String name) {
  for (final part in (cookies ?? '').split('; ')) {
    final eq = part.indexOf('=');
    if (eq > 0 && part.substring(0, eq) == name) {
      return Uri.decodeComponent(part.substring(eq + 1));
    }
  }
  return null;
}

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
  if (readCookie(cookies, dashboardSignedInFlag) != dashboard.origin) {
    return null;
  }
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
