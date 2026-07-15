import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/active_suggestion_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_output.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';

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

      // Re-fire (choreo#2761): fresh outputs replace the active suggestion —
      // except mid-interaction; a tapped card is never yanked from the user.
      if (_activeSuggestion?.selectedChoice != null) {
        _log(
          "Received orchestrator output while a choice is selected, ignoring",
        );
        return;
      }

      // The orchestrator output is sent by the bot, so its sender identifies the
      // bot for excluding bot messages (e.g. a participant-mode reply) and the
      // bot's own role.
      final botUserId = event.senderId;
      final timeline = await room.getTimeline();
      // Staleness key (choreo#2761 rule 6): the latest visible message of ANY
      // sender — recency against the timeline decides, never arrival order.
      final latestMessage = timeline.events.firstWhereOrNull(
        (e) => e.type == EventTypes.Message && e.isVisibleInGui,
      );
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

      // A stale output decides nothing — keep whatever is showing.
      if (output.basedOnEventId != latestMessage?.eventId) {
        _log("Received stale orchestrator output, ignoring");
        return;
      }

      final suggestion = suggestionToShow(
        output: output,
        ownRoleId: roleId,
        currentUserId: room.client.userID,
        latestMessageEventId: latestMessage?.eventId,
        latestHumanMessageSenderId: latestHumanMessage?.senderId,
        humanRoleCount: humanRoleCount,
      );

      // Null clears on purpose — otherwise a chip from an earlier turn would
      // linger after an output that carries no bucket for this role.
      _setActiveSuggestion(
        suggestion == null
            ? null
            : ActiveSuggestionModel(suggestion: suggestion),
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: event.content);
    }
  }

  /// Pure turn-based decision: the suggestion bucket (if any) to show the
  /// current user for an orchestrator output, or null if they should not be
  /// prompted. Extracted from [_onOrchestratorOutputEvent] for unit testing.
  ///
  /// The orchestrator re-fires on every message (choreo#2761), so outputs are
  /// legitimately based on bot replies too; the recommendation goes to the
  /// responder, not the speaker:
  /// - multi-human (>= 2 human roles): prompt the user who did NOT send the
  ///   latest human message — after A's message B is prompted; after B's, A.
  /// - single-human (participant mode, bot holds a role): prompt the lone human
  ///   right after their own message OR after the bot's reply to them.
  /// Stale outputs — not based on the latest visible message of ANY sender —
  /// are dropped (the caller also checks this before deciding to clear).
  @visibleForTesting
  static OrchestratorRoleSuggestions? suggestionToShow({
    required OrchestratorOutput output,
    required String ownRoleId,
    required String? currentUserId,
    required String? latestMessageEventId,
    required String? latestHumanMessageSenderId,
    required int humanRoleCount,
  }) {
    final roleSuggestion = output.suggestionsByRoleId(ownRoleId).firstOrNull;
    if (roleSuggestion == null) return null;

    if (output.basedOnEventId != latestMessageEventId) return null;

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
