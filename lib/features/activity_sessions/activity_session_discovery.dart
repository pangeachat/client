import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';

/// Local inputs to activity-session discovery. The discovery itself — "which
/// session rooms exist under my courses" — is answered server-side by the
/// space-scoped activity_session_previews module
/// (loadActivitySessionPreviews), which replaced the client-side hierarchy
/// walk that missed sessions in courses with more rooms than one hierarchy
/// page (#7982). What stays client-side is knowing WHICH spaces to ask about,
/// and which invited rooms need their own preview. See
/// world-map.instructions.md ("Discovering joinable sessions").
extension ActivitySessionDiscovery on Client {
  /// The learner's joined course spaces (a joined space carrying a course plan)
  /// — the spaces input to the activity_session_previews read.
  List<Room> get joinedCourseSpaces => rooms
      .where(
        (r) =>
            r.isSpace &&
            r.membership == Membership.join &&
            r.coursePlan != null,
      )
      .toList();

  /// Session rooms the learner is **invited** to. They sit in `client.rooms`,
  /// but an invite's stripped state carries no `pangea.activity_roles`, so any
  /// seat/participant data read locally is wrong (#7488) — callers must
  /// room_preview these ids, never trust the local room. (The space-scoped
  /// module can't see them either: an invite may come from outside any shared
  /// course.)
  Set<String> get invitedActivitySessionRoomIds => rooms
      .where((r) => r.membership == Membership.invite && r.activityId != null)
      .map((r) => r.id)
      .toSet();
}
