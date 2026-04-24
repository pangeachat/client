import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/tokens/tokens_util.dart';

PangeaToken _token({
  required String content,
  required int offset,
  String pos = 'NOUN',
}) {
  return PangeaToken(
    text: PangeaTokenText.fromJson({'content': content, 'offset': offset}),
    lemma: Lemma(text: content, saveVocab: false, form: content),
    pos: pos,
    morph: const {},
  );
}

String _sliceByGraphemes(String text, int startIndex, int endIndex) {
  return text.characters
      .skip(startIndex)
      .take(endIndex - startIndex)
      .toString();
}

void main() {
  group('TokensUtil.getGlobalTokenPositions', () {
    test('ASCII: hello world — positions match rendered substrings', () {
      const transcript = 'hello world';
      final tokens = [
        _token(content: 'hello', offset: 0),
        _token(content: 'world', offset: 6),
      ];

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      // One gap (" ") + two tokens.
      final wordSlices = positions
          .where((p) => p.token != null)
          .map((p) => _sliceByGraphemes(transcript, p.startIndex, p.endIndex))
          .toList();

      expect(wordSlices, ['hello', 'world']);
    });

    test(
      'Punjabi (issue #1963): "ਕਿਰਪਾ ਕਰਕੇ" — both words fully selectable',
      () {
        // From the bug report: token offsets are code-points (Python len()).
        // "ਕਿਰਪਾ" = 5 code points, 3 grapheme clusters (ਕਿ, ਰ, ਪਾ)
        // "ਕਰਕੇ"  = 4 code points, 3 grapheme clusters (ਕ, ਰ, ਕੇ)
        const transcript = 'ਕਿਰਪਾ ਕਰਕੇ';
        final tokens = [
          _token(content: 'ਕਿਰਪਾ', offset: 0),
          _token(content: 'ਕਰਕੇ', offset: 6),
        ];

        final positions = TokensUtil.instance.getGlobalTokenPositions(
          tokens,
          transcript: transcript,
        );

        final wordSlices = positions
            .where((p) => p.token != null)
            .map((p) => _sliceByGraphemes(transcript, p.startIndex, p.endIndex))
            .toList();

        expect(wordSlices, ['ਕਿਰਪਾ', 'ਕਰਕੇ']);
      },
    );

    test('Bangla with emoji — full words + ZWJ-less emoji all recoverable', () {
      // From the bug report's second payload:
      //   "ঠিক আছে, kelrap; আমি এখানেই আছি 😄"
      // Emoji 😄 is 1 code point (Python len), but 2 UTF-16 code units in
      // Dart; grapheme count 1. The backend emits offset=32 in code-points.
      const transcript = 'ঠিক আছে, kelrap; আমি এখানেই আছি 😄';
      final tokens = [
        _token(content: 'ঠিক', offset: 0),
        _token(content: 'আছে', offset: 4),
        _token(content: ',', offset: 7, pos: 'PUNCT'),
        _token(content: 'kelrap', offset: 9),
        _token(content: ';', offset: 15, pos: 'PUNCT'),
        _token(content: 'আমি', offset: 17),
        _token(content: 'এখানেই', offset: 21),
        _token(content: 'আছি', offset: 28),
        _token(content: '😄', offset: 32),
      ];

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      final wordSlices = positions
          .where((p) => p.token != null)
          .map((p) => _sliceByGraphemes(transcript, p.startIndex, p.endIndex))
          .toList();

      // Note: punctuation tokens get merged with adjacent tokens by the
      // existing algorithm; we just require every non-punct word plus the
      // emoji to be fully recoverable as a substring.
      expect(wordSlices, contains('ঠিক'));
      expect(wordSlices.any((s) => s.contains('আছে')), isTrue);
      expect(wordSlices.any((s) => s.contains('kelrap')), isTrue);
      expect(wordSlices, contains('আমি'));
      expect(wordSlices, contains('এখানেই'));
      expect(wordSlices.any((s) => s.contains('আছি')), isTrue);
      expect(wordSlices, contains('😄'));
    });

    test(
      'token positions tile the transcript without overlap and cover it',
      () {
        const transcript = 'ਕਿਰਪਾ ਕਰਕੇ';
        final tokens = [
          _token(content: 'ਕਿਰਪਾ', offset: 0),
          _token(content: 'ਕਰਕੇ', offset: 6),
        ];

        final positions = TokensUtil.instance.getGlobalTokenPositions(
          tokens,
          transcript: transcript,
        );

        // Adjacency: each position's endIndex == next position's startIndex.
        for (var i = 0; i < positions.length - 1; i++) {
          expect(positions[i].endIndex, positions[i + 1].startIndex);
        }
        // First starts at 0, last ends at grapheme count.
        expect(positions.first.startIndex, 0);
        expect(positions.last.endIndex, transcript.characters.length);
      },
    );
  });
}
