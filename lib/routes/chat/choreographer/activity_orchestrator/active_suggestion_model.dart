import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_goal_completion.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';

class ActiveSuggestionModel {
  final OrchestratorRoleSuggestions suggestion;

  /// The `based_on_event_id` of the orchestrator output that produced
  /// this suggestion — the turn internal feedback points at.
  final String basedOnEventId;

  /// The awards this turn carried. A goal flag must name one of these, so
  /// the reviewer picks rather than describes — prose alone made the model
  /// re-judge a different award than the one meant.
  final List<OrchestratorRoleGoalCompletion> goalCompletion;
  final List<OrchestratorSuggestion> shuffledChoices;

  final OrchestratorSuggestion? selectedChoice;
  final OrchestratorSuggestion? acceptedChoice;

  ActiveSuggestionModel({
    required this.suggestion,
    required this.basedOnEventId,
    this.goalCompletion = const [],
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
    basedOnEventId: basedOnEventId,
    goalCompletion: goalCompletion,
    selectedChoice: selectedChoice ?? this.selectedChoice,
    acceptedChoice: acceptedChoice ?? this.acceptedChoice,
    shuffledChoices: shuffledChoices,
  );
}
