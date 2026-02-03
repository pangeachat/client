import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  String getDisplayCopy(BuildContext context) {
    switch (this) {
      case PartOfSpeechEnum.sconj:
        return L10n.of(context).grammarCopyPOSsconj;
      case PartOfSpeechEnum.num:
        return L10n.of(context).grammarCopyPOSnum;
      case PartOfSpeechEnum.verb:
        return L10n.of(context).grammarCopyPOSverb;
      case PartOfSpeechEnum.affix:
        return L10n.of(context).grammarCopyPOSaffix;
      case PartOfSpeechEnum.part:
        return L10n.of(context).grammarCopyPOSpart;
      case PartOfSpeechEnum.adj:
        return L10n.of(context).grammarCopyPOSadj;
      case PartOfSpeechEnum.cconj:
        return L10n.of(context).grammarCopyPOScconj;
      case PartOfSpeechEnum.punct:
        return L10n.of(context).grammarCopyPOSpunct;
      case PartOfSpeechEnum.adv:
        return L10n.of(context).grammarCopyPOSadv;
      case PartOfSpeechEnum.aux:
        return L10n.of(context).grammarCopyPOSaux;
      case PartOfSpeechEnum.space:
        return L10n.of(context).grammarCopyPOSspace;
      case PartOfSpeechEnum.sym:
        return L10n.of(context).grammarCopyPOSsym;
      case PartOfSpeechEnum.det:
        return L10n.of(context).grammarCopyPOSdet;
      case PartOfSpeechEnum.pron:
        return L10n.of(context).grammarCopyPOSpron;
      case PartOfSpeechEnum.adp:
        return L10n.of(context).grammarCopyPOSadp;
      case PartOfSpeechEnum.propn:
        return L10n.of(context).grammarCopyPOSpropn;
      case PartOfSpeechEnum.noun:
        return L10n.of(context).grammarCopyPOSnoun;
      case PartOfSpeechEnum.intj:
        return L10n.of(context).grammarCopyPOSintj;
      case PartOfSpeechEnum.idiom:
        return L10n.of(context).grammarCopyPOSidiom;
      case PartOfSpeechEnum.phrasalv:
        return L10n.of(context).grammarCopyPOSphrasalv;
      case PartOfSpeechEnum.compn:
        return L10n.of(context).grammarCopyPOScompn;
      case PartOfSpeechEnum.x:
        return L10n.of(context).grammarCopyPOSx;
    }
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

  bool get canBeDefined => [
        PartOfSpeechEnum.noun,
        PartOfSpeechEnum.verb,
        PartOfSpeechEnum.adj,
        PartOfSpeechEnum.adv,
        PartOfSpeechEnum.propn,
        PartOfSpeechEnum.intj,
        PartOfSpeechEnum.det,
        PartOfSpeechEnum.pron,
        PartOfSpeechEnum.sconj,
        PartOfSpeechEnum.cconj,
        PartOfSpeechEnum.adp,
        PartOfSpeechEnum.aux,
        PartOfSpeechEnum.num,
        PartOfSpeechEnum.idiom,
        PartOfSpeechEnum.phrasalv,
        PartOfSpeechEnum.compn,
      ].contains(this);

  bool get canBeHeard => [
        PartOfSpeechEnum.noun,
        PartOfSpeechEnum.verb,
        PartOfSpeechEnum.adj,
        PartOfSpeechEnum.adv,
        PartOfSpeechEnum.propn,
        PartOfSpeechEnum.intj,
        PartOfSpeechEnum.det,
        PartOfSpeechEnum.pron,
        PartOfSpeechEnum.sconj,
        PartOfSpeechEnum.cconj,
        PartOfSpeechEnum.adp,
        PartOfSpeechEnum.aux,
        PartOfSpeechEnum.num,
        PartOfSpeechEnum.idiom,
        PartOfSpeechEnum.phrasalv,
        PartOfSpeechEnum.compn,
      ].contains(this);

  bool eligibleForPractice(ActivityTypeEnum activityType) {
    switch (activityType) {
      case ActivityTypeEnum.emoji:
      case ActivityTypeEnum.wordMeaning:
      case ActivityTypeEnum.morphId:
        return canBeDefined;
      case ActivityTypeEnum.wordFocusListening:
        return canBeHeard;
      default:
        debugger(when: kDebugMode);
        return false;
    }
  }
}

String? getVocabCategoryName(String category, BuildContext context) {
  return PartOfSpeechEnum.values
      .firstWhereOrNull(
        (pos) => pos.name.toLowerCase() == category.toLowerCase(),
      )
      ?.getDisplayCopy(context);
}
