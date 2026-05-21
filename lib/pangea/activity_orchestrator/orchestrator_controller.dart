import 'dart:async';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_output.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';

class ActiveSuggestionModel {
  final OrchestratorRoleSuggestions suggestion;
  final OrchestratorSuggestion? acceptedChoice;

  const ActiveSuggestionModel({required this.suggestion, this.acceptedChoice});

  bool isChoiceSelected(OrchestratorSuggestion choice) =>
      acceptedChoice == choice;

  List<OrchestratorSuggestion> get shuffledChoices {
    final choices = [...suggestion.suggestions];
    choices.shuffle();
    return choices;
  }

  ActiveSuggestionModel copyWith({
    OrchestratorRoleSuggestions? suggestion,
    OrchestratorSuggestion? acceptedChoice,
  }) => ActiveSuggestionModel(
    suggestion: suggestion ?? this.suggestion,
    acceptedChoice: acceptedChoice ?? this.acceptedChoice,
  );
}

class OrchestratorController {
  final Room room;

  OrchestratorController({required this.room}) {
    _setOrchestratorOutputSubscription();
    _setInitialSuggestion();
  }

  late final StreamSubscription _orchestratorOutputSubscription;

  ActiveSuggestionModel? _activeSuggestion;

  final StreamController<ActiveSuggestionModel?> suggestionStream =
      StreamController<ActiveSuggestionModel?>.broadcast();

  ActiveSuggestionModel? get activeSuggestion => _activeSuggestion;

  bool get hasAcceptedSuggestion => _activeSuggestion?.acceptedChoice != null;

  void _log(String message) => Logs().w("[Orchestrator] $message");

  void dispose() {
    suggestionStream.close();
    _orchestratorOutputSubscription.cancel();
  }

  Future<void> _setInitialSuggestion() async {
    final timeline = await room.getTimeline();
    for (final event in timeline.events) {
      if (event.type == PangeaEventTypes.orchestratorOutput) {
        _onOrchestratorOutputEvent(event);
        break;
      }
    }
  }

  void _setActiveSuggestion(ActiveSuggestionModel? update) {
    _activeSuggestion = update;
    if (!suggestionStream.isClosed) {
      suggestionStream.add(update);
    }
  }

  void _setOrchestratorOutputSubscription() {
    _orchestratorOutputSubscription = room.client.onSync.stream.listen(
      _onRoomTimelineUpdate,
    );
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

  Future<void> _onOrchestratorOutputEvent(MatrixEvent event) async {
    try {
      final output = OrchestratorOutput.fromJson(event.content);
      final roleId = room.ownRole?.id;
      if (roleId == null) {
        _log("User does not have roleID in room ${room.id}");
        return;
      }

      final roleSuggestion = output.suggestionsByRoleId(roleId).firstOrNull;
      if (roleSuggestion == null) return;

      if (_activeSuggestion != null) {
        _log(
          "Received orchestrator output event but already have active suggestion, ignoring",
        );
        return;
      }

      final timeline = await room.getTimeline();
      final userLatestMessage = timeline.events.firstWhereOrNull(
        (e) =>
            e.senderId == room.client.userID &&
            e.type == EventTypes.Message &&
            e.isVisibleInGui,
      );

      if (output.basedOnEventId != userLatestMessage?.eventId) {
        _log(
          "Received orchestrator output event but it is based on event ${output.basedOnEventId} which is different from user's latest message ${userLatestMessage?.eventId}, ignoring",
        );
        return;
      }

      _setActiveSuggestion(ActiveSuggestionModel(suggestion: roleSuggestion));
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: event.content);
    }
  }

  void clearSuggestionState() {
    _setActiveSuggestion(null);
  }

  void resetSuggestionState() {
    final activeSuggestion = _activeSuggestion;
    if (activeSuggestion == null) return;
    _setActiveSuggestion(
      ActiveSuggestionModel(suggestion: activeSuggestion.suggestion),
    );
  }

  void selectChoice(OrchestratorSuggestion choice) {
    final activeSuggestion = _activeSuggestion;
    if (activeSuggestion == null) {
      throw StateError("Cannot select choice without active suggestion");
    }

    if (!activeSuggestion.suggestion.suggestions.contains(choice)) {
      throw StateError("Invalid choice selection");
    }

    _setActiveSuggestion(activeSuggestion.copyWith(acceptedChoice: choice));
  }
}
