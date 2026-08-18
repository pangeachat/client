import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_user_summaries_widget.dart';

/// Which participant's feedback the finished-activity summary shows.
///
/// The summary used to lay every participant out in a horizontally-scrolling
/// carousel, so a learner had to scroll sideways to reach their own feedback
/// (#8289). One card shows at a time now, and the default has to be the
/// learner's own — the picker is for looking at somebody else on purpose.
void main() {
  ParticipantSummaryModel participant(String userId) => ParticipantSummaryModel(
    participantId: userId,
    feedback: 'feedback for $userId',
    cefrLevel: 'A1',
    superlatives: const [],
  );

  final alice = participant('@alice:example.com');
  final bob = participant('@bob:example.com');
  final carol = participant('@carol:example.com');
  final summaries = [alice, bob, carol];

  group('selectedParticipantSummary', () {
    test('shows the viewer their own feedback before they pick anyone', () {
      expect(
        selectedParticipantSummary(
          summaries: summaries,
          highlightedUserId: null,
          ownUserId: bob.participantId,
        ),
        bob,
      );
    });

    test('a picked participant wins over the viewer\'s own', () {
      expect(
        selectedParticipantSummary(
          summaries: summaries,
          highlightedUserId: carol.participantId,
          ownUserId: bob.participantId,
        ),
        carol,
      );
    });

    test('an observer with no feedback of their own still sees a card', () {
      expect(
        selectedParticipantSummary(
          summaries: summaries,
          highlightedUserId: null,
          ownUserId: '@dave:example.com',
        ),
        alice,
      );
    });

    test('a pick that no longer has a summary falls back to the viewer\'s '
        'own, not to an empty card', () {
      expect(
        selectedParticipantSummary(
          summaries: summaries,
          highlightedUserId: '@dave:example.com',
          ownUserId: bob.participantId,
        ),
        bob,
      );
    });
  });
}
