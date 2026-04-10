import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';
import 'package:fluffychat/pangea/learning_settings/learning_settings_tiles.dart';
import 'package:fluffychat/pangea/learning_settings/settings_learning.dart';
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
              (event) => event.type == ModelKey.userProfile,
            );
      }),
      builder: (context, _) {
        final dialogContent = Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !controller.widget.isDialog,
            centerTitle: true,
            title: Text(L10n.of(context).learningSettings),
            leading: controller.widget.isDialog
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: controller.onSettingsClose,
                  )
                : null,
          ),
          body: Column(
            children: [
              Expanded(
                child: MaxWidthBody(
                  scrollController: controller.scrollController,
                  showBorder: !controller.widget.isDialog,
                  child: LearningSettingsTiles(
                    viewModel: controller.viewModel,
                    languageErrorNotifier: controller.languageMatchError,
                    aboutTextController: controller.aboutTextController,
                    languageTileController: controller.languageTileController,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: controller.viewModel,
                builder: (context, _) => Container(
                  padding: const EdgeInsets.all(16.0),
                  constraints: BoxConstraints(maxWidth: 600),
                  child: ElevatedButton(
                    onPressed: controller.viewModel.haveSettingsChanged
                        ? controller.submit
                        : null,
                    child: Row(
                      mainAxisAlignment: .center,
                      children: [Text(L10n.of(context).saveChanges)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        if (!controller.widget.isDialog) return dialogContent;
        return FullWidthDialog(
          dialogContent: dialogContent,
          maxWidth: 600,
          maxHeight: 800,
        );
      },
    );
  }
}
