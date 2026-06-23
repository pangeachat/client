import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/world/activity_course_resolver.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Activity detail, rendered as a capped detail panel over the persistent map
/// (world_v2). Two entry points share it: in-place via the `?activity=<id>`
/// query param over another route (e.g. a course), and the first-class
/// `/<activityId>` route. Either way it renders the activity session start
/// flow — it never remounts a second map. Closing drops the `?activity` param
/// (returning to the underlying route) or, on the standalone route, returns to
/// the world map.
///
/// The parent course is the active course space when one is selected;
/// otherwise the first joined course whose plan includes the activity (or none
/// — you no longer need a course to play).
class ActivityDetailPanel extends StatefulWidget {
  final String activityId;

  /// The selected course space, if the detail was opened from within a course.
  final String? parentSpaceId;

  /// An existing session room to join (the `?roomid=` of the canonical open),
  /// when re-entering an in-progress session rather than starting fresh.
  final String? roomId;

  /// Begin launching a session immediately (the first-class `?launch=true`
  /// flow) instead of showing the not-started start screen.
  final bool launch;

  const ActivityDetailPanel({
    super.key,
    required this.activityId,
    this.parentSpaceId,
    this.roomId,
    this.launch = false,
  });

  @override
  State<ActivityDetailPanel> createState() => _ActivityDetailPanelState();
}

class _ActivityDetailPanelState extends State<ActivityDetailPanel> {
  String? _parentId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveParent();
  }

  @override
  void didUpdateWidget(covariant ActivityDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activityId != widget.activityId ||
        oldWidget.parentSpaceId != widget.parentSpaceId) {
      setState(() {
        _loading = true;
        _parentId = null;
      });
      _resolveParent();
    }
  }

  Future<void> _resolveParent() async {
    if (widget.parentSpaceId != null) {
      setState(() {
        _parentId = widget.parentSpaceId;
        _loading = false;
      });
      return;
    }
    // No course selected (e.g. opened from World): find a joined course that
    // includes this activity. Null L2 skips the language filter.
    try {
      final spaces = await ActivityCourseResolver.matchingCourseSpaces(
        Matrix.of(context).client,
        widget.activityId,
        null,
      );
      if (!mounted) return;
      setState(() {
        _parentId = spaces.firstOrNull?.id;
        _loading = false;
      });
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'activityId': widget.activityId},
      );
      if (mounted) setState(() => _loading = false);
    }
  }

  void _close() {
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    // In-place (`?activity=`): drop the overlay params (activity/roomid/launch)
    // to return to the underlying route, preserving everything else (e.g.
    // `tab`). Standalone (`/<activityId>`): no overlay param, so go to World.
    if (!uri.queryParameters.containsKey('activity')) {
      context.go('/');
      return;
    }
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('activity')
      ..remove('roomid')
      ..remove('launch');
    context.go(
      params.isEmpty
          ? uri.path
          : uri.replace(queryParameters: params).toString(),
    );
  }

  /// Back returns toward the course: pop history if there's something to pop,
  /// otherwise just drop the `?activity` param. Either way the course context
  /// stays — this never leaves for the standalone activity page.
  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Once resolved, render the activity — with or without a parent course.
    // You no longer need to be in a course to do an activity, so a null parent
    // is fine; the session launches standalone. The activity view brings its
    // own AppBar (the back/X nav row when embedded), so it renders directly.
    if (!_loading) {
      return ActivitySessionStartPage(
        activityId: widget.activityId,
        parentId: _parentId,
        roomId: widget.roomId,
        launch: widget.launch,
      );
    }

    // While resolving, a minimal close row over a spinner. ONE control only,
    // matching the loaded start view's rule (activity_sessions_start_view.dart):
    // a back-arrow when the activity is still course-scoped (`?m=course:` over
    // `?activity=`), so it returns toward the course; an X otherwise (a map pin /
    // standalone), so it dismisses to the map. Rendering both ← and X here was a
    // redundant pair that did the same thing in the pin case (#7115).
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    final embedded = uri.queryParameters['activity'] != null;
    final courseScoped =
        uri.queryParameters['m']?.startsWith('course:') ?? false;
    final showBack = embedded && courseScoped;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ActivityLoadingHeader(
              showBack: showBack,
              onBack: _back,
              onClose: _close,
            ),
            const Expanded(
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The single close control shown over the activity-resolve spinner. Exactly ONE
/// control, mirroring the loaded start view's rule (activity_sessions_start_view
/// and routing.instructions.md → one close affordance per panel): a back-arrow
/// when [showBack] (the activity is still course-scoped, so it returns toward the
/// course), an X otherwise (a map pin / standalone, so it dismisses to the map).
/// Rendering both ← and X here was a redundant pair doing the same thing (#7115).
class ActivityLoadingHeader extends StatelessWidget {
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onClose;

  const ActivityLoadingHeader({
    super.key,
    required this.showBack,
    required this.onBack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
    child: Align(
      alignment: Alignment.centerLeft,
      child: showBack
          ? IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            )
          : IconButton(
              tooltip: L10n.of(context).close,
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
    ),
  );
}
