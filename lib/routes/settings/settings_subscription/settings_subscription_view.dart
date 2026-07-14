import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/features/subscription/widgets/pro_features_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_options.dart';

class SettingsSubscriptionView extends StatelessWidget {
  final SubscriptionStatusResponse subscriptionStatus;
  final Widget closeButton;

  const SettingsSubscriptionView({
    super.key,
    required this.subscriptionStatus,
    required this.closeButton,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = DateFormat('yyyy-MM-dd');
    return Scaffold(
      appBar: AppBar(
        leading: Center(child: closeButton),
        title: Text(
          L10n.of(context).subscriptionManagement,
          style: FluffyThemes.isColumnMode(context)
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Container(
        alignment: Alignment.topCenter,
        padding: EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 600),
          child: Column(
            spacing: 16.0,
            children: [
              ProFeaturesCard(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: switch (subscriptionStatus.accessLevel) {
                  SubscriptionAccessLevel.full => () {
                    final trialEnds = subscriptionStatus.trialEndsAt;
                    final winning = subscriptionStatus.winning;
                    final endsOn = winning?.endsAt;
                    final cancelAtEnd = winning?.cancelAtPeriodEnd == true;
                    return Column(
                      children: [
                        if (trialEnds != null)
                          Text(
                            L10n.of(
                              context,
                            ).trialExpiration(formatter.format(trialEnds)),
                          ),
                        if (winning != null)
                          FrameContainer(
                            title: L10n.of(context).yourPlan,
                            frameColor: theme.colorScheme.primary,
                            backgroundColor: theme.colorScheme.surface,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: EdgeInsets.all(8.0),
                            titlePadding: EdgeInsetsGeometry.symmetric(
                              vertical: 8.0,
                              horizontal: 2.0,
                            ),
                            borderRadius: 12.0,
                            child: Column(
                              spacing: 8.0,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        winning.duration.copy(L10n.of(context)),
                                      ),
                                    ),
                                    Text(""),
                                  ],
                                ),
                                if (endsOn != null)
                                  Text(
                                    cancelAtEnd
                                        ? L10n.of(context).subscriptionEndsOn(
                                            formatter.format(endsOn),
                                          )
                                        : L10n.of(context).subscriptionRenewsOn(
                                            formatter.format(endsOn),
                                          ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  }(),
                  SubscriptionAccessLevel.none => Column(
                    spacing: 12.0,
                    children: [
                      SubscriptionOptions(),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Text(L10n.of(context).enterDiscountCode)],
                        ),
                      ),
                    ],
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
