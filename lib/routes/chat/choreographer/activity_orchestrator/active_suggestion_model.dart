import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';

class ActiveSuggestionModel {
  final OrchestratorRoleSuggestions suggestion;

  /// The `based_on_event_id` of the orchestrator output that produced
  /// this suggestion — the turn internal feedback points at.
  final String basedOnEventId;
  final List<OrchestratorSuggestion> shuffledChoices;

  final OrchestratorSuggestion? selectedChoice;
  final OrchestratorSuggestion? acceptedChoice;

  ActiveSuggestionModel({
    required this.suggestion,
    required this.basedOnEventId,
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
    selectedChoice: selectedChoice ?? this.selectedChoice,
    acceptedChoice: acceptedChoice ?? this.acceptedChoice,
    shuffledChoices: shuffledChoices,
  );
}
