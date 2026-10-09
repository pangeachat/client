import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';

/// The two URLs a Canvas launch redirects to (C5.2). Both carry a
/// single-use secret, so each redirect takes it out of the address bar
/// before anything renders (the redirect replaces the location).
abstract class LtiEntry {
  /// `/lti/link?ticket=…&course=…` (learner) or `…&role=instructor`: ferry
  /// the ticket (SpaceCodeRepo.pendingLtiTicket) and land on the bare page.
  /// `course` is the Canvas course title, display-only. Null when there is
  /// no ticket to take, so the page renders.
  static Future<String?> linkRedirect(Uri uri) async {
    final params = uri.queryParameters;
    if (params.isEmpty) return null;
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
    return PRoutes.ltiLink;
  }

  static String? _loginToken;

  /// `/lti/token?loginToken=…`: hold the token in memory for the one sign-in
  /// the page makes, and land on the bare page. A reload finds nothing to
  /// replay. Null when there is no token in the URL.
  static String? tokenRedirect(Uri uri) {
    if (uri.queryParameters.isEmpty) return null;
    final token = uri.queryParameters['loginToken'];
    // Only this landing's token may be used: one without a usable token must
    // not revive an older held one.
    _loginToken = token != null && token.isNotEmpty && token.length <= 512
        ? token
        : null;
    return PRoutes.ltiToken;
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
