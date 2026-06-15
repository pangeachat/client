import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/map_context.dart';
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
///
/// This is the "completion data, stored in Matrix and automatically synced"
/// that colours the pins before any click — no CMS read needed for it.
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
/// selected course shows only that quest's activities and the camera refits
/// to it. Pins are thin (id, title, point); tapping one opens a preview card
/// in place — its thin title shows immediately while the full plan loads
/// behind a shimmer. Star colour reflects Matrix-synced goal progress.
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

  /// When set, the map centers this activity within the exposed canvas (the
  /// area the left column and detail panel don't cover) instead of fitting the
  /// whole course — e.g. while its `?activity=` detail panel is open.
  final String? focusedActivityId;

  const WorldMap({
    super.key,
    this.initialCenter,
    this.initialZoom,
    this.controller,
    this.leftOverlayWidth = 0.0,
    this.focusedActivityId,
  });

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap> {
  final MapController _ownController = MapController();
  MapController get _controller => widget.controller ?? _ownController;

  /// The activity pins currently shown — the active context's set (the whole
  /// world, or a selected quest's activities). Thin: id, title, point.
  List<QuestActivityCard> _pins = [];

  /// The pin whose preview popup is open (tapping a star selects it; tapping
  /// the map background or the popup's close clears it). Stays on the
  /// persistent map — no navigation, no second map.
  QuestActivityCard? _selectedActivity;

  /// The selected activity's full plan, fetched lazily on tap. Null while the
  /// fetch is in flight (the preview shows a shimmer) and when none is open.
  ActivityPlanModel? _selectedPlan;

  /// True while the selected activity's full plan is loading (drives the
  /// shimmer vs. the loaded card in the preview).
  bool _planLoading = false;

  Client? _client;
  StreamSubscription<dynamic>? _syncSub;

  @override
  void initState() {
    super.initState();
    // Invariant: the shell owns a single persistent instance, so this runs
    // once per app session — section navigation overlays the map, never
    // remounts it.
    _loadForContext();
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
  void didUpdateWidget(covariant WorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-center when the focused activity changes or the exposed canvas
    // resizes (a panel opened/closed), so the selection stays centered in the
    // visible map area rather than behind a panel.
    if (oldWidget.focusedActivityId != widget.focusedActivityId ||
        oldWidget.leftOverlayWidth != widget.leftOverlayWidth) {
      _fitToContext();
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    MapContextController.notifier.removeListener(_onContextChange);
    super.dispose();
  }

  void _onContextChange() {
    // Close any open preview when the map re-scopes (e.g. entering a course),
    // then reload pins for the new scope and refit.
    if (mounted) {
      setState(() {
        _selectedActivity = null;
        _selectedPlan = null;
        _planLoading = false;
      });
    }
    _loadForContext();
  }

  /// Load the pins for the active map context: a selected course shows that
  /// quest's activities; World shows all placed activities.
  Future<void> _loadForContext() async {
    final mapContext = MapContextController.notifier.value;
    try {
      final pins = mapContext is CourseMapContext
          ? await QuestRepo.questPins(mapContext.coursePlanId)
          : await QuestRepo.mapActivities();
      if (!mounted) return;
      setState(() => _pins = pins);
      // If a context was set before the pins loaded, fit now that we have them.
      _fitToContext();
    } catch (_) {
      // Map stays usable without activity pins.
    }
  }

  /// Open the preview for [card] immediately, then fetch its full plan in the
  /// background (the preview shimmers until it arrives).
  Future<void> _selectActivity(QuestActivityCard card) async {
    setState(() {
      _selectedActivity = card;
      _selectedPlan = null;
      _planLoading = true;
    });
    try {
      final plan = await QuestRepo.activity(card.activityId);
      if (!mounted || _selectedActivity?.activityId != card.activityId) return;
      setState(() {
        _selectedPlan = plan;
        _planLoading = false;
      });
    } catch (_) {
      if (mounted && _selectedActivity?.activityId == card.activityId) {
        setState(() => _planLoading = false);
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedActivity = null;
      _selectedPlan = null;
      _planLoading = false;
    });
  }

  /// Centers the current selection within the *exposed* canvas — the map area
  /// the left column and detail panel don't cover. A specifically-focused
  /// activity centers on itself (keeping the current zoom); a course fits all
  /// its activities. Returning to World keeps the current view rather than
  /// yanking the camera.
  void _fitToContext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        // Inset the left edge by the overlay so content lands in the uncovered
        // area to the right of the column/panel, not behind it.
        final padding = EdgeInsets.fromLTRB(
          widget.leftOverlayWidth + 64.0,
          64.0,
          64.0,
          64.0,
        );

        // A specifically selected activity centers on itself, at the current
        // zoom, within the exposed canvas.
        final focusedId = widget.focusedActivityId;
        if (focusedId != null) {
          LatLng? point;
          for (final card in _pins) {
            if (card.activityId == focusedId) {
              point = card.point;
              break;
            }
          }
          if (point != null) {
            _controller.fitCamera(
              CameraFit.coordinates(
                coordinates: [point],
                padding: padding,
                maxZoom: _controller.camera.zoom,
              ),
            );
            return;
          }
        }

        // Otherwise a course context fits all of its activities.
        if (MapContextController.notifier.value is! CourseMapContext) return;
        final points = _pins.map((c) => c.point).whereType<LatLng>().toList();
        if (points.isEmpty) return;
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: padding,
            maxZoom: 12.0,
          ),
        );
      } catch (_) {
        // Controller/camera not ready yet; the next change will refit.
      }
    });
  }

  /// Open the activity detail in-place, preserving the current route (course
  /// stays selected, map stays put) via the `?activity=<id>` param. The detail
  /// panel fetches the full plan on open. Reached from the preview's "Details".
  void _openActivity(QuestActivityCard card) {
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    context.go(
      uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'activity': card.activityId,
        },
      ).toString(),
    );
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    // Per-activity goal progress for the logged-in user (gray/bronze/gold).
    final goalTiers = _userGoalTiers(Matrix.of(context).client);
    // world-map-tiles Phase 1: free hosted tiles switched by app theme —
    // OpenStreetMap (light) / CartoDB Dark Matter (dark).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final retina = dark && MediaQuery.devicePixelRatioOf(context) > 1.0;

    // Place the preview above the pin, but flip it below when the pin is too
    // near the top to fit (edge-aware, no map move).
    final selected = _selectedActivity;
    final selectedVisible =
        selected != null &&
        selected.point != null &&
        _pins.any((c) => c.activityId == selected.activityId);
    bool popupAbove = true;
    if (selectedVisible) {
      try {
        popupAbove =
            _controller.camera.latLngToScreenOffset(selected.point!).dy > 360.0;
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
          if (_selectedActivity != null) _clearSelection();
        },
      ),
      children: [
        // Base tiles, switched by app theme: OpenStreetMap (light) / CartoDB
        // Dark Matter (dark). Retina (@2x) keeps the dark basemap's small
        // labels sharp; CartoDB serves @2x, light (OSM) stays 1x. Brighter,
        // on-brand labels are a vector-tile job (see world-map-tiles doc) — on
        // raster, lifting just the labels needs a second tile layer, which
        // doubles tile requests, so it is not worth it here.
        TileLayer(
          urlTemplate: dark
              ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          retinaMode: retina,
          userAgentPackageName: 'com.talktolearn.chat',
        ),
        // world_v2: the map surfaces activities as star pins coloured by the
        // user's goal progress. Tapping a pin opens an in-place preview (no
        // navigation, no second map).
        MarkerLayer(
          markers: _pins
              .map((card) {
                final point = card.point;
                if (point == null) return null;
                return Marker(
                  point: point,
                  width: 36,
                  height: 36,
                  child: Tooltip(
                    message: card.title,
                    child: GestureDetector(
                      onTap: () => _selectActivity(card),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _starColor(
                            goalTiers[card.activityId] ?? _GoalTier.none,
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
                );
              })
              .whereType<Marker>()
              .toList(),
        ),
        // Preview popup for the tapped activity — a marker so it stays glued to
        // its pin as the map moves. Opens immediately with the thin title; the
        // full plan loads behind a shimmer. No navigation; the map stays put.
        if (selectedVisible)
          MarkerLayer(
            markers: [
              Marker(
                point: selected.point!,
                width: 230,
                height: 400,
                alignment: popupAbove
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: _ActivityPreviewPopup(
                  card: selected,
                  plan: _selectedPlan,
                  loading: _planLoading,
                  below: !popupAbove,
                  onClose: _clearSelection,
                  onDetails: () => _openActivity(selected),
                ),
              ),
            ],
          ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
            if (dark) TextSourceAttribution('CARTO', onTap: () {}),
          ],
        ),
      ],
    );
  }
}

