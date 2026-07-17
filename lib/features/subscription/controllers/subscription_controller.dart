import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/enums/subscription_paywall_status_enum.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
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
      await _updateCurrentSubscription(userID);

      final state = _state;
      if (state is SubscriptionInactive &&
          state.response.isTrialOfferable &&
          _inTrialWindow) {
        await _activateNewUserTrial(userID);
      }

      final isSubscribed = _state is SubscriptionActive;
      final beganPayment = SubscriptionManagementRepo.getBeganPayment();
      if (beganPayment && isSubscribed) {
        await SubscriptionManagementRepo.removeBeganPayment();
        _onSubscribe();
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      _state = SubscriptionError(error: e);
    } finally {
      notifyListeners();
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
    );

    final response = result.result;
    if (response == null) {
      _state = SubscriptionError(
        error: result.error ?? "Failed to fetch subscription status",
      );
      notifyListeners();
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

    _state = SubscriptionState.fromSubscriptionStatus(response);
    notifyListeners();
  }
}
