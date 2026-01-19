import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/login/sso_provider_enum.dart';
import 'package:fluffychat/pangea/login/widgets/p_sso_dialog.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PangeaSsoButton extends StatelessWidget {
  final SSOProvider provider;
  final String? title;

  const PangeaSsoButton({
    required this.provider,
    this.title,
    super.key,
  });

  Future<void> _runSSOLogin(BuildContext context) async {
    final token = await showAdaptiveDialog<String?>(
      context: context,
      builder: (context) => SSODialog(
        future: () => _getSSOToken(context),
      ),
    );

    if (token == null || token.isEmpty) {
      return;
    }

    await showFutureLoadingDialog(
      context: context,
      future: () => _ssoAction(token, context),
    );
  }

  Future<String?> _getSSOToken(BuildContext context) async {
    final bool isDefaultPlatform = (PlatformInfos.isMobile ||
        PlatformInfos.isWeb ||
        PlatformInfos.isMacOS);
    final redirectUrl = kIsWeb
        ? Uri.parse(html.window.location.href)
            .resolveUri(
              Uri(pathSegments: ['auth.html']),
            )
            .toString()
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

  Future<void> _ssoAction(
    String token,
    BuildContext context,
  ) async {
    final client = Matrix.of(context).client;
    final redirect = client.onLoginStateChanged.stream
        .where((state) => state == LoginState.loggedIn)
        .first
        .then(
      (_) {
        final route = FluffyChatApp.router.state.fullPath;
        if (route == null ||
            (!route.contains("/rooms") && !route.contains('registration'))) {
          context.go('/rooms');
        }
      },
    ).timeout(const Duration(seconds: 30));

    final loginRes = await client.login(
      LoginType.mLoginToken,
      token: token,
      initialDeviceDisplayName: PlatformInfos.clientName,
    );

    if (client.onLoginStateChanged.value == LoginState.loggedIn) {
      final route = FluffyChatApp.router.state.fullPath;
      if (route == null ||
          (!route.contains("/rooms") && !route.contains('registration'))) {
        context.go('/rooms');
      }
    } else {
      await redirect;
    }

    GoogleAnalytics.login(provider.name, loginRes.userId);
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
