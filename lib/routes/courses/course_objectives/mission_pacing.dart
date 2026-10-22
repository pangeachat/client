import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/quests/mission_due_date.dart';
import 'package:fluffychat/widgets/expandable_text.dart';

/// A Mission's soft due date from the course's own copy (content-studio), as
/// a muted chip. Shared by the full course plan's Mission headers and the
/// course page's Mission card (#9559), so the date reads the same in both.
/// The date stays after it passes; nothing is blocked or marked.
class MissionDueChip extends StatelessWidget {
  final DateTime dueAt;
  final String? timeZone;

  const MissionDueChip({required this.dueAt, this.timeZone, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(6.0, 2.0, 8.0, 2.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 4.0),
                child: Icon(
                  Icons.event,
                  size: 14.0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextSpan(text: missionDueLabel(context, dueAt, timeZone)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The teacher's note for a Mission, muted with a notes icon and clamped
/// behind its own "Show more" so a long one doesn't push what follows down.
/// Inset so its icon lines up with [MissionDueChip]'s.
class MissionNoteLine extends StatelessWidget {
  final String note;

  const MissionNoteLine({required this.note, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.0),
            child: Icon(
              Icons.notes,
              size: 14.0,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4.0),
          Expanded(
            child: ExpandableText(
              note,
              maxLines: FluffyThemes.isColumnMode(context) ? 2 : 3,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
