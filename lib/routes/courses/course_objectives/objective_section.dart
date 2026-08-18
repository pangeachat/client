import 'package:flutter/material.dart';

import 'package:flutter_svg/svg.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section_scroll_arrow.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

class ObjectiveSection extends StatefulWidget {
  final QuestObjectiveGroup group;
  final void Function(QuestActivity) onTap;
  final int Function(String) userStarsByActivity;
  final bool Function(String activityId)? hasCompletedActivity;

  /// The activity's live map-pin state (colour fill + banner) and "Open (N)"
  /// count, resolved by the parent which holds the course room. See
  /// [CourseObjectivesList].
  final ({
    ActivityPinState? state,
    int openSessions,
    List<String> participants,
    int openSlots,
  })
  Function(String activityId)
  liveStateByActivity;

  /// Course members available to fill activity roles (start-page invite math),
  /// or null until it loads. An activity needing more than this — and not
  /// already live — renders dimmed. See [CourseObjectivesList].
  final int? availableParticipants;
  final double spacing;
  final double? cardWidth;
  final double? cardHeight;

  /// The Mission's rollup from the shared resolver, or null when there is
  /// nothing to show (preview, or the rollup hasn't resolved yet).
  final MissionProgress? progress;

  /// The activity a course ping pointed at, when it lives in this section —
  /// its card gets the bell badge (#8319). Null everywhere else.
  final String? pingedActivityId;

  /// Tapping the Mission header collapses/expands its activity carousel
  /// (expanded by default). On for the full course plan (#8357); off for the
  /// course page's Up-next highlight and plan previews.
  final bool collapsible;

  /// Accent the header as the learner's "Up next" Mission — the shared
  /// resolver's anchor (#8357).
  final bool isUpNext;

  const ObjectiveSection({
    super.key,
    required this.group,
    required this.onTap,
    required this.userStarsByActivity,
    required this.hasCompletedActivity,
    required this.liveStateByActivity,
    required this.availableParticipants,
    required this.progress,
    this.pingedActivityId,
    this.collapsible = false,
    this.isUpNext = false,
    this.spacing = 16.0,
    this.cardWidth,
    this.cardHeight,
  });

  @override
  ObjectiveSectionState createState() => ObjectiveSectionState();
}

