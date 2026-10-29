import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/central_courses/central_course_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// Offers a learner in no course their language's central course: Join, or a
/// private course of their own on its plan. It can't be dismissed, so the
/// learner ends up in a course either way (joining-courses.instructions.md §
/// The central course).
class CentralCourseOfferDialog extends StatelessWidget {
  final Client client;
  final PublicCoursesChunk central;

  /// The learner's target language, as a code and as they read its name.
  final String language;
  final String languageName;

  const CentralCourseOfferDialog({
    super.key,
    required this.client,
    required this.central,
    required this.language,
    required this.languageName,
  });

  Future<void> _join(BuildContext context) =>
      _settle(context, () => client.joinCourse(central.room.roomId));

  /// A quest that doesn't load gives a course with no plan, which a later
  /// app open repairs.
  Future<void> _makeOwnCourse(BuildContext context) => _settle(
    context,
    () async => client.createOwnCourse(
      language: language,
      plan: await QuestPlansRepo.get(central.courseId),
    ),
  );

  /// A failure shows its error and leaves the offer open to try again.
  Future<void> _settle(
    BuildContext context,
    Future<String> Function() choose,
  ) async {
    final roomId = (await showFutureLoadingDialog(
      context: context,
      future: choose,
    )).result;
    if (roomId == null || !context.mounted) return;
    Navigator.of(context).pop();
    // The router's own location: GoRouterState is not reachable from a dialog.
    final router = FluffyChatApp.router;
    router.go(
      WorkspaceNav.openCourse(
        router.routeInformationProvider.value.uri,
        roomId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog.adaptive(
      title: Text(l10n.centralCourseOfferTitle(central.room.name ?? '')),
      content: Text(l10n.centralCourseOfferBody(languageName)),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => _makeOwnCourse(context),
          child: Text(l10n.makeMyOwnCourseInstead),
        ),
        AdaptiveDialogAction(
          onPressed: () => _join(context),
          autofocus: true,
          child: Text(l10n.join),
        ),
      ],
    );
  }
}
