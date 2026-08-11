import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/toolbar/message_toolbar_host.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/select_mode_buttons.dart';

/// The toolbar's host config (#8081): chat shows everything; the analytics
/// example-message host hides practice, the more menu, the reaction picker,
/// and word-card analytics navigation. [SelectModeButtonsState.visibleModes]
/// is the seam that applies the practice flag to the mode-button row.
void main() {
  group('MessageToolbarConfig presets', () {
    test('chat preset shows the full toolbar', () {
      const config = MessageToolbarConfig.chat;
      expect(config.showPracticeButton, isTrue);
      expect(config.showMoreButton, isTrue);
      expect(config.showReactionPicker, isTrue);
      expect(config.enableWordCardAnalyticsNavigation, isTrue);
      // Chat mirrors the timeline: own messages anchor right.
      expect(config.alignMessageLeft, isFalse);
    });

    test('analyticsExample preset hides chat-only surfaces', () {
      const config = MessageToolbarConfig.analyticsExample;
      expect(config.showPracticeButton, isFalse);
      expect(config.showMoreButton, isFalse);
      expect(config.showReactionPicker, isFalse);
      expect(config.enableWordCardAnalyticsNavigation, isFalse);
      // Example chips are left-aligned whoever sent them, so the word card
      // grows right instead of being squeezed against the left edge (#8252).
      expect(config.alignMessageLeft, isTrue);
    });
  });

  group('SelectModeButtonsState.visibleModes', () {
    const textModes = [
      SelectMode.audio,
      SelectMode.translate,
      SelectMode.practice,
      SelectMode.emoji,
    ];

    test('chat config keeps every mode, in order', () {
      expect(
        SelectModeButtonsState.visibleModes(
          textModes,
          MessageToolbarConfig.chat,
        ),
        textModes,
      );
    });

    test('analyticsExample config filters exactly the practice mode', () {
      expect(
        SelectModeButtonsState.visibleModes(
          textModes,
          MessageToolbarConfig.analyticsExample,
        ),
        [SelectMode.audio, SelectMode.translate, SelectMode.emoji],
      );
    });

    test('modes without practice pass through unchanged', () {
      const translateOnly = [SelectMode.translate];
      expect(
        SelectModeButtonsState.visibleModes(
          translateOnly,
          MessageToolbarConfig.analyticsExample,
        ),
        translateOnly,
      );
      expect(
        SelectModeButtonsState.visibleModes(
          const [],
          MessageToolbarConfig.analyticsExample,
        ),
        isEmpty,
      );
    });
  });
}
