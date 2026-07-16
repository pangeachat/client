import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/morphs/grammar_meaning_feedback_repo.dart';

void main() {
  group('GrammarMeaningFeedbackResponse.fromJson', () {
    final bundle = {
      'feature': 'Tense',
      'feature_title': 'Tiempo verbal',
      'values': [
        {
          'value': 'Past',
          'title': 'Pasado',
          'description': 'Acciones terminadas.',
        },
      ],
    };

    test('parses the gate reply fields (choreo #2769)', () {
      final response = GrammarMeaningFeedbackResponse.fromJson({
        ...bundle,
        'user_friendly_response': 'Thanks! We simplified the explanation.',
        'edits_applied': true,
      });
      expect(
        response.userFriendlyResponse,
        'Thanks! We simplified the explanation.',
      );
      expect(response.editsApplied, true);
      expect(response.appliedEdits, true);
      expect(response.values.single.title, 'Pasado');
    });

    test('declined feedback carries edits_applied false', () {
      final response = GrammarMeaningFeedbackResponse.fromJson({
        ...bundle,
        'user_friendly_response': 'That is out of scope.',
        'edits_applied': false,
      });
      expect(response.appliedEdits, false);
    });

    test('pre-gate server response (no reply fields) parses and counts '
        'as applied', () {
      final response = GrammarMeaningFeedbackResponse.fromJson(bundle);
      expect(response.userFriendlyResponse, isNull);
      expect(response.editsApplied, isNull);
      expect(response.appliedEdits, true);
    });
  });
}
