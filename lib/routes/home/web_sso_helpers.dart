import 'package:fluffychat/routes/home/sso_provider_enum.dart';

/// Pure helpers for the web SSO flow. Unit-tested (web_sso_helpers_test.dart).

/// The localStorage key the auth package and `web/auth.html` share for a
/// callback that could not be posted to an opener window.
const String pendingSsoStorageKey = 'flutter-web-auth-2';

/// Which provider started a same-tab sign-in, so the return can finish it.
const String pendingSsoProviderKey = 'pangea-web-sso-provider';

/// Mobile browsers, and every in-app browser (a mail app's, Instagram's),
/// refuse a window opened outside a synchronous tap. The SSO flow opens its
/// window after awaits, so on these browsers the open is silently dropped
/// and the user waits on a dialog for a tab that never came. They get a
/// same-tab navigation instead.
bool browserNeedsSameTabSso(String userAgent) => RegExp(
  r'iPhone|iPad|iPod|Android',
  caseSensitive: false,
).hasMatch(userAgent);

/// The homeserver appends `loginToken` to the callback URL; the callback page
/// stores its own href when it had no opener to post to.
String? loginTokenFromCallbackHref(String? href) {
  if (href == null || href.isEmpty) return null;
  final token = Uri.tryParse(href)?.queryParameters['loginToken'];
  if (token == null || token.isEmpty) return null;
  return token;
}

/// The callback URL for a same-tab sign-in: the root `auth.html` carrying the
/// page to return to, so the callback can bring the user back to where they
/// tapped the button.
String sameTabSsoRedirectUrl(String authHtmlUrl, String returnHref) =>
    Uri.parse(
      authHtmlUrl,
    ).replace(queryParameters: {'return': returnHref}).toString();

/// A URL on the provider's sign-in host that a network filter blocking that
/// provider would refuse. A 204 endpoint for Google; a static file for Apple.
String ssoProviderProbeUrl(SSOProvider provider) {
  switch (provider) {
    case SSOProvider.google:
      return 'https://accounts.google.com/generate_204';
    case SSOProvider.apple:
      return 'https://appleid.apple.com/favicon.ico';
  }
}

SSOProvider? ssoProviderFromName(String? name) {
  for (final p in SSOProvider.values) {
    if (p.name == name) return p;
  }
  return null;
}

/// A same-tab sign-in waiting to be finished: both the stored callback and
/// the provider marker must be present. The marker is written only by the
/// same-tab flow, so a callback without it belongs to the desktop popup flow
/// (its tab polls localStorage for it) and must not be touched.
class PendingSameTabLogin {
  final String token;
  final SSOProvider provider;
  const PendingSameTabLogin(this.token, this.provider);
}

PendingSameTabLogin? pendingSameTabLogin({
  required String? storedHref,
  required String? storedProvider,
}) {
  final provider = ssoProviderFromName(storedProvider);
  if (provider == null) return null;
  final token = loginTokenFromCallbackHref(storedHref);
  if (token == null) return null;
  return PendingSameTabLogin(token, provider);
}
