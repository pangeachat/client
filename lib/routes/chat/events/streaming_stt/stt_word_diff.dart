import 'dart:math' as math;

import 'package:characters/characters.dart';

/// One ordered run of the edited transcript: [text] verbatim, and whether it
/// diverges from the original ASR ([changed]). Concatenating every run's [text]
/// reconstructs the edited string exactly.
typedef SttDiffRun = ({String text, bool changed});

/// One word-level edit shown on a sent transcript. [current] is null only for
/// a deletion; [original] is present only when a changed word replaces or
/// removes a spoken word.
typedef SttWordChange = ({String? current, String? original, bool changed});

/// A PURE, grapheme-aware, WORD-level span diff of [edited] against [original].
///
/// Extends the distance-only [sttEditDistance] DP into a WORD-token LCS
/// backtrace, then walks the edited token stream emitting ordered runs: a word
/// present in the LCS (matched in order) is UNCHANGED; an inserted/substituted
/// word is CHANGED; a separator whitespace is changed iff BOTH adjacent words
/// are changed, so an inserted/replaced multi-word PHRASE stays ONE continuous
/// changed run and a changed<->unchanged boundary stays unchanged. Deletions
/// leave no run in the edited text (they surface only via the struck-through
/// original). Word-level is friendlier
/// for learners than char-level; operates on Unicode grapheme clusters so an
/// emoji or combining mark is one unit. `ChoreoEditModel` (UTF-16 single
/// replacement) is deliberately NOT used — it cannot express multiple changes.
List<SttDiffRun> sttWordDiff(String original, String edited) {
  final oTok = _tokenize(original);
  final eTok = _tokenize(edited);

  final oWords = <String>[
    for (final t in oTok)
      if (t.isWord) t.text,
  ];
  final eWords = <String>[
    for (final t in eTok)
      if (t.isWord) t.text,
  ];

  // LCS length DP over words (grapheme-exact equality).
  final n = oWords.length, m = eWords.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = oWords[i] == eWords[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  // Backtrace: which edited words are matched (unchanged).
  final matched = List<bool>.filled(m, false);
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (oWords[i] == eWords[j]) {
      matched[j] = true;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }

  // Pass 1 — per-WORD changed flag: a word is changed iff it is not in the LCS.
  final flags = List<bool>.filled(eTok.length, false);
  var w = 0;
  for (var k = 0; k < eTok.length; k++) {
    if (eTok[k].isWord) {
      flags[k] = !matched[w];
      w++;
    }
  }
  // Pass 2 — whitespace CONTINUITY: a separator is changed iff BOTH adjacent
  // word tokens exist and are changed, so an inserted/replaced multi-word PHRASE
  // highlights as ONE continuous run (no green gap breaking an orange backfill),
  // while a changed<->unchanged boundary stays unchanged. Tokens strictly
  // alternate word/whitespace, so k-1 / k+1 are the adjacent words when present;
  // a missing edge neighbour counts as unchanged (edge spaces never highlight).
  for (var k = 0; k < eTok.length; k++) {
    if (!eTok[k].isWord) {
      final left = k > 0 && eTok[k - 1].isWord && flags[k - 1];
      final right = k + 1 < eTok.length && eTok[k + 1].isWord && flags[k + 1];
      flags[k] = left && right;
    }
  }

  // Merge adjacent same-flag tokens into runs.
  final runs = <SttDiffRun>[];
  final buf = StringBuffer();
  bool? cur;
  for (var k = 0; k < eTok.length; k++) {
    if (cur == null) {
      cur = flags[k];
      buf.write(eTok[k].text);
    } else if (flags[k] == cur) {
      buf.write(eTok[k].text);
    } else {
      runs.add((text: buf.toString(), changed: cur));
      buf.clear();
      buf.write(eTok[k].text);
      cur = flags[k];
    }
  }
  if (cur != null) runs.add((text: buf.toString(), changed: cur));
  return runs;
}

/// Aligns the edited words with the spoken words using a minimum word-edit
/// script. Unlike [sttWordDiff], this retains the one original word associated
/// with a replacement while keeping insertions and deletions local.
List<SttWordChange> sttWordChanges(String original, String edited) {
  final originalWords = <String>[
    for (final token in _tokenize(original))
      if (token.isWord) token.text,
  ];
  final currentWords = <String>[
    for (final token in _tokenize(edited))
      if (token.isWord) token.text,
  ];
  final n = originalWords.length;
  final m = currentWords.length;
  final distance = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

  for (var i = n; i >= 0; i--) {
    for (var j = m; j >= 0; j--) {
      if (i == n) {
        distance[i][j] = m - j;
      } else if (j == m) {
        distance[i][j] = n - i;
      } else if (originalWords[i] == currentWords[j]) {
        distance[i][j] = distance[i + 1][j + 1];
      } else {
        final replace = distance[i + 1][j + 1];
        final remove = distance[i + 1][j];
        final insert = distance[i][j + 1];
        distance[i][j] = 1 + math.min(replace, math.min(remove, insert));
      }
    }
  }

  final changes = <SttWordChange>[];
  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n &&
        j < m &&
        originalWords[i] == currentWords[j] &&
        distance[i][j] == distance[i + 1][j + 1]) {
      changes.add((current: currentWords[j], original: null, changed: false));
      i++;
      j++;
    } else if (i < n && j < m && distance[i][j] == distance[i + 1][j + 1] + 1) {
      changes.add((
        current: currentWords[j],
        original: originalWords[i],
        changed: true,
      ));
      i++;
      j++;
    } else if (j < m && distance[i][j] == distance[i][j + 1] + 1) {
      changes.add((current: currentWords[j], original: null, changed: true));
      j++;
    } else {
      changes.add((current: null, original: originalWords[i], changed: true));
      i++;
    }
  }
  return changes;
}

typedef _Tok = ({String text, bool isWord});

bool _isWhitespace(String cluster) => cluster.trim().isEmpty;

/// Split [s] into alternating word / whitespace tokens over grapheme clusters,
/// so concatenating the token texts reconstructs [s] exactly.
List<_Tok> _tokenize(String s) {
  final out = <_Tok>[];
  final buf = StringBuffer();
  bool? curWord;
  for (final c in s.characters) {
    final isWord = !_isWhitespace(c);
    if (curWord == null) {
      curWord = isWord;
      buf.write(c);
    } else if (isWord == curWord) {
      buf.write(c);
    } else {
      out.add((text: buf.toString(), isWord: curWord));
      buf.clear();
      buf.write(c);
      curWord = isWord;
    }
  }
  if (curWord != null) out.add((text: buf.toString(), isWord: curWord));
  return out;
}
