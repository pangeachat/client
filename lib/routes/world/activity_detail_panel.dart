import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/world/activity_course_resolver.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Activity detail, opened in-place over the persistent map via the
/// `?activity=<id>` query param (world_v2). It renders the activity session
/// start flow as a capped detail panel — it does NOT remount the map or leave
/// the current course; closing just drops the query param.
///
/// The parent course is the active course space when one is selected;
/// otherwise the first joined course whose plan includes the activity.
class ActivityDetailPanel extends StatefulWidget {
  final String activityId;

  /// The selected course space, if the detail was opened from within a course.
  final String? parentSpaceId;

  const ActivityDetailPanel({
    super.key,
    required this.activityId,
    this.parentSpaceId,
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
      ErrorHandler.logError(e: e, s: s, data: {'activityId': widget.activityId});
      if (mounted) setState(() => _loading = false);
    }
  }

  void _close() {
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('activity');
    context.go(
      params.isEmpty ? uri.path : uri.replace(queryParameters: params).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final closeButton = Positioned(
      top: 8,
      right: 8,
      child: IconButton.filledTonal(
        tooltip: L10n.of(context).close,
        icon: const Icon(Icons.close),
        onPressed: _close,
      ),
    );

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (_parentId == null) {
      // Activity isn't in a course the learner has joined.
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12.0,
            children: [
              const Icon(Icons.school_outlined, size: 40),
              Text(
                L10n.of(context).joinTheCourseToPlay,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    } else {
      body = ActivitySessionStartPage(
        activityId: widget.activityId,
        parentId: _parentId,
      );
    }

    return Scaffold(
      body: Stack(children: [body, closeButton]),
    );
  }
}
