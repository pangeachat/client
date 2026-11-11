import 'package:flutter/material.dart';

import 'package:fluffychat/features/tutorials/tutorial_seen_backfill.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/user_type_prompt_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/user_type_prompt_repo.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Headless shell resident that asks an account with no self-identified role
/// for one when the app opens, at most once a day (profile.instructions.md).
/// The workspace shell mounts it, so it never runs during onboarding.
class UserTypePrompt extends StatefulWidget {
  const UserTypePrompt({super.key});

  @override
  State<UserTypePrompt> createState() => _UserTypePromptState();
}

class _UserTypePromptState extends State<UserTypePrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  /// Gives way to the world-map greeting still to come, as the notifications
  /// dialog does on a course page; that open is not counted, so a later one
  /// asks.
  bool get _orientationRunningOrAboutToStart {
    final tutorials = MatrixState.tutorialOverlayController;
    return tutorials.hasActiveSequence ||
        TutorialSequences.worldOrientationSequence.any(tutorials.isPending);
  }

  Future<void> _maybeAsk() async {
    // Waits for the profile and first sync, so the role and the tutorial
    // seen-flags read below are the account's own.
    await TutorialSeenBackfill.instance.ensureResolved();
    if (!mounted) return;

    final client = Matrix.of(context).client;
    final userId = client.userID;
    if (userId == null) {
      ErrorHandler.logError(
        e: 'No user ID in the workspace shell when checking the role prompt',
        data: {},
      );
      return;
    }
    if (client.selfIdentifiedRole != null) return;
    if (_orientationRunningOrAboutToStart) return;
    if (!await UserTypePromptRepo.canAsk(userId)) return;
    if (!mounted) return;

    await UserTypePromptRepo.markAsked(userId);
    if (!mounted) return;
    final type = await showDialog<UserType>(
      context: context,
      builder: (_) => const UserTypePromptDialog(),
    );
    if (type != null) await _save(type);
  }

  Future<void> _save(UserType type) async {
    try {
      await MatrixState.pangeaController.userController.updateProfile(
        (profile) => profile.copyWith(
          userSettings: profile.userSettings.copyWith(selfIdentifiedRole: type),
        ),
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'user_type': type.name});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBarAnnounced(
        SnackBar(
          content: Text(L10n.of(context).oopsSomethingWentWrong),
          showCloseIcon: true,
        ),
        assertive: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
