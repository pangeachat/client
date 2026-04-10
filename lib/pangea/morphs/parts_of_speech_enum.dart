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

  bool get isContentWord => [
    PartOfSpeechEnum.noun,
    PartOfSpeechEnum.verb,
    PartOfSpeechEnum.adj,
    PartOfSpeechEnum.adv,
    PartOfSpeechEnum.idiom,
    PartOfSpeechEnum.phrasalv,
    PartOfSpeechEnum.compn,
  ].contains(this);
}
