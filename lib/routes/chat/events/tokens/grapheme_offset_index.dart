import 'package:characters/characters.dart';

/// Maps Unicode code-point offsets (the unit used by backend tokenizers — see
/// `2-step-choreographer/app/handlers/tokens/token_schema.py`, which computes
/// offsets via Python `len()`) to grapheme-cluster indices (the unit used by
/// Dart's [String.characters], which is what renderers slice by).
///
/// The two units disagree whenever a grapheme cluster contains more than one
/// code point: Indic scripts with matras ("ਕਿ" = 2 cp, 1 grapheme), Vietnamese
/// tone marks, ZWJ emoji sequences, and flag / skin-tone emoji.
///
/// Constructed once per transcript (O(n) in grapheme count). Lookups are
/// O(log n) via binary search.
class GraphemeOffsetIndex {
  /// `_starts[i]` is the code-point index at which grapheme cluster `i`
  /// begins. Sorted ascending; `_starts.length` equals the grapheme count.
  final List<int> _starts;
  final int _codepointCount;

  GraphemeOffsetIndex._(this._starts, this._codepointCount);

  factory GraphemeOffsetIndex.fromText(String text) {
    final List<int> starts = [];
    int cp = 0;
    for (final g in text.characters) {
      starts.add(cp);
      cp += g.runes.length;
    }
    return GraphemeOffsetIndex._(starts, cp);
  }

  int get graphemeCount => _starts.length;
  int get codepointCount => _codepointCount;

  /// Returns the grapheme-cluster index that contains code-point position
  /// [codepoint]. If [codepoint] falls inside a multi-codepoint grapheme,
  /// returns that grapheme's index.
  ///
  /// Values `<= 0` clamp to `0`; values `>= codepointCount` clamp to
  /// `graphemeCount` (one past the last grapheme), matching the
  /// half-open-range convention used by [String.characters] slicing.
  int graphemeStartOfCodepoint(int codepoint) {
    if (codepoint <= 0) return 0;
    if (codepoint >= _codepointCount) return _starts.length;
    // Largest i with _starts[i] <= codepoint.
    int lo = 0, hi = _starts.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= codepoint) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Returns the exclusive grapheme-cluster end for a code-point range that
  /// ends at [codepoint]. An end that falls inside a grapheme rounds up to
  /// include that grapheme — so partial graphemes are never silently
  /// truncated when translating a range.
  int graphemeEndOfCodepoint(int codepoint) {
    if (codepoint <= 0) return 0;
    if (codepoint >= _codepointCount) return _starts.length;
    // Smallest i with _starts[i] >= codepoint.
    int lo = 0, hi = _starts.length;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (_starts[mid] < codepoint) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
