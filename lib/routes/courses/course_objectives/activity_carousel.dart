import 'package:flutter/material.dart';

import 'package:flutter_svg/svg.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section_scroll_arrow.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// A horizontal row of activity cards, in the order it is given them. Shared by
/// the Missions of the full course plan ([ObjectiveSection], which orders by
/// party size) and the course page's Activities row (ordered by the
/// Priority matrix), so both draw the same card, dimming, completion overlay
/// and ping bell.
class ActivityCarousel extends StatefulWidget {
  /// The activities to draw, already in display order — this widget never
  /// reorders them.
  final List<QuestActivity> activities;

  final void Function(QuestActivity) onTap;
  final int Function(String) userStarsByActivity;
  final bool Function(String activityId)? hasCompletedActivity;

  /// The activity's live map-pin state (colour fill + banner) and "Open (N)"
  /// count, resolved by the parent which holds the course room.
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
  /// already live — renders dimmed.
  final int? availableParticipants;

  /// The activity a course ping pointed at, when it is drawn in this row — its
  /// card gets the bell badge (#8319). Null everywhere else.
  final String? pingedActivityId;

  final double spacing;
  final double? cardWidth;
  final double? cardHeight;

  const ActivityCarousel({
    super.key,
    required this.activities,
    required this.onTap,
    required this.userStarsByActivity,
    required this.hasCompletedActivity,
    required this.liveStateByActivity,
    required this.availableParticipants,
    this.pingedActivityId,
    this.spacing = 16.0,
    this.cardWidth,
    this.cardHeight,
  });

  @override
  State<ActivityCarousel> createState() => _ActivityCarouselState();
}

class _ActivityCarouselState extends State<ActivityCarousel> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showBackArrowNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _showForwardArrowNotifier = ValueNotifier(false);

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
    return SizedBox(
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
              itemCount: widget.activities.length,
              separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
              padding: EdgeInsets.symmetric(vertical: widget.spacing / 2.0),
              itemBuilder: (context, i) {
                final ref = widget.activities[i];
                final complete =
                    (widget.hasCompletedActivity?.call(ref.activityId) ??
                    false);
                final starsEarned = widget.userStarsByActivity(ref.activityId);
                final liveState = widget.liveStateByActivity(ref.activityId);
                // A completed activity drops its state colouring for
                // the check overlay, so the card and its ping bell
                // both read it from here.
                final pinState = complete ? null : liveState.state;
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
                            pinState: pinState,
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
                        // The course-ping bell, top-left so it shares
                        // the banner's row without covering it (#8319),
                        // in the card's own state hue (#8481).
                        if (ref.activityId == widget.pingedActivityId)
                          Positioned(
                            top: 8.0,
                            left: 6.0,
                            child: CoursePingBadge(pinState: pinState),
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
                      onTap: () => _scrollByArrow(ArrowDirection.forward),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
