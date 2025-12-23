import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/constructs/construct_repo.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension LevelSummaryExtension on Room {
  ConstructSummary? get levelUpSummary {
    final summaryEvent = getState(PangeaEventTypes.constructSummary);
    if (summaryEvent != null) {
      return ConstructSummary.fromJson(summaryEvent.content);
    }
    return null;
  }

  DateTime? get lastLevelUpTimestamp {
    final lastLevelUp = getState(PangeaEventTypes.constructSummary);
    return lastLevelUp is Event ? lastLevelUp.originServerTs : null;
  }

  Future<void> setLevelUpSummary(ConstructSummary summary) =>
      client.setRoomStateWithKey(
        id,
        PangeaEventTypes.constructSummary,
        '',
        summary.toJson(),
      );
}
