import 'package:collection/collection.dart';

/// list ordered by priority
enum PartOfSpeechEnum {
  //Content tokens
  noun,
  verb,
  adj,
  adv,
  idiom,
  phrasalv,
  compn,

  //Function tokens
  sconj,
  num,
  affix,
  part,
  cconj,
  punct,
  aux,
  space,
  sym,
  det,
  pron,
  adp,
  propn,
  intj,
  x;

  static Set<PartOfSpeechEnum> _contentPartsOfSpeech = {
    PartOfSpeechEnum.noun,
    PartOfSpeechEnum.verb,
    PartOfSpeechEnum.adj,
    PartOfSpeechEnum.adv,
    PartOfSpeechEnum.idiom,
    PartOfSpeechEnum.phrasalv,
    PartOfSpeechEnum.compn,
  };

  bool get isContentWord => _contentPartsOfSpeech.contains(this);

  /// categories that describe non-lemma tokens (punctuation, symbols,
  /// whitespace, affixes, unclassified) rather than a real word a learner
  /// could produce. No lemma should ever be tagged with one of these, so
  /// they must never surface as practice targets or distractors.
  static final Set<PartOfSpeechEnum> _neverALemma = {
    PartOfSpeechEnum.affix,
    PartOfSpeechEnum.punct,
    PartOfSpeechEnum.space,
    PartOfSpeechEnum.sym,
    PartOfSpeechEnum.x,
  };

  bool get isEligibleLemmaCategory => !_neverALemma.contains(this);

  /// same check as [isEligibleLemmaCategory], but for a raw UD POS tag
  /// string (case-insensitive). Unrecognized tags are treated as eligible
  /// so this only ever excludes known non-lemma categories.
  static bool isEligibleLemmaTag(String tag) {
    final pos = PartOfSpeechEnum.values.firstWhereOrNull(
      (p) => p.name.toLowerCase() == tag.toLowerCase(),
    );
    return pos?.isEligibleLemmaCategory ?? true;
  }
}
