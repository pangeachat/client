import 'package:flutter/material.dart';

import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_tiles.dart';
import 'package:fluffychat/routes/settings/settings_learning/settings_learning.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SettingsLearningView extends StatelessWidget {
  final SettingsLearningController controller;
  const SettingsLearningView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Matrix.of(context).client.onSync.stream.where((update) {
        return update.accountData != null &&
            update.accountData!.any(
              (event) => event.type == UserConstants.userProfile,
            );
      }),
      builder: (context, _) {
        return SafeArea(
          child: Scaffold(
            body: MaxWidthBody(
              scrollController: controller.scrollController,
              child: LearningSettingsTiles(
                viewModel: controller.viewModel,
                languageErrorNotifier: controller.languageMatchError,
              ),
            ),
          ),
        );
      },
    );
  }
}
