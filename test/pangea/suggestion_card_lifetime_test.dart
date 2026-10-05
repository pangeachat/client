import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/assistance_state_enum.dart';

/// #8953 — the suggestion card follows the state that offered it. It is an
/// offer to fill an empty composer, so the learner's first typed character
/// leaves the suggesting states and the card closes with them; left open it
/// sits over the learner's own message and holds the single popup slot the
/// span card needs when they press check.
void main() {
  test('only the lightbulb states keep the suggestion card open', () {
    expect(
      AssistanceStateEnum.values
          .where((state) => state.keepsSuggestionCardOpen)
          .toSet(),
      {
        // A suggestion is waiting on an empty composer.
        AssistanceStateEnum.suggesting,
        // The accepted suggestion's text is now the message; the card closes
        // itself after its confirmation rather than being yanked.
        AssistanceStateEnum.suggestionComplete,
      },
    );
  });

  test("typing the learner's own message withdraws the card", () {
    // The states a composer with text can be in, none of which is an offer to
    // fill it: writing assistance not yet run, running, or done.
    for (final state in [
      AssistanceStateEnum.notFetched,
      AssistanceStateEnum.fetching,
      AssistanceStateEnum.fetched,
      AssistanceStateEnum.igcComplete,
    ]) {
      expect(state.keepsSuggestionCardOpen, isFalse, reason: '$state');
    }
  });
}
