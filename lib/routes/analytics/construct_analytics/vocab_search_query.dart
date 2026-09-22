import 'package:collection/collection.dart';
import 'package:diacritic/diacritic.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/vocab_search_match.dart';

/// The vocab search box's text, matched against a word or the meanings the
/// learner already has for it, ignoring case and diacritics.
class VocabSearchQuery {
  final String _text;

  VocabSearchQuery(String text) : _text = _normalize(text.trim());

  bool get isEmpty => _text.isEmpty;

  VocabSearchMatch? matchLemma(String lemma) {
    final normalized = _normalize(lemma);
    if (normalized == _text) return const VocabSearchMatch.exactLemma();
    final position = normalized.indexOf(_text);
    return position < 0 ? null : VocabSearchMatch.inLemma(position);
  }

  /// The best match among [meanings], or null when none contains the text.
  VocabSearchMatch? matchMeanings(Iterable<String> meanings) => meanings
      .map((meaning) => _normalize(meaning).indexOf(_text))
      .where((position) => position >= 0)
      .map(VocabSearchMatch.inMeaning)
      .minOrNull;

  static String _normalize(String text) => removeDiacritics(text).toLowerCase();
}
