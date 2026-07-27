import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';

/// The floating goal-header card shared by the live session and the start/
/// summary pages. It crossfades between its [collapsed] face (star summary +
/// active goal) and its [expanded] face (goal list + any actions) as it grows.
/// When [isComplete] the whole card turns gold.
///
/// Toggling is owned by the faces themselves — only their top row opens/closes
/// the menu.
class ActivityGoalHeaderCard extends StatelessWidget {
  final Widget collapsed;
  final Widget expanded;
  final bool showDropdown;
  final bool isComplete;

  const ActivityGoalHeaderCard({
    super.key,
    required this.collapsed,
    required this.expanded,
    required this.showDropdown,
    this.isComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = AppConfig.goldByTheme(context);

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.columnWidth * 1.5,
          ),
          child: AnimatedContainer(
            duration: FluffyThemes.animationDuration,
            curve: Curves.easeInOut,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: isComplete
                  ? Color.alphaBlend(
                      gold.withAlpha(40),
                      theme.colorScheme.surface,
                    )
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              border: Border.all(
                color: isComplete ? gold : theme.dividerColor,
                width: isComplete ? 2.0 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(30),
                  blurRadius: 8.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                children: [
                  // Behind the content: swallow taps that land on the card's own
                  // footprint but miss a real control (the padding between the
                  // top row and subtitle, the gaps between goal rows, the border).
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: const SizedBox.expand(),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: FluffyThemes.animationDuration,
                    sizeCurve: Curves.easeInOut,
                    firstCurve: Curves.easeInOut,
                    secondCurve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    crossFadeState: showDropdown
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: SizedBox(
                      width: double.infinity,
                      child: collapsed,
                    ),
                    secondChild: SizedBox(
                      width: double.infinity,
                      child: expanded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
