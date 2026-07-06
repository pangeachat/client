// Flutter imports:

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/home/login/tos_indicator.dart';
import 'package:fluffychat/routes/home/p_sso_button.dart';
import 'package:fluffychat/routes/home/pangea_logo_svg.dart';
import 'package:fluffychat/routes/home/sso_provider_enum.dart';
import 'signup.dart';

class SignupPageView extends StatelessWidget {
  final SignupPageController controller;
  const SignupPageView(this.controller, {super.key});

  bool validator() {
    return controller.formKey.currentState?.validate() ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: L10n.of(context).pageLabel(L10n.of(context).signUp),
      child: Form(
        key: controller.formKey,
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: SizedBox(
              width: 450,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  BackButton(onPressed: Navigator.of(context).pop),
                  ExcludeSemantics(child: Text(L10n.of(context).signUp)),
                  const SizedBox(width: 40.0),
                ],
              ),
            ),
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 300,
                  maxHeight: 600,
                ),
                child: Column(
                  spacing: 16.0,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      L10n.of(context).signupOption,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (controller.prevInfo != null)
                      MergeSemantics(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                            ),
                            children: [
                              TextSpan(
                                text: L10n.of(context).welcomeBackLogin(
                                  controller.prevInfo!.method.label(
                                    L10n.of(context),
                                  ),
                                ),
                              ),
                              TextSpan(text: ' '),
                              TextSpan(
                                text: L10n.of(context).clickToLogin,
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    context.go('/home/login');
                                  },
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    PangeaSsoButton(provider: SSOProvider.apple),
                    PangeaSsoButton(provider: SSOProvider.google),
                    ElevatedButton(
                      onPressed: () => context.go('/home/signup/email'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                      child: Row(
                        spacing: 8.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ExcludeSemantics(
                            child: PangeaLogoSvg(
                              width: 20,
                              forceColor: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(L10n.of(context).withEmail),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: TOSIndicator(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
