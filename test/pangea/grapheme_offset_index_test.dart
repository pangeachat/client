import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/tokens/grapheme_offset_index.dart';

/// Exhaustive unit tests for [GraphemeOffsetIndex].
///
/// The map converts **code-point offsets** (Python `len()` / Dart `runes`
/// semantics — what backend tokenizers emit) into **grapheme-cluster
/// indices** (what Dart's `String.characters` slices by). Bugs in this
/// translation are the root of issue #1963, so each scripting category that
/// stresses the distinction has its own test.
void main() {
  group('GraphemeOffsetIndex.fromText — structural properties', () {
    test('empty string has zero graphemes and zero code points', () {
      final index = GraphemeOffsetIndex.fromText('');
      expect(index.graphemeCount, 0);
      expect(index.codepointCount, 0);
      expect(index.graphemeStartOfCodepoint(0), 0);
      expect(index.graphemeEndOfCodepoint(0), 0);
    });

    test('ASCII: grapheme count equals code point count equals length', () {
      const text = 'hello world';
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.graphemeCount, text.length);
      expect(index.codepointCount, text.length);
      expect(index.graphemeCount, text.characters.length);
    });

    test('CJK ideographs: 1 codepoint == 1 grapheme (no matras)', () {
      const text = '你好世界'; // 4 Han characters
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.graphemeCount, 4);
      expect(index.codepointCount, 4);
    });

    test('Punjabi (Gurmukhi): matras collapse code points into graphemes', () {
      // "ਕਿਰਪਾ" = 5 code points; graphemes: [ਕਿ, ਰ, ਪਾ] = 3
      const text = 'ਕਿਰਪਾ';
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.codepointCount, 5);
      expect(index.graphemeCount, 3);
      expect(index.graphemeCount, text.characters.length);
    });

    test('Devanagari (Hindi): virama + consonant form conjunct graphemes', () {
      // "नमस्ते" - the virama ् creates conjuncts; exact count depends on ICU
      // rules, so we assert against the authoritative `characters` iterator.
      const text = 'नमस्ते';
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.codepointCount, text.runes.length);
      expect(index.graphemeCount, text.characters.length);
      expect(index.graphemeCount, lessThan(index.codepointCount));
    });

    test('Tamil: vowel signs attach to consonants', () {
      const text = 'வணக்கம்'; // "hello"
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.codepointCount, text.runes.length);
      expect(index.graphemeCount, text.characters.length);
      expect(index.graphemeCount, lessThan(index.codepointCount));
    });

    test('Vietnamese: combining diacritics', () {
      // Using decomposed form to guarantee multi-codepoint graphemes.
      // "tiếng" with the composed ế = t + i + ế + n + g or decomposed variant
      const text =
          'tiếng'; // may be precomposed (1cp per grapheme) depending on source
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.codepointCount, text.runes.length);
      expect(index.graphemeCount, text.characters.length);
    });

    test('Supplementary-plane emoji: 1 code point = 1 grapheme', () {
      const text = '😄'; // U+1F604 — 1 code point, 2 UTF-16 units, 1 grapheme
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.graphemeCount, 1);
      expect(index.codepointCount, 1);
    });

    test('ZWJ family emoji collapses multiple code points into 1 grapheme', () {
      // 👨‍👩‍👧 = 👨 + ZWJ + 👩 + ZWJ + 👧 = 5 code points, 1 grapheme
      const text = '👨‍👩‍👧';
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.codepointCount, 5);
      expect(index.graphemeCount, 1);
    });

    test('Skin-tone modifier: base + modifier = 1 grapheme', () {
      const text =
          '👍🏽'; // thumbs up + medium skin tone = 2 code points, 1 grapheme
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.codepointCount, 2);
      expect(index.graphemeCount, 1);
    });

    test('Flag emoji: two regional indicators = 1 grapheme', () {
      const text = '🇺🇸'; // U+1F1FA + U+1F1F8
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.codepointCount, 2);
      expect(index.graphemeCount, 1);
    });

    test('Mixed scripts: sum of per-segment counts', () {
      const text = 'hi ਕਿਰਪਾ 😄 नमस्ते';
      final index = GraphemeOffsetIndex.fromText(text);
      expect(index.codepointCount, text.runes.length);
      expect(index.graphemeCount, text.characters.length);
    });
  });

  group('GraphemeOffsetIndex.graphemeStartOfCodepoint', () {
    test('clamps negative input to 0', () {
      final index = GraphemeOffsetIndex.fromText('hello');
      expect(index.graphemeStartOfCodepoint(-1), 0);
      expect(index.graphemeStartOfCodepoint(-100), 0);
    });

    test('clamps input >= codepointCount to graphemeCount', () {
      final index = GraphemeOffsetIndex.fromText('hello');
      expect(index.graphemeStartOfCodepoint(5), 5);
      expect(index.graphemeStartOfCodepoint(100), 5);
    });

    test('ASCII: grapheme start equals code point', () {
      final index = GraphemeOffsetIndex.fromText('hello');
      for (var i = 0; i <= 5; i++) {
        expect(index.graphemeStartOfCodepoint(i), i);
      }
    });

    test(
      'Punjabi: code points inside a matra cluster map to cluster start',
      () {
        // "ਕਿਰਪਾ" — graphemes: ਕਿ (cp 0-1), ਰ (cp 2), ਪਾ (cp 3-4)
        final index = GraphemeOffsetIndex.fromText('ਕਿਰਪਾ');
        expect(index.graphemeStartOfCodepoint(0), 0); // ਕ → grapheme 0 (ਕਿ)
        expect(index.graphemeStartOfCodepoint(1), 0); // ਿ → grapheme 0 (ਕਿ)
        expect(index.graphemeStartOfCodepoint(2), 1); // ਰ → grapheme 1
        expect(index.graphemeStartOfCodepoint(3), 2); // ਪ → grapheme 2 (ਪਾ)
        expect(index.graphemeStartOfCodepoint(4), 2); // ਾ → grapheme 2 (ਪਾ)
      },
    );

    test(
      'ZWJ sequence: all interior code points map to the single grapheme',
      () {
        const text = '👨‍👩‍👧';
        final index = GraphemeOffsetIndex.fromText(text);
        for (var cp = 0; cp < 5; cp++) {
          expect(index.graphemeStartOfCodepoint(cp), 0);
        }
        expect(index.graphemeStartOfCodepoint(5), 1); // past end
      },
    );
  });

  group('GraphemeOffsetIndex.graphemeEndOfCodepoint', () {
    test('clamps negative input to 0', () {
      final index = GraphemeOffsetIndex.fromText('hello');
      expect(index.graphemeEndOfCodepoint(-1), 0);
    });

    test('clamps input >= codepointCount to graphemeCount', () {
      final index = GraphemeOffsetIndex.fromText('hello');
      expect(index.graphemeEndOfCodepoint(5), 5);
      expect(index.graphemeEndOfCodepoint(100), 5);
    });

    test('end at 0 is always 0 (empty range)', () {
      final index = GraphemeOffsetIndex.fromText('ਕਿਰਪਾ');
      expect(index.graphemeEndOfCodepoint(0), 0);
    });

    test('end at a grapheme boundary returns that grapheme index exactly', () {
      // "ਕਿਰਪਾ" — grapheme starts: [0, 2, 3]
      final index = GraphemeOffsetIndex.fromText('ਕਿਰਪਾ');
      expect(index.graphemeEndOfCodepoint(2), 1); // includes ਕਿ only
      expect(index.graphemeEndOfCodepoint(3), 2); // includes ਕਿ + ਰ
      expect(index.graphemeEndOfCodepoint(5), 3); // includes all
    });

    test('end inside a grapheme rounds up (never silently truncates)', () {
      // "ਕਿਰਪਾ" — cp 1 is inside grapheme 0; ending there should still
      // include grapheme 0 (rounding up) rather than returning 0.
      final index = GraphemeOffsetIndex.fromText('ਕਿਰਪਾ');
      expect(index.graphemeEndOfCodepoint(1), 1);
      expect(index.graphemeEndOfCodepoint(4), 3); // cp 4 inside ਪਾ
    });

    test('ZWJ sequence: end anywhere past start of sequence yields 1', () {
      const text = '👨‍👩‍👧';
      final index = GraphemeOffsetIndex.fromText(text);
      for (var cp = 1; cp <= 5; cp++) {
        expect(index.graphemeEndOfCodepoint(cp), 1);
      }
    });
  });

  group('GraphemeOffsetIndex — invariants over every position', () {
    // Running the same structural properties across every script keeps us
    // honest if the underlying `characters` package ever changes.
    final samples = <String>[
      '',
      'hello',
      '你好世界',
      'ਕਿਰਪਾ ਕਰਕੇ',
      'ঠিক আছে',
      'नमस्ते दुनिया',
      'வணக்கம்',
      'tiếng Việt',
      '😄',
      '👍🏽',
      '🇺🇸🇯🇵🇰🇷',
      '👨‍👩‍👧',
      'a👨‍👩‍👧b',
      'hi ਕਿਰਪਾ 😄 नमस्ते',
    ];

    for (final text in samples) {
      test('monotonic + range-consistent on: ${_label(text)}', () {
        final index = GraphemeOffsetIndex.fromText(text);

        expect(index.codepointCount, text.runes.length);
        expect(index.graphemeCount, text.characters.length);

        // Every code-point position maps to a valid grapheme index.
        for (var cp = 0; cp <= index.codepointCount; cp++) {
          final gs = index.graphemeStartOfCodepoint(cp);
          final ge = index.graphemeEndOfCodepoint(cp);
          expect(gs, inInclusiveRange(0, index.graphemeCount));
          expect(ge, inInclusiveRange(0, index.graphemeCount));
          // start(cp) <= end(cp) — the grapheme containing cp is always at or
          // before the exclusive end of a range ending at cp.
          expect(gs, lessThanOrEqualTo(ge));
        }

        // Monotonicity: start and end are non-decreasing.
        int prevStart = 0, prevEnd = 0;
        for (var cp = 0; cp <= index.codepointCount; cp++) {
          final gs = index.graphemeStartOfCodepoint(cp);
          final ge = index.graphemeEndOfCodepoint(cp);
          expect(gs, greaterThanOrEqualTo(prevStart));
          expect(ge, greaterThanOrEqualTo(prevEnd));
          prevStart = gs;
          prevEnd = ge;
        }

        // Round-trip: every [graphemeStart, graphemeEnd) produces the
        // expected substring when sliced by `characters`.
        final chars = text.characters.toList();
        int cursor = 0;
        for (var gi = 0; gi < index.graphemeCount; gi++) {
          // Start of grapheme gi in code points.
          final startCp = cursor;
          final endCp = cursor + chars[gi].runes.length;
          expect(index.graphemeStartOfCodepoint(startCp), gi);
          expect(index.graphemeEndOfCodepoint(endCp), gi + 1);
          cursor = endCp;
        }
      });
    }
  });
}

String _label(String text) => text.isEmpty
    ? '<empty>'
    : (text.length > 20 ? '${text.substring(0, 20)}…' : text);
