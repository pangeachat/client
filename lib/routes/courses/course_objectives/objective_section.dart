import 'package:flutter/material.dart';

import 'package:flutter_svg/svg.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section_scroll_arrow.dart';

class ObjectiveSection extends StatefulWidget {
  final int index;
  final QuestObjectiveGroup group;
  final void Function(QuestActivity) onTap;
  final int Function(String) userStarsByActivity;
  final bool Function(String activityId)? hasCompletedActivity;
  final double spacing;
  final double? cardWidth;
  final double? cardHeight;

  /// The Mission's rollup from the shared resolver, or null when there is
  /// nothing to show (preview, or the rollup hasn't resolved yet).
  final MissionProgress? progress;

  const ObjectiveSection({
    super.key,
    required this.index,
    required this.group,
    required this.onTap,
    required this.userStarsByActivity,
    required this.hasCompletedActivity,
    required this.progress,
    this.spacing = 16.0,
    this.cardWidth,
    this.cardHeight,
  });

  @override
  ObjectiveSectionState createState() => ObjectiveSectionState();
}

class ObjectiveSectionState extends State<ObjectiveSection> {
  final ScrollController _scrollController = ScrollController();

  bool get _isColumnMode => FluffyThemes.isColumnMode(context);
  double get _cardWidth => widget.cardWidth ?? (_isColumnMode ? 160.0 : 120.0);
  double get _cardHeight =>
      widget.cardHeight ?? (_isColumnMode ? 280.0 : 200.0);

  double get _cardScrollDistance => _cardWidth + widget.spacing;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollByArrow(ArrowDirection direction) {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final maxExtent = _scrollController.position.maxScrollExtent;

    final delta = direction == ArrowDirection.forward
        ? _cardScrollDistance
        : -_cardScrollDistance;

    final targetOffset = (offset + delta).clamp(0.0, maxExtent);

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activities = widget.group.activities;
    activities.sort(
      (a, b) => a.plan.req.numberOfParticipants.compareTo(
        b.plan.req.numberOfParticipants,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Objective header: placeholder icon + the can-do statement, with the
        // Mission's earned/threshold stars when the shared rollup is in.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ObjectivePlaceholderIcon(index: widget.index),
            const SizedBox(width: 12.0),
            Expanded(
              child: Text(
                widget.group.objective.objective,
                style: const TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (widget.progress != null) ...[
              const SizedBox(width: 8.0),
              Semantics(
                label: L10n.of(context).starsEarnedOfTotal(
                  widget.progress!.stars,
                  widget.progress!.threshold,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      size: 18.0,
                      color: AppConfig.goldByTheme(context),
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      // Raw stars over the satisfaction threshold — surplus
                      // shows (12/7); only the quest header caps.
                      '${widget.progress!.stars}/${widget.progress!.threshold}',
                      style: const TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        // No per-Mission progress bar — only the overall course has a bar (in
        // the header). A Mission shows just its star count above (#7597).
        const SizedBox(height: 12.0),
        // The activities that satisfy this objective.
        SizedBox(
          height: _cardHeight,
          child: Stack(
            children: [
              ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: activities.length,
                separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
                padding: EdgeInsets.symmetric(vertical: widget.spacing / 2.0),
                itemBuilder: (context, i) {
                  final ref = activities[i];
                  final complete =
                      (widget.hasCompletedActivity?.call(ref.activityId) ??
                      false);
                  final starsEarned = widget.userStarsByActivity(
                    ref.activityId,
                  );
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      // In a preview (no room), open the activity as a standalone
                      // world object (`/<activityId>`). In a joined course, open it
                      // as the focused detail over the map: DROP the `left=course`
                      // card (so it isn't left blank beside the activity) but KEEP
                      // the `?m=course:` filter. That surviving course scope is what
                      // marks this plan as the card's child: its close is a back-arrow
                      // that reopens the card (a pin-opened plan drops the scope and so
                      // closes with an X). The map stays course-scoped and zooms to
                      // this activity (`mapFocusFor` → `ActivityFocus`). See
                      // routing.instructions.md.
                      onTap: () => widget.onTap(ref),
                      child: Stack(
                        children: [
                          ActivitySuggestionCard(
                            activity: ref.plan,
                            width: _cardWidth,
                            height: _cardHeight,
                            fontSize: _isColumnMode ? 16.0 : 12.0,
                            fontSizeSmall: _isColumnMode ? 12.0 : 8.0,
                            iconSize: _isColumnMode ? 12.0 : 8.0,
                            starsEarned: starsEarned,
                          ),
                          if (complete)
                            Container(
                              width: _cardWidth,
                              height: _cardHeight,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.0),
                                color: theme.colorScheme.surface.withAlpha(180),
                              ),
                              child: Center(
                                child: SvgPicture.asset(
                                  'assets/pangea/check.svg',
                                  width: 48.0,
                                  height: 48.0,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ListenableBuilder(
                listenable: _scrollController,
                builder: (context, _) {
                  bool showArrow = false;
                  try {
                    showArrow =
                        _scrollController.hasClients &&
                        _scrollController.offset > 0;
                  } catch (_) {}

                  return Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !showArrow,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        offset: showArrow ? Offset.zero : const Offset(-1, 0),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: showArrow ? 1 : 0,
                          child: ObjectiveSectionScrollArrow(
                            direction: ArrowDirection.back,
                            onTap: () => _scrollByArrow(ArrowDirection.back),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              ListenableBuilder(
                listenable: _scrollController,
                builder: (context, _) {
                  bool showArrow = false;
                  try {
                    showArrow =
                        _scrollController.hasClients &&
                        _scrollController.position.pixels <
                            _scrollController.position.maxScrollExtent;
                  } catch (_) {}

                  return Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !showArrow,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        offset: showArrow ? Offset.zero : const Offset(1, 0),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: showArrow ? 1 : 0,
                          child: ObjectiveSectionScrollArrow(
                            direction: ArrowDirection.forward,
                            onTap: () => _scrollByArrow(ArrowDirection.forward),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Placeholder objective icon until real learning-objective icons exist.
/// Deterministic color per position so the list reads as distinct items.
class _ObjectivePlaceholderIcon extends StatelessWidget {
  final int index;
  const _ObjectivePlaceholderIcon({required this.index});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ];
    return Container(
      width: 40.0,
      height: 40.0,
      decoration: BoxDecoration(
        color: palette[index % palette.length],
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Icon(Icons.flag_outlined, size: 22.0, color: scheme.onSurface),
    );
  }
}
