import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/subscription/subscription_constants.dart';
import 'package:fluffychat/pangea/subscription/widgets/pro_features_card.dart';

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

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          L10n.of(context).welcomeToPangeaChat,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          SizedBox.expand(
            child: CachedNetworkImage(
              imageUrl:
                  "${AppConfig.assetsBaseURL}/${SubscriptionConstants.starBackground}",
              fit: BoxFit.cover,
              alignment: Alignment.center,
              placeholder: (context, url) => const SizedBox(),
              errorWidget: (context, url, error) => const SizedBox(),
            ),
          ),
          SafeArea(
            child: Center(
              child: Container(
                width: 350,
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              Column(
                                spacing: 16.0,
                                children: [
                                  Column(
                                    spacing: 8.0,
                                    children: [
                                      Text(
                                        L10n.of(context).thanksForSigningUp,
                                        style: theme.textTheme.bodyLarge,
                                      ),
                                      Text(
                                        L10n.of(context).sevenDaysFree,
                                        style: theme.textTheme.displayMedium
                                            ?.copyWith(
                                              color: gold,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ],
                                  ),
                                  ProFeaturesCard(
                                    padding: const EdgeInsets.all(12.0),
                                    titlePadding: const EdgeInsets.all(4.0),
                                    borderRadius: 12.0,
                                    frameColor: gold,
                                    borderWidth: 2,
                                  ),
                                  Text(
                                    L10n.of(context).manageTrialInSettings,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: forward,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(L10n.of(context).claimTrial),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.of(context).noCreditCardRequired,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
