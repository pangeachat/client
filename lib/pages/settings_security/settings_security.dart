import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../bootstrap/bootstrap_dialog.dart';
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

  void deleteAccountAction() async {
    // #Pangea
    final subscriptionController =
        MatrixState.pangeaController.subscriptionController;
    if (subscriptionController.currentSubscriptionInfo?.isPaidSubscription ==
            true &&
        subscriptionController.defaultManagementURL != null) {
      final resp = await showOkCancelAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).deleteSubscriptionWarningTitle,
        message: L10n.of(context).deleteSubscriptionWarningBody,
        okLabel: L10n.of(context).manageSubscription,
        cancelLabel: L10n.of(context).continueText,
      );
      if (resp == OkCancelResult.ok) {
        launchUrlString(
          subscriptionController.defaultManagementURL!,
          mode: LaunchMode.externalApplication,
        );
        return;
      }
    }
    // Pangea#
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).warning,
          message: L10n.of(context).deactivateAccountWarning,
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
    );
    if (mxid == null || mxid.isEmpty || mxid != supposedMxid) {
      return;
    }
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).pleaseEnterYourPassword,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      isDestructive: true,
      obscureText: true,
      hintText: '******',
      minLines: 1,
      maxLines: 1,
    );
    if (input == null) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(context).client.deactivateAccount(
            auth: AuthenticationPassword(
              password: input,
              identifier: AuthenticationUserIdentifier(
                user: Matrix.of(context).client.userID!,
              ),
            ),
          ),
    );
  }

  void showBootstrapDialog(BuildContext context) async {
    await BootstrapDialog(
      client: Matrix.of(context).client,
    ).show(context);
  }

  Future<void> dehydrateAction() => Matrix.of(context).dehydrateAction(context);

  @override
  Widget build(BuildContext context) => SettingsSecurityView(this);
}
