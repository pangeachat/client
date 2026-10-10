import 'package:fluffychat/pangea/common/config/environment.dart';

/// The one wait every choreo request passes through before it is sent.
///
/// choreo's HTTP gate grants a trial to a signed-in account with no paid
/// access, on ANY gated call (status, grammar_constructs, ...). A student who
/// arrived with a seat invitation (or a Canvas learner ticket) may have a
/// seat waiting, so the claim must exist before the first choreo call of the
/// session (SPEC: a student with a waiting seat never burns their trial).
/// [preflight] opens it (openPendingClaimsBeforeChoreo); every choreo
/// request awaits it. It resolves at once when nothing is waiting.
abstract class ChoreoGate {
  /// Installed once at app start (PangeaController).
  static Future<void> Function()? preflight;

  /// Whether [url] is a choreo URL (http(s) or the streaming ws(s) form).
  static bool isChoreo(Uri url) {
    final base = Uri.tryParse(Environment.choreoApi);
    if (base == null || base.host.isEmpty) return false;
    // The socket's ws/wss is the same origin as http/https (Uri knows no
    // default port for ws schemes).
    final httpUrl = switch (url.scheme) {
      'wss' => url.replace(scheme: 'https'),
      'ws' => url.replace(scheme: 'http'),
      _ => url,
    };
    return httpUrl.host == base.host &&
        httpUrl.port == base.port &&
        httpUrl.path.startsWith(base.path);
  }

  /// Await [preflight] when [url] is a choreo URL. Requests calls this for
  /// every request it sends.
  static Future<void> beforeRequest(Uri url) async {
    // Nothing installed (tools, tests): no wait and no environment read.
    if (preflight == null || !isChoreo(url)) return;
    await awaitPreflight();
  }

  /// Await [preflight] whatever the URL. BaseRepo calls this BEFORE starting
  /// its own fetch deadline, so a sign-in claim in flight is not counted
  /// against (and does not time out) the repo's fetch; the request's own
  /// [beforeRequest] then resolves at once.
  static Future<void> awaitPreflight() async {
    final run = preflight;
    if (run != null) await run();
  }
}
