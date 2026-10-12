import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_plans_repo.dart';

/// Builds with the image a course shows: its own [avatar] when it has one,
/// otherwise its quest's cover (course-plans.instructions.md § Course avatar).
/// [builder] gets null while the cover loads and when there is none, so the
/// letter avatar shows in both cases.
///
/// Every surface that renders a course's image goes through this widget, so a
/// room created before its quest had a cover shows the cover everywhere at
/// once, and an admin-set avatar wins everywhere at once.
class CourseImageBuilder extends StatefulWidget {
  final Uri? avatar;

  /// The course's quest-plan id. Null for a room that is not a course, which
  /// then builds with [avatar] alone.
  final String? courseId;

  final Widget Function(BuildContext context, Uri? image) builder;

  const CourseImageBuilder({
    required this.avatar,
    required this.courseId,
    required this.builder,
    super.key,
  });

  /// A room's image: its `m.room.avatar`, else the cover of the quest in its
  /// `pangea.course_plan`.
  CourseImageBuilder.room({
    required Room room,
    required this.builder,
    super.key,
  }) : avatar = room.avatar,
       courseId = room.coursePlan?.uuid;

  @override
  State<CourseImageBuilder> createState() => _CourseImageBuilderState();
}

class _CourseImageBuilderState extends State<CourseImageBuilder> {
  /// Requested once per mount and per course id — not per build — so a room
  /// that rebuilds on every sync never repeats a failed read.
  Future<Uri?>? _cover;

  @override
  void initState() {
    super.initState();
    _requestCover();
  }

  @override
  void didUpdateWidget(CourseImageBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId ||
        (oldWidget.avatar != null) != (widget.avatar != null)) {
      _requestCover();
    }
  }

  void _requestCover() {
    final courseId = widget.courseId;
    _cover = widget.avatar == null && courseId != null
        ? QuestPlansRepo.cover(courseId)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final avatar = widget.avatar;
    final courseId = widget.courseId;
    if (avatar != null || courseId == null) {
      return widget.builder(context, avatar);
    }
    return FutureBuilder<Uri?>(
      future: _cover,
      initialData: QuestPlansRepo.cachedCover(courseId),
      builder: (context, snapshot) => widget.builder(context, snapshot.data),
    );
  }
}
