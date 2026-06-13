import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/course_plans/payload_client/models/course_plan/cms_course_plan_topic_location.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_activities_repo.dart';
import 'package:fluffychat/routes/world/world_locations_repo.dart';

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

  const WorldMap({
    super.key,
    this.initialCenter,
    this.initialZoom,
    this.controller,
  });

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap> {
  final MapController _ownController = MapController();
  MapController get _controller => widget.controller ?? _ownController;

  List<CmsCoursePlanTopicLocation> _locations = [];
  List<WorldActivityPin> _activities = [];

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
  void dispose() {
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
            padding: const EdgeInsets.all(64.0),
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
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        // The persistent instance keeps its own camera across navigation,
        // so no external camera-state restore is needed.
        initialCenter: widget.initialCenter ?? const LatLng(20, 0),
        initialZoom: widget.initialZoom ?? 3,
        minZoom: 2,
        maxZoom: 18,
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(const LatLng(-85, -180), const LatLng(85, 180)),
        ),
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
                          color: AppConfig.gold,
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
