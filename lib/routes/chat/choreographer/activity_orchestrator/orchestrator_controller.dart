import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_output.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';

class ActiveSuggestionModel {
  final OrchestratorRoleSuggestions suggestion;
  final List<OrchestratorSuggestion> shuffledChoices;

  final OrchestratorSuggestion? selectedChoice;
  final OrchestratorSuggestion? acceptedChoice;

  ActiveSuggestionModel({
    required this.suggestion,
    this.selectedChoice,
    this.acceptedChoice,
    List<OrchestratorSuggestion>? shuffledChoices,
  }) : shuffledChoices =
           shuffledChoices ?? (List.from(suggestion.suggestions)..shuffle());

  ActiveSuggestionModel copyWith({
    OrchestratorSuggestion? selectedChoice,
    OrchestratorSuggestion? acceptedChoice,
  }) => ActiveSuggestionModel(
    suggestion: suggestion,
    selectedChoice: selectedChoice ?? this.selectedChoice,
    acceptedChoice: acceptedChoice ?? this.acceptedChoice,
    shuffledChoices: shuffledChoices,
  );
}

class OrchestratorController {
  final Room room;

  OrchestratorController({required this.room}) {
    _seenAwardedGoals.addAll(room.ownCompletedGoals);
    _setOrchestratorOutputSubscription();
    _setGoalCompletionSubscription();
    _setInitialSuggestion();
  }

  late final StreamSubscription _orchestratorOutputSubscription;
  late final StreamSubscription _goalCompletionSubscription;

  final StreamController<ActiveSuggestionModel?> suggestionStream =
      StreamController<ActiveSuggestionModel?>.broadcast();

  final StreamController<Set<ActivityRoleGoal>> goalCompletionStream =
      StreamController<Set<ActivityRoleGoal>>.broadcast();

  ActiveSuggestionModel? _activeSuggestion;
  final Set<ActivityRoleGoal> _seenAwardedGoals = {};

  ActiveSuggestionModel? get activeSuggestion => _activeSuggestion;

  bool get hasAcceptedSuggestion => _activeSuggestion?.acceptedChoice != null;

  void _log(String message) => Logs().w("[Orchestrator] $message");

  void dispose() {
    _orchestratorOutputSubscription.cancel();
    _goalCompletionSubscription.cancel();
    suggestionStream.close();
    goalCompletionStream.close();
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

      if (_activeSuggestion != null) {
        _log(
          "Received orchestrator output event but already have active suggestion, ignoring",
        );
        return;
      }

      // The orchestrator output is sent by the bot, so its sender identifies the
      // bot for excluding bot messages (e.g. a participant-mode reply) and the
      // bot's own role.
      final botUserId = event.senderId;
      final timeline = await room.getTimeline();
      final latestHumanMessage = timeline.events.firstWhereOrNull(
        (e) =>
            e.type == EventTypes.Message &&
            e.isVisibleInGui &&
            e.senderId != botUserId,
      );
      final humanRoleCount =
          room.assignedRoles?.values
              .map((r) => r.userId)
              .where((userId) => userId != botUserId)
              .toSet()
              .length ??
          0;

      final suggestion = suggestionToShow(
        output: output,
        ownRoleId: roleId,
        currentUserId: room.client.userID,
        latestHumanMessageEventId: latestHumanMessage?.eventId,
        latestHumanMessageSenderId: latestHumanMessage?.senderId,
        humanRoleCount: humanRoleCount,
      );
      if (suggestion == null) return;

      _setActiveSuggestion(ActiveSuggestionModel(suggestion: suggestion));
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: event.content);
    }
  }

  /// Pure turn-based decision: the suggestion bucket (if any) to show the
  /// current user for an orchestrator output, or null if they should not be
  /// prompted. Extracted from [_onOrchestratorOutputEvent] for unit testing.
  ///
  /// The orchestrator broadcasts a single event (triggered by whoever spoke
  /// last) carrying a bucket per role; the recommendation goes to the responder,
  /// not the speaker:
  /// - multi-human (>= 2 human roles): prompt the user who did NOT send the
  ///   latest human message — after A's message B is prompted; after B's, A.
  /// - single-human (participant mode, bot holds a role): prompt the lone human
  ///   right after their own message.
  /// Stale outputs — not based on the latest human message — are dropped.
  @visibleForTesting
  static OrchestratorRoleSuggestions? suggestionToShow({
    required OrchestratorOutput output,
    required String ownRoleId,
    required String? currentUserId,
    required String? latestHumanMessageEventId,
    required String? latestHumanMessageSenderId,
    required int humanRoleCount,
  }) {
    final roleSuggestion = output.suggestionsByRoleId(ownRoleId).firstOrNull;
    if (roleSuggestion == null) return null;

    if (output.basedOnEventId != latestHumanMessageEventId) return null;

    final isMultiHumanActivity = humanRoleCount >= 2;
    final currentUserSpokeLast = latestHumanMessageSenderId == currentUserId;
    final shouldPrompt = isMultiHumanActivity
        ? !currentUserSpokeLast
        : currentUserSpokeLast;
    return shouldPrompt ? roleSuggestion : null;
  }

  void _setGoalCompletionSubscription() {
    _goalCompletionSubscription = room.client.onRoomState.stream
        .where(
          (s) =>
              s.roomId == room.id &&
              s.state.type == PangeaEventTypes.orchestratorAwardedGoals,
        )
        .listen((_) => _onGoalCompletionEvent());
  }

  void _onGoalCompletionEvent() {
    final updatedAwardedGoals = room.ownCompletedGoals.toSet();
    if (_seenAwardedGoals.length < updatedAwardedGoals.length) {
      final diff = updatedAwardedGoals.difference(_seenAwardedGoals);
      goalCompletionStream.add(diff);
    }
    _seenAwardedGoals.addAll(updatedAwardedGoals);
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

    final update = choice.type == OrchestratorSuggestionType.best
        ? activeSuggestion.copyWith(
            selectedChoice: choice,
            acceptedChoice: choice,
          )
        : activeSuggestion.copyWith(selectedChoice: choice);

    _setActiveSuggestion(update);
  }
}
