import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_progress_circles.dart';

class ObjectiveCircle extends StatelessWidget {
  final ObjectiveCircleData item;
  final int count;
  final bool showSelectedLabel;
  final bool showClassStrip;
  final VoidCallback? onTap;

  const ObjectiveCircle({
    required this.item,
    required this.count,
    required this.showSelectedLabel,
    required this.showClassStrip,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final complete = item.state == ObjectiveCircleState.complete;
    final (fill, ink, label) = switch (item.state) {
      // A finished Mission is its star (#9420): gold, the same
      // mark the Mission card and the Learning Objectives list fill.
      ObjectiveCircleState.complete => (
        theme.pangea.goldContainer,
        theme.pangea.goldGraphic,
        l10n.objectiveCircleComplete(item.index),
      ),
      ObjectiveCircleState.current => (
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
        l10n.objectiveCircleUpNext(item.index),
      ),
      ObjectiveCircleState.later => (
        theme.colorScheme.surface,
        theme.colorScheme.onSurfaceVariant,
        l10n.missionNofM(item.index, count),
      ),
    };
    const inner =
        ObjectiveProgressCircles.diameter -
        2 * (ObjectiveProgressCircles.ringWidth + 1.5);
    Widget circle = MissionXpRing(
      size: ObjectiveProgressCircles.diameter,
      strokeWidth: ObjectiveProgressCircles.ringWidth,
      trackColor: theme.colorScheme.outlineVariant,
      gapColor: theme.colorScheme.surface,
      segments: [
        MissionXpRingSegment(
          fraction: complete ? 1.0 : item.progress,
          color: theme.pangea.goldGraphic,
        ),
      ],
      child: Container(
        width: inner,
        height: inner,
        decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
        alignment: Alignment.center,
        child: complete
            ? Icon(Icons.star_rounded, size: 20.0, color: ink)
            : Text(
                '${item.index}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
    if (item.state == ObjectiveCircleState.later) {
      circle = Opacity(opacity: 0.8, child: circle);
    }
    if (item.pinged) {
      // Inside the circle's own box (top-right, over the ring): the row's
      // scroll view clips anything that sticks out.
      circle = Stack(
        children: [
          circle,
          const Positioned(
            top: 0,
            right: 0,
            child: CoursePingBadge(size: 16.0),
          ),
        ],
      );
    }
    // The pointer ties the circle to the Mission card under the row; every
    // circle keeps its slot so the row doesn't shift when the pick moves.
    final pointer = SizedBox(
      width: ObjectiveProgressCircles.diameter,
      height: ObjectiveProgressCircles.pointerHeight,
      child: item.selected
          ? CustomPaint(
              painter: _PointerPainter(color: theme.colorScheme.primary),
            )
          : null,
    );
    // The class's place, from the teacher's due dates: a quiet grey bubble
    // whose pointer turns down onto the circle — muted beside the Mission
    // pill, so it reads as the class's mark, not the learner's.
    final classFill = theme.colorScheme.outlineVariant;
    final classInk = theme.colorScheme.onSurfaceVariant;
    final classMarker = SizedBox(
      width: ObjectiveProgressCircles.diameter,
      height: ObjectiveProgressCircles.classLocationHeight,
      child: item.classLocation
          ? Column(
              children: [
                SizedBox(
                  height: ObjectiveProgressCircles.classLabelHeight,
                  child: OverflowBox(
                    maxWidth: 120.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7.0),
                      decoration: BoxDecoration(
                        color: classFill,
                        borderRadius: BorderRadius.circular(999.0),
                      ),
                      // Hug the text: an aligned Container would stretch
                      // to the OverflowBox's full width.
                      child: Center(
                        widthFactor: 1.0,
                        child: Text(
                          l10n.classLocation,
                          maxLines: 1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: classInk,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: ObjectiveProgressCircles.diameter,
                  height: ObjectiveProgressCircles.pointerHeight,
                  child: CustomPaint(
                    painter: _PointerPainter(color: classFill, down: true),
                  ),
                ),
              ],
            )
          : null,
    );
    final tappable = onTap == null
        ? circle
        : InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: circle,
          );
    // The state is in the accessible name and the statement in the tooltip,
    // so neither the colour nor the number is the only carrier.
    return Semantics(
      label:
          '${[label, if (item.classLocation) l10n.classLocation, if (item.pinged) l10n.pingedLabel].join(', ')}: ${item.statement}',
      selected: item.selected,
      button: onTap != null,
      // The InkWell below is excluded, so the tap is published here.
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: item.statement,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showClassStrip) classMarker,
              tappable,
              pointer,
              if (showSelectedLabel)
                SizedBox(
                  width: ObjectiveProgressCircles.diameter,
                  height: ObjectiveProgressCircles.labelHeight,
                  child: item.selected
                      ? OverflowBox(
                          maxWidth: 120.0,
                          child: Text(
                            l10n.missionNumber(item.index),
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A triangle pointing at the circle: up from below (the tip at the top
/// centre), or [down] from above (the tip at the bottom centre).
class _PointerPainter extends CustomPainter {
  final Color color;
  final bool down;

  _PointerPainter({required this.color, this.down = false});

  @override
  void paint(Canvas canvas, Size size) {
    const halfWidth = 8.0;
    final tip = down ? size.height - 1.0 : 1.0;
    final base = down ? 0.0 : size.height;
    final path = Path()
      ..moveTo(size.width / 2, tip)
      ..lineTo(size.width / 2 + halfWidth, base)
      ..lineTo(size.width / 2 - halfWidth, base)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PointerPainter old) =>
      old.color != color || old.down != down;
}
