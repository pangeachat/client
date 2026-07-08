import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_password/settings_password_view.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SettingsPassword extends StatefulWidget {
  const SettingsPassword({super.key});

  @override
  SettingsPasswordController createState() => SettingsPasswordController();
}

class SettingsPasswordController extends State<SettingsPassword> {
  final TextEditingController oldPasswordController = TextEditingController();
  final TextEditingController newPassword1Controller = TextEditingController();
  final TextEditingController newPassword2Controller = TextEditingController();

  String? oldPasswordError;
  String? newPassword1Error;
  String? newPassword2Error;

  bool loading = false;

  void changePassword() async {
    setState(() {
      oldPasswordError = newPassword1Error = newPassword2Error = null;
    });
    if (oldPasswordController.text.isEmpty) {
      setState(() {
        oldPasswordError = L10n.of(context).pleaseEnterYourPassword;
      });
      return;
    }
    if (newPassword1Controller.text.isEmpty ||
        newPassword1Controller.text.length < 6) {
      setState(() {
        newPassword1Error = L10n.of(context).pleaseChooseAStrongPassword;
      });
      return;
    }
    if (newPassword1Controller.text != newPassword2Controller.text) {
      setState(() {
        newPassword2Error = L10n.of(context).passwordsDoNotMatch;
      });
      return;
    }

    setState(() {
      loading = true;
    });
    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      await Matrix.of(context).client.changePassword(
        newPassword1Controller.text,
        oldPassword: oldPasswordController.text,
      );
      scaffoldMessenger.showSnackBarAnnounced(
        SnackBar(content: Text(L10n.of(context).passwordHasBeenChanged)),
      );
      // world_v2: this is the `settingspage:security/password` token panel, not
      // a route. A bare context.pop() has nothing on the navigator stack to pop
      // to and falls out of the shell to the blank loading page (#7076); fall
      // back to the Security page (the parent). As a real pushed route popOrGo
      // still pops normally.
      if (mounted) {
        NavigationUtil.popOrGo(
          context,
          WorkspaceNav.settingsBack(
            GoRouterState.of(context).uri,
            'security/password',
          ),
        );
      }
    } catch (e) {
      setState(() {
        newPassword2Error = e.toLocalizedString(
          context,
          ExceptionContext.changePassword,
        );
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPasswordView(this);
}