class ObjectiveSectionState extends State<ObjectiveSection> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showBackArrowNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _showForwardArrowNotifier = ValueNotifier(false);

  /// Missions render expanded; a [ObjectiveSection.collapsible] header tap
  /// folds the carousel to just the header row (#8357).
  bool _collapsed = false;

  bool get _isColumnMode => FluffyThemes.isColumnMode(context);
  double get _cardWidth => widget.cardWidth ?? (_isColumnMode ? 160.0 : 120.0);
  double get _cardHeight =>
      widget.cardHeight ?? (_isColumnMode ? 280.0 : 225.0);

  double get _cardScrollDistance => _cardWidth + widget.spacing;

  bool get _showBackArrow {
    try {
      return _scrollController.hasClients && _scrollController.offset > 0;
    } catch (_) {}
    return false;
  }

  bool get _showForwardArrow {
    try {
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        if (position.hasContentDimensions) {
          return position.pixels < position.maxScrollExtent;
        }
      }
    } catch (_) {}
    return false;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateArrowVisibility);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateArrowVisibility);
    _scrollController.dispose();
    _showBackArrowNotifier.dispose();
    _showForwardArrowNotifier.dispose();
    super.dispose();
  }

  void _updateArrowVisibility() {
    _showBackArrowNotifier.value = _showBackArrow;
    _showForwardArrowNotifier.value = _showForwardArrow;
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

    final statement = Text(
      widget.group.objective.objective,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: widget.isUpNext ? theme.colorScheme.primary : null,
      ),
    );
    final starFraction = widget.progress == null
        ? null
        : Semantics(
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
                ExcludeSemantics(
                  child: Text(
                    // Raw stars over the satisfaction threshold — surplus
                    // shows (12/7); only the quest header caps.
                    '${widget.progress!.stars}/${widget.progress!.threshold}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
    final collapseChevron = widget.collapsible
        ? AnimatedRotation(
            turns: _collapsed ? -0.25 : 0,
            duration: FluffyThemes.animationDuration,
            child: const Icon(Icons.expand_more, size: 20.0),
          )
        : null;

    final activities = widget.group.activities;
    activities.sort(
      (a, b) => a.plan.req.numberOfParticipants.compareTo(
        b.plan.req.numberOfParticipants,
      ),
    );

    return Semantics(
      label: L10n.of(context).objective,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Objective header, left to right: the collapse chevron (full plan
          // only), the Mission's earned/threshold stars when the shared
          // rollup is in, then the can-do statement. The Up-next Mission's
          // statement wears the accent.
          Semantics(
            // Without an explicit button container the toggle flattens into
            // the section's group semantics and is unreachable on web, where
            // clicks route through the semantics DOM.
            button: widget.collapsible,
            container: widget.collapsible,
            expanded: widget.collapsible ? !_collapsed : null,
            child: InkWell(
              onTap: widget.collapsible
                  ? () => setState(() => _collapsed = !_collapsed)
                  : null,
              borderRadius: BorderRadius.circular(8.0),
              // The star fraction leads and the collapse chevron trails. In
              // column mode the row has room for the statement between them;
              // on narrow screens the statement drops to its own full-width
              // row so a wrapped statement never shares lines with the icons.
              child: _isColumnMode
                  ? Row(
                      children: [
                        if (starFraction != null) ...[
                          starFraction,
                          const SizedBox(width: 8.0),
                        ],
                        Expanded(child: statement),
                        if (collapseChevron != null) ...[
                          const SizedBox(width: 4.0),
                          collapseChevron,
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (collapseChevron != null || starFraction != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Row(
                              children: [
                                ?starFraction,
                                const Spacer(),
                                ?collapseChevron,
                              ],
                            ),
                          ),
                        statement,
                      ],
                    ),
            ),
          ),
          // No per-Mission progress bar — only the overall course has a bar (in
          // the header). A Mission shows just its star count above (#7597).
          if (!_collapsed) const SizedBox(height: 12.0),
          // The activities that satisfy this objective.
          if (!_collapsed)
            SizedBox(
              height: _cardHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  NotificationListener<ScrollMetricsNotification>(
                    onNotification: (ScrollMetricsNotification notification) {
                      _updateArrowVisibility();
                      return true;
                    },
                    child: ListView.separated(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      itemCount: activities.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(width: widget.spacing),
                      padding: EdgeInsets.symmetric(
                        vertical: widget.spacing / 2.0,
                      ),
                      itemBuilder: (context, i) {
                        final ref = activities[i];
                        final complete =
                            (widget.hasCompletedActivity?.call(
                              ref.activityId,
                            ) ??
                            false);
                        final starsEarned = widget.userStarsByActivity(
                          ref.activityId,
                        );
                        final liveState = widget.liveStateByActivity(
                          ref.activityId,
                        );
                        // Dim activities that can't be started yet: the course lacks
                        // enough members for their roles (tapping opens the start page's
                        // Invite CTA). A live (ongoing/joinable) session already filled
                        // its seats so it never dims
                        final available = widget.availableParticipants;
                        final canStart =
                            available == null ||
                            complete ||
                            liveState.state != null ||
                            ref.plan.req.numberOfParticipants <= available;
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
                              // The card's state banner peeks past its top-left
                              // corner, so this wrapping Stack must not clip it.
                              clipBehavior: Clip.hardEdge,
                              children: [
                                Opacity(
                                  opacity: canStart ? 1.0 : 0.5,
                                  child: ActivitySuggestionCard(
                                    activity: ref.plan,
                                    width: _cardWidth,
                                    height: _cardHeight,
                                    fontSize: _isColumnMode ? 16.0 : 12.0,
                                    fontSizeSmall: _isColumnMode ? 12.0 : 8.0,
                                    iconSize: _isColumnMode ? 12.0 : 8.0,
                                    starsEarned: starsEarned,
                                    pinState: complete ? null : liveState.state,
                                    openSessions: liveState.openSessions,
                                    participants: liveState.participants,
                                    openSlots: liveState.openSlots,
                                  ),
                                ),
                                if (complete)
                                  Container(
                                    width: _cardWidth,
                                    height: _cardHeight,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12.0),
                                      color: theme.colorScheme.surface
                                          .withAlpha(180),
                                    ),
                                    child: Center(
                                      child: SvgPicture.asset(
                                        'assets/pangea/check.svg',
                                        width: 48.0,
                                        height: 48.0,
                                      ),
                                    ),
                                  ),
                                // The course-ping bell, top-left so it shares
                                // the banner's row without covering it (#8319).
                                if (ref.activityId == widget.pingedActivityId)
                                  const Positioned(
                                    top: 8.0,
                                    left: 6.0,
                                    child: CoursePingBadge(),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // No BlockSemantics here (#8011): blocking is tree-order, not
                  // geometric, so it would drop every card's semantics node in the
                  // row — and on Flutter web with the semantics tree on (staging
                  // forces it via ENABLE_SEMANTICS) a node-less card cannot be
                  // clicked at all. Worse, the section's labeled container then
                  // merges with the only surviving node (the arrow) into one
                  // row-sized button, so every card click scrolls. Each arrow
                  // instead defends its own strip with an opaque semantics hit
                  // test — see ObjectiveSectionScrollArrow.
                  // The scroll arrows overlay the ends of the ListView. Only mount
                  // the arrow that is currently usable — a hidden-but-present arrow
                  // (IgnorePointer / opacity 0) still leaves a semantics node at the
                  // edge that, on Flutter web, lets a tap fall through to the card
                  // beneath it.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _showBackArrowNotifier,
                      builder: (context, showArrow, _) => showArrow
                          ? ObjectiveSectionScrollArrow(
                              direction: ArrowDirection.back,
                              onTap: () => _scrollByArrow(ArrowDirection.back),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _showForwardArrowNotifier,
                      builder: (context, showArrow, _) => showArrow
                          ? ObjectiveSectionScrollArrow(
                              direction: ArrowDirection.forward,
                              onTap: () =>
                                  _scrollByArrow(ArrowDirection.forward),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
