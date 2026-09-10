import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/igc/igc_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_data_model.dart';

/// Regression: Sentry CLIENT-EN8 (#8951).
///
/// `Choreographer._runWritingAssistance` awaits `getIGCTextData` and then calls
/// `acceptNormalizationMatches`. Closing the chat during that await disposes the
/// controller, which closes `matchUpdateStream` — and the accept loop then ran
/// `updateMatchStatus`, whose unguarded `matchUpdateStream.add` throws
/// `StateError: Cannot add new events after calling close`.
///
/// The throw is real in release builds because `StreamController.add` checks its
/// closed state unconditionally, unlike the disposed `ValueNotifier` writes on
/// the same path, which are assert-only and stripped outside debug.
void main() {
  SpanData buildSpan() => SpanData(
    message: null,
    shortMessage: null,
    choices: [SpanChoice(value: 'Hola', type: SpanChoiceTypeEnum.suggestion)],
    offset: 0,
    length: 4,
    fullText: 'hola mundo',
    // An auto-apply type, so the match counts as a normalization error and
    // reaches the accept loop that produced the reported stack.
    type: ReplacementTypeEnum.cap,
    rule: null,
  );

  PangeaMatchState seatMatch(IgcController controller) {
    final span = buildSpan();
    final state = PangeaMatchState(
      original: PangeaMatch(match: span, status: PangeaMatchStatusEnum.open),
      match: span,
      status: PangeaMatchStatusEnum.open,
    );
    controller.setSpanData(state, span);
    return state;
  }

  IgcController buildController() => IgcController((_) {}, () {});

  group('after the chat closes mid-run', () {
    test('updateMatchStatus declines instead of throwing', () {
      final controller = buildController();
      final match = seatMatch(controller);

      controller.dispose();

      expect(controller.isDisposed, isTrue);
      expect(
        () => controller.updateMatchStatus(match, PangeaMatchStatusEnum.viewed),
        returnsNormally,
      );
    });

    test('acceptNormalizationMatches leaves the matches untouched', () async {
      final controller = buildController();
      final match = seatMatch(controller);

      expect(controller.openNormalizationMatches, isNotEmpty);
      controller.dispose();

      await expectLater(controller.acceptNormalizationMatches(), completes);

      // Unguarded, the loop reaches `selectBestChoice` and flips the status to
      // `automatic` before `_applyReplacement` throws into the surrounding
      // try/catch — so "it completed" alone cannot tell the two paths apart.
      expect(match.updatedMatch.status, PangeaMatchStatusEnum.open);
      expect(match.updatedMatch.match.choices!.any((c) => c.selected), isFalse);
    });
  });

  // Negative control: the guard must decline only once disposed. Without this,
  // a guard that always returned early would pass both cases above.
  test('a live controller still publishes match updates', () async {
    final controller = buildController();
    final match = seatMatch(controller);

    final published = controller.matchUpdateStream.stream.first;
    controller.updateMatchStatus(match, PangeaMatchStatusEnum.viewed);

    expect(await published, same(match));
    expect(controller.isDisposed, isFalse);

    controller.dispose();
  });
}
