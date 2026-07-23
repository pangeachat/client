import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/enums/subscription_paywall_status_enum.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/repo_v2/free_trial_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/free_trial_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionController {
  final ValueNotifier<SubscriptionState> _state = ValueNotifier(
    SubscriptionLoading(),
  );
  Completer<void>? _initCompleter;
  final ValueNotifier<bool> subscriptionNotifier = ValueNotifier<bool>(false);

  ValueNotifier<SubscriptionState> get state => _state;

  bool get showSubscriptionGatedContent => switch (_state.value) {
    SubscriptionInactive() => _inTrialWindow,
    _ => true,
  };

  SubscriptionPaywallStatus get paywallStatus => switch (_state.value) {
    SubscriptionActive() => SubscriptionPaywallStatus.subscribed,
    _ =>
      shouldShowPaywall
          ? SubscriptionPaywallStatus.shouldShowPaywall
          : SubscriptionPaywallStatus.dimissedPaywall,
  };

  bool get shouldShowPaywall => switch (_state.value) {
    SubscriptionInactive() => !SubscriptionManagementRepo.getDismissedPaywall(),
    _ => false,
  };

  bool get _inTrialWindow =>
      MatrixState.pangeaController.userController.inTrialWindow();

  SubscriptionStatusResponse? get subscriptionStatus {
    return switch (_state.value) {
      SubscriptionActive(response: final response) ||
      SubscriptionInactive(response: final response) => response,
      _ => null,
    };
  }

  void dispose() {
    _state.dispose();
    subscriptionNotifier.dispose();
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
    _state.value = SubscriptionLoading();
    await initialize(userID);
  }

  Future<void> _initialize(String userID) async {
    try {
      await MatrixState.pangeaController.userController.initCompleter.future;
      await _updateCurrentSubscription(userID);

      final state = _state.value;
      if (state is SubscriptionInactive &&
          state.response.isTrialOfferable &&
          _inTrialWindow) {
        await _activateNewUserTrial(userID);
      }

      final isSubscribed = _state.value is SubscriptionActive;
      final beganPayment = SubscriptionManagementRepo.getBeganPayment();
      if (beganPayment && isSubscribed) {
        final planId = SubscriptionManagementRepo.getBeganPaymentPlanId();
        await SubscriptionManagementRepo.removeBeganPayment();
        GoogleAnalytics.purchaseSubscription(planId);
        _onSubscribe();
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      _state.value = SubscriptionError(error: e);
    }
  }

  Future<void> _activateNewUserTrial(String userID) async {
    final result = await FreeTrialRepo.instance.get(
      FreeTrialRequest(userID: userID),
    );
    final activated = !result.isError;
    if (!activated) return;
    await _updateCurrentSubscription(userID);
  }

  Future<void> _updateCurrentSubscription(String userID) async {
    final result = await SubscriptionStatusRepo.instance.get(
      SubscriptionStatusRequest(userID: userID),
      forceRefresh: true,
    );

    final response = result.result;
    if (response == null) {
      _state.value = SubscriptionError(
        error: result.error ?? "Failed to fetch subscription status",
      );
      return;
    }

    if (response.isPaidWithoutPlan) {
      // a paid entitlement should always map to a catalog plan. If it
      // does not, log it (this shouldn't happen) — the controller renders a
      // generic tile so the paying user still sees management + the
      // account-delete warning, rather than a broken/empty tile.
      ErrorHandler.logError(
        m: "v2 paid entitlement missing a catalog planId",
        s: StackTrace.current,
        data: {},
      );
    }

    _state.value = SubscriptionState.fromSubscriptionStatus(response);
  }
}
