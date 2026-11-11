import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/world/world_map.dart';

/// Where a course's map fades when a Mission is on show (org course-view doc,
/// "The camera"; pangeachat/.github#780): the Mission's placed activities,
/// else the city the course record names for it, else nowhere.
void main() {
  QuestActivityCard card(String id, List<String> los, List<double>? at) =>
      QuestActivityCard(
        activityId: id,
        title: id,
        l2: 'es',
        coordinates: at,
        learningObjectiveRefs: los,
      );

  final oaxaca = LatLng(17.0654, -96.7266);

  test('the Mission\'s placed activities are the target', () {
    final targets = WorldMapController.missionFadeTargets(
      pins: [
        card('a', ['lo1'], [-96.73, 17.06]),
        card('b', ['lo1'], [-96.71, 17.08]),
        card('c', ['lo2'], [-99.13, 19.43]),
        card('d', ['lo1'], null),
      ],
      missionId: 'lo1',
      recordedCity: oaxaca,
    );
    expect(targets, hasLength(2));
    expect(targets.every((p) => p.longitude < -96), isTrue);
  });

  test('with no placed activity, the record\'s city is the target', () {
    final targets = WorldMapController.missionFadeTargets(
      pins: [
        card('c', ['lo2'], [-99.13, 19.43]),
      ],
      missionId: 'lo1',
      recordedCity: oaxaca,
    );
    expect(targets, [oaxaca]);
  });

  test('with neither, there is nowhere to fade and the camera stays', () {
    expect(
      WorldMapController.missionFadeTargets(pins: const [], missionId: 'lo1'),
      isEmpty,
    );
  });
}
