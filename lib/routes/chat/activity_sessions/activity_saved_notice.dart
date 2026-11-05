import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// The end card's word that a finished session was saved (#9418): "Activity
/// saved to Learning Objectives", shown once the save has archived the
/// learner's role. The line opens the Learning Objectives page where the
/// session is listed: its Mission's page for a course activity, else the
/// page's own list (activity-session.instructions.md, "Completion saves
/// itself").
class ActivitySavedNotice extends StatelessWidget {
  final Room room;

  const ActivitySavedNotice({required this.room, super.key});

  Future<void> _openLearningObjectives(BuildContext context) async {
    final courses = await showFutureLoadingDialog(
      context: context,
      future: () => CourseMissions.load(room.client),
    );
    final loaded = courses.result;
    if (loaded == null || !context.mounted) return;

    final mission = CourseMissions.missionPageFor(
      CourseMissions.listed(loaded),
      room.activityId,
    );
    final list = WorkspaceNav.openAnalytics(
      GoRouterState.of(context).uri,
      subpage: ProgressIndicatorEnum.activities,
    );
    context.go(
      mission == null
          ? list
          : WorkspaceNav.openObjectiveDetail(
              Uri.parse(list),
              mission.missionId,
              courseId: mission.courseId,
            ),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    // The save lands while the end card is on screen.
    stream: room.client.onRoomState.stream.where(
      (update) =>
          update.roomId == room.id &&
          update.state.type == PangeaEventTypes.activityRole,
    ),
    builder: (context, _) {
      if (!room.hasArchivedActivity) return const SizedBox.shrink();

      final l10n = L10n.of(context);
      final page = l10n.learningObjectives;
      // The whole line is the one control; the page's name in it is drawn as
      // the link.
      final parts = l10n.activitySavedTo(page).split(page);
      final scheme = Theme.of(context).colorScheme;
      // A quiet foot to the card, under the feedback, so the card's text
      // doesn't stack into one block.
      return TextButton(
        onPressed: () => _openLearningObjectives(context),
        child: Text.rich(
          TextSpan(
            style: Theme.of(context).textTheme.labelMedium,
            children: [
              for (final (index, part) in parts.indexed) ...[
                if (index > 0)
                  TextSpan(
                    text: page,
                    style: TextStyle(
                      color: scheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                TextSpan(
                  text: part,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          textAlign: TextAlign.center,
        ),
      );
    },
  );
}
