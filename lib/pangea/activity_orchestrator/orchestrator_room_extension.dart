import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension OrchestratorRoomExtension on Room {
  OrchestratorAwardedGoals get orchestratorAwardedGoals {
    final state = getState(PangeaEventTypes.orchestratorAwardedGoals);
    if (state == null) return OrchestratorAwardedGoals(goalIds: []);
    try {
      return OrchestratorAwardedGoals.fromJson(state.content);
    } catch (_) {
      return OrchestratorAwardedGoals(goalIds: []);
    }
  }

  bool isGoalCompleted(String id) => false;
}
