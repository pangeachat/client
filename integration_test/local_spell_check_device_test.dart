import 'dart:ui';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Exercises the real platform spell checker, which no unit test can reach —
/// every other test in this feature stands in a fake for the method channel.
///
/// These assertions are the contract `local_spell_check.dart` is built on:
/// that the channel answers at all, and that its offsets are UTF-16 code
/// units rather than grapheme clusters. The rest is reported rather than
/// asserted, because dictionary availability varies by device and OS version
/// and a hard expectation would be flaky rather than informative.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A fresh service per call: DefaultSpellCheckService caches its last
  // results and merges into them, which would blur one probe into the next.
  Future<List<SuggestionSpan>?> check(String text, Locale locale) =>
      DefaultSpellCheckService().fetchSpellCheckSuggestions(locale, text);

  test('the platform answers a spell check request', () async {
    final result = await check('I have a speling mistake', const Locale('en'));

    debugPrint('[probe] en misspelling -> $result');
    expect(
      result,
      isNotNull,
      reason: 'the channel returned null for a language iOS should know',
    );
    expect(result, isNotEmpty, reason: 'a clear misspelling was not flagged');
  });

  test('offsets are UTF-16 code units, not graphemes', () async {
    // The emoji is one grapheme and two UTF-16 code units. If the platform
    // counted graphemes, the span would start at 2 instead of 3 — and
    // GraphemeOffsetIndex.fromTextUtf16 would be converting the wrong unit.
    const text = 'a 👍 speling';
    final result = await check(text, const Locale('en'));

    debugPrint('[probe] emoji offsets -> $result');
    expect(result, isNotNull);
    expect(result, isNotEmpty);

    final span = result!.first;
    expect(
      text.substring(span.range.start, span.range.end),
      'speling',
      reason: 'range does not slice the misspelled word in UTF-16 units',
    );
    expect(
      span.range.start,
      text.indexOf('speling'),
      reason: 'offsets are not UTF-16 code units',
    );
  });

  test('clean text comes back empty rather than null', () async {
    final result = await check('This sentence is spelled correctly.',
        const Locale('en'));

    debugPrint('[probe] clean text -> $result');
    expect(
      result,
      isNotNull,
      reason: 'clean text must be distinguishable from a failed lookup',
    );
    expect(result, isEmpty);
  });

  test('REPORT: what an unavailable dictionary returns', () async {
    // The whole no-dictionary fallback rests on this being null rather than
    // an empty list. Reported, not asserted: whether a given locale is
    // absent depends on the device, so a hard expectation would be flaky.
    for (final tag in ['zu', 'yo', 'haw', 'cy', 'is']) {
      final result = await check('qwrtplkjhgfd asdfghjkl', Locale(tag));
      debugPrint(
        '[probe] locale $tag -> ${result == null ? 'NULL' : '${result.length} spans'}',
      );
    }
  });

  test('REPORT: does a suggestion ever echo the flagged word', () async {
    for (final word in ['Mumbai', 'Nairobi', 'kimchi', 'wrold', 'teh']) {
      final result = await check(word, const Locale('en'));
      final first = (result != null && result.isNotEmpty)
          ? result.first.suggestions
          : const <String>[];
      debugPrint(
        '[probe] "$word" -> ${result == null ? 'NULL' : first.take(3).toList()}'
        '${first.isNotEmpty && first.first == word ? '  <-- ECHOES INPUT' : ''}',
      );
    }
  });

  test('REPORT: a non-English dictionary', () async {
    for (final probe in {'es': 'Hoy es un dia bonto', 'fr': 'Je suis alle'}
        .entries) {
      final result = await check(probe.value, Locale(probe.key));
      debugPrint(
        '[probe] ${probe.key} "${probe.value}" -> '
        '${result == null ? 'NULL' : result.map((s) => s.suggestions.take(2).toList()).toList()}',
      );
    }
  });
}
