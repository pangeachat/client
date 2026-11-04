import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_map_view.dart';

/// #9402: the wide map's search leaves its slot while an activity is open and
/// comes back when it closes. The open activity is
/// [WorldMapController.focusedActivityId]: the plan's `activity:` token,
/// resolved through [WorldMapController.focusedActivityIdOf] as here, or the
/// activity behind an open session chat.
void main() {
  group('WorldMapView.activityHidesSearch (#9402)', () {
    test('with no activity open, the search shows', () {
      expect(WorldMapView.activityHidesSearch(null), isFalse);
    });

    test('an open activity hides the search', () {
      expect(
        WorldMapView.activityHidesSearch(
          WorldMapController.focusedActivityIdOf(const ActivityFocus('a1')),
        ),
        isTrue,
      );
    });
  });
}
