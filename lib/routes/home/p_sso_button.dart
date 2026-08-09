import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/home/login_loading_dialog.dart';
import 'package:fluffychat/routes/home/p_sso_dialog.dart';
import 'package:fluffychat/routes/home/sso_provider_enum.dart';
import 'package:fluffychat/routes/home/store_login_method_repo.dart';
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

class PangeaSsoButton extends StatelessWidget {
  final SSOProvider provider;
  final String? title;

  const PangeaSsoButton({required this.provider, this.title, super.key});

  Future<void> _runSSOLogin(BuildContext context) async {
    final token = await showAdaptiveDialog<String?>(
      context: context,
      builder: (context) => SSODialog(future: () => _getSSOToken(context)),
    );

    if (token == null || token.isEmpty) {
      return;
    }

    final client = Matrix.of(context).client;
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
          Text(title ?? provider.description(context)),
        ],
      ),
      onPressed: () => _runSSOLogin(context),
    );
  }
}
