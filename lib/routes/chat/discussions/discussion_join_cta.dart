import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/features/discussions/discussion_room_service.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A discussion start page's call to action (#9647): how many classmates are
/// in the room the learner would join, and one Join button. A discussion has
/// nothing to choose, so it has no other buttons.
///
/// The count is the server's own placement, asked when the page opens and
/// every [_refresh] while it stays open, so it follows rooms filling. Joining
/// places the learner by the rooms as they are at the tap, never by the count.
///
/// A discussion belongs to one course. A page opened without one (a learner in
/// two courses sharing its Missions, which the page cannot tell apart) finds
/// it by asking each of the learner's courses: only the discussion's own
/// course answers rather than "not a discussion of this course".
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
  static const _refresh = Duration(seconds: 5);

  DiscussionPlacement? _placement;
  Room? _course;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refresh, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final course = _course ?? widget.course;
      if (course != null) {
        final placement = await DiscussionRoomService.preview(
          course.client,
          courseId: course.id,
          activityId: widget.activityId,
        );
        if (mounted) {
          setState(() {
            _course = course;
            _placement = placement;
          });
        }
        return;
      }
      await _findCourse();
    } catch (e, s) {
      // The page still offers Join; it just shows no count.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'activityId': widget.activityId},
        level: SentryLevel.warning,
      );
    }
  }

  /// Asks each of the learner's courses for the discussion; the first that
  /// owns it becomes the page's course.
  Future<void> _findCourse() async {
    final client = Matrix.of(context).client;
    final courses = client.rooms.where(
      (room) =>
          room.isSpace &&
          room.membership == Membership.join &&
          room.coursePlan != null,
    );
    for (final course in courses) {
      try {
        final placement = await DiscussionRoomService.preview(
          client,
          courseId: course.id,
          activityId: widget.activityId,
        );
        if (!mounted) return;
        setState(() {
          _course = course;
          _placement = placement;
        });
        return;
      } on PangeaHttpException catch (e) {
        // silent-ok: 404 is "not a discussion of this course", an answer
        if (e.statusCode == 404) continue;
        rethrow;
      }
    }
    // None of the learner's courses owns it: they cannot join it.
    ErrorHandler.logError(
      e: StateError('No joined course owns the discussion'),
      data: {'activityId': widget.activityId},
      level: SentryLevel.warning,
    );
  }

  Future<void> _join() async {
    final course = _course;
    if (course == null) return;
    final roomId = await DiscussionRoomService.open(
      context,
      course: course,
      activityId: widget.activityId,
      imageUrl: widget.activity?.discussionImageUrl,
    );
    if (roomId == null || !mounted) return;
    NavigationUtil.goToSpaceRoute(roomId, [], context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final placement = _placement;
    final status = placement == null
        ? null
        : placement.students > 0
        ? l10n.discussionClassmatesInRoom(placement.students)
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
          _course == null ? null : _join,
          icon: ActivityMode.discussion.icon,
        ),
      ],
    );
  }
}
