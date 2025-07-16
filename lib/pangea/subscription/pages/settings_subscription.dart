import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/subscription/pages/settings_subscription_view.dart';
import 'package:fluffychat/pangea/subscription/widgets/subscription_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionManagement extends StatefulWidget {
  const SubscriptionManagement({super.key});

  @override
  SubscriptionManagementController createState() =>
      SubscriptionManagementController();
}

class SubscriptionManagementController extends State<SubscriptionManagement> {
  final SubscriptionController subscriptionController =
      MatrixState.pangeaController.subscriptionController;

  SubscriptionDetails? selectedSubscription;
  StreamSubscription? _subscriptionStatusStream;
  bool loading = false;

  late StreamSubscription _settingsSubscription;

  @override
  void initState() {
    super.initState();
    if (!subscriptionController.initCompleter.isCompleted) {
      subscriptionController.initialize().then((_) => setState(() {}));
    }

    _settingsSubscription = subscriptionController.stateStream.listen((_) {
      _setDefaultSubscription();
    });

    _subscriptionStatusStream ??=
        subscriptionController.subscriptionStream.stream.listen((_) {
      showSubscribedSnackbar(context);
      context.go('/rooms');
    });

    subscriptionController.updateCustomerInfo();
    _setDefaultSubscription();
  }

  @override
  void dispose() {
    super.dispose();
    _settingsSubscription.cancel();
    _subscriptionStatusStream?.cancel();
  }

  void _setDefaultSubscription() {
    if (selectedSubscription != null) return;
    final yearly = subscriptionController
        .availableSubscriptionInfo?.availableSubscriptions
        .firstWhereOrNull((s) => s.duration == SubscriptionDuration.year);

    if (yearly != null) {
      selectSubscription(yearly);
    }
  }

  List<SubscriptionDetails> get availableSubscriptions {
    final List<SubscriptionDetails> products = List.from(
      subscriptionController
              .availableSubscriptionInfo?.availableSubscriptions ??
          [],
    );
    products.insert(0, SubscriptionDetails.free);
    return products;
  }

  // bool get subscriptionsAvailable =>
  //     subscriptionController
  //         .availableSubscriptionInfo?.availableSubscriptions.isNotEmpty ??
  //     false;

  // bool get currentSubscriptionAvailable =>
  //     subscriptionController.isSubscribed != null &&
  //     subscriptionController.isSubscribed! &&
  //     subscriptionController.currentSubscriptionInfo?.currentSubscription !=
  //         null;

  // bool get currentSubscriptionIsTrial =>
  //     currentSubscriptionAvailable &&
  //     (subscriptionController
  //             .currentSubscriptionInfo?.currentSubscription?.isTrial ??
  //         false);

  // String? get purchasePlatformDisplayName => subscriptionController
  //     .currentSubscriptionInfo?.purchasePlatformDisplayName;

  // bool get currentSubscriptionIsPromotional =>
  //     subscriptionController
  //         .currentSubscriptionInfo?.currentSubscriptionIsPromotional ??
  //     false;

  // String get currentSubscriptionTitle =>
  //     subscriptionController.currentSubscriptionInfo?.currentSubscription
  //         ?.displayName(context) ??
  //     "";

  // String get currentSubscriptionPrice =>
  //     subscriptionController.currentSubscriptionInfo?.currentSubscription
  //         ?.displayPrice(context) ??
  //     "";

  // bool get showManagementOptions {
  //   if (!currentSubscriptionAvailable) {
  //     return false;
  //   }
  //   if (subscriptionController.currentSubscriptionInfo!.purchasedOnWeb) {
  //     return true;
  //   }
  //   return subscriptionController
  //       .currentSubscriptionInfo!.currentPlatformMatchesPurchasePlatform;
  // }

  // Future<void> submitChange(
  //   SubscriptionDetails subscription, {
  //   bool isPromo = false,
  // }) async {
  //   setState(() => loading = true);
  //   await showFutureLoadingDialog(
  //     context: context,
  //     future: () async => subscriptionController.submitSubscriptionChange(
  //       subscription,
  //       context,
  //       isPromo: isPromo,
  //     ),
  //     onError: (error, s) {
  //       setState(() => loading = false);
  //       return null;
  //     },
  //   );

  //   if (mounted && loading) {
  //     setState(() => loading = false);
  //   }
  // }

  // Future<void> launchMangementUrl(ManagementOption option) async {
  //   String managementUrl = Environment.stripeManagementUrl;
  //   final String? email =
  //       await MatrixState.pangeaController.userController.userEmail;
  //   if (email != null) {
  //     managementUrl += "?prefilled_email=${Uri.encodeComponent(email)}";
  //   }
  //   final String? purchaseAppId = subscriptionController
  //       .currentSubscriptionInfo?.currentSubscription?.appId;
  //   if (purchaseAppId == null) return;

  //   final SubscriptionAppIds? appIds =
  //       subscriptionController.availableSubscriptionInfo!.appIds;

  //   if (purchaseAppId == appIds?.stripeId) {
  //     launchUrlString(managementUrl);
  //     return;
  //   }
  //   if (purchaseAppId == appIds?.appleId) {
  //     launchUrlString(
  //       AppConfig.appleMangementUrl,
  //       mode: LaunchMode.externalApplication,
  //     );
  //     return;
  //   }
  //   switch (option) {
  //     case ManagementOption.history:
  //       launchUrlString(
  //         AppConfig.googlePlayHistoryUrl,
  //         mode: LaunchMode.externalApplication,
  //       );
  //       break;
  //     case ManagementOption.paymentMethod:
  //       launchUrlString(
  //         AppConfig.googlePlayPaymentMethodUrl,
  //         mode: LaunchMode.externalApplication,
  //       );
  //       break;
  //     default:
  //       launchUrlString(
  //         AppConfig.googlePlayMangementUrl,
  //         mode: LaunchMode.externalApplication,
  //       );
  //       break;
  //   }
  // }

  void selectSubscription(SubscriptionDetails subscription) {
    setState(() => selectedSubscription = subscription);
  }

  // bool isCurrentSubscription(SubscriptionDetails subscription) =>
  //     subscriptionController.currentSubscriptionInfo?.currentSubscription ==
  //     subscription;

  @override
  Widget build(BuildContext context) => SettingsSubscriptionView(this);
}

enum ManagementOption {
  cancel,
  paymentMethod,
  history,
}
