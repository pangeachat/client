import 'package:flutter/material.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/routes/world/course_context_bar.dart';
import 'package:fluffychat/routes/world/panel_card.dart';

/// Docks the [CourseContextBar] directly above an open activity plan, sharing
/// that panel's left edge (#8816).
///
/// The course is the plan's contextual parent, so the way back to it belongs
/// beside the plan rather than across the map, where the bar's map-slot
/// position put it — a diagonal trip to the far side of the screen to reach
/// the thing the plan sits inside. Tapping the bar there closes the activity
/// and opens the course card at full panel width in this same slot: the tap
/// runs [CourseContextBar]'s ordinary open, and `WorkspaceNav.openCourseTab`
/// already drops an open `activity` token (#7385), so the destination falls
/// out of the existing grammar rather than needing a navigation of its own.
///
/// A **pass-through for every other case**: another panel type, a narrow
/// screen (an activity plan is full-screen there and keeps its vertical
/// space), or no `?c=` context to name. The decision lives here rather than at
/// the shell's call site so the left-column loop stays one expression per
/// panel. See world-map.instructions.md → The course context bar.
class ActivityCourseDock extends StatelessWidget {
  final PanelToken token;
  final bool isColumnMode;

  /// The `?c=` course context, or null when the workspace is unscoped.
  final String? spaceId;

  final Widget child;

  const ActivityCourseDock({
    required this.token,
    required this.isColumnMode,
    required this.spaceId,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final courseSpaceId = spaceId;
    if (!isColumnMode ||
        courseSpaceId == null ||
        token.type != PanelTypesEnum.activity) {
      return child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // The card margin's horizontal inset, so the bar and the panel below
          // it share a left edge exactly; the panel's own top margin then
          // supplies the gap between them.
          padding: EdgeInsets.only(
            left: PanelCard.margin.left,
            right: PanelCard.margin.right,
            top: PanelCard.margin.top,
          ),
          child: CourseContextBar(spaceId: courseSpaceId),
        ),
        Expanded(child: child),
      ],
    );
  }
}
