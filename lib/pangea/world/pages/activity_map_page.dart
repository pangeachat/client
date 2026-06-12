import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/navigation/route_paths.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/course_activity_repo.dart';
import 'package:fluffychat/pangea/course_plans/course_activities/course_activity_translation_request.dart';
import 'package:fluffychat/pangea/course_settings/activity_suggestion_card.dart';
import 'package:fluffychat/pangea/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/pangea/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/pangea/world/activity_course_resolver.dart';
import 'package:fluffychat/pangea/world/widgets/world_map.dart';
import 'package:fluffychat/pangea/world/world_activities_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// First-class activity page: `/#/<activityId>`.
///
/// Shows the world map centered on the activity's location with a
/// thumbnail popup (image, title, completion check). Expanding embeds
/// the full [ActivitySessionStartPage] under the user's matching course
/// space; sessions created from there are shared into every matching
/// course space by [launchActivitySession].
class ActivityMapPage extends StatefulWidget {
  final String activityId;
  final bool launch;

  const ActivityMapPage({
    super.key,
    required this.activityId,
    this.launch = false,
  });

  @override
  State<ActivityMapPage> createState() => _ActivityMapPageState();
}

class _ActivityMapPageState extends State<ActivityMapPage> {
  final MapController _mapController = MapController();
  bool _loading = true;
  Object? _error;
  bool _expanded = false;

  ActivityPlanModel? _activity;
  LatLng? _center;
  String? _locationName;
  List<Room> _matchingSpaces = [];
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.launch;
    _load();
  }

  @override
  void didUpdateWidget(covariant ActivityMapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activityId != widget.activityId) {
      setState(() {
        _loading = true;
        _expanded = widget.launch;
        _activity = null;
        _center = null;
        _complete = false;
      });
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final l1 =
          MatrixState.pangeaController.userController.userL1Code ?? 'en';
      final activitiesResp = await CourseActivityRepo.get(
        TranslateActivityRequest(activityIds: [widget.activityId], l1: l1),
        widget.activityId,
      );
      final activity = activitiesResp.plans[widget.activityId];
      if (activity == null) {
        throw Exception('Activity not found: ${widget.activityId}');
      }

      final pins = await WorldActivitiesRepo.activityPins();
      final pin = pins.firstWhereOrNull(
        (p) => p.activityId == widget.activityId,
      );

      final client = Matrix.of(context).client;
      final matching = await ActivityCourseResolver.matchingCourseSpaces(
        client,
        widget.activityId,
        activity.req.targetLanguage,
      );

      bool complete = false;
      if (matching.isNotEmpty) {
        final roomIds = matching
            .expand((s) => s.spaceChildren.map((c) => c.roomId))
            .whereType<String>()
            .toSet()
            .toList();
        if (roomIds.isNotEmpty) {
          final summaries = await client.loadRoomSummaries(roomIds);
          complete = CourseInfoSummariesModel(
            summaries,
          ).hasCompletedActivity(client.userID!, widget.activityId);
        }
      }

      if (!mounted) return;
      setState(() {
        _activity = activity;
        _center = pin?.point;
        _locationName = pin?.locationName;
        _matchingSpaces = matching;
        _complete = complete;
        _loading = false;
      });
      if (pin != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _mapController.move(pin.point, 10),
        );
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'activityId': widget.activityId},
      );
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_expanded) {
      return Scaffold(
        body: Stack(
          children: [
            ActivitySessionStartPage(
              activityId: widget.activityId,
              parentId: _matchingSpaces.firstOrNull?.id,
              launch: widget.launch,
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: L10n.of(context).close,
                icon: const Icon(Icons.map_outlined),
                onPressed: () => setState(() => _expanded = false),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          WorldMap(
            controller: _mapController,
            initialCenter: _center,
            initialZoom: _center != null ? 10 : null,
          ),
          Center(
            child: _loading
                ? const CircularProgressIndicator.adaptive()
                : _error != null || _activity == null
                ? _ErrorPopup(activityId: widget.activityId)
                : _popup(theme),
          ),
        ],
      ),
    );
  }

  Widget _popup(ThemeData theme) {
    const cardWidth = 200.0;
    const cardHeight = 350.0;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260.0),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16.0),
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Stack(
              children: [
                ActivitySuggestionCard(
                  activity: _activity!,
                  width: cardWidth,
                  height: cardHeight,
                  fontSize: 20.0,
                  fontSizeSmall: 12.0,
                  iconSize: 12.0,
                ),
                if (_complete)
                  Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.0),
                      color: theme.colorScheme.surface.withAlpha(180),
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        "assets/pangea/check.svg",
                        width: 48.0,
                        height: 48.0,
                      ),
                    ),
                  ),
              ],
            ),
            if (_locationName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_pin,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(_locationName!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            const SizedBox(height: 12.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => context.go(PRoutes.world),
                  child: const Icon(Icons.close),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.open_in_full, size: 16),
                  label: Text(L10n.of(context).details),
                  onPressed: _matchingSpaces.isNotEmpty
                      ? () => setState(() => _expanded = true)
                      : () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Join the course for "${_activity!.title}" to play it!',
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPopup extends StatelessWidget {
  final String activityId;
  const _ErrorPopup({required this.activityId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16.0),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 8),
            Text('Activity not found', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go(PRoutes.world),
              child: const Icon(Icons.home_outlined),
            ),
          ],
        ),
      ),
    );
  }
}
