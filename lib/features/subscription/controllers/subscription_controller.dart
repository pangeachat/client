import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fluffychat/features/subscription/models/mobile_subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/models/subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/models/subscription_status_v2.dart';
import 'package:fluffychat/features/subscription/models/web_subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/repo/all_products_repo.dart';
import 'package:fluffychat/features/subscription/repo/cancel_v2_repo.dart';
import 'package:fluffychat/features/subscription/repo/products_v2_repo.dart';
import 'package:fluffychat/features/subscription/repo/status_v2_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_app_ids_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_repo.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/utils/subscription_app_id.dart';
import 'package:fluffychat/features/subscription/utils/subscription_status_enum.dart';
import 'package:fluffychat/features/subscription/utils/v2_subscription_catalog.dart';
import 'package:fluffychat/features/subscription/utils/v2_ui_gating.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionController with ChangeNotifier {
  SubscriptionState _state = SubscriptionLoading();

  SubscriptionAppIds? _appIds;
  List<SubscriptionDetails> _allSubscriptions = [];
  List<SubscriptionDetails> _availableSubscriptions = [];

  /// The `/subscription/status` snapshot fetched once at v2-web init and reused
  /// for BOTH the initial state AND the trial-card decision in
  /// `_setAvailableSubscriptions` (finding #3). Null on the RC/mobile path.
  SubscriptionStatusV2? _statusV2;

  Completer<void>? _initCompleter;

  final ValueNotifier<bool> subscriptionNotifier = ValueNotifier<bool>(false);

  SubscriptionController();

  SubscriptionState get state => _state;

  SubscriptionAppIds? get appIds => _appIds;

  List<SubscriptionDetails> get availableSubscriptions =>
      _availableSubscriptions;

  bool get loading => _state is SubscriptionLoading;

  bool get showSubscriptionGatedContent => switch (_state) {
    SubscriptionInactive() => inTrialWindow,
    _ => true,
  };

  SubscriptionStatus get paywallStatus => switch (_state) {
    SubscriptionActive() => SubscriptionStatus.subscribed,
    _ =>
      shouldShowPaywall
          ? SubscriptionStatus.shouldShowPaywall
          : SubscriptionStatus.dimissedPaywall,
  };

  bool get inTrialWindow =>
      MatrixState.pangeaController.userController.inTrialWindow();

  bool get shouldShowPaywall => switch (_state) {
    SubscriptionInactive() => !SubscriptionManagementRepo.getDismissedPaywall(),
    _ => false,
  };

  bool get hasPaidSubscription => switch (_state) {
    SubscriptionActive() => !hasPromotionalSubscription,
    _ => false,
  };

  bool get hasPromotionalSubscription => switch (_state) {
    // I11: on the v2 web path `isPromotional` is set (`!isV2PaidType(...)`, so
    // paid/individual are NOT promotional); on the RC/mobile path it is null, so
    // this falls back to today's exact `id.startsWith("rc_promo")` check —
    // behavior unchanged off the flag.
    SubscriptionActive(subscriptionId: final id, isPromotional: final promo) =>
      promo ?? id.startsWith("rc_promo"),
    _ => false,
  };

  String? get _subscriptionId => switch (_state) {
    SubscriptionActive(subscriptionId: final id) => id,
    _ => null,
  };

  /// Whether a v2 trial can be STARTED (D3). Drives trial-card enablement on the
  /// v2 web path in place of the RC-only `inTrialWindow`. False off the flag and
  /// on mobile, so those paths keep using `inTrialWindow` unchanged.
  bool get v2TrialOfferable =>
      Environment.subsV2WebEnabled && kIsWeb && v2TrialOfferableFor(_statusV2);

  SubscriptionDetails? get subscription {
    final id = _subscriptionId;
    if (id == null) return null;
    final resolved = _allSubscriptions.firstWhereOrNull(
      (SubscriptionDetails sub) => sub.id.contains(id) || id.contains(sub.id),
    );
    if (resolved != null) return resolved;

    // v2 (finding #4b): a PAID entitlement whose plan is not in the catalog
    // (e.g. a grandfathered price with a null planId) still bills the user —
    // render a generic tile with working management instead of an empty/broken
    // one (which would also skip the account-delete warning). comp/seat/trial
    // legitimately have no sellable plan and keep returning null here. Off the
    // flag / on mobile this fallback is never reached, so behavior is unchanged.
    final state = _state;
    if (Environment.subsV2WebEnabled &&
        kIsWeb &&
        state is SubscriptionActive &&
        state.isPromotional == false &&
        !state.isTrial) {
      return _genericV2PaidSubscription();
    }
    return null;
  }

  /// A generic tile for a paid v2 entitlement missing from the catalog (#4b):
  /// `appId == stripeId` so management resolves, `duration == null` so the name
  /// is the default-subscription copy, and a blank price (we do not know the
  /// grandfathered amount) rather than the misleading "free trial" that a
  /// `price <= 0` would render.
  SubscriptionDetails _genericV2PaidSubscription() {
    final stripeId = _appIds?.stripeId ?? kStripeAppIdFallback;
    return SubscriptionDetails(
      id: _subscriptionId ?? stripeId,
      appId: stripeId,
      price: 1,
      localizedPrice: "",
      duration: null,
    );
  }

  String? get defaultManagementURL {
    final appIds = _appIds;
    final appId = subscription?.appId;
    if (appId == null) return null;
    return appIds?.defaultManagementURL(appId);
  }

  SubscriptionInfoManager get _manager =>
      kIsWeb ? WebSubscriptionInfoManager() : MobileSubscriptionInfoManager();

  void _onSubscribe() {
    subscriptionNotifier.value = true;
    GoogleAnalytics.updateUserSubscriptionStatus(true);
  }

  Future<void> initialize(String? userID) async {
    if (userID == null) return;

    final init = _initCompleter;
    if (init?.isCompleted == true) return;
    if (init != null && !init.isCompleted) {
      await init.future;
      return;
    }

    _initCompleter = Completer();
    await _initialize(userID);

    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      _initCompleter!.complete();
    }
  }

  Future<void> reinitialize(String? userID) async {
    if (_initCompleter?.isCompleted == false) {
      _initCompleter?.complete();
    }

    _initCompleter = null;
    _state = SubscriptionLoading();
    await initialize(userID);
  }

  Future<void> _initialize(String userID) async {
    try {
      await MatrixState.pangeaController.userController.initCompleter.future;
      await configurePurchases(userID);

      await _setAppIds();

      if (Environment.subsV2WebEnabled && kIsWeb) {
        // v2 web (finding #3): fetch /status ONCE, reuse it for BOTH the
        // trial-card decision (_setAvailableSubscriptions) AND the initial
        // state, so /status is read before /products and only once.
        _statusV2 = await StatusV2Repo.get();
        await _setAvailableSubscriptions();
        _state = mapStatusV2ToState(
          _statusV2!,
          stripeAppId: _appIds?.stripeId ?? kStripeAppIdFallback,
        );
        notifyListeners();
      } else {
        await _setAvailableSubscriptions();
        await updateCurrentSubscription();
      }

      // Auto-activate a trial for a brand-new user. On the v2 web path this
      // uses the SERVER signal (v2TrialOfferable) rather than the RC-only local
      // `inTrialWindow`, so a server-eligible user outside the local window
      // still gets their trial; off the flag / on mobile it stays on
      // `inTrialWindow`, byte-for-byte. `_statusV2` is already fetched above on
      // the v2 path, so `v2TrialOfferable` is populated here.
      final bool trialOfferable = isTrialOfferable(
        v2Path: Environment.subsV2WebEnabled && kIsWeb,
        v2TrialOfferable: v2TrialOfferable,
        inTrialWindow: inTrialWindow,
      );
      if (_subscriptionId == null && trialOfferable) {
        await activateNewUserTrial();
      }

      await _handleWebSubscriptionFlow();
      _registerSubscriptionListener();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      _state = SubscriptionError(error: e);
    } finally {
      notifyListeners();
    }
  }

  Future<void> configurePurchases(String userID) async {
    if (kIsWeb) return;

    final PurchasesConfiguration configuration = Platform.isAndroid
        ? PurchasesConfiguration(Environment.rcGoogleKey)
        : PurchasesConfiguration(Environment.rcIosKey);

    try {
      await Purchases.configure(configuration..appUserID = userID);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"userID": userID});
    }
  }

  Future<void> _setAppIds() async {
    final appIdsResult = await SubscriptionAppIdsRepo.get();
    final appIds = appIdsResult.result;
    if (appIds != null) {
      _appIds = appIds;
    }
  }

  Future<void> _setAvailableSubscriptions() async {
    if (Environment.subsV2WebEnabled && kIsWeb) {
      // v2 web: build the catalog from /products + the /status snapshot. No
      // appId/isVisible filter is needed (these are already the sellable web
      // plans, all appId==stripeId), and the trial card is synthesized off the
      // status snapshot (D3). Pure logic lives in buildV2SubscriptionCatalog.
      final productsResponse = await ProductsV2Repo.get();
      final catalog = buildV2SubscriptionCatalog(
        productsResponse?.plans ?? const [],
        _statusV2,
        stripeAppId: _appIds?.stripeId ?? kStripeAppIdFallback,
      );
      _allSubscriptions = catalog.all;
      _availableSubscriptions = catalog.available;
      return;
    }

    final allProductsResult = await AllProductsRepo.get();
    final allProducts = allProductsResult.result;
    if (allProducts != null) {
      _allSubscriptions = await _setSubscriptionPackages(allProducts);
      _availableSubscriptions = _allSubscriptions
          .where(
            (product) =>
                (product.appId == appIds?.currentAppId && product.isVisible) ||
                product.appId == "trial",
          )
          .sorted((a, b) => a.price.compareTo(b.price))
          .toList();
    }
  }

  Future<List<SubscriptionDetails>> _setSubscriptionPackages(
    List<SubscriptionDetails> subscriptions,
  ) async {
    final updatedSubscriptions = List<SubscriptionDetails>.from(subscriptions);
    if (kIsWeb) return updatedSubscriptions;

    final Offerings offerings = await Purchases.getOfferings();
    final Offering? offering = offerings.all[Environment.rcOfferingName];
    if (offering == null) return updatedSubscriptions;

    for (final package in offering.availablePackages) {
      final int productIndex = updatedSubscriptions.indexWhere(
        (product) => product.id.contains(package.storeProduct.identifier),
      );

      if (productIndex < 0) continue;
      final current = updatedSubscriptions[productIndex];
      final updated = current.copyWith(
        package: package,
        localizedPrice: package.storeProduct.priceString,
      );
      updatedSubscriptions[productIndex] = updated;
    }

    return updatedSubscriptions;
  }

  void _registerSubscriptionListener() {
    if (kIsWeb) return;

    Purchases.addCustomerInfoUpdateListener((CustomerInfo info) async {
      final wasSubscribed = _state is SubscriptionActive;
      await updateCurrentSubscription();
      if (wasSubscribed == false && _state is SubscriptionActive) {
        _onSubscribe();
      }
    });
  }

  Future<void> _handleWebSubscriptionFlow() async {
    if (!kIsWeb) return;

    if (!SubscriptionManagementRepo.getBeganWebPayment()) {
      return;
    }

    await SubscriptionManagementRepo.removeBeganWebPayment();
    if (_state is SubscriptionActive) {
      _onSubscribe();
    }
  }

  Future<void> submitSubscriptionChange(
    SubscriptionDetails selectedSubscription,
    BuildContext context,
  ) async {
    try {
      if (selectedSubscription.isTrial) {
        await activateNewUserTrial();
        return;
      }

      GoogleAnalytics.beginPurchaseSubscription(selectedSubscription, context);
      await _manager.submitSubscriptionChange(selectedSubscription);
    } catch (e, s) {
      if (e is PlatformException &&
          e.message?.contains("Purchase was cancelled") == true) {
        return;
      }

      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"subscription_id": selectedSubscription.id},
      );

      rethrow;
    }
  }

  Future<void> activateNewUserTrial() async {
    final activated = await SubscriptionRepo.activateFreeTrial();
    if (!activated) return;
    await updateCurrentSubscription();
  }

  Future<void> updateCurrentSubscription() async {
    // stripeAppId is web-v2 only; the mobile/RC manager ignores it.
    _state = await _manager.getCurrentSubscriptionInfo(
      stripeAppId: _appIds?.stripeId,
    );
    notifyListeners();
  }

  /// In-app v2 cancel (S4/D4): POST /cancel for the user-owned entitlement, then
  /// refresh from /status so the UI reflects the server-confirmed
  /// cancel-at-period-end. [entitlementRef] MUST come from `/status` (I5) — the
  /// caller sources it from the active state's `entitlementRef`. Errors are
  /// logged and rethrown (matching submitSubscriptionChange) so the UI can react.
  Future<void> cancelSubscription(String entitlementRef) async {
    try {
      await CancelV2Repo.cancel(entitlementRef);
      await updateCurrentSubscription();
      notifyListeners();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"entitlementRef": entitlementRef},
      );
      rethrow;
    }
  }
}
