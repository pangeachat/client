import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/journey_checklist/journey_checklist_model.dart';
import 'package:fluffychat/features/journey_checklist/journey_step_enum.dart';

void main() {
  final earlier = DateTime.fromMillisecondsSinceEpoch(1000);
  final later = DateTime.fromMillisecondsSinceEpoch(2000);

  group('JourneyChecklistModel', () {
    test('a write carries through fields this version does not know', () {
      final json = <String, Object?>{
        'steps': {'complete_practice': 1000, 'step_from_a_newer_client': 1500},
        'prompts': {
          'get_the_app': {'dismissCount': 2},
        },
      };

      final written = JourneyChecklistModel.fromJson(
        json,
      ).withStep(JourneyStep.closeTrialPage, later).toJson();

      expect(written['prompts'], json['prompts']);
      expect(written['steps'], {
        'complete_practice': 1000,
        'step_from_a_newer_client': 1500,
        'close_trial_page': 2000,
      });
    });

    test('a step keeps the time it first happened', () {
      final checklist = const JourneyChecklistModel()
          .withStep(JourneyStep.completePractice, earlier)
          .withStep(JourneyStep.completePractice, later);

      expect(checklist.steps['complete_practice'], earlier);
    });

    test('merging keeps every step at its earliest time', () {
      final synced = const JourneyChecklistModel()
          .withStep(JourneyStep.completePractice, later)
          .withStep(JourneyStep.acceptTranslation, later);
      final unsynced = const JourneyChecklistModel()
          .withStep(JourneyStep.completePractice, earlier)
          .withStep(JourneyStep.viewSubscriptionPage, later);

      expect(synced.merge(unsynced).steps, {
        'complete_practice': earlier,
        'accept_translation': later,
        'view_subscription_page': later,
      });
    });

    test('unreadable step entries are flagged and dropped', () {
      final checklist = JourneyChecklistModel.fromJson({
        'steps': {'complete_practice': 'yesterday', 'close_trial_page': 1000},
      });

      expect(checklist.hadMalformedField, isTrue);
      expect(checklist.steps.keys, ['close_trial_page']);
    });

    test('a steps field that is not a map is flagged', () {
      final checklist = JourneyChecklistModel.fromJson({'steps': 'oops'});

      expect(checklist.hadMalformedField, isTrue);
      expect(checklist.steps, isEmpty);
    });
  });
}
