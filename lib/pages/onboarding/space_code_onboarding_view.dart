import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/onboarding/space_code_onboarding.dart';

class SpaceCodeOnboardingView extends StatelessWidget {
  final SpaceCodeOnboardingState controller;
  const SpaceCodeOnboardingView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: Navigator.of(context).pop),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24.0,
                        horizontal: 16.0,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Logo — small, no white background
                          SvgPicture.asset(
                            "assets/pangea/pangea_logo.svg",
                            width: 72,
                            height: 72,
                            colorFilter: ColorFilter.mode(
                              theme.colorScheme.primary,
                              BlendMode.srcIn,
                            ),
                          ),
                          // Main group: question + input + join button
                          Column(
                            spacing: 16.0,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                L10n.of(context).joinSpaceOnboardingDesc,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              TextField(
                                decoration: InputDecoration(
                                  hintText: L10n.of(context).enterCodeToJoin,
                                ),
                                controller: controller.codeController,
                                onSubmitted: (_) => controller.submitCode(),
                              ),
                              ElevatedButton(
                                onPressed:
                                    controller.codeController.text.isNotEmpty
                                        ? controller.submitCode
                                        : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  foregroundColor:
                                      theme.colorScheme.onPrimaryContainer,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [Text(L10n.of(context).join)],
                                ),
                              ),
                            ],
                          ),
                          // Skip — separated at the bottom
                          TextButton(
                            onPressed: () => context.go("/rooms"),
                            child: Text(L10n.of(context).skipForNow),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
