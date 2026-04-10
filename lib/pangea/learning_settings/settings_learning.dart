import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/learning_settings/learning_settings_view_model.dart';
import 'package:fluffychat/pangea/learning_settings/settings_learning_view.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SettingsLearning extends StatefulWidget {
  final bool isDialog;

  const SettingsLearning({this.isDialog = true, super.key});

  @override
  SettingsLearningController createState() => SettingsLearningController();
}

class SettingsLearningController extends State<SettingsLearning> {
  final viewModel = LearningSettingsViewModel(
    MatrixState.pangeaController.userController.profile,
  );

  final ValueNotifier<String?> languageMatchError = ValueNotifier(null);
  final ScrollController scrollController = ScrollController();
  final TextEditingController aboutTextController = TextEditingController();
  final ExpansibleController languageTileController = ExpansibleController();

  @override
  void initState() {
    super.initState();
    aboutTextController.text = viewModel.about ?? '';
    if (viewModel.hasIdenticalLanguages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          languageMatchError.value = L10n.of(context).noIdenticalLanguages;
        }
      });
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    aboutTextController.dispose();
    viewModel.dispose();
    languageMatchError.dispose();
    languageTileController.dispose();
    super.dispose();
  }

  // if the settings have been changed, show a dialog the user wants to exit without saving
  // if the settings have not been changed, just close the settings page
  Future<void> onSettingsClose() async {
    if (!viewModel.haveSettingsChanged) {
      Navigator.of(context).pop();
      return;
    }

    final resp = await showOkCancelAlertDialog(
      title: L10n.of(context).exitWithoutSaving,
      okLabel: L10n.of(context).submit,
      cancelLabel: L10n.of(context).leave,
      context: context,
    );

    resp == OkCancelResult.ok ? await submit() : Navigator.of(context).pop();
  }

  Future<void> submit() async {
    if (viewModel.hasIdenticalLanguages) {
      languageMatchError.value = L10n.of(context).noIdenticalLanguages;
      languageTileController.expand();
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    languageMatchError.value = null;
    await showFutureLoadingDialog(
      context: context,
      future: () async => MatrixState.pangeaController.userController
          .updateProfile(
            (_) => viewModel.updatedProfile,
            waitForDataInSync: true,
          )
          .timeout(const Duration(seconds: 15)),
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => SettingsLearningView(this);
}
