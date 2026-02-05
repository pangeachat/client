import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

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

  static PartOfSpeechEnum? fromString(String categoryName) {
    final pos = PartOfSpeechEnum.values.firstWhereOrNull(
      (pos) => pos.name.toLowerCase() == categoryName.toLowerCase(),
    );
    if (pos == null && categoryName.toLowerCase() != 'other') {
      ErrorHandler.logError(
        e: "Missing part of speech",
        s: StackTrace.current,
        data: {"category": categoryName},
      );
    }
    return pos;
  }

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
