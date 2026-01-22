import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/onboarding/space_code_onboarding.dart';
import 'package:fluffychat/pangea/authentication/p_logout.dart';
import 'package:fluffychat/pangea/login/pages/pangea_login_scaffold.dart';

class SpaceCodeOnboardingView extends StatelessWidget {
  final SpaceCodeOnboardingState controller;
  const SpaceCodeOnboardingView({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return PangeaLoginScaffold(
      customAppBar: AppBar(
        leading: BackButton(
          onPressed: () => pLogoutAction(
            context,
            bypassWarning: true,
          ),
        ),
      ),
      showAppName: false,
      mainAssetUrl: controller.profile?.avatarUrl,
      children: [
        Column(
          spacing: 8.0,
          children: [
            Text(
              L10n.of(context).welcomeUser(
                controller.profile?.displayName ??
                    controller.client.userID?.localpart ??
                    "",
              ),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              L10n.of(context).joinSpaceOnboardingDesc,
              textAlign: TextAlign.center,
            ),
            TextField(
              decoration: InputDecoration(
                hintText: L10n.of(context).enterCodeToJoin,
              ),
              controller: controller.codeController,
              onSubmitted: (_) => controller.submitCode,
            ),
            ElevatedButton(
              onPressed: controller.codeController.text.isNotEmpty
                  ? controller.submitCode
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(L10n.of(context).join),
                ],
              ),
            ),
            TextButton(
              child: Text(L10n.of(context).skipForNow),
              onPressed: () => context.go("/rooms"),
            ),
          ],
        ),
      ],
    );
  }
}
