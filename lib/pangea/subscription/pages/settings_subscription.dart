import 'dart:async';

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/subscription/pages/settings_subscription_view.dart';
import 'package:fluffychat/pangea/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/pangea/subscription/utils/subscription_app_id.dart';
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
  bool loading = false;

  @override
  void initState() {
    if (!subscriptionController.initCompleter.isCompleted) {
      subscriptionController.initialize().then((_) => setState(() {}));
    }

    subscriptionController.addListener(_onSubscriptionUpdate);
    subscriptionController.subscriptionNotifier.addListener(_onSubscribe);
    subscriptionController.updateCustomerInfo();
    super.initState();
  }

  @override
  void dispose() {
    subscriptionController.subscriptionNotifier.removeListener(_onSubscribe);
    subscriptionController.removeListener(_onSubscriptionUpdate);
    super.dispose();
  }

  bool get subscriptionsAvailable =>
      subscriptionController
          .availableSubscriptionInfo?.availableSubscriptions.isNotEmpty ??
      false;

  bool get currentSubscriptionAvailable =>
      subscriptionController.isSubscribed != null &&
      subscriptionController.isSubscribed! &&
      subscriptionController.currentSubscriptionInfo?.currentSubscription !=
          null;

  bool get currentSubscriptionIsTrial =>
      currentSubscriptionAvailable &&
      (subscriptionController
              .currentSubscriptionInfo?.currentSubscription?.isTrial ??
          false);

  String? get purchasePlatformDisplayName => subscriptionController
      .currentSubscriptionInfo?.purchasePlatformDisplayName;

  bool get currentSubscriptionIsPromotional =>
      subscriptionController
          .currentSubscriptionInfo?.currentSubscriptionIsPromotional ??
      false;

  String get currentSubscriptionTitle =>
      subscriptionController.currentSubscriptionInfo?.currentSubscription
          ?.displayName(context) ??
      "";

  String get currentSubscriptionPrice =>
      subscriptionController.currentSubscriptionInfo?.currentSubscription
          ?.displayPrice(context) ??
      "";

  bool get showManagementOptions {
    if (!currentSubscriptionAvailable) {
      return false;
    }
    if (subscriptionController.currentSubscriptionInfo!.purchasedOnWeb) {
      return true;
    }
    return subscriptionController
        .currentSubscriptionInfo!.currentPlatformMatchesPurchasePlatform;
  }

  DateTime? get expirationDate =>
      subscriptionController.currentSubscriptionInfo?.expirationDate;

  DateTime? get subscriptionEndDate =>
      subscriptionController.currentSubscriptionInfo?.subscriptionEndDate;

  void _onSubscriptionUpdate() => setState(() {});
  void _onSubscribe() => showSubscribedSnackbar(context);

  Future<void> submitChange(
    SubscriptionDetails subscription, {
    bool isPromo = false,
  }) async {
    setState(() => loading = true);
    try {
      await subscriptionController.submitSubscriptionChange(
        subscription,
        context,
        isPromo: isPromo,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "subscription_id": subscription.id,
          "is_promo": isPromo,
        },
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> onClickCancelSubscription() async {
    await SubscriptionManagementRepo.setClickedCancelSubscription();
    await launchMangementUrl(ManagementOption.cancel);
    if (mounted) setState(() {});
  }

  Future<void> launchMangementUrl(ManagementOption option) async {
    String managementUrl = Environment.stripeManagementUrl;
    final String? email =
        await MatrixState.pangeaController.userController.userEmail;
    if (email != null) {
      managementUrl += "?prefilled_email=${Uri.encodeComponent(email)}";
    }
    final String? purchaseAppId = subscriptionController
        .currentSubscriptionInfo?.currentSubscription?.appId;
    if (purchaseAppId == null) return;

    final SubscriptionAppIds? appIds =
        subscriptionController.availableSubscriptionInfo!.appIds;

    if (purchaseAppId == appIds?.stripeId) {
      launchUrlString(managementUrl);
      return;
    }
    if (purchaseAppId == appIds?.appleId) {
      launchUrlString(
        AppConfig.appleMangementUrl,
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    switch (option) {
      case ManagementOption.history:
        launchUrlString(
          AppConfig.googlePlayHistoryUrl,
          mode: LaunchMode.externalApplication,
        );
        break;
      case ManagementOption.paymentMethod:
        launchUrlString(
          AppConfig.googlePlayPaymentMethodUrl,
          mode: LaunchMode.externalApplication,
        );
        break;
      default:
        launchUrlString(
          AppConfig.googlePlayMangementUrl,
          mode: LaunchMode.externalApplication,
        );
        break;
    }
  }

  void selectSubscription(SubscriptionDetails? subscription) {
    if (selectedSubscription == subscription) {
      setState(() => selectedSubscription = null);
      return;
    }
    setState(() => selectedSubscription = subscription);
  }

  bool isCurrentSubscription(SubscriptionDetails subscription) =>
      subscriptionController.currentSubscriptionInfo?.currentSubscription ==
      subscription;

  @override
  Widget build(BuildContext context) => SettingsSubscriptionView(this);
}

enum ManagementOption {
  cancel,
  paymentMethod,
  history,
}
