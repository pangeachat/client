import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/dialog_wrapper.dart';
import 'package:fluffychat/routes/settings/settings_subscription/selected_subscription_view.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SelectedSubscriptionPopup extends StatelessWidget {
  final ProductPlan plan;
  const SelectedSubscriptionPopup(this.plan, {super.key});

  @override
  Widget build(BuildContext context) {
    return DialogWrapper(
      backgroundColor: Theme.of(context).colorScheme.surface,
      borderRadius: 16.0,
      side: BorderSide(color: AppConfig.goldByTheme(context)),
      maxWidth: 325.0,
      maxHeight: 600.0,
      child: Column(
        spacing: 10.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CloseButton(onPressed: Navigator.of(context).pop),
              Expanded(
                child: Text(
                  plan.duration.copy(L10n.of(context)),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(width: 40.0),
            ],
          ),
          SelectedSubscriptionView(
            plan,
            onSubscribe: () => Navigator.of(context).pop(
              CheckoutRequest(
                userID: Matrix.of(context).client.userID!,
                planId: plan.planId,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
