import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/settings_learning_view.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SettingsLearning extends StatefulWidget {
  const SettingsLearning({super.key});

  @override
  SettingsLearningController createState() => SettingsLearningController();
}

class SettingsLearningController extends State<SettingsLearning> {
  late final LearningSettingsViewModel viewModel;

  final ValueNotifier<String?> languageMatchError = ValueNotifier(null);
  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    viewModel = LearningSettingsViewModel(
      MatrixState.pangeaController.userController.profile,
      onUpdateProfile: _updateProfile,
    );

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
    viewModel.dispose();
    languageMatchError.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    if (viewModel.hasIdenticalLanguages) {
      languageMatchError.value = L10n.of(context).noIdenticalLanguages;
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      languageMatchError.value = null;
    }

    try {
      await MatrixState.pangeaController.userController
          .updateProfile(
            (_) => viewModel.updatedProfile,
            waitForDataInSync: true,
          )
          .timeout(const Duration(seconds: 15));
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"updatedProfile": viewModel.updatedProfile.toJson()},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBarAnnounced(
          SnackBar(
            content: Text(L10n.of(context).oopsSomethingWentWrong),
            showCloseIcon: true,
          ),
          assertive: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SettingsLearningView(this);
}
