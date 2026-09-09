import 'package:flutter/material.dart';

import 'package:badges/badges.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/pangea/common/widgets/pass_through_tooltip.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';
import '../config/themes.dart';

class NaviRailItem extends StatelessWidget {
  final String toolTip;
  final bool isSelected;
  final void Function() onTap;
  final Widget icon;
  final Widget? selectedIcon;
  final bool Function(Room)? unreadBadgeFilter;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final double naviRailWidth;

  /// When set, the item wears an explicit gold [FocusRingTapTarget] ring of
  /// this shape while focused, instead of relying on InkWell's
  /// behind-the-child focus highlight — which an opaque [icon] (the course
  /// avatar banner) swallows to imperceptibility (#8724). Pass the icon's own
  /// silhouette (the rail passes MapBorder) so the ring traces the control
  /// rather than floating over it. Null keeps the plain InkWell: the section
  /// glyphs are transparent, so the ink highlight already shows through them.
  final OutlinedBorder? focusRingShape;

  /// Registers this item as a tutorial spotlight target. Null for items no
  /// tutorial points at.
  final String? tutorialTargetId;

  /// This item's id in the enclosing [RovingFocusGroup]: the rail is one Tab
  /// stop, with the arrow keys moving between its items (#8877). Null for an
  /// item outside a group.
  final String? rovingId;

  const NaviRailItem({
    required this.toolTip,
    required this.isSelected,
    required this.onTap,
    required this.icon,
    this.selectedIcon,
    this.unreadBadgeFilter,
    required this.naviRailWidth,
    this.backgroundColor,
    this.borderRadius,
    this.focusRingShape,
    this.tutorialTargetId,
    this.rovingId,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = this.borderRadius ?? BorderRadius.circular(10.0);

    final isColumnMode = FluffyThemes.isColumnMode(context);
    final height = naviRailWidth - (isColumnMode ? 16.0 : 12.0);

    final icon = isSelected ? selectedIcon ?? this.icon : this.icon;
    final rovingId = this.rovingId;
    final focusNode = rovingId == null
        ? null
        : RovingFocusGroup.nodeOf(context, rovingId);

    return TutorialTarget(
      targetId: tutorialTargetId,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: HoverBuilder(
            builder: (context, hovered) {
              // No background fill here: WorkspaceDock already paints the
              // rail-wide surface. Per-item opaque fills leave hairline seams
              // between items at fractional device pixel ratios (Windows
              // 125%/150% display scaling) — see #7032.
              return SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Positioned(
                      top: 8,
                      bottom: 8,
                      left: 0,
                      child: AnimatedContainer(
                        width: isSelected
                            ? FluffyThemes.isColumnMode(context)
                                  ? 8
                                  : 4
                            : 0,
                        duration: FluffyThemes.animationDuration,
                        curve: FluffyThemes.animationCurve,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(90),
                            bottomRight: Radius.circular(90),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: AnimatedScale(
                        scale: hovered ? 1.1 : 1.0,
                        duration: FluffyThemes.animationDuration,
                        curve: FluffyThemes.animationCurve,
                        child: MergeSemantics(
                          // The same isSelected that drives the visual highlight
                          // (indicator bar + fill) is announced to assistive
                          // tech, so visible and spoken state cannot drift
                          // (#8743).
                          child: Semantics(
                            selected: isSelected,
                            child: UnreadRoomsBadge(
                              filter: unreadBadgeFilter ?? (_) => false,
                              badgePosition: BadgePosition.topEnd(
                                top: 1,
                                end: isColumnMode ? 8 : 4,
                              ),
                              child: Container(
                                alignment: Alignment.center,
                                margin: EdgeInsets.symmetric(
                                  horizontal: isColumnMode ? 16.0 : 12.0,
                                  vertical: isColumnMode ? 8.0 : 6.0,
                                ),
                                // Material + InkWell give the item real Material
                                // interaction states — hover overlay, pressed
                                // ripple, focus. The InkWell's own borderRadius
                                // bounds the ripple; no Material clip, so angular
                                // icons (e.g. the Pangea mark) aren't cut.
                                child: Material(
                                  color:
                                      backgroundColor ??
                                      (isSelected
                                          ? theme.colorScheme.primaryContainer
                                          : theme
                                                .colorScheme
                                                .surfaceContainerHigh),
                                  borderRadius: borderRadius,
                                  // The label takes no pointer input, so one
                                  // that has already shown can't stall the
                                  // scroll once the rail carries it under the
                                  // cursor (#8857). The delay keeps items
                                  // sweeping under the cursor mid-scroll from
                                  // each spawning one (#8215).
                                  child: PassThroughTooltip(
                                    message: toolTip,
                                    waitDuration: const Duration(
                                      milliseconds: 500,
                                    ),
                                    child: focusRingShape != null
                                        ? FocusRingTapTarget(
                                            onTap: onTap,
                                            focusNode: focusNode,
                                            shape: focusRingShape!,
                                            child: icon,
                                          )
                                        : InkWell(
                                            borderRadius: borderRadius,
                                            onTap: onTap,
                                            focusNode: focusNode,
                                            child: icon,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
