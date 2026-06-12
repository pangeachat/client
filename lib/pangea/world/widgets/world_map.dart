import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan_topic_location.dart';
import 'package:fluffychat/pangea/world/world_activities_repo.dart';
import 'package:fluffychat/pangea/world/world_camera_state.dart';
import 'package:fluffychat/pangea/world/world_locations_repo.dart';

/// Full-bleed world map shown on the home surface (right column when no
/// chat is selected). First slice of the Pangea World designs; star
/// progress and travel mechanics land on top of this later.
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
  List<CmsCoursePlanTopicLocation> _locations = [];
  List<WorldActivityPin> _activities = [];

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _loadActivities();
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
      if (mounted) setState(() => _activities = activities);
    } catch (_) {
      // Map stays usable without activity pins.
    }
  }

  /// Open the activity's first-class page (map popup) at `/<activityId>`.
  void _openActivity(WorldActivityPin activity) {
    context.go('/${activity.activityId}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCenter: widget.initialCenter ??
            WorldCameraState.lastCenter ??
            const LatLng(20, 0),
        initialZoom: widget.initialZoom ?? WorldCameraState.lastZoom ?? 3,
        onPositionChanged: (camera, hasGesture) =>
            WorldCameraState.remember(camera.center, camera.zoom),
        minZoom: 2,
        maxZoom: 18,
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(
            const LatLng(-85, -180),
            const LatLng(85, 180),
          ),
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
          markers: _locations
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
          markers: _activities
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
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }
}
