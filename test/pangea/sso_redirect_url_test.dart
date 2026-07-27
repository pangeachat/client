import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/home/p_sso_button.dart';

/// The web SSO callback must always be the static `auth.html` at the WEB
/// ROOT. With path URLs the login page lives at a nested path, and resolving
/// the callback RELATIVE to the page produced `/home/auth.html` — a
/// non-file the SPA fallback boots the app on, stranding the homeserver's
/// `loginToken` on a routerless Page Not Found (the post-#7820 SSO
/// breakage).
void main() {
  group('webSsoRedirectUrl', () {
    test('resolves to root auth.html from the nested login page', () {
      expect(
        webSsoRedirectUrl('https://app.staging.pangea.chat/home/login'),
        'https://app.staging.pangea.chat/auth.html',
      );
    });

    test('resolves to root auth.html from the root', () {
      expect(
        webSsoRedirectUrl('https://app.pangea.chat/'),
        'https://app.pangea.chat/auth.html',
      );
    });

    test('drops query and fragment state from the page URL', () {
      expect(
        webSsoRedirectUrl('http://localhost:8090/home/login?devlogin=1#x'),
        'http://localhost:8090/auth.html',
      );
    });
  });
}
