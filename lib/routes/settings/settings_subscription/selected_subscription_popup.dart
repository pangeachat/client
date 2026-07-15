import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';

class SelectedSubscriptionPopup extends StatelessWidget {
  final ProductPlan plan;
  const SelectedSubscriptionPopup(this.plan, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = DateFormat('yyyy-MM-dd');

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        child: Container(
          width: 325.0,
          constraints: const BoxConstraints(maxHeight: 600.0),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            spacing: 10.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CloseButton(
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
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
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.primaryContainer),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(8),
                child: Row(
                  spacing: 10.0,
                  children: [
                    CachedNetworkImage(
                      imageUrl:
                          "${AppConfig.assetsBaseURL}/${SpaceConstants.sideBearFileName}",
                      width: 80.0,
                      height: 80.0,
                      errorWidget: (_, _, _) => SizedBox(),
                      placeholder: (_, _) =>
                          Center(child: CircularProgressIndicator.adaptive()),
                    ),
                    Flexible(
                      child: Column(
                        spacing: 12.0,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.periodPriceDisplay(L10n.of(context)),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            L10n.of(context).paidSubscriptionStarts(
                              formatter.format(DateTime.now()),
                            ),
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            L10n.of(context).cancelAnytime,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.goldByTheme(context),
                  foregroundColor: theme.brightness == Brightness.light
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.surface,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Text(L10n.of(context).subscribe)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
