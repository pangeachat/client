// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

enum MorphFeaturesEnum {
  Pos,
  AdvType,
  Aspect,
  Case,
  ConjType,
  Definite,
  Degree,
  Evident,
  Foreign,
  Gender,
  Mood,
  NounType,
  NumForm,
  NumType,
  Number,
  NumberPsor,
  Person,
  Polarity,
  Polite,
  Poss,
  PrepCase,
  PronType,
  PunctSide,
  PunctType,
  Reflex,
  Tense,
  VerbForm,
  VerbType,
  Voice,
}

extension MorphFeaturesEnumExtension on MorphFeaturesEnum {
  /// Convert enum to string
  String toShortString() {
    return toString().split('.').last.toLowerCase();
  }

  /// Convert string to enum
  static MorphFeaturesEnum? fromString(String category) {
    final morph = MorphFeaturesEnum.values.firstWhereOrNull(
      (e) =>
          e.toShortString() ==
          category.toLowerCase().replaceAll(RegExp(r'[,\[\]]'), ''),
    );
    if (morph == null) {
      ErrorHandler.logError(
        e: "Missing morphological category",
        s: StackTrace.current,
        data: {"category": category},
      );
    }
    return morph;
  }

  String getDisplayCopy(BuildContext context) {
    switch (this) {
      case MorphFeaturesEnum.Pos:
        return L10n.of(context).grammarCopyPOS;
      case MorphFeaturesEnum.AdvType:
        return L10n.of(context).grammarCopyADVTYPE;
      case MorphFeaturesEnum.Aspect:
        return L10n.of(context).grammarCopyASPECT;
      case MorphFeaturesEnum.Case:
        return L10n.of(context).grammarCopyCASE;
      case MorphFeaturesEnum.ConjType:
        return L10n.of(context).grammarCopyCONJTYPE;
      case MorphFeaturesEnum.Definite:
        return L10n.of(context).grammarCopyDEFINITE;
      case MorphFeaturesEnum.Degree:
        return L10n.of(context).grammarCopyDEGREE;
      case MorphFeaturesEnum.Evident:
        return L10n.of(context).grammarCopyEVIDENT;
      case MorphFeaturesEnum.Foreign:
        return L10n.of(context).grammarCopyFOREIGN;
      case MorphFeaturesEnum.Gender:
        return L10n.of(context).grammarCopyGENDER;
      case MorphFeaturesEnum.Mood:
        return L10n.of(context).grammarCopyMOOD;
      case MorphFeaturesEnum.NounType:
        return L10n.of(context).grammarCopyNOUNTYPE;
      case MorphFeaturesEnum.NumForm:
        return L10n.of(context).grammarCopyNUMFORM;
      case MorphFeaturesEnum.NumType:
        return L10n.of(context).grammarCopyNUMTYPE;
      case MorphFeaturesEnum.Number:
        return L10n.of(context).grammarCopyNUMBER;
      case MorphFeaturesEnum.NumberPsor:
        return L10n.of(context).grammarCopyNUMBERPSOR;
      case MorphFeaturesEnum.Person:
        return L10n.of(context).grammarCopyPERSON;
      case MorphFeaturesEnum.Polarity:
        return L10n.of(context).grammarCopyPOLARITY;
      case MorphFeaturesEnum.Polite:
        return L10n.of(context).grammarCopyPOLITE;
      case MorphFeaturesEnum.Poss:
        return L10n.of(context).grammarCopyPOSS;
      case MorphFeaturesEnum.PrepCase:
        return L10n.of(context).grammarCopyPREPCASE;
      case MorphFeaturesEnum.PronType:
        return L10n.of(context).grammarCopyPRONTYPE;
      case MorphFeaturesEnum.PunctSide:
        return L10n.of(context).grammarCopyPUNCTSIDE;
      case MorphFeaturesEnum.PunctType:
        return L10n.of(context).grammarCopyPUNCTTYPE;
      case MorphFeaturesEnum.Reflex:
        return L10n.of(context).grammarCopyREFLEX;
      case MorphFeaturesEnum.Tense:
        return L10n.of(context).grammarCopyTENSE;
      case MorphFeaturesEnum.VerbForm:
        return L10n.of(context).grammarCopyVERBFORM;
      case MorphFeaturesEnum.VerbType:
        return L10n.of(context).grammarCopyVERBTYPE;
      case MorphFeaturesEnum.Voice:
        return L10n.of(context).grammarCopyVOICE;
    }
  }

  /// the subset of morphological categories that are important to practice for learning the language
  /// by order of importance
  List<MorphFeaturesEnum> get eligibleForPractice => [
        MorphFeaturesEnum.Pos,
        MorphFeaturesEnum.Tense,
        MorphFeaturesEnum.VerbForm,
        MorphFeaturesEnum.VerbType,
        MorphFeaturesEnum.Voice,
        MorphFeaturesEnum.AdvType,
        MorphFeaturesEnum.Aspect,
        MorphFeaturesEnum.Case,
        MorphFeaturesEnum.ConjType,
        MorphFeaturesEnum.Definite,
        MorphFeaturesEnum.Degree,
        MorphFeaturesEnum.Evident,
        MorphFeaturesEnum.Gender,
        MorphFeaturesEnum.Mood,
        MorphFeaturesEnum.NounType,
        MorphFeaturesEnum.NumForm,
        MorphFeaturesEnum.NumType,
        MorphFeaturesEnum.Number,
        MorphFeaturesEnum.NumberPsor,
        MorphFeaturesEnum.Person,
        MorphFeaturesEnum.Polarity,
        MorphFeaturesEnum.Polite,
        MorphFeaturesEnum.Poss,
        MorphFeaturesEnum.PrepCase,
        MorphFeaturesEnum.PronType,
        MorphFeaturesEnum.Reflex,
      ];

  bool get isEligibleForPractice {
    return eligibleForPractice.contains(this);
  }
}

String? getMorphologicalCategoryCopy(
  String categoryName,
  BuildContext context,
) {
  final MorphFeaturesEnum? category =
      MorphFeaturesEnumExtension.fromString(categoryName);

  if (category == null) {
    return null;
  }
  return category.getDisplayCopy(context);
}
