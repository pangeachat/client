import 'package:flutter/material.dart';

import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class CourseInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  final double? fontSize;
  final double? iconSize;
  final EdgeInsets? padding;

  const CourseInfoChip({
    super.key,
    required this.icon,
    required this.text,
    required this.fontSize,
    required this.iconSize,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Row(
        spacing: 4.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize),
          Text(text, style: TextStyle(fontSize: fontSize)),
        ],
      ),
    );
  }
}

/// The course's language / level / module chips, read from the quest outline.
///
/// The module count is the Missions the learner will actually *see* — the same
/// `objectiveGroupsWithActivities` filter the course panel lists through — so a
/// Mission with no activities can no longer be counted here while being hidden
/// there (#7976). That rules out the plan-level count
/// (`CoursePlanModel.topicIds.length`), which is the quest's whole Mission
/// sequence, activity-less ones included.
class CourseInfoChips extends StatefulWidget {
  final String courseId;

  /// The course space this quest is being shown in, where there is one. Admits
  /// the owner's private activities (membership verified server-side) and keys
  /// into the same outline-cache row the course panel and the joined-course
  /// progression cache already built — so the chips normally cost no round trip
  /// and can't count a different activity set than the panel renders.
  final String? courseRoomId;

  final double? fontSize;
  final double? iconSize;
  final EdgeInsets? padding;

  const CourseInfoChips(
    this.courseId, {
    super.key,
    this.courseRoomId,
    this.fontSize,
    this.iconSize,
    this.padding,
  });

  @override
  State<CourseInfoChips> createState() => CourseInfoChipsState();
}

class CourseInfoChipsState extends State<CourseInfoChips> {
  QuestOutline? _outline;

  /// Guards against a superseded load landing last when the widget is recycled
  /// onto another course mid-flight.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadOutline();
  }

  @override
  void didUpdateWidget(covariant CourseInfoChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId ||
        oldWidget.courseRoomId != widget.courseRoomId) {
      _loadOutline();
    }
  }

  Future<void> _loadOutline() async {
    _loadGeneration++;
    final loadGen = _loadGeneration;
    // Clear stale chips when recycled onto another course; on first load there
    // is nothing to clear and setState would be premature.
    if (_outline != null) setState(() => _outline = null);

    final result = await QuestRepo.outline(
      widget.courseId,
      courseRoomId: widget.courseRoomId,
    );
    if (!mounted || loadGen != _loadGeneration) return;
    // A failed read is already logged by the repo; the chips just stay hidden.
    setState(() => _outline = result.result);
  }

  @override
  Widget build(BuildContext context) {
    final outline = _outline;
    if (outline == null) {
      return const SizedBox.shrink();
    }

    // Deliberately unpinned: pinning fails open (`effectivePinnedActivityIds`),
    // so it can never empty a Mission and never changes this count.
    final moduleCount = objectiveGroupsWithActivities(outline.groups).length;

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: [
        Semantics(
          label: outline.quest.targetLanguageFullDisplay,
          child: ExcludeSemantics(
            child: CourseInfoChip(
              icon: Icons.language,
              text: outline.quest.targetLanguageDisplay,
              fontSize: widget.fontSize,
              iconSize: widget.iconSize,
              padding: widget.padding,
            ),
          ),
        ),
        CourseInfoChip(
          icon: Icons.school,
          text: outline.quest.cefrLevel.title(context),
          fontSize: widget.fontSize,
          iconSize: widget.iconSize,
          padding: widget.padding,
        ),
        CourseInfoChip(
          icon: Icons.location_on,
          text: L10n.of(context).numModules(moduleCount),
          fontSize: widget.fontSize,
          iconSize: widget.iconSize,
          padding: widget.padding,
        ),
      ],
    );
  }
}
