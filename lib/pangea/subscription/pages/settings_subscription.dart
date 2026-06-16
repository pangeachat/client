import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/subscription/models/subscription_details.dart';
import 'package:fluffychat/pangea/subscription/models/subscription_state.dart';
import 'package:fluffychat/pangea/subscription/pages/settings_subscription_view.dart';
import 'package:fluffychat/pangea/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/pangea/subscription/widgets/subscription_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionManagement extends StatefulWidget {
  const SubscriptionManagement({super.key});

  @override
  SubscriptionManagementController createState() =>
      SubscriptionManagementController();
}

class SubscriptionManagementController extends State<SubscriptionManagement>
    with WidgetsBindingObserver {
  final SubscriptionController subscriptionController =
      MatrixState.pangeaController.subscriptionController;

  SubscriptionDetails? selectedSubscription;
  bool loading = false;
  String? userEmail;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _refreshSubscription();

    subscriptionController
        .initialize(Matrix.of(context).client.userID!)
        .then((_) => setState(() {}));

    subscriptionController.addListener(_onSubscriptionUpdate);
    subscriptionController.subscriptionNotifier.addListener(_onSubscribe);
    subscriptionController.updateCurrentSubscription();

    MatrixState.pangeaController.userController.userEmail.then((email) {
      if (mounted) {
        setState(() => userEmail = email);
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscriptionController.subscriptionNotifier.removeListener(_onSubscribe);
    subscriptionController.removeListener(_onSubscriptionUpdate);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSubscription();
    }
    super.didChangeAppLifecycleState(state);
  }

  List<SubscriptionDetails> get availableSubscriptions =>
      subscriptionController.availableSubscriptions;

  bool get hasFreeTrial =>
      subscriptionController.hasPromotionalSubscription &&
      subscriptionController.subscription?.appId == "trial";

  bool get currentSubscriptionAvailable =>
      subscriptionController.subscription != null;

  bool get currentSubscriptionIsTrial =>
      currentSubscriptionAvailable &&
      (subscriptionController.subscription?.isTrial ?? false);

  bool get isLifetimeSubscription =>
      subscriptionController.hasPromotionalSubscription &&
      expirationDate != null &&
      expirationDate!.isAfter(DateTime(2100));

  String? get purchasePlatformDisplayName {
    final appId = subscriptionController.subscription?.appId;
    if (appId == null) return null;
    return subscriptionController.appIds?.appDisplayName(appId);
  }

  bool get currentSubscriptionIsPromotional =>
      subscriptionController.hasPromotionalSubscription;

  String get currentSubscriptionTitle =>
      subscriptionController.subscription?.displayName(context) ?? "";

  String get currentSubscriptionPrice =>
      subscriptionController.subscription?.displayPrice(context) ?? "";

  bool get showManagementOptions {
    if (!currentSubscriptionAvailable) {
      return false;
    }

    final subscription = subscriptionController.subscription;
    final appIds = subscriptionController.appIds;
    final purchasedOnWeb =
        (subscription != null && appIds != null) &&
        (subscription.appId == appIds.stripeId);

    if (purchasedOnWeb) {
      return true;
    }

    final currentPlatformMatchesPurchasePlatform =
        (subscription != null && appIds != null) &&
        (subscription.appId == appIds.currentAppId);

    return currentPlatformMatchesPurchasePlatform;
  }

  DateTime? get expirationDate => switch (subscriptionController.state) {
    SubscriptionActive(expirationDate: final exp) => exp,
    _ => null,
  };

  DateTime? get unsubscribeDetectedAt => switch (subscriptionController.state) {
    SubscriptionActive(unsubscribeDetectedAt: final detected) => detected,
    _ => null,
  };

  DateTime? get subscriptionEndDate =>
      unsubscribeDetectedAt == null ? null : expirationDate;

  void _onSubscriptionUpdate() => setState(() {});
  void _onSubscribe() => showSubscribedSnackbar(context);

  Future<void> _refreshSubscription() async {
    if (!kIsWeb) return;

    // if the user previously clicked cancel, check if the subscription end date has changed
    final prevEndDate = SubscriptionManagementRepo.getSubscriptionEndDate();
    final clickedCancel =
        SubscriptionManagementRepo.getClickedCancelSubscription();
    if (clickedCancel == null) return;

    await subscriptionController.reinitialize(
      Matrix.of(context).client.userID!,
    );

    final newEndDate = subscriptionEndDate;

    if (prevEndDate != newEndDate) {
      SubscriptionManagementRepo.removeClickedCancelSubscription();
      SubscriptionManagementRepo.setSubscriptionEndDate(newEndDate);
      if (mounted) setState(() {});
      return;
    }

    // if more than 10 minutes have passed since the user clicked cancel, remove the click flag
    if (DateTime.now().difference(clickedCancel).inMinutes >= 10) {
      SubscriptionManagementRepo.removeClickedCancelSubscription();
      if (mounted) setState(() {});
    }
  }

  Future<void> submitChange(SubscriptionDetails subscription) async {
    setState(() => loading = true);
    try {
      await subscriptionController.submitSubscriptionChange(
        subscription,
        context,
      );
    } catch (e, s) {
      if (e is PlatformException &&
          e.message?.contains("Purchase was cancelled") == true) {
        return;
      }

      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"subscription_id": subscription.id},
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> onClickCancelSubscription() async {
    final uri = await launchMangementUrl(ManagementOption.cancel);
    if (uri != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          duration: const Duration(seconds: 30),
          content: Row(
            children: [
              Expanded(child: Text(L10n.of(context).managementSnackbarMessage)),
              TextButton(
                child: Text(
                  L10n.of(context).tryAgain,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                ),
                onPressed: () {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            ],
          ),
        ),
      );
    }
    await SubscriptionManagementRepo.setClickedCancelSubscription();
    await SubscriptionManagementRepo.setSubscriptionEndDate(
      subscriptionEndDate,
    );
    if (mounted) setState(() {});
  }

  Future<Uri?> launchMangementUrl(ManagementOption option) async {
    String managementUrl = Environment.stripeManagementUrl;
    if (userEmail != null) {
      managementUrl += "?prefilled_email=${Uri.encodeComponent(userEmail!)}";
    }
    final String? purchaseAppId = subscriptionController.subscription?.appId;
    if (purchaseAppId == null) return null;

    final appIds = subscriptionController.appIds;

    if (purchaseAppId == appIds?.stripeId) {
      final uri = Uri.parse(managementUrl);
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return uri;
    }
    if (purchaseAppId == appIds?.appleId) {
      final uri = Uri.parse(AppConfig.appleMangementUrl);
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return uri;
    }
    switch (option) {
      case ManagementOption.history:
        final uri = Uri.parse(AppConfig.googlePlayHistoryUrl);
        launchUrl(uri, mode: LaunchMode.externalApplication);
        return uri;
      case ManagementOption.paymentMethod:
        final uri = Uri.parse(AppConfig.googlePlayPaymentMethodUrl);
        launchUrl(uri, mode: LaunchMode.externalApplication);
        return uri;
      default:
        final uri = Uri.parse(AppConfig.googlePlayMangementUrl);
        launchUrl(uri, mode: LaunchMode.externalApplication);
        return uri;
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
      subscriptionController.subscription == subscription;

  @override
  Widget build(BuildContext context) => SettingsSubscriptionView(this);
}

enum ManagementOption { cancel, paymentMethod, history }
