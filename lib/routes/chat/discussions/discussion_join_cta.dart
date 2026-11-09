import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_discovery.dart';
import 'package:fluffychat/features/discussions/discussion_room_repo.dart';
import 'package:fluffychat/features/discussions/discussion_standing.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A discussion start page's call to action (#9647): how many classmates are
/// in the room the learner would join, and one Join button.
///
/// The count is the server's own placement, re-read while the page stays
/// open so it follows rooms filling. Joining places the learner by the rooms
/// as they are at the tap, never by the count.
///
/// A page opened without a course asks each of the learner's courses for
/// its count until one that lists the discussion answers; rooms are per
/// course, so Join places the learner in that course's room.
class DiscussionJoinCta extends StatefulWidget {
  final Room? course;
  final String activityId;
  final ActivityPlanModel? activity;

  const DiscussionJoinCta({
    super.key,
    required this.course,
    required this.activityId,
    required this.activity,
  });

  @override
  State<DiscussionJoinCta> createState() => _DiscussionJoinCtaState();
}

class _DiscussionJoinCtaState extends State<DiscussionJoinCta> {
  static const Duration _refreshInterval = Duration(seconds: 5);

  /// The course whose room Join places the learner in; null until found.
  Room? _course;

  /// Null until read, and while a read fails: the page then shows no count.
  int? _students;

  Timer? _refreshTimer;

  /// A Join is on its way; a second tap waits for it.
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _course = widget.course;
    if (_course == null) {
      _findCourse();
    } else {
      _refresh();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Asks each joined course in turn. A failed read moves on to the next
  /// course; when none answered "mine" and one failed, the whole search is
  /// tried again after [_refreshInterval], so one timeout never leaves Join
  /// off. Only every course answering "not listed" means none lists it.
  Future<void> _findCourse() async {
    final client = Matrix.of(context).client;
    var failed = false;
    for (final course in client.joinedCourseSpaces) {
      final result = await DiscussionRoomRepo.previewStudents(
        client,
        courseId: course.id,
        activityId: widget.activityId,
      );
      if (!mounted) return;
      if (result.isError) {
        failed = true;
        continue;
      }
      final students = result.asValue!.value;
      if (students == null) continue;
      setState(() {
        _course = course;
        _students = students;
      });
      _scheduleRefresh();
      return;
    }
    if (failed) {
      _refreshTimer = Timer(_refreshInterval, _findCourse);
      return;
    }
    _reportNoOwningCourse();
  }

  /// Each read is scheduled after the last one answers, so reads never
  /// overlap.
  Future<void> _refresh() async {
    final course = _course!;
    final result = await DiscussionRoomRepo.previewStudents(
      course.client,
      courseId: course.id,
      activityId: widget.activityId,
    );
    if (!mounted) return;
    final students = result.asValue?.value;
    setState(() => _students = students);
    if (result.isValue && students == null) {
      _reportNoOwningCourse();
      return;
    }
    _scheduleRefresh();
  }

  void _scheduleRefresh() =>
      _refreshTimer = Timer(_refreshInterval, () => _refresh());

  /// The learner was shown a discussion none of their courses lists: they
  /// cannot join it.
  void _reportNoOwningCourse() => ErrorHandler.logErrorOnce(
    key: 'discussion_without_owning_course',
    e: StateError('No joined course lists the discussion'),
    data: {'activityId': widget.activityId},
  );

  Future<void> _join() async {
    final course = _course;
    if (course == null || _joining) return;
    setState(() => _joining = true);
    try {
      final roomId =
          course.client
              .discussionStandingFor(widget.activityId, courseId: course.id)
              .room
              ?.id ??
          await _placeInRoom(course);
      if (roomId == null || !mounted) return;
      NavigationUtil.goToSpaceRoute(roomId, [], context);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  /// The repo reports a failure, so the dialog only waits; the learner is
  /// told here.
  Future<String?> _placeInRoom(Room course) async {
    final placed = await showFutureLoadingDialog(
      context: context,
      future: () => DiscussionRoomRepo.join(
        course.client,
        courseId: course.id,
        activityId: widget.activityId,
        // The version the page shows, pinned like a roleplay launch pins it.
        versionId: widget.activity?.versionId,
      ),
    );
    final result = placed.asValue?.value;
    final error = result?.asError?.error;
    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toLocalizedString(context))));
    }
    return result?.asValue?.value;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final students = _students;
    final status = students == null
        ? null
        : students > 0
        ? l10n.discussionClassmatesInRoom(students)
        : l10n.discussionStartIt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8.0,
      children: [
        if (status != null)
          Text(
            status,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ActivitySessionCTAButton(
          l10n.joinTheDiscussion,
          _course == null || _joining ? null : _join,
          icon: ActivityMode.discussion.icon,
        ),
      ],
    );
  }
}
