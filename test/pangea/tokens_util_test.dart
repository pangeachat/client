import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/tokens/tokens_util.dart';

/// Exhaustive tests for [TokensUtil.getGlobalTokenPositions], the function
/// whose mixed-unit indexing caused issue #1963.
///
/// The strategy has three layers:
/// 1. **Reproducers** — the exact payloads from the bug report.
/// 2. **Script coverage** — one test per language category that has any
///    multi-codepoint grapheme (Indic matras, Vietnamese diacritics,
///    ZWJ emoji, skin-tone modifiers, flag emoji, supplementary plane).
/// 3. **Edge cases + invariants** — algorithmic behavior (gaps, empty input,
///    punctuation merging, tiling, content recovery).

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

/// Builds a token list from a transcript by finding each word in code-point
/// space — the same unit the backend emits offsets in. This lets tests for
/// Hindi/Tamil/etc. stay correct without hardcoding per-script offsets.
List<PangeaToken> _tokensFor(
  String transcript,
  List<({String content, String pos})> words,
) {
  final runes = transcript.runes.toList();
  int cursor = 0;
  final List<PangeaToken> tokens = [];
  for (final w in words) {
    final wRunes = w.content.runes.toList();
    int found = -1;
    for (var i = cursor; i <= runes.length - wRunes.length; i++) {
      bool match = true;
      for (var j = 0; j < wRunes.length; j++) {
        if (runes[i + j] != wRunes[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        found = i;
        break;
      }
    }
    if (found < 0) {
      throw StateError(
        '"${w.content}" not found in "$transcript" at/after cp $cursor',
      );
    }
    tokens.add(_token(content: w.content, offset: found, pos: w.pos));
    cursor = found + wRunes.length;
  }
  return tokens;
}

String _slice(String transcript, int startIndex, int endIndex) {
  return transcript.characters
      .skip(startIndex)
      .take(endIndex - startIndex)
      .toString();
}

/// Every input token's content must appear somewhere in one of the emitted
/// position slices. Punctuation tokens may be absorbed into an adjacent
/// position rather than keeping their own, so we check substring presence
/// across all slices rather than requiring each token to be a position's
/// representative.
void _expectAllContentPresent(
  String transcript,
  List<PangeaToken> tokens,
  List<TokenPosition> positions,
) {
  final allSlices = positions
      .map((p) => _slice(transcript, p.startIndex, p.endIndex))
      .toList();

  // Sanity check: for token-bearing positions, the slice always contains the
  // representative token's content.
  for (final p in positions) {
    if (p.token == null) continue;
    final slice = _slice(transcript, p.startIndex, p.endIndex);
    expect(
      slice,
      contains(p.token!.text.content),
      reason:
          'representative token "${p.token!.text.content}" missing from slice "$slice"',
    );
  }

  for (final t in tokens) {
    final found = allSlices.any((s) => s.contains(t.text.content));
    expect(
      found,
      isTrue,
      reason:
          'no position slice contains "${t.text.content}"; slices: $allSlices',
    );
  }
}

/// Positions are contiguous, non-overlapping, and cover [0, graphemeCount].
void _expectTiling(String transcript, List<TokenPosition> positions) {
  if (positions.isEmpty) return;
  expect(positions.first.startIndex, 0, reason: 'first position starts at 0');
  expect(
    positions.last.endIndex,
    transcript.characters.length,
    reason: 'last position ends at graphemeCount',
  );
  for (var i = 0; i < positions.length - 1; i++) {
    expect(
      positions[i].endIndex,
      positions[i + 1].startIndex,
      reason: 'gap or overlap between positions $i and ${i + 1}',
    );
  }
  for (final p in positions) {
    expect(p.startIndex, lessThanOrEqualTo(p.endIndex));
  }
}

void main() {
  // -------------------------------------------------------------------------
  // 1. Reproducers — exact inputs from issue #1963.
  // -------------------------------------------------------------------------
  group('TokensUtil.getGlobalTokenPositions — issue #1963 reproducers', () {
    test('Punjabi: "ਕਿਰਪਾ ਕਰਕੇ" — both words fully tappable', () {
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
          .map((p) => _slice(transcript, p.startIndex, p.endIndex))
          .toList();

      expect(wordSlices, ['ਕਿਰਪਾ', 'ਕਰਕੇ']);
      _expectTiling(transcript, positions);
    });

    test(
      'Bangla + supplementary-plane emoji: every word + the emoji tappable',
      () {
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

        _expectAllContentPresent(transcript, tokens, positions);
        _expectTiling(transcript, positions);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 2. Script coverage — multi-codepoint graphemes in a variety of scripts.
  // -------------------------------------------------------------------------
  group('TokensUtil.getGlobalTokenPositions — script coverage', () {
    test('ASCII (regression): positions are trivial', () {
      const transcript = 'hello world';
      final tokens = _tokensFor(transcript, [
        (content: 'hello', pos: 'NOUN'),
        (content: 'world', pos: 'NOUN'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('CJK ideographs: no matras, one codepoint per grapheme', () {
      const transcript = '你好 世界';
      final tokens = _tokensFor(transcript, [
        (content: '你好', pos: 'NOUN'),
        (content: '世界', pos: 'NOUN'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('Hindi (Devanagari): virama conjuncts', () {
      const transcript = 'नमस्ते दुनिया';
      final tokens = _tokensFor(transcript, [
        (content: 'नमस्ते', pos: 'NOUN'),
        (content: 'दुनिया', pos: 'NOUN'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('Tamil: consonant + vowel-sign sequences', () {
      const transcript = 'வணக்கம் உலகம்';
      final tokens = _tokensFor(transcript, [
        (content: 'வணக்கம்', pos: 'NOUN'),
        (content: 'உலகம்', pos: 'NOUN'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('Thai: no spaces between words (segmented tokens)', () {
      // Thai doesn't use spaces, so tokens butt right up against each other.
      const transcript = 'สวัสดีครับ';
      final tokens = _tokensFor(transcript, [
        (content: 'สวัสดี', pos: 'NOUN'),
        (content: 'ครับ', pos: 'PART'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('Arabic (RTL, ligatures)', () {
      const transcript = 'مرحبا بالعالم';
      final tokens = _tokensFor(transcript, [
        (content: 'مرحبا', pos: 'NOUN'),
        (content: 'بالعالم', pos: 'NOUN'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('Mixed scripts in one transcript', () {
      const transcript = 'hi नमस्ते ਕਿਰਪਾ 😄';
      final tokens = _tokensFor(transcript, [
        (content: 'hi', pos: 'INTJ'),
        (content: 'नमस्ते', pos: 'INTJ'),
        (content: 'ਕਿਰਪਾ', pos: 'NOUN'),
        (content: '😄', pos: 'SYM'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });
  });

  // -------------------------------------------------------------------------
  // 3. Emoji coverage — each structural variant that produces multi-codepoint
  //    graphemes.
  // -------------------------------------------------------------------------
  group('TokensUtil.getGlobalTokenPositions — emoji coverage', () {
    test('Simple supplementary-plane emoji at start of transcript', () {
      const transcript = '😀 hello';
      final tokens = _tokensFor(transcript, [
        (content: '😀', pos: 'SYM'),
        (content: 'hello', pos: 'NOUN'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('Skin-tone modifier (👍🏽) — base + modifier form one grapheme', () {
      const transcript = 'nice 👍🏽';
      final tokens = _tokensFor(transcript, [
        (content: 'nice', pos: 'ADJ'),
        (content: '👍🏽', pos: 'SYM'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('Flag emoji (🇺🇸) — regional indicators form one grapheme', () {
      const transcript = 'from 🇺🇸 to 🇯🇵';
      final tokens = _tokensFor(transcript, [
        (content: 'from', pos: 'ADP'),
        (content: '🇺🇸', pos: 'SYM'),
        (content: 'to', pos: 'ADP'),
        (content: '🇯🇵', pos: 'SYM'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('ZWJ family emoji (👨‍👩‍👧) — 5 code points, 1 grapheme', () {
      const transcript = 'my family 👨‍👩‍👧';
      final tokens = _tokensFor(transcript, [
        (content: 'my', pos: 'PRON'),
        (content: 'family', pos: 'NOUN'),
        (content: '👨‍👩‍👧', pos: 'SYM'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('Emoji immediately between two words (no whitespace)', () {
      const transcript = 'hi😄hello';
      final tokens = _tokensFor(transcript, [
        (content: 'hi', pos: 'INTJ'),
        (content: '😄', pos: 'SYM'),
        (content: 'hello', pos: 'INTJ'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });
  });

  // -------------------------------------------------------------------------
  // 4. Edge cases for the algorithm itself.
  // -------------------------------------------------------------------------
  group('TokensUtil.getGlobalTokenPositions — edge cases', () {
    test('empty token list returns empty positions', () {
      final positions = TokensUtil.instance.getGlobalTokenPositions(
        [],
        transcript: 'hello',
      );
      expect(positions, isEmpty);
    });

    test('single token covering the whole transcript', () {
      const transcript = 'hello';
      final tokens = [_token(content: 'hello', offset: 0)];

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      expect(positions, hasLength(1));
      expect(positions.first.token?.text.content, 'hello');
      expect(positions.first.startIndex, 0);
      expect(positions.first.endIndex, transcript.characters.length);
    });

    test('single token with leading whitespace emits a gap position first', () {
      const transcript = '  hello';
      final tokens = [_token(content: 'hello', offset: 2)];

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      expect(positions, hasLength(2));
      expect(positions.first.token, isNull);
      expect(
        _slice(
          transcript,
          positions.first.startIndex,
          positions.first.endIndex,
        ),
        '  ',
      );
      expect(positions.last.token?.text.content, 'hello');
    });

    test(
      'single token with trailing whitespace leaves the trailing gap out',
      () {
        // The algorithm advances globalPointer only up to the last emitted
        // token; anything after is not emitted. That matches existing behavior
        // on main; we assert it explicitly so future changes surface.
        const transcript = 'hello  ';
        final tokens = [_token(content: 'hello', offset: 0)];

        final positions = TokensUtil.instance.getGlobalTokenPositions(
          tokens,
          transcript: transcript,
        );

        expect(positions, hasLength(1));
        expect(positions.first.endIndex, 5); // trailing spaces not emitted
      },
    );

    test('adjacent tokens with no gap produce no gap position', () {
      // Hindi doesn't separate these, but for the sake of the test we
      // construct adjacent tokens directly.
      const transcript = 'abcd';
      final tokens = [
        _token(content: 'ab', offset: 0),
        _token(content: 'cd', offset: 2),
      ];

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      // Two token positions, zero gaps.
      expect(positions.where((p) => p.token == null), isEmpty);
      expect(positions, hasLength(2));
    });

    test('word + trailing punctuation merges when adjacent', () {
      const transcript = 'hello,';
      final tokens = [
        _token(content: 'hello', offset: 0),
        _token(content: ',', offset: 5, pos: 'PUNCT'),
      ];

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      // Existing algorithm merges adjacent non-punct + punct pairs into a
      // single position. We assert the combined slice contains both.
      expect(positions.where((p) => p.token != null), hasLength(1));
      final slice = _slice(
        transcript,
        positions.first.startIndex,
        positions.first.endIndex,
      );
      expect(slice, 'hello,');
    });

    test('leading punctuation + word merges', () {
      const transcript = '¡hola';
      final tokens = [
        _token(content: '¡', offset: 0, pos: 'PUNCT'),
        _token(content: 'hola', offset: 1),
      ];

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      expect(positions.where((p) => p.token != null), hasLength(1));
      expect(
        _slice(
          transcript,
          positions.first.startIndex,
          positions.first.endIndex,
        ),
        '¡hola',
      );
    });

    test('punctuation with a gap before the next word does NOT merge', () {
      const transcript = ', hello';
      final tokens = [
        _token(content: ',', offset: 0, pos: 'PUNCT'),
        _token(content: 'hello', offset: 2),
      ];

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      // Comma, then a gap (space), then hello — three positions.
      expect(positions, hasLength(3));
      expect(positions[0].token?.text.content, ',');
      expect(positions[1].token, isNull);
      expect(positions[2].token?.text.content, 'hello');
    });

    test('three consecutive punctuation tokens merge into one position', () {
      const transcript = '...';
      final tokens = [
        _token(content: '.', offset: 0, pos: 'PUNCT'),
        _token(content: '.', offset: 1, pos: 'PUNCT'),
        _token(content: '.', offset: 2, pos: 'PUNCT'),
      ];

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      expect(positions, hasLength(1));
      expect(
        _slice(
          transcript,
          positions.first.startIndex,
          positions.first.endIndex,
        ),
        '...',
      );
    });

    test('word with a grapheme-multi character in the middle', () {
      // "tiếng" uses the precomposed ế, so it's one grapheme per character,
      // but we test that the algorithm handles offsets correctly regardless.
      const transcript = 'nói tiếng Việt';
      final tokens = _tokensFor(transcript, [
        (content: 'nói', pos: 'VERB'),
        (content: 'tiếng', pos: 'NOUN'),
        (content: 'Việt', pos: 'PROPN'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      _expectAllContentPresent(transcript, tokens, positions);
      _expectTiling(transcript, positions);
    });

    test('multiple spaces between tokens produce one gap position each', () {
      const transcript = 'a    b';
      final tokens = _tokensFor(transcript, [
        (content: 'a', pos: 'NOUN'),
        (content: 'b', pos: 'NOUN'),
      ]);

      final positions = TokensUtil.instance.getGlobalTokenPositions(
        tokens,
        transcript: transcript,
      );

      expect(positions.where((p) => p.token == null), hasLength(1));
      final gap = positions.firstWhere((p) => p.token == null);
      expect(_slice(transcript, gap.startIndex, gap.endIndex), '    ');
    });

    test(
      'transcript can be longer than sum of token spans (trailing gap lost)',
      () {
        // This test documents the known behavior that trailing gaps are not
        // emitted. If this ever needs to change, update both the code and the
        // assertion together.
        const transcript = 'abc def ghi';
        final tokens = _tokensFor(transcript, [
          (content: 'abc', pos: 'NOUN'),
          (content: 'def', pos: 'NOUN'),
        ]);

        final positions = TokensUtil.instance.getGlobalTokenPositions(
          tokens,
          transcript: transcript,
        );

        // Last position ends at end of 'def' (7), not end of transcript (11).
        expect(positions.last.endIndex, 7);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 5. Invariants — run every sample through the same property checks.
  // -------------------------------------------------------------------------
  group(
    'TokensUtil.getGlobalTokenPositions — invariants across many inputs',
    () {
      final samples =
          <({String transcript, List<({String content, String pos})> words})>[
            (
              transcript: 'hello world',
              words: [
                (content: 'hello', pos: 'NOUN'),
                (content: 'world', pos: 'NOUN'),
              ],
            ),
            (
              transcript: 'ਕਿਰਪਾ ਕਰਕੇ',
              words: [
                (content: 'ਕਿਰਪਾ', pos: 'NOUN'),
                (content: 'ਕਰਕੇ', pos: 'VERB'),
              ],
            ),
            (
              transcript: 'नमस्ते दुनिया',
              words: [
                (content: 'नमस्ते', pos: 'NOUN'),
                (content: 'दुनिया', pos: 'NOUN'),
              ],
            ),
            (
              transcript: 'வணக்கம் உலகம்',
              words: [
                (content: 'வணக்கம்', pos: 'NOUN'),
                (content: 'உலகம்', pos: 'NOUN'),
              ],
            ),
            (
              transcript: 'from 🇺🇸 to 🇯🇵',
              words: [
                (content: 'from', pos: 'ADP'),
                (content: '🇺🇸', pos: 'SYM'),
                (content: 'to', pos: 'ADP'),
                (content: '🇯🇵', pos: 'SYM'),
              ],
            ),
            (
              transcript: 'my family 👨‍👩‍👧',
              words: [
                (content: 'my', pos: 'PRON'),
                (content: 'family', pos: 'NOUN'),
                (content: '👨‍👩‍👧', pos: 'SYM'),
              ],
            ),
            (
              transcript: 'nice 👍🏽 work',
              words: [
                (content: 'nice', pos: 'ADJ'),
                (content: '👍🏽', pos: 'SYM'),
                (content: 'work', pos: 'NOUN'),
              ],
            ),
            (
              transcript: '你好 世界',
              words: [
                (content: '你好', pos: 'NOUN'),
                (content: '世界', pos: 'NOUN'),
              ],
            ),
            (
              transcript: 'hi😄hello',
              words: [
                (content: 'hi', pos: 'INTJ'),
                (content: '😄', pos: 'SYM'),
                (content: 'hello', pos: 'INTJ'),
              ],
            ),
          ];

      for (final s in samples) {
        test('tiling + content recovery on: "${s.transcript}"', () {
          final tokens = _tokensFor(s.transcript, s.words);
          final positions = TokensUtil.instance.getGlobalTokenPositions(
            tokens,
            transcript: s.transcript,
          );
          _expectTiling(s.transcript, positions);
          _expectAllContentPresent(s.transcript, tokens, positions);
        });
      }
    },
  );
}
