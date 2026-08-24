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

/// The deliberate "bring the camera to my selection" request — the focus
/// button on the activity plan page and the course card header (#7616).
/// Selecting an activity or course only PANS the camera (the automatic zoom
/// was jarring — #7496, #7616); this button is the one path that zooms: in on
/// a focused activity's pin, or to fit a course's activities. A one-shot tick
/// the persistent map listens to; fired with no map alive it does nothing.
abstract class MapCameraFocusRequests {
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static void request() => notifier.value++;
}

/// Whether the activity plan's mobile sheet is at its FULL rest. At full the
/// sheet grows over the top analytics bar, so the shell hides the bar (its
/// band is reclaimed for the sheet's height). Set by the nav cavity for the
/// activity only — false for every other cavity and when nothing is open.
abstract class ActivitySheetFull {
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static void set({required bool value}) {
    if (notifier.value != value) notifier.value = value;
  }
}
