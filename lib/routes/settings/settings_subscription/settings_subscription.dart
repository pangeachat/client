import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/repo/billing_portal_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/utils/cancel_eligibility.dart';
import 'package:fluffychat/features/subscription/utils/single_flight_guard.dart';
import 'package:fluffychat/features/subscription/utils/v2_ui_gating.dart';
import 'package:fluffychat/features/subscription/widgets/subscription_snackbar.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/routes/settings/settings_subscription/settings_subscription_view.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
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

  /// True on the v2 web path (flag-on, web) only. Off the flag and on mobile
  /// this is false and every v2 branch below is inert.
  bool get _v2CancelPath => Environment.subsV2WebEnabled && kIsWeb;

  /// Re-entry guards (unit-tested SingleFlightGuard): a double-tap on the
  /// cancel tile or a manage tile must not fire concurrent requests or open
  /// duplicate confirm dialogs / portal tabs.
  final SingleFlightGuard _cancelGuard = SingleFlightGuard();
  final SingleFlightGuard _portalGuard = SingleFlightGuard();

  /// Gates the cancel / re-enable-renewal tile in the view. Off the v2 path
  /// this is always true (RC behavior byte-for-byte unchanged — the tile always
  /// renders in that block). On the v2 path the in-app cancel tile shows ONLY
  /// when a user-owned, cancelable, not-already-cancelling entitlement exists
  /// (shouldShowV2Cancel, I5); D4 keeps re-enable-renewal out of scope.
  bool get showCancelRenewalTile {
    if (!_v2CancelPath) return true;
    final state = subscriptionController.state;
    return state is SubscriptionActive && shouldShowV2Cancel(state);
  }

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
    final state = subscriptionController.state;
    // #3: the v2 path is SELF-CONTAINED — it either runs the in-app cancel or
    // no-ops, and NEVER falls through to the legacy external-portal +
    // clicked-cancel polling shim. Only the non-v2 path reaches the legacy code
    // below (byte-for-byte unchanged off the flag). classifyCancelClick encodes
    // this so the routing is unit-tested.
    switch (classifyCancelClick(v2CancelPath: _v2CancelPath, state: state)) {
      case CancelClickAction.v2Cancel:
        // Cancel is synchronous + server-confirmed, so we do NOT set the
        // clicked-cancel/end-date polling shim — we refresh via
        // updateCurrentSubscription inside the controller.
        if (!_cancelGuard.tryEnter()) return; // no concurrent cancels
        try {
          final result = await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context).cancelSubscription,
            message: L10n.of(context).areYouSure,
            okLabel: L10n.of(context).yes,
            cancelLabel: L10n.of(context).cancel,
            isDestructive: true,
          );
          if (result != OkCancelResult.ok) return;

          // The repo idiom for exactly this: a blocking loading dialog while
          // the cancel runs, and a dismissible error surface if it throws —
          // the tile stays available, so the user can retry.
          await showFutureLoadingDialog(
            context: context,
            future: () => subscriptionController.cancelSubscription(
              (state as SubscriptionActive).entitlementRef!,
            ),
          );
          if (mounted) setState(() {});
        } finally {
          _cancelGuard.exit();
        }
        return;
      case CancelClickAction.v2NoOp:
        return;
      case CancelClickAction.legacy:
        break;
    }

    final uri = await launchMangementUrl(ManagementOption.cancel);
    if (uri != null) {
      ScaffoldMessenger.of(context).showSnackBarAnnounced(
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
        announcement: L10n.of(context).managementSnackbarMessage,
      );
    }
    await SubscriptionManagementRepo.setClickedCancelSubscription();
    await SubscriptionManagementRepo.setSubscriptionEndDate(
      subscriptionEndDate,
    );
    if (mounted) setState(() {});
  }

  Future<Uri?> launchMangementUrl(ManagementOption option) async {
    // v2 web path: BOTH the payment-method and payment-history tiles mint a
    // fresh Stripe billing-portal session — the portal surfaces the payment
    // method AND the full invoice history, which is the minimal correct
    // wiring onto the canonical v2 APIs without building new client UI
    // (Gabby's history page will consume PaymentHistoryRepo directly). The
    // legacy static stripeManagementUrl is NEVER launched on this path; off
    // the flag / on mobile the legacy code below is byte-for-byte unchanged.
    // The routing decision is the unit-tested classifyManagementLaunch.
    switch (classifyManagementLaunch(v2Path: _v2CancelPath)) {
      case ManagementLaunchRoute.v2BillingPortal:
        return _launchV2BillingPortal();
      case ManagementLaunchRoute.legacy:
        break;
    }

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

  /// Mints a fresh Stripe billing-portal session and opens it (v2 web path).
  /// Portal URLs are SHORT-LIVED — always minted on click, never cached (the
  /// repo only dedupes an in-flight request). The typed no-portal outcome
  /// ([NoBillingAccountException] — the user has no canonical Stripe customer)
  /// is NOT an error: it renders the management-unavailable message instead of
  /// an error dialog. Transient failures surface in the loading dialog's
  /// dismissible error state, so the user can retry from the same tile.
  Future<Uri?> _launchV2BillingPortal() async {
    if (!_portalGuard.tryEnter()) return null; // no duplicate portal mints
    try {
      final userID = Matrix.of(context).client.userID;
      if (userID == null) return null;

      final result = await showFutureLoadingDialog(
        context: context,
        future: () async {
          final res = await BillingPortalRepo.get(userID);
          final error = res.asError?.error;
          if (error != null) throw error;
          return res.asValue!.value;
        },
        // The typed no-portal outcome is handled below, not as an error UI.
        showError: (e) => e is! NoBillingAccountException,
      );
      if (!mounted) return null;

      if (result.error is NoBillingAccountException) {
        ScaffoldMessenger.of(context).showSnackBarAnnounced(
          SnackBar(
            content: Text(L10n.of(context).subscriptionManagementUnavailable),
          ),
          announcement: L10n.of(context).subscriptionManagementUnavailable,
        );
        return null;
      }

      final portal = result.result;
      if (portal == null) return null;

      final uri = Uri.parse(portal.url);
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return uri;
    } finally {
      _portalGuard.exit();
    }
  }

  @override
  Widget build(BuildContext context) => SettingsSubscriptionView(this);
}

enum ManagementOption { cancel, paymentMethod, history }
