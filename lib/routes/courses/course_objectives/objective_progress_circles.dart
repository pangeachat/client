import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section_scroll_arrow.dart';
import 'package:fluffychat/routes/world/world_map_pins_manager.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Where one Mission stands in the plan, for its circle.
enum ObjectiveCircleState { complete, current, later }

/// One Mission's circle: its number, its statement (as the tooltip), its
/// state, and how full its XP ring is.
class ObjectiveCircleData {
  final int index;
  final String statement;
  final ObjectiveCircleState state;

  /// The Mission's XP over its threshold, 0..1, drawn as the gold ring around
  /// the circle. A later Mission can already have some, from an activity it
  /// shares with another Mission.
  final double progress;

  /// The Mission on show in the course page's Mission card — marked by a
  /// pointer under the circle, apart from the state's fill, since a learner
  /// can pick a complete or a later Mission to look at.
  final bool selected;

  /// Where the teacher's due dates put the class: marked by a quieter
  /// pointer above the circle, labelled "Class location".
  final bool classLocation;

  /// A coursemate pinged a session of this Mission that is still open to
  /// join — a bell on the circle, since the map shows only the Mission on
  /// show (#9420 prototype).
  final bool pinged;

  const ObjectiveCircleData({
    required this.index,
    required this.statement,
    required this.state,
    this.progress = 0.0,
    this.selected = false,
    this.classLocation = false,
    this.pinged = false,
  });
}

/// The course's Missions as one horizontal row of numbered circles, in plan
/// order, each inside a gold ring of its XP toward its star: a green check for
/// a complete Mission, a tint on the current one, a plain number for the rest
/// (drawn a little lighter), and a pointer under the one the Mission card
/// shows. The row never wraps: it scrolls, with the activity row's arrows over
/// whichever end it can still move toward, each tap moving it one circle. It
/// opens scrolled so the picked circle is in view.
class ObjectiveProgressCircles extends StatefulWidget {
  final List<ObjectiveCircleData> items;

  /// Tapping a circle, with its 1-based index; null draws the circles inert.
  final void Function(int index)? onTap;

  /// Name the picked Mission ("Mission 3") under its pointer — for the
  /// collapsed course header and peek, where no Mission card below says it.
  final bool showSelectedLabel;

  /// Keep the "Class location" strip above the circles even when no circle
  /// carries it, so a fixed-height host ([labelledHeight]) never shifts.
  final bool reserveClassLocation;

  static const double diameter = 40.0;
  static const double _ringWidth = 3.5;
  static const double _pointerHeight = 9.0;
  static const double _labelHeight = 18.0;
  static const double _classLabelHeight = 16.0;
  static const double _spacing = 8.0;

  /// The strip above the circles holding the "Class location" label and its
  /// pointer.
  static const double classLocationHeight = _classLabelHeight + _pointerHeight;

  /// The row's height with [showSelectedLabel] and [reserveClassLocation] on.
  static const double labelledHeight =
      classLocationHeight + diameter + _pointerHeight + _labelHeight;

  const ObjectiveProgressCircles({
    required this.items,
    this.onTap,
    this.showSelectedLabel = false,
    this.reserveClassLocation = false,
    super.key,
  });

  @override
  State<ObjectiveProgressCircles> createState() =>
      _ObjectiveProgressCirclesState();
}

class _ObjectiveProgressCirclesState extends State<ObjectiveProgressCircles> {
  final ScrollController _controller = ScrollController();
  bool _canBack = false;
  bool _canForward = false;
  int? _revealedIndex;

  static const double _step =
      ObjectiveProgressCircles.diameter + ObjectiveProgressCircles._spacing;

  bool get _hasClassStrip =>
      widget.reserveClassLocation ||
      widget.items.any((item) => item.classLocation);

