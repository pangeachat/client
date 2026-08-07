import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/models/llm_feedback_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_constants.dart';

void main() {
  group('LemmaInfoRequest feedback', () {
    LemmaInfoRequest buildRequest({
      List<LLMFeedbackModel<LemmaInfoResponse>> feedback = const [],
    }) => LemmaInfoRequest(
      lemma: 'manzana',
      partOfSpeech: 'noun',
      lemmaLang: 'es',
      userL1: 'en',
      messageInfo: {},
      feedback: feedback,
    );

    test('serializes feedback in the server LLMFeedbackSchema shape', () {
      final prior = LemmaInfoResponse(emoji: ['🍇'], meaning: 'apple');
      final request = buildRequest(
        feedback: [
          LLMFeedbackModel(
            feedback: 'This emoji is a grape, not an apple',
            content: prior,
            contentToJson: (c) => c.toJson(),
          ),
        ],
      );

      final json = request.toJson();
      expect(json['feedback'], [
        {
          ChoreoConstants.feedback: 'This emoji is a grape, not an apple',
          ChoreoConstants.content: {
            'emoji': ['🍇'],
            'meaning': 'apple',
          },
        },
      ]);
    });

    test('serializes an empty list when no feedback is given', () {
      expect(buildRequest().toJson()['feedback'], isEmpty);
    });

    test('storageKey is identical with and without feedback', () {
      // The cache-overwrite invariant: a feedback-bearing request must write
      // its regenerated response into the same cache slot as the plain
      // request, so the corrected content replaces the flagged content.
      final plain = buildRequest();
      final withFeedback = buildRequest(
        feedback: [
          LLMFeedbackModel(
            feedback: 'wrong emoji',
            content: LemmaInfoResponse(emoji: ['🍇'], meaning: 'apple'),
            contentToJson: (c) => c.toJson(),
          ),
        ],
      );

      expect(withFeedback.storageKey, plain.storageKey);
      // But the requests themselves are distinguishable (e.g. for the
      // practice exercise cache, which keys on hashCode).
      expect(withFeedback, isNot(equals(plain)));
    });
  });
}
