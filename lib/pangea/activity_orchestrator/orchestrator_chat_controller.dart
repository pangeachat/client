import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_output.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

class OrchestratorChatController {
  final Room room;

  OrchestratorChatController({required this.room}) {
    _setOrchestratorOutputSubscription();
    _setOrchestratorAwardedGoalsSubscription();
  }

  late final StreamSubscription _orchestratorOutputSubscription;
  late final StreamSubscription _orchestratorAwardedGoalsSubscription;

  void dispose() {
    _orchestratorOutputSubscription.cancel();
    _orchestratorAwardedGoalsSubscription.cancel();
  }

  void _setOrchestratorOutputSubscription() {
    _orchestratorOutputSubscription = room.client.onSync.stream.listen(
      _onRoomTimelineUpdate,
    );
  }

  void _setOrchestratorAwardedGoalsSubscription() {
    _orchestratorAwardedGoalsSubscription = room.client.onRoomState.stream
        .where(
          (s) =>
              s.roomId == room.id &&
              s.state.type == PangeaEventTypes.orchestratorAwardedGoals,
        )
        .listen((s) => _onOrchestratorAwardedGoals());
  }

  void _onRoomTimelineUpdate(SyncUpdate update) {
    final events = update.rooms?.join?[room.id]?.timeline?.events;
    if (events == null) return;
    for (final event in events) {
      if (event.type == PangeaEventTypes.orchestratorOutput) {
        _onOrchestratorOutputEvent(event);
      }
    }
  }

  void _onOrchestratorOutputEvent(MatrixEvent event) {
    try {
      final output = OrchestratorOutput.fromJson(event.content);
      Logs().d("Received orchestrator output event: ${output.toJson()}");
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: event.content);
    }
  }

  void _onOrchestratorAwardedGoals() {
    Logs().d(
      "Received orchestrator awarded goals update: ${room.orchestratorAwardedGoals.toJson()}",
    );
  }
}
