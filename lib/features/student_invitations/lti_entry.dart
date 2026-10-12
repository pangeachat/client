import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';

/// Reads and clears the URL fragment the Canvas hand-offs ride in.
abstract class LtiFragment {
  /// The fragment without its `#`, removed from the address bar, or null.
  String? take();
}

/// The browser's own fragment. The router never sees it (path URL strategy
/// without `includeHash`), so it is read from `window.location`. Off web
/// there is none.
class BrowserLtiFragment implements LtiFragment {
  const BrowserLtiFragment();

  @override
  String? take() {
    final location = html.window.location;
    final hash = location.hash;
    if (hash.length <= 1) return null;
    html.window.history.replaceState(
      null,
      '',
      '${location.pathname}${location.search}',
    );
    return hash.substring(1);
  }
}

/// The two URLs a Canvas launch redirects to (C5.2). Both carry a
/// single-use secret in the URL FRAGMENT, which a browser never sends to a
/// server, so no web host or proxy can log it. Each redirect takes the
/// fragment out of the address bar before the page renders. A secret in the
/// query (already exposed to logs) is never used, only stripped.
abstract class LtiEntry {
  /// Where the fragment is read from; tests swap it.
  static LtiFragment fragment = const BrowserLtiFragment();

  static Map<String, String> _takeFragment() {
    final raw = fragment.take();
    if (raw == null || raw.isEmpty) return const {};
    try {
      return Uri.splitQueryString(raw);
    } on FormatException {
      return const {'': ''};
    }
  }

  /// `/lti/link#ticket=…&course=…` (learner) or `…&role=instructor`: ferry
  /// the ticket (SpaceCodeRepo.pendingLtiTicket) and render the page.
  /// `course` is the Canvas course title, display-only. A query is stripped
  /// (route returned) and never used.
  static Future<String?> linkRedirect(Uri uri) async {
    final params = _takeFragment();
    // A landing (fragment or query) is a new launch: only its own fragment
    // ticket may be ferried, so anything else drops an older held one.
    if (params.isNotEmpty || uri.query.isNotEmpty) {
      final ticket = params['ticket'];
      if (ticket != null && PRoutes.isLtiTicket(ticket)) {
        final course = params['course']?.trim();
        await SpaceCodeRepo.setPendingLtiTicket(
          PendingLtiTicket(
            ticket,
            instructor: params['role'] == 'instructor',
            courseName: course == null || course.isEmpty
                ? null
                : course.length > 200
                ? course.substring(0, 200)
                : course,
          ),
        );
      } else {
        // A launch without a usable ticket must not revive an older one.
        await SpaceCodeRepo.clearPendingLtiTicket();
      }
    }
    return uri.query.isEmpty ? null : PRoutes.ltiLink;
  }

  static String? _loginToken;

  /// `/lti/token#loginToken=…`: hold the token in memory for the one
  /// sign-in the page makes, and render the page. A reload finds nothing to
  /// replay. A query is stripped (route returned) and never used.
  static String? tokenRedirect(Uri uri) {
    final params = _takeFragment();
    if (params.isNotEmpty || uri.query.isNotEmpty) {
      final token = params['loginToken'];
      // Only this landing's token may be used: one without a usable token
      // must not revive an older held one.
      _loginToken = token != null && token.isNotEmpty && token.length <= 512
          ? token
          : null;
    }
    return uri.query.isEmpty ? null : PRoutes.ltiToken;
  }

  /// Hand a login token to the `/lti/token` page from inside the app (the
  /// link page, when the module answers a bound ticket with one).
  static void holdLoginToken(String token) => _loginToken = token;

  /// The held login token, at most once.
  static String? takeLoginToken() {
    final token = _loginToken;
    _loginToken = null;
    return token;
  }
}
