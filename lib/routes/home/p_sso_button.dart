import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/network_filter/filtered_network_controller.dart';
import 'package:fluffychat/features/network_filter/network_verdict.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/home/login_loading_dialog.dart';
import 'package:fluffychat/routes/home/p_sso_dialog.dart';
import 'package:fluffychat/routes/home/sso_provider_enum.dart';
import 'package:fluffychat/routes/home/store_login_method_repo.dart';
import 'package:fluffychat/routes/home/web_sso_helpers.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The web SSO callback URL — the static `auth.html` shipped at the WEB
/// ROOT, resolved from the page's origin. Never resolve it relative to the
/// current page URL: with path URLs the login page lives at `/home/login`,
/// so a relative resolve produced `/home/auth.html` — no such file, the SPA
/// fallback boots the app there, and the homeserver's `loginToken` dies on
/// a routerless page (the post-path-strategy SSO breakage). Pure —
/// unit-tested (sso_redirect_url_test.dart).
String webSsoRedirectUrl(String href) =>
    Uri.parse(href).resolve('/auth.html').toString();

class PangeaSsoButton extends StatefulWidget {
  final SSOProvider provider;
  final String? title;

  const PangeaSsoButton({required this.provider, this.title, super.key});

  @override
  State<PangeaSsoButton> createState() => _PangeaSsoButtonState();

  /// Finish a same-tab web sign-in: the callback page stored the
  /// homeserver's callback URL and brought the user back to the page the
  /// sign-in started from, where this button is. Runs once per page load;
  /// a no-op when nothing is pending or off web.
  static bool _pendingChecked = false;
  static Future<void> completePendingWebLogin(BuildContext context) async {
    if (!kIsWeb || _pendingChecked) return;
    _pendingChecked = true;
    final storage = html.window.localStorage;
    final pending = pendingSameTabLogin(
      storedHref: storage[pendingSsoStorageKey],
      storedProvider: storage[pendingSsoProviderKey],
    );
    // Only the same-tab flow sets the provider marker. Without it, a stored
    // callback belongs to the desktop popup flow, whose tab is polling for
    // it: leave it alone (v5.0.7+2 consumed it here and stranded that tab).
    if (pending == null) return;
    storage.remove(pendingSsoStorageKey);
    storage.remove(pendingSsoProviderKey);
    if (!context.mounted) return;
    await _PangeaSsoButtonState._finishLogin(
      context,
      pending.token,
      pending.provider,
    );
  }
}

class _PangeaSsoButtonState extends State<PangeaSsoButton> {
  SSOProvider get provider => widget.provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PangeaSsoButton.completePendingWebLogin(context);
    });
  }

  /// A network filter (school or office Wi-Fi) that blocks the provider's
  /// sign-in host fails the sign-in in a way the app cannot repair. Check
  /// the host first and say so, offering email instead; a slow answer lets
  /// the sign-in proceed, so nobody is stopped by a slow network. See
  /// filtered-network.instructions.md.
  Future<bool> _providerReachable() async {
    if (!kIsWeb) return true;
    final verdict = await FilteredNetworkController.instance.check(
      provider.networkHostCategory,
    );
    // Only a filter earns the dialog: offline, the sign-in fails on its own.
    return verdict != NetworkVerdict.filtered;
  }

  Future<void> _runSSOLogin(BuildContext context) async {
    if (kIsWeb && !await _providerReachable()) {
      if (!context.mounted) return;
      final proceed = await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(L10n.of(context).ssoNetworkBlockedTitle),
          content: Text(
            L10n.of(
              context,
            ).ssoNetworkBlockedDesc(provider.description(context)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(L10n.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(L10n.of(context).ssoTryAnyway),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
    }

    if (kIsWeb && browserNeedsSameTabSso(html.window.navigator.userAgent)) {
      // Phones and in-app browsers refuse the popup; navigate this tab to
      // the provider and finish on the way back (completePendingWebLogin).
      final client = await Matrix.of(context).getLoginClient();
      final href = html.window.location.href;
      final url = client.homeserver!.replace(
        path: '/_matrix/client/v3/login/sso/redirect/${provider.id}',
        queryParameters: {
          'redirectUrl': sameTabSsoRedirectUrl(webSsoRedirectUrl(href), href),
        },
      );
      html.window.localStorage[pendingSsoProviderKey] = provider.name;
      html.window.location.assign(url.toString());
      return;
    }

    final token = await showAdaptiveDialog<String?>(
      context: context,
      builder: (context) => SSODialog(future: () => _getSSOToken(context)),
    );

    if (token == null || token.isEmpty) {
      return;
    }
    if (!context.mounted) return;
    await _finishLogin(context, token, provider);
  }

  static Future<void> _finishLogin(
    BuildContext context,
    String token,
    SSOProvider provider,
  ) async {
    // The login must run on the client [getLoginClient] resolved when
    // [_getSSOToken] built the redirect URL (memoized, so this returns the
    // same instance) — that is the client carrying the login-success listener
    // that navigates and closes the loading dialog. After a logout, the
    // active-client getter instead resolves to the logged-out account, whose
    // listeners are gone or mid-teardown: the token login then succeeds on a
    // client nothing is watching, and the dialog hangs on "Finalizing..."
    // until a refresh (#8640).
    final client = await Matrix.of(context).getLoginClient();
    await LoginMethodRepo.clearStoredLoginMethod();

    GoogleAnalytics.prepareLogin(provider.name);
    await showAdaptiveDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => LoginLoadingDialog(
        client: client,
        loginType: LoginType.mLoginToken,
        token: token,
        initialDeviceDisplayName: PlatformInfos.clientName,
      ),
    );

    if (!client.isLogged() || client.userID == null) {
      GoogleAnalytics.cancelPendingLogin();
      return;
    }

    await LoginMethodRepo.storeLoginMethod(
      userID: client.userID!,
      method: provider.loginMethod,
    );
  }

  Future<String?> _getSSOToken(BuildContext context) async {
    final bool isDefaultPlatform =
        (PlatformInfos.isMobile ||
        PlatformInfos.isWeb ||
        PlatformInfos.isMacOS);
    final redirectUrl = kIsWeb
        ? webSsoRedirectUrl(html.window.location.href)
        : isDefaultPlatform
        ? '${AppConfig.appOpenUrlScheme.toLowerCase()}://login'
        : 'http://localhost:3001//login';
    final client = await Matrix.of(context).getLoginClient();
    final url = client.homeserver!.replace(
      path: '/_matrix/client/v3/login/sso/redirect/${provider.id}',
      queryParameters: {'redirectUrl': redirectUrl},
    );

    final urlScheme = isDefaultPlatform
        ? Uri.parse(redirectUrl).scheme
        : "http://localhost:3001";
    String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: urlScheme,
      );
    } catch (err) {
      if (err is PlatformException && err.code == 'CANCELED') {
        debugPrint("user cancelled SSO login");
        return null;
      }
      rethrow;
    }
    final token = Uri.parse(result).queryParameters['loginToken'];
    if (token?.isEmpty ?? false) return null;
    return token;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
      ),
      child: Row(
        spacing: 8.0,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            provider.asset,
            height: 20,
            width: 20,
            colorFilter: ColorFilter.mode(
              theme.colorScheme.onPrimaryContainer,
              BlendMode.srcIn,
            ),
          ),
          Text(widget.title ?? provider.description(context)),
        ],
      ),
      onPressed: () => _runSSOLogin(context),
    );
  }
}
