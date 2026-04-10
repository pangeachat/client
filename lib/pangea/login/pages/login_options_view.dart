import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/login/login.dart';
import 'package:fluffychat/pangea/authentication/store_login_method_repo.dart';
import 'package:fluffychat/pangea/common/widgets/pangea_logo_svg.dart';
import 'package:fluffychat/pangea/login/sso_provider_enum.dart';
import 'package:fluffychat/pangea/login/widgets/p_sso_button.dart';

class LoginOptionsView extends StatefulWidget {
  final LoginController controller;

  const LoginOptionsView(this.controller, {super.key});

  @override
  State<LoginOptionsView> createState() => LoginOptionsViewState();
}

class LoginOptionsViewState extends State<LoginOptionsView> {
  PreviousLoginInfo? _prevInfo;

  @override
  void initState() {
    super.initState();
    _setPreviousLoginMethod();
  }

  Future<void> _setPreviousLoginMethod() async {
    final loginMethod = await LoginMethodRepo.getStoredLoginMethod();
    if (!mounted) return;
    if (loginMethod != null) {
      setState(() => _prevInfo = loginMethod);
    }
  }

  double _buttonOpacity(LoginMethod method) => _prevInfo == null
      ? 1.0
      : _prevInfo!.method == method
      ? 1.0
      : 0.6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BackButton(onPressed: Navigator.of(context).pop),
              Text(L10n.of(context).login),
              const SizedBox(width: 40.0),
            ],
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300, maxHeight: 600),
            child: Column(
              spacing: 16.0,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  L10n.of(context).loginToAccount,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_prevInfo != null)
                  Text(
                    L10n.of(context).welcomeBackLogin(
                      _prevInfo!.method.label(L10n.of(context)),
                    ),
                    textAlign: TextAlign.center,
                  ),
                Opacity(
                  opacity: _buttonOpacity(LoginMethod.apple),
                  child: PangeaSsoButton(
                    provider: SSOProvider.apple,
                    title: "Apple",
                  ),
                ),
                Opacity(
                  opacity: _buttonOpacity(LoginMethod.google),
                  child: PangeaSsoButton(
                    provider: SSOProvider.google,
                    title: "Google",
                  ),
                ),
                Opacity(
                  opacity: _buttonOpacity(LoginMethod.email),
                  child: ElevatedButton(
                    onPressed: () => context.go('/home/login/email'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                    ),
                    child: Row(
                      spacing: 8.0,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PangeaLogoSvg(
                          width: 20,
                          forceColor: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                        Text(L10n.of(context).email),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: RichText(
                    textAlign: TextAlign.justify,
                    text: TextSpan(
                      text: L10n.of(context).byUsingPangeaChat,
                      children: [
                        TextSpan(
                          text: L10n.of(context).termsAndConditions,
                          style: TextStyle(
                            decoration: TextDecoration.underline,
                            color: theme.colorScheme.primary,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              launchUrlString(AppConfig.termsOfServiceUrl);
                            },
                        ),
                        TextSpan(
                          text: L10n.of(
                            context,
                          ).andCertifyIAmAtLeast13YearsOfAge,
                        ),
                      ],
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