  double get _labelInset =>
      widget.showSelectedLabel || _hasClassStrip ? 22.0 : 0.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncArrows() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final back = position.pixels > position.minScrollExtent + 0.5;
    final forward = position.pixels < position.maxScrollExtent - 0.5;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  /// Once per pick, bring the picked circle into view (a cold open on
  /// Mission 9 shouldn't hide it off the end).
  void _revealSelected() {
    final selected = widget.items.indexWhere((item) => item.selected);
    if (selected < 0 || selected == _revealedIndex) return;
    _revealedIndex = selected;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final left = _labelInset + selected * _step;
      final right = left + ObjectiveProgressCircles.diameter;
      final viewport = position.viewportDimension;
      double? target;
      if (left < position.pixels) {
        target = left;
      } else if (right > position.pixels + viewport) {
        target = right - viewport;
      }
      if (target != null) {
        _controller.jumpTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
      _syncArrows();
    });
  }

  void _scrollBy(int circles) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // Snap to circle boundaries so each press moves exactly one circle.
    final current = (position.pixels / _step).round();
    final target = ((current + circles) * _step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    _revealSelected();
    final onTap = widget.onTap;
    final classStrip = _hasClassStrip;
    final circleTop = classStrip
        ? ObjectiveProgressCircles.classLocationHeight
        : 0.0;
    // The activity row's arrows and behaviour (ActivityCarousel): each arrow
    // floats over its edge of the row and exists only while the row can still
    // move that way — never a hidden-but-present arrow, whose semantics node
    // would swallow taps meant for the circle beneath it on web.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncArrows();
            });
            return false;
          },
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            // Room at either end for the picked Mission's label, which is
            // wider than its circle.
            padding: EdgeInsets.symmetric(horizontal: _labelInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: ObjectiveProgressCircles._spacing,
              children: [
                for (final item in widget.items)
                  _ObjectiveCircle(
                    item: item,
                    count: widget.items.length,
                    showSelectedLabel: widget.showSelectedLabel,
                    showClassStrip: classStrip,
                    onTap: onTap == null ? null : () => onTap(item.index),
                  ),
              ],
            ),
          ),
        ),
        if (_canBack)
          Positioned(
            left: 0,
            top: circleTop,
            height: ObjectiveProgressCircles.diameter,
            child: ObjectiveSectionScrollArrow(
              direction: ArrowDirection.back,
              onTap: () => _scrollBy(-1),
            ),
          ),
        if (_canForward)
          Positioned(
            right: 0,
            top: circleTop,
            height: ObjectiveProgressCircles.diameter,
            child: ObjectiveSectionScrollArrow(
              direction: ArrowDirection.forward,
              onTap: () => _scrollBy(1),
            ),
          ),
      ],
    );
  }
}

class _ObjectiveCircle extends StatelessWidget {
  final ObjectiveCircleData item;
  final int count;
  final bool showSelectedLabel;
  final bool showClassStrip;
  final VoidCallback? onTap;

