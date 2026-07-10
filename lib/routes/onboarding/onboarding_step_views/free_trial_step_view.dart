import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/pro_features_card.dart';
import 'package:fluffychat/l10n/l10n.dart';

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

    return Semantics(
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
        body: Stack(
          children: [
            SizedBox.expand(
              child: ExcludeSemantics(
                child: CachedNetworkImage(
                  imageUrl:
                      "${AppConfig.assetsBaseURL}/${SubscriptionConstants.starBackground}",
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  placeholder: (context, url) => const SizedBox(),
                  errorWidget: (context, url, error) => const SizedBox(),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: Container(
                  width: 350,
                  padding: const EdgeInsets.only(bottom: 20.0),
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
                                                L10n.of(
                                                  context,
                                                ).thanksForSigningUp,
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
                                        padding: const EdgeInsets.all(12.0),
                                        titlePadding: const EdgeInsets.all(4.0),
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
                                            L10n.of(
                                              context,
                                            ).manageTrialInSettings,
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
                        child: ElevatedButton(
                          onPressed: forward,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            foregroundColor:
                                theme.colorScheme.onPrimaryContainer,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: Text(L10n.of(context).claimTrial),
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
          ],
        ),
      ),
    );
  }
}
