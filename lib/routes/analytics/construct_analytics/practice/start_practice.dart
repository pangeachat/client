import 'package:flutter/widgets.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/end_practice_session_dialog.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';

/// Open practice of [type] as the right-column practice panel, scoped to
/// [missionId]'s target vocabulary when given (#9438). One session at a time:
/// a tap on the session already live simply reopens it; any other unfinished
/// session is confirmed and ended first. The one tap site for every Practice
/// control that can start a scoped session — the course page's tile, the
/// Learning Objectives page's buttons, the course-complete card — so they
/// cannot disagree on the replace rule (routing.instructions.md § Practice is
/// a persistent background session).
Future<void> startPractice(
  BuildContext context,
  ConstructTypeEnum type, {
  String? missionId,
}) async {
  final holder = PracticeSessionHolder.instance;
  final resumes = holder.liveType == type && holder.liveMissionId == missionId;
  if (holder.hasUnfinishedSession && !resumes) {
    final ended = await EndPracticeSessionDialog.confirmAndEnd(
      context,
      type: holder.liveType!,
    );
    if (!ended) return;
  }
  if (!context.mounted) return;
  context.go(
    WorkspaceNav.openPractice(
      GoRouterState.of(context).uri,
      type,
      missionId: missionId,
    ),
  );
}
