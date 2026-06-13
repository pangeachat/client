import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/course_plans/payload_client/models/course_plan/cms_course_plan_topic_location.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_activities_repo.dart';
import 'package:fluffychat/routes/world/world_locations_repo.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// How many of an activity's goals the current user has collected, across all
/// of their sessions of it. Drives the pin's star colour on the world map.
enum _GoalTier { none, some, all }

/// Pin star colour for a goal tier: gray = none collected, bronze = some,
/// gold = all (world_v2 progress affordance).
Color _starColor(_GoalTier tier) {
  switch (tier) {
    case _GoalTier.all:
      return AppConfig.gold;
    case _GoalTier.some:
      return const Color(0xFFCD7F32); // bronze
    case _GoalTier.none:
      return Colors.grey;
  }
}

/// Build `activityId -> best goal tier` from the user's own activity-session
/// rooms. Per session, the tier is measured against *the user's own role's*
/// goals ("by that particular user"): collected via the
/// `orchestrator_awarded_goals` room state. Activities the user hasn't started
/// (or that have no goals) are absent → they default to [_GoalTier.none]
/// (gray). Multiple sessions of one activity keep the highest tier reached.
Map<String, _GoalTier> _userGoalTiers(Client client) {
  final tiers = <String, _GoalTier>{};
  for (final room in client.rooms) {
    final activityId = room.activityId;
    if (activityId == null) continue;
    final role = room.ownRole;
    if (role == null) continue;
    final total = role.allGoals.length;
    if (total == 0) continue;
    final collected = room.ownCompletedGoals.length;
    final tier = collected <= 0
        ? _GoalTier.none
        : (collected >= total ? _GoalTier.all : _GoalTier.some);
    final existing = tiers[activityId];
    if (existing == null || tier.index > existing.index) {
      tiers[activityId] = tier;
    }
  }
  return tiers;
}

/// The world map. In world_v2 a single instance is hosted persistently by
/// the app shell ([TwoColumnLayout]) as the base layer every section
/// overlays — built once and never remounted on navigation, so tiles,
/// camera, and pins are preserved as you move around the nav.
///
/// Its content is scoped by [MapContextController]: World shows all pins; a
/// selected course shows only that course's content and the camera refits
/// to it. Star progress and travel mechanics land on top of this later.
class WorldMap extends StatefulWidget {
  /// Optional camera override, e.g. to center on an activity's location.
  final LatLng? initialCenter;
  final double? initialZoom;

  /// Optional controller so parents can move the camera after build.
  final MapController? controller;

  /// Logical-pixel width of the nav-rail + left-column overlay the shell
  /// draws *on top* of this full-bleed map. A course camera-fit adds it as
  /// left padding so the fitted content lands in the uncovered area to the
  /// right of the overlay instead of behind it. 0 when nothing overlays it.
  final double leftOverlayWidth;

