import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/features/subscription/models/mobile_subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/models/subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/models/web_subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/repo/all_products_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_app_ids_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_repo.dart';
import 'package:fluffychat/features/subscription/utils/subscription_app_id.dart';
import 'package:fluffychat/features/subscription/utils/subscription_status_enum.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionController with ChangeNotifier {
  SubscriptionState _state = SubscriptionLoading();

  SubscriptionAppIds? _appIds;
  List<SubscriptionDetails> _allSubscriptions = [];
  List<SubscriptionDetails> _availableSubscriptions = [];

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
    SubscriptionActive(subscriptionId: final id) => id.startsWith("rc_promo"),
    _ => false,
  };

  String? get _subscriptionId => switch (_state) {
    SubscriptionActive(subscriptionId: final id) => id,
    _ => null,
  };

  SubscriptionDetails? get subscription {
    final id = _subscriptionId;
    if (id == null) return null;
    return _allSubscriptions.firstWhereOrNull(
      (SubscriptionDetails sub) => sub.id.contains(id) || id.contains(sub.id),
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
      await _setAvailableSubscriptions();
      await updateCurrentSubscription();

      if (_subscriptionId == null && inTrialWindow) {
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
    _state = await _manager.getCurrentSubscriptionInfo();
    notifyListeners();
  }
}
