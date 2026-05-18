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
}
