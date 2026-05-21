import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_output.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

class ActiveSuggestionModel {
  final OrchestratorRoleSuggestions suggestion;
  final Set<OrchestratorSuggestion> selectedChoices;
  final OrchestratorSuggestion? currentSelectedChoice;
  final OrchestratorSuggestion? acceptedChoice;

  const ActiveSuggestionModel({
    required this.suggestion,
    this.selectedChoices = const {},
    this.currentSelectedChoice,
    this.acceptedChoice,
  });

  bool isChoiceSelected(OrchestratorSuggestion choice) =>
      selectedChoices.contains(choice);

  ActiveSuggestionModel copyWith({
    OrchestratorRoleSuggestions? suggestion,
    Set<OrchestratorSuggestion>? selectedChoices,
    OrchestratorSuggestion? currentSelectedChoice,
    OrchestratorSuggestion? acceptedChoice,
  }) => ActiveSuggestionModel(
    suggestion: suggestion ?? this.suggestion,
    selectedChoices: selectedChoices ?? this.selectedChoices,
    currentSelectedChoice: currentSelectedChoice ?? this.currentSelectedChoice,
    acceptedChoice: acceptedChoice ?? this.acceptedChoice,
  );
}

class OrchestratorController {
  final Room room;

  OrchestratorController({required this.room}) {
    _setOrchestratorOutputSubscription();
    _setRoomStateSubscription();
  }

  late final StreamSubscription _orchestratorOutputSubscription;
  late final StreamSubscription _roomStateSubscription;

  ActiveSuggestionModel? _activeSuggestion;

  final StreamController<ActiveSuggestionModel?> suggestionStream =
      StreamController<ActiveSuggestionModel?>.broadcast();

  ActiveSuggestionModel? get activeSuggestion => _activeSuggestion;

  bool get hasAcceptedSuggestion => _activeSuggestion?.acceptedChoice != null;

  void _log(String message) => Logs().w("[Orchestrator] $message");

  void dispose() {
    suggestionStream.close();
    _orchestratorOutputSubscription.cancel();
    _roomStateSubscription.cancel();
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

  void _onOrchestratorOutputEvent(MatrixEvent event) {
    try {
      final output = OrchestratorOutput.fromJson(event.content);
      _log("Received orchestrator output event: ${output.toJson()}");
      // final roleId = room.ownRole?.id;
      // if (roleId == null) {
      //   _log("User does not have roleID in room ${room.id}");
      //   return;
      // }

      // final roleSuggestions = output.suggestionsByRoleId(roleId);
      final roleSuggestions = output.suggestions.firstOrNull;
      if (_activeSuggestion == null && roleSuggestions != null) {
        _setActiveSuggestion(
          ActiveSuggestionModel(suggestion: roleSuggestions),
        );
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: event.content);
    }
  }

  void _setRoomStateSubscription() {
    final targetEvents = {PangeaEventTypes.orchestratorAwardedGoals};
    _roomStateSubscription = room.client.onRoomState.stream
        .where(
          (s) => s.roomId == room.id && targetEvents.contains(s.state.type),
        )
        .listen((s) => _onOrchestratorAwardedGoals());
  }

  void _onOrchestratorAwardedGoals() {
    _log(
      "Received orchestrator awarded goals update: ${room.orchestratorAwardedGoals.toJson()}",
    );
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
      _log("Cannot select choice without active suggestion");
      return;
    }

    if (!activeSuggestion.suggestion.suggestions.contains(choice)) {
      _log("Invalid choice selection");
      return;
    }

    final updatedSelectedChoices = {
      ...activeSuggestion.selectedChoices,
      choice,
    };

    _setActiveSuggestion(
      activeSuggestion.copyWith(
        selectedChoices: updatedSelectedChoices,
        currentSelectedChoice: choice,
      ),
    );
  }

  void acceptChoice() {
    final activeSuggestion = _activeSuggestion;
    if (activeSuggestion == null) {
      _log("Cannot accept suggestion choice without active suggestion");
      return;
    }

    final selectedChoice = activeSuggestion.currentSelectedChoice;
    if (selectedChoice == null) {
      _log("Cannot accept suggestion choice without selected choice");
      return;
    }

    if (!selectedChoice.type.isSuggestion) {
      _log("Selected suggestion choice is not correct");
      return;
    }

    _setActiveSuggestion(
      activeSuggestion.copyWith(acceptedChoice: selectedChoice),
    );
  }
}