/// In-map preview popup for a tapped activity pin. Opens immediately: the
/// activity card renders the moment the full plan is available, and shows a
/// shimmer skeleton (with the title we already have from the pin) while it
/// loads. Plus a "Details" action — all without leaving the current view.
class _ActivityPreviewPopup extends StatelessWidget {
  final QuestActivityCard card;
  final ActivityPlanModel? plan;
  final bool loading;
  final bool below;
  final VoidCallback onClose;
  final VoidCallback onDetails;

  const _ActivityPreviewPopup({
    required this.card,
    required this.plan,
    required this.loading,
    required this.onClose,
    required this.onDetails,
    this.below = false,
  });

  static const double _cardWidth = 180.0;
  static const double _cardHeight = 262.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activity = plan;
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
                SizedBox(
                  width: _cardWidth,
                  height: _cardHeight,
                  child: activity != null
                      ? ActivitySuggestionCard(
                          activity: activity,
                          width: _cardWidth,
                          height: _cardHeight,
                          fontSize: 16.0,
                          fontSizeSmall: 11.0,
                          iconSize: 11.0,
                        )
                      : _PreviewSkeleton(title: card.title, loading: loading),
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

/// Card-shaped placeholder shown while the full plan loads: the real title
/// (known from the pin) over a shimmering image block + meta line, matching
/// the [ActivitySuggestionCard] layout so the swap-in is seamless. When
/// [loading] is false but no plan arrived, it just holds the title (no
/// shimmer) rather than spinning forever.
class _PreviewSkeleton extends StatelessWidget {
  final String title;
  final bool loading;

  const _PreviewSkeleton({required this.title, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget block(double width, double height) {
      final box = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6.0),
        ),
      );
      if (!loading) return box;
      return Shimmer.fromColors(
        baseColor: theme.colorScheme.surfaceContainerHigh,
        highlightColor: theme.colorScheme.surfaceBright,
        child: box,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        color: theme.colorScheme.surfaceContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            block(_ActivityPreviewPopup._cardWidth, 150.0),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.0,
                  vertical: 6.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16.0),
                    ),
                    block(90.0, 12.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
