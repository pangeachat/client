import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/subscription/widgets/subscription_option_card.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionPaywall extends StatefulWidget {
  final String title;
  final String description;
  final String? assetPath;

  final VoidCallback? onClose;

  const SubscriptionPaywall({
    super.key,
    required this.title,
    required this.description,
    this.onClose,
    this.assetPath,
  });

  @override
  SubscriptionPaywallState createState() => SubscriptionPaywallState();
}

class SubscriptionPaywallState extends State<SubscriptionPaywall> {
  SubscriptionDetails? _selectedSubscription;

  final SubscriptionController subscriptionController =
      MatrixState.pangeaController.subscriptionController;

  StreamSubscription? _settingsSubscription;

  @override
  void initState() {
    super.initState();
    _setDefaultSubscription();

    _settingsSubscription = subscriptionController.stateStream.listen((_) {
      _setDefaultSubscription();
    });
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    super.dispose();
  }

  void _setDefaultSubscription() {
    if (_selectedSubscription != null) return;
    final yearly = subscriptionController
        .availableSubscriptionInfo?.availableSubscriptions
        .firstWhereOrNull((s) => s.duration == SubscriptionDuration.year);

    if (yearly != null) {
      _selectSubscription(yearly);
    }
  }

  void _selectSubscription(SubscriptionDetails subscription) {
    setState(() => _selectedSubscription = subscription);
  }

  Future<void> submitChange() async {
    await showFutureLoadingDialog(
      context: context,
      future: () async => subscriptionController.submitSubscriptionChange(
        _selectedSubscription,
        context,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final theme = Theme.of(context);

    final controller = MatrixState.pangeaController.subscriptionController;
    final products = controller.currentSubscriptionInfo
        ?.availableSubscriptionInfo.availableSubscriptions;

    return Material(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          spacing: 12.0,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.assetPath != null)
              CachedNetworkImage(imageUrl: widget.assetPath!),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 24,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              widget.description,
              style: const TextStyle(
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (products != null)
              Row(
                spacing: isColumnMode ? 24.0 : 8.0,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: products.map((subscription) {
                  return Expanded(
                    child: SubscriptionOptionCard(
                      subscription: subscription,
                      selectedSubscription: _selectedSubscription,
                      selectSubscription: () =>
                          _selectSubscription(subscription),
                    ),
                  );
                }).toList(),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: theme.colorScheme.onSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 8.0,
                ),
              ),
              onPressed: _selectedSubscription != null ? submitChange : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(L10n.of(context).choosePlan),
                ],
              ),
            ),
            if (widget.onClose != null)
              TextButton(
                onPressed: widget.onClose,
                child: Text(L10n.of(context).remindMeLater),
              ),
          ],
        ),
      ),
    );
  }
}
