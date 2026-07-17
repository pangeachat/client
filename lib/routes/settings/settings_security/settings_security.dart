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

  Future<String?> _entitlementToCancel() async {
    final userID = Matrix.of(context).client.userID!;
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
    final entitlementResult = await showFutureLoadingDialog(
      context: context,
      future: _entitlementToCancel,
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
    final supposedMxid = Matrix.of(context).client.userID!;
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
        final client = Matrix.of(context).client;
        if (entitlementRef != null) {
          final result = await SubscriptionCancelRepo.instance
              .cancelSubscription(
                SubscriptionCancelRequest(
                  userID: client.userID!,
                  entitlementRef: entitlementRef,
                ),
              );
          final error = result.error;
          if (error != null) throw error;
        }

        await client.deleteAccount();
        await client.uiaRequestBackground<IdServerUnbindResult?>(
          (auth) => Matrix.of(
            context,
          ).client.deactivateAccount(auth: auth, erase: true),
        );
      },
      // Pangea#
    );

    if (!resp.isError) {
      await showFutureLoadingDialog(
        context: context,
        future: () => Matrix.of(context).client.logout(),
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
