import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/settings/settings_subscription/payment_page_mixin.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_builder.dart';
import 'package:fluffychat/routes/settings/settings_subscription/selected_subscription_view.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SelectedSubscriptionPage extends StatefulWidget {
  final Widget closeButton;
  final String planId;
  const SelectedSubscriptionPage({
    super.key,
    required this.closeButton,
    required this.planId,
  });

  @override
  SelectedSubscriptionPageState createState() =>
      SelectedSubscriptionPageState();
}

class SelectedSubscriptionPageState extends State<SelectedSubscriptionPage>
    with PaymentPageMixin {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return ProductsBuilder(
      builder: (context, productsState) {
        return Scaffold(
          appBar: AppBar(
            leading: Center(child: widget.closeButton),
            title: switch (productsState) {
              AsyncLoaded(value: final products) => () {
                final plan = products.firstWhereOrNull(
                  (p) => p.planId == widget.planId,
                );
                if (plan == null) return null;
                return Text(
                  plan.duration.copy(L10n.of(context)),
                  style: isColumnMode
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                );
              }(),
              _ => null,
            },
            centerTitle: false,
            titleSpacing: 0,
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
                child: SingleChildScrollView(
                  child: Container(
                    alignment: Alignment.topCenter,
                    child: Container(
                      padding: EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        bottom: 16.0,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      constraints: BoxConstraints(maxWidth: 400),
                      child: switch (productsState) {
                        AsyncLoading() || AsyncIdle() => Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                        AsyncError() => Center(
                          child: ErrorIndicator(
                            message: L10n.of(context).oopsSomethingWentWrong,
                          ),
                        ),
                        AsyncLoaded(value: final products) => () {
                          final plan = products.firstWhereOrNull(
                            (p) => p.planId == widget.planId,
                          );

                          if (plan == null) {
                            return Center(
                              child: ErrorIndicator(
                                message: L10n.of(
                                  context,
                                ).oopsSomethingWentWrong,
                              ),
                            );
                          }

                          return SelectedSubscriptionView(
                            plan,
                            onSubscribe: () => processCheckoutRequest(
                              CheckoutRequest(
                                userID: Matrix.of(context).client.userID!,
                                planId: widget.planId,
                              ),
                            ),
                          );
                        }(),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
