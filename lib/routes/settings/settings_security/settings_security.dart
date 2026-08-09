import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/authentication/delete_account_extension.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'settings_security_view.dart';

class SettingsSecurity extends StatefulWidget {
  const SettingsSecurity({super.key});

  @override
  SettingsSecurityController createState() => SettingsSecurityController();
}

class SettingsSecurityController extends State<SettingsSecurity> {
  void setAppLockAction() async {
    if (AppLock.of(context).isActive) {
      AppLock.of(context).showLockScreen();
    }
    final newLock = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).pleaseChooseAPasscode,
      message: L10n.of(context).pleaseEnter4Digits,
      cancelLabel: L10n.of(context).cancel,
      validator: (text) {
        if (text.isEmpty || (text.length == 4 && int.tryParse(text)! >= 0)) {
          return null;
        }
        return L10n.of(context).pleaseEnter4Digits;
      },
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLines: 1,
      minLines: 1,
      maxLength: 4,
    );
    if (newLock != null) {
      await AppLock.of(context).changePincode(newLock);
    }
  }

  Future<String?> _entitlementToCancel(String userID) async {
    final statusResult = await SubscriptionStatusRepo.instance.get(
      SubscriptionStatusRequest(userID: userID),
    );
    final statusResponse = statusResult.result;
    if (statusResponse == null) {
      throw statusResult.error ?? "Failed to fetch subscription status";
    }

    return statusResponse.cancelableEntitlement?.entitlementRef;
  }

  void deleteAccountAction() async {
    // #Pangea
    // Capture THE account being deleted at action entry — before any await —
    // and thread it through entitlement lookup, the confirm dialog, and the
    // destructive calls. Never re-read Matrix.of(context).client after an await
    // (an account switch mid-flow would otherwise confirm A but delete B); the
    // identity is revalidated immediately before the destructive call.
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final clientName = client.clientName;
    // Nullable capture: a soft-logout race could leave userID null, and an
    // async-void action can't surface a `!` failure as a dialog error.
    final capturedUserId = client.userID;
    if (capturedUserId == null) return;
    // Pangea#
    final entitlementResult = await showFutureLoadingDialog(
      context: context,
      future: () => _entitlementToCancel(capturedUserId),
      onError: (_, _) => L10n.of(context).errorTryAgainLater,
    );
    if (entitlementResult.isError) return;

    final entitlementRef = entitlementResult.result;
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).warning,
          message: entitlementRef != null
              ? L10n.of(context).deactivateSubscribedAccountWarning
              : L10n.of(context).deactivateAccountWarning,
          okLabel: L10n.of(context).ok,
          cancelLabel: L10n.of(context).cancel,
          isDestructive: true,
        ) ==
        OkCancelResult.cancel) {
      return;
    }
    final supposedMxid = capturedUserId;
    final mxid = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      // #Pangea
      // title: L10n.of(context).confirmMatrixId,
      title: L10n.of(context).confirmUserId,
      // Pangea#
      validator: (text) => text == supposedMxid
          ? null
          : L10n.of(context).supposedMxid(supposedMxid),
      isDestructive: true,
      okLabel: L10n.of(context).delete,
      cancelLabel: L10n.of(context).cancel,
      // #Pangea
      maxLength: 128,
      // Pangea#
    );
    if (mxid == null || mxid.isEmpty || mxid != supposedMxid) {
      return;
    }
    final resp = await showFutureLoadingDialog(
      context: context,
      delay: false,
      // #Pangea
      // future: () =>
      //     Matrix.of(context).client.uiaRequestBackground<IdServerUnbindResult?>(
      //       (auth) => Matrix.of(
      //         context,
      //       ).client.deactivateAccount(auth: auth, erase: true),
      //     ),
      future: () async {
        // Flush the final dosage span while the bearer is still valid, BEFORE
        // deletion invalidates it (best-effort, never blocks the deletion).
        await matrix.flushAccountTelemetry(clientName);
        // Revalidate the captured identity immediately before the destructive
        // calls (after the flush await): if the active account switched during
        // the dialogs/flush, abort rather than delete the wrong account.
        if (matrix.client != client || client.userID != capturedUserId) {
          throw Exception('Active account changed; aborting account deletion');
        }
        if (entitlementRef != null) {
          final result = await SubscriptionCancelRepo.instance
              .cancelSubscription(
                SubscriptionCancelRequest(
                  userID: capturedUserId,
                  entitlementRef: entitlementRef,
                ),
              );
          final error = result.error;
          if (error != null) throw error;
        }

        await client.deleteAccount();
        await client.uiaRequestBackground<IdServerUnbindResult?>(
          (auth) => client.deactivateAccount(auth: auth, erase: true),
        );
      },
      // Pangea#
    );

    if (!resp.isError) {
      await showFutureLoadingDialog(
        context: context,
        // The CAPTURED client — its loggedOut listener disposes its services.
        future: () => client.logout(),
      );
    }
  }

  Future<void> dehydrateAction() => Matrix.of(context).dehydrateAction(context);

  void changeShareKeysWith(ShareKeysWith? shareKeysWith) async {
    if (shareKeysWith == null) return;
    AppSettings.shareKeysWith.setItem(shareKeysWith.name);
    Matrix.of(context).client.shareKeysWith = shareKeysWith;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsSecurityView(this);
}
