import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/widgets/pro_features_card.dart';
import 'package:fluffychat/features/subscription/widgets/star_backdrop.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';

class FreeTrialStepView extends StatelessWidget {
  final VoidCallback forward;
  const FreeTrialStepView({super.key, required this.forward});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = Color.alphaBlend(
      Theme.of(context).colorScheme.surface.withAlpha(70),
      AppConfig.gold,
    );

    final isColumnMode = FluffyThemes.isColumnMode(context);

    final mediumTextStyle = isColumnMode
        ? theme.textTheme.bodyMedium
        : theme.textTheme.bodySmall;

    final largeTextStyle = isColumnMode
        ? theme.textTheme.displayMedium
        : theme.textTheme.headlineMedium;

    // See the note on the same wrapper in onboarding_page.dart —
    // `explicitChildNodes` stops this page container from absorbing a
    // descendant's semantics config.
    return Semantics(
      explicitChildNodes: true,
      label: L10n.of(context).pageLabel(L10n.of(context).freeTrial),
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Semantics(
            container: true,
            child: Text(
              L10n.of(context).welcomeToPangeaChat,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          automaticallyImplyLeading: false,
        ),
        body: StarBackdrop(
          reserveStarBand: false,
          child: Center(
            child: Container(
              // Matches the wizard shell in onboarding_page.dart.
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 600.0),
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                bottom: 20.0,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Semantics(
                        label:
                            '${L10n.of(context).thanksForSigningUp} ${L10n.of(context).sevenDaysFree}',
                        container: true,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              Column(
                                spacing: 16.0,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(2.0),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                    ),
                                    child: ExcludeSemantics(
                                      child: Column(
                                        spacing: 8.0,
                                        children: [
                                          Text(
                                            L10n.of(context).thanksForSigningUp,
                                            style: mediumTextStyle,
                                            textAlign: TextAlign.center,
                                          ),
                                          Text(
                                            L10n.of(context).sevenDaysFree,
                                            style: largeTextStyle?.copyWith(
                                              color: gold,
                                              fontWeight: FontWeight.w900,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ProFeaturesCard(
                                    titlePadding: const EdgeInsets.all(4.0),
                                    padding: const EdgeInsets.all(12.0),
                                    borderRadius: 12.0,
                                    frameColor: gold,
                                    borderWidth: 2,
                                  ),
                                  Container(
                                    padding: EdgeInsets.all(2.0),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                    ),
                                    child: Semantics(
                                      container: true,
                                      child: Text(
                                        L10n.of(context).manageTrialInSettings,
                                        textAlign: TextAlign.center,
                                        style: mediumTextStyle,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    container: true,
                    child: OnboardingForwardButton(
                      onPressed: forward,
                      label: L10n.of(context).claimTrial,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    container: true,
                    child: Text(
                      L10n.of(context).noCreditCardRequired,
                      style: mediumTextStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
