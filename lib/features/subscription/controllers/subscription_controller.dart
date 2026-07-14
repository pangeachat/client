import 'dart:async';

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_paywall_status_enum.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/free_trial_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/free_trial_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionController with ChangeNotifier {
  SubscriptionState _state = SubscriptionLoading();
  Completer<void>? _initCompleter;
  final ValueNotifier<bool> subscriptionNotifier = ValueNotifier<bool>(false);

  SubscriptionState get state => _state;

  bool get showSubscriptionGatedContent => switch (_state) {
    SubscriptionInactive() => _inTrialWindow,
    _ => true,
  };

  SubscriptionPaywallStatus get paywallStatus => switch (_state) {
    SubscriptionActive() => SubscriptionPaywallStatus.subscribed,
    _ =>
      shouldShowPaywall
          ? SubscriptionPaywallStatus.shouldShowPaywall
          : SubscriptionPaywallStatus.dimissedPaywall,
  };

  bool get shouldShowPaywall => switch (_state) {
    SubscriptionInactive() => !SubscriptionManagementRepo.getDismissedPaywall(),
    _ => false,
  };

  bool get _inTrialWindow =>
      MatrixState.pangeaController.userController.inTrialWindow();

  @override
  void dispose() {
    subscriptionNotifier.dispose();
    super.dispose();
  }

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
      await updateCurrentSubscription(userID);

      if (_state is! SubscriptionActive && _inTrialWindow) {
        await activateNewUserTrial(userID);
      }

      if (SubscriptionManagementRepo.getBeganPayment()) {
        await SubscriptionManagementRepo.removeBeganPayment();
        if (_state is SubscriptionActive) _onSubscribe();
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      _state = SubscriptionError(error: e);
    } finally {
      notifyListeners();
    }
  }

  Future<void> submitSubscriptionChange(
    String planId,
    BuildContext context, {
    required String userID,
    String? promoCode,
  }) async {
    try {
      GoogleAnalytics.beginPurchaseSubscription(planId, promoCode, context);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"plan_id": planId, "promo_code": promoCode},
      );
    }

    try {
      final result = await CheckoutRepo.instance.getPaymentLink(
        CheckoutRequest(userID: userID, planId: planId, promoCode: promoCode),
      );

      final response = result.result;
      if (response == null) {
        throw result.asError ?? "Failed to fetch payment link";
      }

      await SubscriptionManagementRepo.setBeganPayment();
      launchUrlString(response, webOnlyWindowName: "_self");
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"plan_id": planId, "promo_code": promoCode},
      );
      rethrow;
    }
  }

  Future<void> activateNewUserTrial(String userID) async {
    final result = await FreeTrialRepo.instance.get(
      FreeTrialRequest(userID: userID),
    );
    final activated = !result.isError;
    if (!activated) return;
    await updateCurrentSubscription(userID);
  }

  Future<void> updateCurrentSubscription(String userID) async {
    final result = await SubscriptionStatusRepo.instance.get(
      SubscriptionStatusRequest(userID: userID),
    );

    final response = result.result;
    if (response == null) {
      _state = SubscriptionError(
        error: result.error ?? "Failed to fetch subscription status",
      );
      notifyListeners();
      return;
    }

    _state = response.accessLevel == SubscriptionAccessLevel.full
        ? SubscriptionActive()
        : SubscriptionInactive();

    notifyListeners();
  }
}
