import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/widgets/subscription_snackbar.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/routes/settings/settings_subscription/settings_subscription_view.dart';
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

  String? _userEmail;

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
        setState(() => _userEmail = email);
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

  bool get loading => subscriptionController.loading;

  bool get showGatedContent =>
      subscriptionController.showSubscriptionGatedContent;

  bool get hasFreeTrial =>
      subscriptionController.hasPromotionalSubscription &&
      subscriptionController.subscription?.appId == "trial";

  bool get currentSubscriptionAvailable =>
      subscriptionController.subscription != null;

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

  DateTime? get _unsubscribeDetectedAt =>
      switch (subscriptionController.state) {
        SubscriptionActive(unsubscribeDetectedAt: final detected) => detected,
        _ => null,
      };

  DateTime? get subscriptionEndDate =>
      _unsubscribeDetectedAt == null ? null : expirationDate;

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
    if (_userEmail != null) {
      managementUrl += "?prefilled_email=${Uri.encodeComponent(_userEmail!)}";
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

  @override
  Widget build(BuildContext context) => SettingsSubscriptionView(this);
}

enum ManagementOption { cancel, paymentMethod, history }
