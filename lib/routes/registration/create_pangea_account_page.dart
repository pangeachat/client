import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

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
                  Row(
                    spacing: 8.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _createUserInPangea,
                        child: Text(L10n.of(context).tryAgain),
                      ),
                      TextButton(
                        onPressed: Navigator.of(context).pop,
                        child: Text(L10n.of(context).cancel),
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
