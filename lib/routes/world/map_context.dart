import 'package:flutter/foundation.dart';

/// What the persistent world map is currently scoped to (world_v2 "Map
/// content, context & filtering"). World shows all content; a selected
/// course scopes the map to that course's content. Set by the shell from
/// the active route; the map listens and re-renders + refits the camera.
@immutable
sealed class MapContext {
  const MapContext();
}

class WorldMapContext extends MapContext {
  const WorldMapContext();

  @override
  bool operator ==(Object other) => other is WorldMapContext;

  @override
  int get hashCode => 0;
}

/// Scoped to one course plan — only that course's content shows.
class CourseMapContext extends MapContext {
  final String coursePlanId;
  const CourseMapContext(this.coursePlanId);

  @override
  bool operator ==(Object other) =>
      other is CourseMapContext && other.coursePlanId == coursePlanId;

  @override
  int get hashCode => coursePlanId.hashCode;
}

/// App-wide singleton the shell writes and the persistent map reads.
abstract class MapContextController {
  static final ValueNotifier<MapContext> notifier = ValueNotifier<MapContext>(
    const WorldMapContext(),
  );

  static void set(MapContext context) {
    if (notifier.value != context) notifier.value = context;
  }
}

/// Whether a map-pin preview is open on a narrow screen — where the preview
/// renders as a bottom sheet over the map rather than a glued-to-pin popup. The
/// persistent map (which owns the pin selection) writes it; the shell reads it
/// to hide the bottom nav while the sheet is up (a bottom sheet replaces the
/// bottom nav). A simple bool: the map keeps the selected pin / its loading
/// plan, this only signals "a pin sheet is showing." See `routing.instructions.md`.
abstract class MapPinController {
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static void set(bool open) {
    if (notifier.value != open) notifier.value = open;
  }
}
