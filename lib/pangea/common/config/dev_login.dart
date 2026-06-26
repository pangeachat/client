import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Intentionally-invoked dev login: signs the local build straight into the
/// shared Matrix test account, bypassing the canvas-rendered login form.
///
/// This is tooling for automated QA and local manual testing. The Flutter web
/// canvas can't be driven by a password manager and is awkward for browser
/// agents to type into, so reaching a logged-in state has been the slowest part
/// of every QA loop.
///
/// It is **opt-in per page load** via the `?devlogin=1` query parameter — a
/// normal load (`/`) shows the real login flow untouched, so the login UI stays
/// testable in debug. Append the param (`/?devlogin=1`, or inside a hash route
/// `/#/world?devlogin=1`) to bypass it.
///
/// Triple-gated so it can NEVER touch production:
///   1. debug builds only — staging and production ship release builds, where
///      [kDebugMode] is false;
///   2. opt-in per load via `?devlogin=1` (does nothing without it);
///   3. only authenticates against a localhost or staging host — the host
///      `login()` actually targets (from `SYNAPSE_URL`), never production.
///
/// Credentials come from `TEST_MATRIX_USERNAME` / `TEST_MATRIX_PASSWORD` in
/// `.env`. It uses the SDK's own password login, so the session it creates is
/// always valid — unlike a saved Playwright `storageState`, which goes stale.
/// See matrix-auth.instructions.md.
Future<void> maybeDevLogin(MatrixState matrix) async {
  final username = Environment.testUsername;
  final password = Environment.testPassword;
  // Gate on the host login() actually authenticates against — the same value
  // getLoginClient() assigns to client.homeserver (AppConfig.defaultHomeserverUri,
  // from SYNAPSE_URL) — NOT Environment.homeServer, which is a separate env var
  // that can disagree and would let a prod SYNAPSE_URL slip past the guard.
  final loginHost = devLoginHost();

  if (!shouldDevLogin(
    isDebug: kDebugMode,
    requested: devLoginRequested(),
    alreadyLoggedIn: matrix.widget.clients.any((c) => c.isLogged()),
    username: username,
    password: password,
    loginHost: loginHost,
  )) {
    return;
  }

  try {
    final client = await matrix.getLoginClient();
    if (client.isLogged()) return;
    Logs().i(
      '[dev-login] ?devlogin=1 → signing in as "$username" on $loginHost',
    );
    await client.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: username!),
      password: password!,
      initialDeviceDisplayName: 'dev-login',
    );
    // getLoginClient()'s onLoginStateChanged handler routes to the world (or
    // registration) once the session is up — no navigation needed here.
  } catch (e, s) {
    Logs().e('[dev-login] sign-in failed', e, s);
  }
}

/// Whether the current URL opted into the dev login via `?devlogin=1`.
///
/// Checks both the top-level query string (`/?devlogin=1`) and the fragment, so
/// it works with the web build's hash routing (`/#/world?devlogin=1`).
@visibleForTesting
bool devLoginRequested([Uri? url]) {
  final uri = url ?? Uri.base;
  if (uri.queryParameters['devlogin'] == '1') return true;
  if (uri.fragment.isNotEmpty) {
    final fragment = Uri.tryParse(uri.fragment);
    if (fragment?.queryParameters['devlogin'] == '1') return true;
  }
  return false;
}

/// The host [Client.login] actually authenticates against — the host of
/// [AppConfig.defaultHomeserverUri] (derived from `SYNAPSE_URL`), the same value
/// [MatrixState.getLoginClient] assigns to the client. The production guard must
/// check THIS, not the independent `HOME_SERVER` env var, or a prod `SYNAPSE_URL`
/// paired with a non-prod `HOME_SERVER` would slip through.
String devLoginHost() => AppConfig.defaultHomeserverUri.host.toLowerCase();

/// Pure gate for [maybeDevLogin], split out so the safety conditions (never in
/// release, never outside localhost/staging, opt-in only, creds required) are
/// unit-testable without a live [MatrixState] or a network login.
@visibleForTesting
bool shouldDevLogin({
  required bool isDebug,
  required bool requested,
  required bool alreadyLoggedIn,
  required String? username,
  required String? password,
  required String loginHost,
}) {
  if (!isDebug) return false; // release builds (staging/prod) — never.
  if (!requested) return false; // no ?devlogin=1 — leave the normal flow alone.
  if (alreadyLoggedIn) return false; // don't disturb an existing session.
  if (username == null || username.isEmpty) return false;
  if (password == null || password.isEmpty) return false;
  // Allowlist the host the credentials are actually sent to: localhost or a
  // staging host only. Everything else — production, an IP, an unknown alias,
  // an empty/unparseable host — is refused. Fail closed, not open: a denylist
  // of prod spellings would miss ports, trailing dots, aliases, raw IPs.
  final host = loginHost.trim().toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == 'staging.pangea.chat' ||
      host.endsWith('.staging.pangea.chat');
}