  const _ObjectiveCircle({
    required this.item,
    required this.count,
    required this.showSelectedLabel,
    required this.showClassStrip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final complete = item.state == ObjectiveCircleState.complete;
    final (fill, ink, label) = switch (item.state) {
      // A finished Mission is its star (#9420 prototype): gold, the same
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
        2 * (ObjectiveProgressCircles._ringWidth + 1.5);
    Widget circle = MissionXpRing(
      size: ObjectiveProgressCircles.diameter,
      strokeWidth: ObjectiveProgressCircles._ringWidth,
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
      height: ObjectiveProgressCircles._pointerHeight,
      child: item.selected
          ? CustomPaint(
              painter: _PointerPainter(color: theme.colorScheme.primary),
            )
          : null,
    );
    // The class's place, from the teacher's due dates: a quiet grey bubble
    // whose pointer turns down onto the circle — a pill like the "Mission N"
    // tags, but muted, so it reads as the class's mark, not the learner's.
    final classFill = theme.colorScheme.outlineVariant;
    final classInk = theme.colorScheme.onSurfaceVariant;
    final classMarker = SizedBox(
      width: ObjectiveProgressCircles.diameter,
      height: ObjectiveProgressCircles.classLocationHeight,
      child: item.classLocation
          ? Column(
              children: [
                SizedBox(
                  height: ObjectiveProgressCircles._classLabelHeight,
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
                  height: ObjectiveProgressCircles._pointerHeight,
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
                  height: ObjectiveProgressCircles._labelHeight,
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

/// The circles for a course, read from its shared resolver: Missions with an
/// activity in plan order, complete when their XP is at the threshold, the
/// anchor pointed at (the first Mission before progress resolves, like the
/// course page's section). Nothing while the plan is still loading.
class CourseObjectiveCircles extends StatelessWidget {
  final QuestObjectivesLoader objectivesProvider;
  final void Function(int index)? onTap;

  /// The Mission the course page shows, to point at; null points at the
  /// current one.
  final String? selectedMissionId;

  /// Passed through to [ObjectiveProgressCircles.showSelectedLabel].
  final bool showSelectedLabel;

  const CourseObjectiveCircles({
    required this.objectivesProvider,
    this.onTap,
    this.selectedMissionId,
    this.showSelectedLabel = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      objectivesProvider.questLoader,
      objectivesProvider.progression,
      WorldMapPinsManager.pingedActivityIds,
      DiscoveredSessionsCache.instance,
    ]),
    builder: (context, _) {
      final groups = objectivesProvider.filteredObjectiveGroups;
      final courseId = objectivesProvider.courseId;
      final course = courseId == null
          ? null
          : objectivesProvider.client.getRoomById(courseId);
      final currentId = objectivesProvider.currentObjectiveGroup?.objective.id;
      final shownId =
          objectivesProvider.objectiveGroup(selectedMissionId)?.objective.id ??
          currentId;
      final pinged = WorldMapPinsManager.pingedActivityIds.value;
      // A Mission other than the one on show with a pinged session still
      // open to join.
      bool hasPing(QuestObjectiveGroup group) =>
          course != null &&
          group.objective.id != shownId &&
          group.activities.any(
            (a) =>
                pinged.contains(a.activityId) &&
                courseActivityLiveState(course, a.activityId).state ==
                    ActivityPinState.joinable,
          );
      final classIndex = classLocationIndex(groups, DateTime.now());
      return ObjectiveProgressCircles(
        onTap: onTap,
        showSelectedLabel: showSelectedLabel,
        reserveClassLocation: showSelectedLabel,
        items: [
          for (var i = 0; i < groups.length; i++)
            ObjectiveCircleData(
              index: i + 1,
              statement: groups[i].objective.objective,
              selected: groups[i].objective.id == shownId,
              classLocation: i == classIndex,
              pinged: hasPing(groups[i]),
              progress:
                  objectivesProvider
                      .missionProgress(groups[i].objective.id)
                      ?.fraction ??
                  0.0,
              state:
                  objectivesProvider
                          .missionProgress(groups[i].objective.id)
                          ?.satisfied ==
                      true
                  ? ObjectiveCircleState.complete
                  : groups[i].objective.id == currentId
                  ? ObjectiveCircleState.current
                  : ObjectiveCircleState.later,
            ),
        ],
      );
    },
  );
}

/// Where the class is, by the teacher's due dates (#9420 prototype): the
/// first Mission in plan order still due at [now], else — every dated Mission
/// past — the last dated one. Null when the course sets no due dates.
int? classLocationIndex(List<QuestObjectiveGroup> groups, DateTime now) {
  int? lastDated;
  for (var i = 0; i < groups.length; i++) {
    final dueAt = groups[i].pacing?.dueAt;
    if (dueAt == null) continue;
    if (dueAt.isAfter(now)) return i;
    lastDated = i;
  }
  return lastDated;
}
