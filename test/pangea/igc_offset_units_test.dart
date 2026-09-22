import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/igc_response_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';

/// #8728: the server addresses spans in Unicode code points; the client counts
/// grapheme clusters. Latin text cannot tell the units apart, so every case here
/// uses text where they differ: Devanagari (several code points per cluster)
/// and emoji (two UTF-16 units per code point, or several code points per
/// cluster when joined).
void main() {
  group('IGCResponseModel converts span offsets', () {
    final cases = <String, ({String text, String target})>{
      'Devanagari, correction at the end': (
        text:
            'मैं कल सुबह बाजार गया था और मैंने बहुत सारी ताजी सब्जियां और '
            'मीठे फल खरीदे बहुत जल्दी',
        target: 'खरीदे बहुत जल्दी',
      ),
      'English phrase after Devanagari': (
        text:
            'मैं कल बाजार गया था और मैंने कुछ सब्जियां खरीदीं but the shop '
            'was closed early',
        target: 'but the shop',
      ),
      'single emoji': (
        text: '🎉 Ayer yo va al mercado y compro muchas frutas',
        target: 'va',
      ),
      'joined emoji before Devanagari': (
        text: '👨‍👩‍👧 मैंने एक अच्छा केला',
        target: 'केला',
      ),
    };

    cases.forEach((name, c) {
      final serverSpan = _spanAt(c.text, c.target);
      final json = _responseJson(c.text, [serverSpan]);

      test('$name: the span covers the text the server meant', () {
        final match = IGCResponseModel.fromJson(json).matches.single.match;
        expect(match.errorSpan, c.target);
      });

      test('$name: feedback sends the server its own offsets back', () {
        final matches =
            IGCResponseModel.fromJson(json).toJson()['matches'] as List;
        final echoed = matches.single as Map<String, dynamic>;
        expect(echoed[ModelKey.offset], serverSpan[ModelKey.offset]);
        expect(echoed[ModelKey.length], serverSpan[ModelKey.length]);
      });
    });

    test('a boundary inside a cluster widens to the whole cluster', () {
      // Code point 1 is the vowel sign inside "मैं", the first cluster.
      final json = _responseJson('मैंने', [
        {
          ModelKey.offset: 1,
          ModelKey.length: 1,
          'choices': [
            {'value': 'मैं', 'type': 'suggestion'},
          ],
          'type': 'grammar',
        },
      ]);
      final match = IGCResponseModel.fromJson(json).matches.single.match;
      expect(match.errorSpan, 'मैं');
    });
  });

  group('IgcController with emoji and Devanagari in one message', () {
    const text =
        '🎉 मैं कल सुबह बाजार गया था और मैंने बहुत सारी ताजी सब्जियां और '
        'मीठे फल खरीदे बहुत जल्दी';
    const corrections = {
      'बाजार': 'बाज़ार',
      'बहुत सारी': 'बहुत सी',
      'खरीदे बहुत जल्दी': 'बहुत जल्दी खरीदे',
    };

    IgcController loadedController() {
      final controller = IgcController((_) {}, () {});
      controller.loadResponse(
        IGCResponseModel.fromJson(
          _responseJson(text, [
            for (final entry in corrections.entries)
              _spanAt(text, entry.key, replacement: entry.value),
          ]),
        ),
      );
      return controller;
    }

    PangeaMatchState matchFor(IgcController controller, String target) =>
        controller.matches.firstWhere(
          (m) => m.originalMatch.match.errorSpan == target,
        );

    void resolve(
      IgcController controller,
      String target,
      PangeaMatchStatusEnum status,
    ) {
      final match = matchFor(controller, target)..selectBestChoice();
      controller.updateMatchStatus(match, status);
    }

    String spanText(IgcController controller, PangeaMatchState match) {
      final span = match.updatedMatch.match;
      return controller.currentText!.characters
          .getRange(span.offset, span.offset + span.length)
          .toString();
    }

    test('accepting every correction replaces each span in place', () {
      final controller = loadedController();
      for (final target in corrections.keys) {
        resolve(controller, target, PangeaMatchStatusEnum.accepted);
      }

      var expected = text;
      corrections.forEach(
        (from, to) => expected = expected.replaceFirst(from, to),
      );
      expect(controller.currentText, expected);

      // The highlight is drawn from these same offsets.
      corrections.forEach((from, to) {
        expect(spanText(controller, matchFor(controller, from)), to);
      });
    });

    test('undoing a middle correction restores only that span', () {
      final controller = loadedController();
      for (final target in corrections.keys) {
        resolve(controller, target, PangeaMatchStatusEnum.accepted);
      }
      controller.updateMatchStatus(
        matchFor(controller, 'बहुत सारी'),
        PangeaMatchStatusEnum.undo,
      );

      expect(
        controller.currentText,
        text
            .replaceFirst('बाजार', 'बाज़ार')
            .replaceFirst('खरीदे बहुत जल्दी', 'बहुत जल्दी खरीदे'),
      );
    });

    test('a tap finds the match under the caret', () {
      final controller = loadedController();
      // The field reports UTF-16 positions; one inside "बहुत सारी".
      final caret = text.indexOf('बहुत सारी') + 2;
      expect(
        controller.getMatchAtFieldOffset(caret),
        same(matchFor(controller, 'बहुत सारी')),
      );
    });

    test('a tap past an auto-applied correction still finds its match', () {
      final controller = loadedController();
      resolve(controller, 'बाजार', PangeaMatchStatusEnum.automatic);

      // The field draws the auto-applied correction as one placeholder unit.
      final autocorrected = matchFor(controller, 'बाजार').updatedMatch.match;
      final chars = controller.currentText!.characters;
      final drawn =
          '${chars.take(autocorrected.offset)}\uFFFC'
          '${chars.skip(autocorrected.offset + autocorrected.length)}';

      expect(
        controller.getMatchAtFieldOffset(drawn.indexOf('बहुत सारी') + 2),
        same(matchFor(controller, 'बहुत सारी')),
      );
      expect(controller.getMatchAtFieldOffset(drawn.indexOf('कल')), isNull);
    });
  });
}

/// A server-shaped span over the first [target] in [text], with offsets in
/// code points as `compute_edit_spans.py` emits them.
Map<String, dynamic> _spanAt(
  String text,
  String target, {
  String replacement = 'x',
}) {
  final utf16Start = text.indexOf(target);
  if (utf16Start < 0) throw ArgumentError('"$target" is not in "$text"');
  return {
    ModelKey.offset: text.substring(0, utf16Start).runes.length,
    ModelKey.length: target.runes.length,
    'choices': [
      {'value': replacement, 'type': 'suggestion'},
    ],
    'type': 'grammar',
  };
}

Map<String, dynamic> _responseJson(
  String text,
  List<Map<String, dynamic>> spans,
) => {
  'original_input': text,
  'full_text_correction': null,
  'matches': spans,
  ModelKey.userL1: 'en',
  ModelKey.userL2: 'hi',
};
