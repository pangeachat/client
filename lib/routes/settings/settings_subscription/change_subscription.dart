import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ChangeSubscription extends StatefulWidget {
  const ChangeSubscription({super.key});

  @override
  ChangeSubscriptionState createState() => ChangeSubscriptionState();
}

class ChangeSubscriptionState extends State<ChangeSubscription> {
  SubscriptionDetails? _selectedSubscription;
  bool _loading = false;

  SubscriptionController get _subscriptionController =>
      MatrixState.pangeaController.subscriptionController;

  List<SubscriptionDetails> get _availableSubscriptions =>
      _subscriptionController.availableSubscriptions;

  String get _formattedDate => DateFormat.yMMMd().format(DateTime.now());

  bool _isSelected(SubscriptionDetails subscription) =>
      _selectedSubscription?.id == subscription.id;

  bool _isCurrentSubscription(SubscriptionDetails subscription) =>
      _subscriptionController.subscription == subscription;

  bool _isEnabled(SubscriptionDetails subscription) =>
      (!subscription.isTrial || _subscriptionController.inTrialWindow) &&
      !_isCurrentSubscription(subscription);

  void _selectSubscription(SubscriptionDetails? subscription) {
    setState(() {
      _selectedSubscription = _selectedSubscription == subscription
          ? null
          : subscription;
    });
  }

  Future<void> _submitChange(SubscriptionDetails subscription) async {
    setState(() => _loading = true);
    try {
      await _subscriptionController.submitSubscriptionChange(
        subscription,
        context,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscriptions = _availableSubscriptions;
    if (subscriptions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }

    return Column(
      spacing: 16.0,
      children: [
        Text(
          L10n.of(context).selectYourPlan,
          style: const TextStyle(fontSize: 16),
        ),
        Column(
          children: [
            ...subscriptions.map((subscription) {
              final selected = _isSelected(subscription);
              return DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 1.0,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      title: Text(subscription.displayName(context)),
                      trailing: Icon(
                        selected
                            ? Icons.keyboard_arrow_right_outlined
                            : Icons.keyboard_arrow_down_outlined,
                      ),
                      enabled: _isEnabled(subscription),
                      onTap: () => _selectSubscription(subscription),
                    ),
                    AnimatedSize(
                      duration: FluffyThemes.animationDuration,
                      child: _selectedSubscription?.id != subscription.id
                          ? const SizedBox()
                          : Column(
                              children: [
                                Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 400.0,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(16.0),
                                    ),
                                  ),
                                  margin: const EdgeInsets.all(8.0),
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Row(
                                          spacing: 4.0,
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                L10n.of(
                                                  context,
                                                ).paidSubscriptionStarts(
                                                  _formattedDate,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                "${subscription.displayPrice(context)}/${subscription.duration?.name}",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 400.0,
                                  ),
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        L10n.of(
                                          context,
                                        ).cancelInSubscriptionSettings,
                                      ),
                                      const SizedBox(height: 20.0),
                                      ElevatedButton(
                                        onPressed: () =>
                                            _submitChange(subscription),
                                        child: _loading
                                            ? const LinearProgressIndicator()
                                            : Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    subscription.isTrial
                                                        ? L10n.of(
                                                            context,
                                                          ).activateTrial
                                                        : L10n.of(context).pay,
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
        if (kIsWeb)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              spacing: 8.0,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outlined),
                Flexible(child: Text(L10n.of(context).promoCodeInfo)),
              ],
            ),
          ),
        const SizedBox(height: 20.0),
      ],
    );
  }
}
