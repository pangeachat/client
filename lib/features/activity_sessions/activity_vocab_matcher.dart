import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';

/// Where an activity's target vocab appears in one message — the one rule the
/// gold highlight and the used-vocab chips share (activities.instructions.md,
/// "Target vocab in the conversation").
///
/// [vocabLemmas] is the plan's lower-cased entry set (`vocabLemmas` on the
/// activity plan); an entry containing whitespace is a phrase. A single-word
/// entry matches a token by lemma. A phrase matches a run of consecutive
/// tokens where each word equals the token's text or its lemma,
/// case-insensitively — "hace sol" matches "Hace sol", "ir de compras"
/// matches "voy de compras", and a punctuation token between the words
/// breaks the run.
///
/// One walk per message: construct it once per build or per scan, not per
/// token (issue #7659).
class ActivityVocabMatcher {
  /// Tokens inside a matched entry — the gold highlight.
  final Set<PangeaToken> matchedTokens = {};

  /// The matched entries, as the strings of [vocabLemmas] — the used state.
  final Set<String> matchedEntries = {};

  static final RegExp _whitespace = RegExp(r'\s+');

  ActivityVocabMatcher(List<PangeaToken> tokens, Set<String>? vocabLemmas) {
    if (vocabLemmas == null || vocabLemmas.isEmpty || tokens.isEmpty) return;

    final phrases = {
      for (final entry in vocabLemmas)
        if (entry.trim().contains(_whitespace))
          entry: entry.trim().split(_whitespace),
    };

    for (var i = 0; i < tokens.length; i++) {
      final lemma = tokens[i].lemma.text.toLowerCase();
      if (vocabLemmas.contains(lemma)) {
        matchedTokens.add(tokens[i]);
        matchedEntries.add(lemma);
      }
      for (final phrase in phrases.entries) {
        if (_phraseStartsAt(tokens, i, phrase.value)) {
          matchedTokens.addAll(tokens.sublist(i, i + phrase.value.length));
          matchedEntries.add(phrase.key);
        }
      }
    }
  }

  static bool _phraseStartsAt(
    List<PangeaToken> tokens,
    int start,
    List<String> words,
  ) {
    if (start + words.length > tokens.length) return false;
    for (var j = 0; j < words.length; j++) {
      if (!_wordMatches(words[j], tokens[start + j])) return false;
    }
    return true;
  }

  static bool _wordMatches(String word, PangeaToken token) =>
      word == token.text.content.toLowerCase() ||
      word == token.lemma.text.toLowerCase();
}
