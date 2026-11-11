import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/authentication/p_logout.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CreatePangeaAccountPage extends StatefulWidget {
  const CreatePangeaAccountPage({super.key});

  @override
  CreatePangeaAccountPageState createState() => CreatePangeaAccountPageState();
}

class CreatePangeaAccountPageState extends State<CreatePangeaAccountPage> {
  bool _loading = true;
  Object? _profileError;

  @override
  void initState() {
    super.initState();
    _createUserInPangea();
  }

  Future<void> _createUserInPangea() async {
    try {
      if (MatrixState.pangeaController.userController.createdAt != null) {
        context.go('/onboarding');
        return;
      }

      setState(() {
        _loading = true;
        _profileError = null;
      });

      await MatrixState.pangeaController.userController
          .updateProfile((profile) {
            return profile.copyWith(
              userSettings: profile.userSettings.copyWith(
                createdAt: DateTime.now(),
              ),
            );
          }, waitForDataInSync: true)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException(L10n.of(context).oopsSomethingWentWrong);
            },
          );

      final userID = Matrix.of(context).client.userID;
      await MatrixState.pangeaController.subscriptionController.reinitialize(
        userID,
      );
      context.go('/onboarding');
    } catch (err, s) {
      ErrorHandler.logError(e: err, s: s, data: {});
      if (err is MatrixException) {
        _profileError = err.errorMessage;
      } else {
        _profileError = err;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _loading
            ? const CircularProgressIndicator.adaptive()
            : _profileError != null
            ? Column(
                spacing: 8.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ErrorIndicator(
                    message: L10n.of(context).oopsSomethingWentWrong,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      L10n.of(context).accountSetupFailedHelp,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Row(
                    spacing: 8.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _createUserInPangea,
                        child: Text(L10n.of(context).tryAgain),
                      ),
                      // Nothing is behind this page, and an account without
                      // an L2 is routed back here, so logging out is the
                      // only other way out.
                      TextButton(
                        onPressed: () => pLogoutAction(context),
                        child: Text(L10n.of(context).logout),
                      ),
                    ],
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
