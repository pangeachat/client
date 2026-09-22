/// Where a vocab search hit a word, for ranking the results. A match on the
/// word's own text always ranks above a match on one of its meanings.
class VocabSearchMatch implements Comparable<VocabSearchMatch> {
  final int _tier;

  /// Where the search text starts inside the matched text: earlier is better.
  final int _position;

  const VocabSearchMatch._(this._tier, this._position);

  const VocabSearchMatch.exactLemma() : this._(0, 0);

  const VocabSearchMatch.inLemma(int position) : this._(1, position);

  const VocabSearchMatch.inMeaning(int position) : this._(2, position);

  @override
  int compareTo(VocabSearchMatch other) => _tier != other._tier
      ? _tier.compareTo(other._tier)
      : _position.compareTo(other._position);
}
