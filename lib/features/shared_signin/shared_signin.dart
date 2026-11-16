import 'dart:math';

/// Shared sign-in with the teacher dashboard (admin-dash#235), the pure half;
/// routing.instructions.md § Signing in from the dashboard.
///
/// The side that signs in starts the hand-off: it saves a random state in its
/// tab, asks the other side, and accepts the single-use Matrix login token that
/// comes back only with that state. A token pushed in a link (login CSRF) is
/// therefore refused. Everything travels in URL fragments, which no server
/// sees. The browser side effects live in shared_signin_web.dart.

/// sessionStorage: the fragment `web/index.html` moved out of the address bar.
const String handoffArrivalStorageKey = 'pangea-handoff-arrival';

/// sessionStorage: the state this tab sent to the dashboard.
const String handoffStateStorageKey = 'pangea-handoff-state';

/// sessionStorage: this tab asked once already, so it never asks again.
const String handoffTriedStorageKey = 'pangea-handoff-tried';

final RegExp _stateFormat = RegExp(r'^[0-9a-f]{32}$');

/// A fresh 128-bit state, as 32 hex characters.
String newHandoffState([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Whether a returned state is the one this tab saved, compared in time
/// independent of where they differ.
bool statesMatch(String? saved, String? returned) {
  if (saved == null || returned == null) return false;
  if (!_stateFormat.hasMatch(saved) || !_stateFormat.hasMatch(returned)) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < saved.length; i++) {
    diff |= saved.codeUnitAt(i) ^ returned.codeUnitAt(i);
  }
  return diff == 0;
}

/// What a page load arrived with in its fragment.
sealed class HandoffArrival {
  const HandoffArrival();
}

/// A link the teacher opened from the dashboard (`#from=dashboard`): a hint,
/// never a credential.
class HandoffHint extends HandoffArrival {
  const HandoffHint();
}

/// The dashboard asking this app for its sign-in (`/handoff/dashboard`).
class HandoffRequest extends HandoffArrival {
  final String state;
  const HandoffRequest(this.state);
}

/// The dashboard's answer to this tab's request: a login token, or none.
class HandoffAnswer extends HandoffArrival {
  final String state;
  final String? loginToken;
  const HandoffAnswer(this.state, this.loginToken);
}

/// Reads an arrival fragment, or null when it is not exactly one of the known
/// shapes: an unknown, repeated or malformed field is refused, not guessed at.
HandoffArrival? parseHandoffArrival(String? fragment) {
  if (fragment == null || fragment.isEmpty) return null;
  final fields = <String, String>{};
  for (final part in fragment.split('&')) {
    final eq = part.indexOf('=');
    if (eq <= 0) return null;
    final key = part.substring(0, eq);
    final String value;
    try {
      value = Uri.decodeQueryComponent(part.substring(eq + 1));
    } on ArgumentError {
      return null;
    }
    if (value.isEmpty || fields.containsKey(key)) return null;
    fields[key] = value;
  }
  if (fields.length == 1 && fields['from'] == 'dashboard') {
    return const HandoffHint();
  }
  final state = fields.remove('state');
  if (state == null || !_stateFormat.hasMatch(state)) return null;
  if (fields.isEmpty) return HandoffRequest(state);
  if (fields.length != 1) return null;
  final token = fields['loginToken'];
  if (token != null) return HandoffAnswer(state, token);
  return fields['handoff'] == 'none' ? HandoffAnswer(state, null) : null;
}

/// The login token of an answer whose state is the one this tab saved
/// (consumed by the caller before this check), else null.
String? acceptedHandoffToken(HandoffArrival? arrival, String? savedState) {
  if (arrival is! HandoffAnswer) return null;
  if (!statesMatch(savedState, arrival.state)) return null;
  return arrival.loginToken;
}

/// The configured dashboard (`DASHBOARD_URL`) as a base URL, or null when it
/// is unset or not a plain https origin (plain http only on this machine). The
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

/// Where the app answers the dashboard: a token when signed in, else none.
String dashboardAnswerUrl(Uri dashboard, String state, {String? loginToken}) {
  final answer = loginToken == null
      ? 'handoff=none'
      : 'loginToken=${Uri.encodeQueryComponent(loginToken)}';
  return '$dashboard/auth/handoff/#$answer&state=$state';
}

/// Where a signed-out app asks the dashboard's API for this browser's sign-in.
/// The API answers only to an app origin it already trusts.
String dashboardSignInRequestUrl(
  String teacherBffApi,
  String state,
  String appOrigin,
) => Uri.parse(
  '$teacherBffApi/api/auth/handoff/app',
).replace(queryParameters: {'state': state, 'origin': appOrigin}).toString();

/// Whether a signed-out visit asks the dashboard: on web, for a link opened
/// from the dashboard, once per tab, with the dashboard's API configured, and
/// never over a session already here.
bool shouldAskDashboard({
  required bool isWeb,
  required bool hinted,
  required bool alreadyTried,
  required bool hasSession,
  required String teacherBffApi,
}) =>
    isWeb && hinted && !alreadyTried && !hasSession && teacherBffApi.isNotEmpty;
