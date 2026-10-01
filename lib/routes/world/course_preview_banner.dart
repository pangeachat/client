import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/map_context.dart';

/// The "Course preview" pill floating over the map while the add-course flow
/// previews a course (#7826) — the one label saying the map is scoped to that
/// course. Tapping it fires the same camera request as the other focus
/// buttons, re-running the course bounds-fit after the learner pans away.
class CoursePreviewBanner extends StatelessWidget {
  const CoursePreviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2.0,
      borderRadius: BorderRadius.circular(20.0),
      child: Tooltip(
        message: L10n.of(context).focusOnMap,
        child: InkWell(
          borderRadius: BorderRadius.circular(20.0),
          onTap: MapCameraFocusRequests.request,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8.0,
              children: [
                Icon(
                  Icons.travel_explore,
                  size: 18.0,
                  color: theme.colorScheme.primary,
                ),
                Text(
                  L10n.of(context).coursePreview,
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
