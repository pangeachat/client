// Word matching for the read-aloud exercise: which words of a sentence the
// learner was heard to say. See practice-exercises.instructions.md,
// "Speaking practice".

final RegExp _edgePunctuation = RegExp(
  r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
  unicode: true,
);
final RegExp _whitespace = RegExp(r'\s+');

/// Accented vowels to their base letter. A recognizer drops a stress mark as
/// readily as it writes one, so "Cuándo" and "cuando" are the same spoken
/// word. Consonants with marks (ñ, ç) are their own sounds and stay.
const Map<String, String> _accentedVowels = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

/// A spoken word, folded for comparison: lower-cased, accented vowels
/// folded, and the punctuation glued to its edges removed, because the
/// recognizer writes "Gato." and the sentence "gato" for the same spoken
/// word. Empty when [word] holds no letter or digit at all.
String normalizeSpokenWord(String word) => word
    .toLowerCase()
    .replaceAll(_edgePunctuation, '')
    .split('')
    .map((c) => _accentedVowels[c] ?? c)
    .join();

/// Whether [text] is something a learner can be heard saying, as opposed to a
/// punctuation-only token.
bool isSpokenWord(String text) => normalizeSpokenWord(text).isNotEmpty;

/// The words of a transcript, normalized, in order.
List<String> spokenWords(String transcript) => [
  for (final word in transcript.split(_whitespace))
    if (isSpokenWord(word)) normalizeSpokenWord(word),
];

/// For each word of [reference], whether it was heard in [heard], in order.
///
/// A longest-common-subsequence match, so a word counts only where it falls in
/// the right place: "el gato come" against "gato el come" hears two of three,
/// never all three. Both sides are normalized with [normalizeSpokenWord], so
/// the caller passes surface forms as they are.
List<bool> readAloudHeard(List<String> reference, List<String> heard) {
  final ref = reference.map(normalizeSpokenWord).toList();
  final got = heard.map(normalizeSpokenWord).toList();
  final n = ref.length, m = got.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = ref[i] == got[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final matched = List<bool>.filled(n, false);
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (ref[i] == got[j]) {
      matched[i] = true;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return matched;
}
