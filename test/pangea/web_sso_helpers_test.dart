import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/home/sso_provider_enum.dart';
import 'package:fluffychat/routes/home/web_sso_helpers.dart';

void main() {
  group('browserNeedsSameTabSso', () {
    test('phones and in-app browsers do', () {
      const gmailOnIphone =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
      const chromeOnAndroid =
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Mobile Safari/537.36';
      const safariOnIpad =
          'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Safari/604.1';
      for (final ua in [gmailOnIphone, chromeOnAndroid, safariOnIpad]) {
        expect(browserNeedsSameTabSso(ua), isTrue, reason: ua);
      }
    });

    test('desktop browsers keep the popup flow', () {
      const chromeOnMac =
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36';
      const firefoxOnWindows =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0';
      for (final ua in [chromeOnMac, firefoxOnWindows, '']) {
        expect(browserNeedsSameTabSso(ua), isFalse, reason: ua);
      }
    });
  });

  group('loginTokenFromCallbackHref', () {
    test('reads the token the homeserver appended', () {
      expect(
        loginTokenFromCallbackHref(
          'https://app.pangea.chat/auth.html?return=https%3A%2F%2Fapp.pangea.chat%2Fhome%2Fsignup&loginToken=syl_abc',
        ),
        'syl_abc',
      );
    });

    test('nothing stored, no token, or an empty token is null', () {
      expect(loginTokenFromCallbackHref(null), isNull);
      expect(loginTokenFromCallbackHref(''), isNull);
      expect(
        loginTokenFromCallbackHref('https://app.pangea.chat/auth.html'),
        isNull,
      );
      expect(
        loginTokenFromCallbackHref(
          'https://app.pangea.chat/auth.html?loginToken=',
        ),
        isNull,
      );
    });
  });

  group('sameTabSsoRedirectUrl', () {
    test('carries the page to return to on the root callback', () {
      expect(
        sameTabSsoRedirectUrl(
          'https://app.pangea.chat/auth.html',
          'https://app.pangea.chat/home/signup',
        ),
        'https://app.pangea.chat/auth.html?return=https%3A%2F%2Fapp.pangea.chat%2Fhome%2Fsignup',
      );
    });
  });

  group('provider helpers', () {
    test('a stored provider name round-trips', () {
      expect(ssoProviderFromName('google'), SSOProvider.google);
      expect(ssoProviderFromName('apple'), SSOProvider.apple);
      expect(ssoProviderFromName('x'), isNull);
      expect(ssoProviderFromName(null), isNull);
    });
  });

  group('pendingSameTabLogin', () {
    const href =
        'https://app.pangea.chat/auth.html?return=x&loginToken=syl_abc';

    test('needs both the callback and the same-tab provider marker', () {
      final p = pendingSameTabLogin(storedHref: href, storedProvider: 'google');
      expect(p?.token, 'syl_abc');
      expect(p?.provider, SSOProvider.google);
    });

    test(
      'a callback without the marker is the popup flow and is left alone',
      () {
        // The desktop popup stores the same value for its own tab to poll;
        // consuming it here stranded that tab on the login page (v5.0.7+2).
        expect(
          pendingSameTabLogin(storedHref: href, storedProvider: null),
          isNull,
        );
      },
    );

    test('a marker without a callback is nothing to finish', () {
      expect(
        pendingSameTabLogin(storedHref: null, storedProvider: 'google'),
        isNull,
      );
    });
  });
}
