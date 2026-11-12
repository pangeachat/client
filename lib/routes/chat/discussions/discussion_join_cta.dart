import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_discovery.dart';
import 'package:fluffychat/features/discussions/discussion_join_exceptions.dart';
import 'package:fluffychat/features/discussions/discussion_preview.dart';
import 'package:fluffychat/features/discussions/discussion_room_repo.dart';
import 'package:fluffychat/features/discussions/discussion_standing.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A discussion start page's call to action (#9647): how many classmates are
/// in the room the learner would join, and one Join button.
///
/// The count is the server's own placement, re-read while the page is on
/// screen so it follows rooms filling: never while the app or the page is
/// hidden, and less often while the server is rate-limiting. Joining places
/// the learner by the rooms as they are at the tap, never by the count. A
/// learner removed from the course's room for it is told they can't join, and
/// nothing is re-read.
///
/// A page opened without a course looks for the course whose room Join
/// places the learner in: the course of the room they already hold a seat in,
/// else each of their courses in turn until one lists the discussion. It
/// looks again when their courses change.
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

class _DiscussionJoinCtaState extends State<DiscussionJoinCta>
    with WidgetsBindingObserver {
  static const Duration _refreshInterval = Duration(seconds: 5);

  /// The longest wait between reads while the server answers 429.
  static const Duration _maxBackoff = Duration(minutes: 1);

  /// The course whose room Join places the learner in; null until found.
  Room? _course;

  /// The last answer for [_course]; null until read, and while a read fails:
  /// the page then shows no count.
  DiscussionPreview? _preview;

  Timer? _refreshTimer;

  /// The wait before the next read: [_refreshInterval], doubled on each 429.
  Duration _interval = _refreshInterval;

  /// Bumped whenever the course or the activity changes, so a read still on
  /// its way for the old one is dropped.
  int _generation = 0;

  /// The joined courses the last search went through, so a change to them
  /// starts a new one.
  Set<String> _searchedCourseIds = const {};

  StreamSubscription? _syncSub;

  /// The app is in front and this page is on screen: reads run only then.
  bool _onScreen = true;

  /// This page is shown, not offstage behind another one.
  bool _pageShown = true;

  /// A read waits for the page to come back on screen.
  bool _readPending = false;

  /// A Join is on its way; a second tap waits for it.
  bool _joining = false;

  bool get _removed => _preview?.access == DiscussionAccess.removed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onScreen = _appResumed;
    _syncSub = Matrix.of(
      context,
    ).client.onSync.stream.listen((_) => _onCoursesMaybeChanged());
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageShown = TickerMode.valuesOf(context).enabled;
    _setOnScreen(_appResumed && _pageShown);
  }

  @override
  void didUpdateWidget(DiscussionJoinCta oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course?.id != widget.course?.id ||
        oldWidget.activityId != widget.activityId) {
      _start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _setOnScreen(state == AppLifecycleState.resumed && _pageShown);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool get _appResumed {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Back on screen, a read that was held runs at once.
  void _setOnScreen(bool onScreen) {
    if (onScreen == _onScreen) return;
    _onScreen = onScreen;
    if (!onScreen) {
      _refreshTimer?.cancel();
      _readPending = true;
      return;
    }
    if (_readPending) _read();
  }

  /// Forgets the previous course's answer and reads the current one.
  void _start() {
    _generation++;
    _refreshTimer?.cancel();
    _interval = _refreshInterval;
    _course = widget.course;
    _preview = null;
    _read();
  }

  /// A page without a course searches again when the learner's courses
  /// change: one they just joined may list the discussion, and the one found
  /// may have been left.
  void _onCoursesMaybeChanged() {
    if (!mounted || widget.course != null) return;
    final ids = _joinedCourseIds;
    if (const SetEquality<String>().equals(ids, _searchedCourseIds)) return;
    setState(_start);
  }

  Set<String> get _joinedCourseIds => {
    for (final course in Matrix.of(context).client.joinedCourseSpaces)
      course.id,
  };

  void _read() {
    if (!_onScreen) {
      _readPending = true;
      return;
    }
    _readPending = false;
    if (_course == null) {
      _findCourse();
    } else {
      _refresh();
    }
  }

  void _scheduleRead() {
    _refreshTimer?.cancel();
    if (!_onScreen) {
      _readPending = true;
      return;
    }
    _refreshTimer = Timer(_interval, _read);
  }

  /// The learner's courses, the one holding their seat in this discussion
  /// first: rooms are per course, so that course's Join reopens their room.
  List<Room> get _coursesToSearch {
    final client = Matrix.of(context).client;
    final seatCourseId = client
        .discussionStandingInAnyCourse(widget.activityId)
        .room
        ?.discussionCourseId;
    final courses = client.joinedCourseSpaces;
    return [
      ...courses.where((c) => c.id == seatCourseId),
      ...courses.where((c) => c.id != seatCourseId),
    ];
  }

  /// Asks each joined course in turn until one lists the discussion. A
  /// failed read moves on to the next course; when none answered "open" and
  /// one failed, the whole search is tried again later, so one timeout never
  /// leaves Join off. A course that removed the learner is the answer only
  /// when no other course lets them in.
  Future<void> _findCourse() async {
    final generation = _generation;
    final courses = _coursesToSearch;
    _searchedCourseIds = {for (final course in courses) course.id};
    var failed = false;
    Room? removedFrom;
    for (final course in courses) {
      final result = await DiscussionRoomRepo.previewStudents(
        course.client,
        courseId: course.id,
        activityId: widget.activityId,
      );
      if (!mounted || generation != _generation) return;
      final preview = result.asValue?.value;
      if (preview == null) {
        failed = true;
        _backOffOn(result);
        continue;
      }
      if (preview.access == DiscussionAccess.removed) {
        removedFrom ??= course;
        continue;
      }
      if (preview.access != DiscussionAccess.open) continue;
      _interval = _refreshInterval;
      setState(() {
        _course = course;
        _preview = preview;
      });
      _scheduleRead();
      return;
    }
    if (failed) {
      _scheduleRead();
      return;
    }
    if (removedFrom != null) {
      setState(() {
        _course = removedFrom;
        _preview = const DiscussionPreview.removed();
      });
      return;
    }
    _reportNoOwningCourse();
  }

  /// Each read is scheduled after the last one answers, so reads never
  /// overlap. Only an open discussion is read again: "not listed" and
  /// "removed" are answers that stand until the course changes.
  Future<void> _refresh() async {
    final generation = _generation;
    final course = _course!;
    final result = await DiscussionRoomRepo.previewStudents(
      course.client,
      courseId: course.id,
      activityId: widget.activityId,
    );
    if (!mounted || generation != _generation) return;
    final preview = result.asValue?.value;
    setState(() => _preview = preview);
    if (preview == null) {
      _backOffOn(result);
      _scheduleRead();
      return;
    }
    _interval = _refreshInterval;
    switch (preview.access) {
      case DiscussionAccess.open:
        _scheduleRead();
      case DiscussionAccess.notListed:
        _reportNoOwningCourse();
      case DiscussionAccess.removed:
        break;
    }
  }

  /// A rate-limited read waits as long as the server asks, else twice as
  /// long as the last wait, up to [_maxBackoff].
  void _backOffOn(Result<DiscussionPreview> result) {
    final error = result.asError?.error;
    if (error is! PangeaHttpException || error.statusCode != 429) return;
    final next = error.retryAfter ?? _interval * 2;
    _interval = next < _refreshInterval
        ? _refreshInterval
        : next > _maxBackoff
        ? _maxBackoff
        : next;
  }

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
  /// told here. A learner placed in a room that hasn't synced yet is told it
  /// is on its way, and the room opens once it lands while the page is open.
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
    if (error == null || !mounted) return result?.asValue?.value;
    if (error is DiscussionRemovedException) {
      _refreshTimer?.cancel();
      setState(() => _preview = const DiscussionPreview.removed());
      return null;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toLocalizedString(context))));
    if (error is! DiscussionRoomNotArrivedException) return null;
    await course.client.waitForRoomInSync(error.roomId, join: true);
    return error.roomId;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final statusStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_removed) {
      return Text(
        l10n.discussionRemoved,
        textAlign: TextAlign.center,
        style: statusStyle,
      );
    }
    final students = _preview?.students;
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
          Text(status, textAlign: TextAlign.center, style: statusStyle),
        ActivitySessionCTAButton(
          l10n.joinTheDiscussion,
          _course == null || _joining ? null : _join,
          icon: ActivityMode.discussion.icon,
        ),
      ],
    );
  }
}
