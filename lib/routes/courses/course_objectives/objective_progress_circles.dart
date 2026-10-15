import 'package:flutter/material.dart';

import 'package:fluffychat/routes/courses/course_objectives/objective_circle.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section_scroll_arrow.dart';

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
  /// show (#9420).
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
/// order, each inside a gold ring of its XP toward its star: a gold star for
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
  static const double ringWidth = 3.5;
  static const double pointerHeight = 9.0;
  static const double labelHeight = 18.0;
  static const double classLabelHeight = 16.0;
  static const double _spacing = 8.0;

  /// The strip above the circles holding the "Class location" label and its
  /// pointer.
  static const double classLocationHeight = classLabelHeight + pointerHeight;

  /// The row's height with [showSelectedLabel] and [reserveClassLocation] on.
  static const double labelledHeight =
      classLocationHeight + diameter + pointerHeight + labelHeight;

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
                  ObjectiveCircle(
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