  const WorldMap({
    super.key,
    this.initialCenter,
    this.initialZoom,
    this.controller,
    this.leftOverlayWidth = 0.0,
  });

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap> {
  final MapController _ownController = MapController();
  MapController get _controller => widget.controller ?? _ownController;

  List<CmsCoursePlanTopicLocation> _locations = [];
  List<WorldActivityPin> _activities = [];

  Client? _client;
  StreamSubscription<dynamic>? _syncSub;

  @override
  void initState() {
    super.initState();
    // Invariant: the shell owns a single persistent instance, so this runs
    // once per app session — section navigation overlays the map, never
    // remounts it.
    _loadLocations();
    _loadActivities();
    MapContextController.notifier.addListener(_onContextChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recolour activity pins when the user collects a goal (room state sync).
    final client = Matrix.of(context).client;
    if (_client != client) {
      _client = client;
      _syncSub?.cancel();
      _syncSub = client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 2))
          .listen((_) {
            if (mounted) setState(() {});
          });
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    MapContextController.notifier.removeListener(_onContextChange);
    super.dispose();
  }

  void _onContextChange() {
    if (mounted) setState(() {});
    _fitToContext();
  }

  Future<void> _loadLocations() async {
    try {
      final locations = await WorldLocationsRepo.mappableLocations();
      if (mounted) setState(() => _locations = locations);
    } catch (_) {
      // Map stays usable without pins; Sentry catches repo errors.
    }
  }

  Future<void> _loadActivities() async {
    try {
      final activities = await WorldActivitiesRepo.activityPins();
      if (mounted) {
        setState(() => _activities = activities);
        // If a course context was already set before the pins loaded, fit
        // to it now that we have its activities.
        _fitToContext();
      }
    } catch (_) {
      // Map stays usable without activity pins.
    }
  }

  /// Pins for the active context: a course shows only its own activities.
  List<WorldActivityPin> get _visibleActivities {
    final context = MapContextController.notifier.value;
    if (context is CourseMapContext) {
      return _activities
          .where((a) => a.coursePlanId == context.coursePlanId)
          .toList();
    }
    return _activities;
  }

  /// Location pins are global; hidden when scoped to a course so the course's
  /// own activities read clearly.
  List<CmsCoursePlanTopicLocation> get _visibleLocations =>
      MapContextController.notifier.value is CourseMapContext
      ? const []
      : _locations;

  /// When the scope becomes a course, fit the camera to that course's pins
  /// so the learner sees its content. Returning to World keeps the current
  /// view (all content reappears) rather than yanking the camera.
  void _fitToContext() {
    if (MapContextController.notifier.value is! CourseMapContext) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final points = _visibleActivities.map((a) => a.point).toList();
      if (points.isEmpty) return;
      try {
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            // Inset the left edge by the overlay width so the course fits in
            // the area the left column doesn't cover, not behind it.
            padding: EdgeInsets.fromLTRB(
              widget.leftOverlayWidth + 64.0,
              64.0,
              64.0,
              64.0,
            ),
            maxZoom: 12.0,
          ),
        );
      } catch (_) {
        // Controller not attached yet; the next change will refit.
      }
    });
  }

  /// Open the activity's first-class page (map popup) at `/<activityId>`.
  void _openActivity(WorldActivityPin activity) {
    context.go('/${activity.activityId}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Per-activity goal progress for the logged-in user (gray/bronze/gold).
    final goalTiers = _userGoalTiers(Matrix.of(context).client);
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        // The persistent instance keeps its own camera across navigation,
        // so no external camera-state restore is needed.
        initialCenter: widget.initialCenter ?? const LatLng(20, 0),
        initialZoom: widget.initialZoom ?? 3,
        // minZoom 3 (not 2): containLatitude rejects a move when the
        // constrained latitude band is shorter than the viewport, and the
        // ±90 band is only ~1024px tall at z2 — that would freeze *all*
        // panning on windows taller than ~1024px (common when maximized).
        // z3 gives a ~2048px band, clearing any realistic viewport.
        minZoom: 3,
        maxZoom: 18,
        // Clamp latitude only — leaving longitude free so the user can pan
        // east-west and the world wraps seamlessly ("rotate the world
        // around"). Epsg3857 replicates longitude, so tiles and markers
        // repeat across world copies automatically. A longitude-bounded
        // `contain`/`containCenter` pins the camera when zoomed out and hides
        // content behind the left column with no way to pan it out.
        cameraConstraint: const CameraConstraint.containLatitude(90, -90),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.talktolearn.chat',
        ),
        MarkerLayer(
          markers: _visibleLocations
              .map(
                (location) => Marker(
                  // CMS stores [longitude, latitude].
                  point: LatLng(
                    location.coordinates![1],
                    location.coordinates![0],
                  ),
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: Tooltip(
                    message: location.name,
                    child: Icon(
                      Icons.location_pin,
                      size: 40,
                      color: theme.colorScheme.primary,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black45),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        MarkerLayer(
          markers: _visibleActivities
              .map(
                (activity) => Marker(
                  point: activity.point,
                  width: 36,
                  height: 36,
                  child: Tooltip(
                    message: '${activity.title}\n${activity.locationName}',
                    child: GestureDetector(
                      onTap: () => _openActivity(activity),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _starColor(
                            goalTiers[activity.activityId] ?? _GoalTier.none,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(blurRadius: 4, color: Colors.black38),
                          ],
                        ),
                        child: const Icon(
                          Icons.star,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
          ],
        ),
      ],
    );
  }
}
