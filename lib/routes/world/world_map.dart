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
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
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

  /// The pin whose preview popup is open (tapping a star selects it; tapping
  /// the map background or the popup's close clears it). Stays on the
  /// persistent map — no navigation, no second map.
  WorldActivityPin? _selectedActivity;

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
    // Close any open preview when the map re-scopes (e.g. entering a course).
    if (mounted) setState(() => _selectedActivity = null);
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

  /// Open the activity's first-class page (the full session start flow).
  /// Reached only from the preview popup's "Details" button — an explicit
  /// action, not the pin tap.
  void _openActivity(WorldActivityPin activity) {
    context.go('/${activity.activityId}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Per-activity goal progress for the logged-in user (gray/bronze/gold).
    final goalTiers = _userGoalTiers(Matrix.of(context).client);
    // Place the preview above the pin, but flip it below when the pin is too
    // near the top to fit (edge-aware, no map move).
    bool popupAbove = true;
    final selected = _selectedActivity;
    if (selected != null) {
      try {
        popupAbove =
            _controller.camera.latLngToScreenOffset(selected.point).dy > 360.0;
      } catch (_) {
        // Camera not ready yet; default to above.
      }
    }
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
        // Tap empty map → dismiss any open activity preview.
        onTap: (_, _) {
          if (_selectedActivity != null) {
            setState(() => _selectedActivity = null);
          }
        },
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
                      onTap: () =>
                          setState(() => _selectedActivity = activity),
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
        // Preview popup for the tapped activity — a marker so it stays glued
        // to its pin as the map moves. No navigation; the persistent map and
        // the surrounding view stay put.
        if (_selectedActivity != null &&
            _visibleActivities.contains(_selectedActivity))
          MarkerLayer(
            markers: [
              Marker(
                point: _selectedActivity!.point,
                width: 230,
                height: 400,
                // Float the card above the pin (or below near the top edge),
                // so the location stays visible.
                alignment: popupAbove
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: _ActivityPreviewPopup(
                  activity: _selectedActivity!,
                  below: !popupAbove,
                  onClose: () => setState(() => _selectedActivity = null),
                  onDetails: () => _openActivity(_selectedActivity!),
                ),
              ),
            ],
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

/// In-map preview popup for a tapped activity pin. Renders the same activity
/// card the full activity page uses, plus location and a "Details" action,
/// without leaving the current view.
class _ActivityPreviewPopup extends StatelessWidget {
  final WorldActivityPin activity;
  final bool below;
  final VoidCallback onClose;
  final VoidCallback onDetails;

  const _ActivityPreviewPopup({
    required this.activity,
    required this.onClose,
    required this.onDetails,
    this.below = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Gap sits between the card and the pin — on top when the card hangs
        // below the pin, on the bottom when it floats above.
        if (below) const SizedBox(height: 14.0),
        Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16.0),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ActivitySuggestionCard(
                  activity: activity.plan,
                  width: 180.0,
                  height: 262.0,
                  fontSize: 16.0,
                  fontSizeSmall: 11.0,
                  iconSize: 11.0,
                ),
                if (activity.locationName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_pin,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            activity.locationName,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: L10n.of(context).close,
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_full, size: 14),
                      label: Text(L10n.of(context).details),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onDetails,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!below) const SizedBox(height: 14.0),
      ],
    );
  }
}
