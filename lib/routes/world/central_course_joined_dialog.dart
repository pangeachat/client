import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Tells an existing learner the app joined them to their language's central
/// course, once, with a way to leave (joining-courses.instructions.md § The
/// central course).
class CentralCourseJoinedDialog extends StatelessWidget {
  final Room room;
  final String languageName;

  const CentralCourseJoinedDialog({
    super.key,
    required this.room,
    required this.languageName,
  });

  static Future<void> show(
    BuildContext context,
    Client client,
    String roomId,
  ) async {
    final room = client.getRoomById(roomId);
    final language = MatrixState.pangeaController.userController.userL2;
    if (room == null || language == null) {
      ErrorHandler.logError(
        e: 'Joined central course could not be shown to the learner',
        data: {'room_id': roomId, 'has_room': room != null},
        level: SentryLevel.warning,
      );
      return;
    }
    await showAdaptiveDialog<void>(
      context: context,
      builder: (context) => CentralCourseJoinedDialog(
        room: room,
        languageName: language.getDisplayName(L10n.of(context)),
      ),
    );
  }

  Future<void> _leave(BuildContext context) async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: room.leaveSpace,
    );
    if (result.isError || !context.mounted) return;
    Navigator.of(context).pop();
  }

  void _open(BuildContext context) {
    Navigator.of(context).pop();
    // The router's own location: GoRouterState is not reachable from a dialog.
    final router = FluffyChatApp.router;
    router.go(
      WorkspaceNav.openCourse(
        router.routeInformationProvider.value.uri,
        room.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog.adaptive(
      title: Text(
        l10n.centralCourseJoinedTitle(
          room.getLocalizedDisplayname(MatrixLocals(l10n)),
        ),
      ),
      content: Text(l10n.centralCourseJoinedBody(languageName)),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => _leave(context),
          child: Text(l10n.leave),
        ),
        AdaptiveDialogAction(
          onPressed: () => _open(context),
          autofocus: true,
          child: Text(l10n.openCourse),
        ),
      ],
    );
  }
}
