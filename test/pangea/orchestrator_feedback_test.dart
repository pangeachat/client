import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/active_suggestion_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_feedback_repo.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_goal_completion.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_role_suggestions.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_suggestion.dart';

void main() {
  group('OrchestratorFeedbackPart', () {
    test('sends the wire values the endpoint accepts', () {
      // The server constrains `part` to exactly these two; a Dart enum name
      // (goalCompletion) would be a 422.
      expect(OrchestratorFeedbackPart.suggestion.wireValue, 'suggestion');
      expect(
        OrchestratorFeedbackPart.goalCompletion.wireValue,
        'goal_completion',
      );
    });
  });

  group('ActiveSuggestionModel carries the turn it came from', () {
    ActiveSuggestionModel model() => ActiveSuggestionModel(
      suggestion: OrchestratorRoleSuggestions(
        roleId: 'customer',
        suggestions: const [
          OrchestratorSuggestion(
            text: 'Buenas tardes',
            type: OrchestratorSuggestionType.best,
          ),
        ],
      ),
      basedOnEventId: r'$evt001',
      goalCompletion: const [
        OrchestratorRoleGoalCompletion(
          roleId: 'customer',
          goalIds: ['greet', 'ask_drinks'],
        ),
      ],
    );

    test('exposes the id the flag points at', () {
      expect(model().basedOnEventId, r'$evt001');
    });

    test('carries the turn\'s awards for the picker', () {
      // A goal flag must name one of these. Prose alone made the model
      // re-judge a different award than the reviewer meant.
      expect(model().goalCompletion.single.goalIds, ['greet', 'ask_drinks']);
    });

    test('copyWith keeps the awards too', () {
      final selected = model().copyWith(
        selectedChoice: model().suggestion.suggestions.first,
      );
      expect(selected.goalCompletion.single.goalIds, ['greet', 'ask_drinks']);
    });

    test('copyWith keeps it', () {
      // A tapped choice must not lose the pointer — the flag is most likely
      // pressed after interacting with the card.
      final selected = model().copyWith(
        selectedChoice: model().suggestion.suggestions.first,
      );
      expect(selected.basedOnEventId, r'$evt001');
    });
  });
}
