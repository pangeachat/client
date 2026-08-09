// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:material_symbols_icons/symbols.dart';

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
  Unknown;

  static final Map<String, MorphFeaturesEnum> _morphFeatureCache = {};

  /// Convert string to enum
  static MorphFeaturesEnum fromString(String category) {
    // Repeated regex operations are causing performance issues,
    // so we cache the results in a static map
    if (_morphFeatureCache.containsKey(category)) {
      return _morphFeatureCache[category]!;
    }

    final morph = MorphFeaturesEnum.values.firstWhereOrNull(
      (e) =>
          e.name.toLowerCase() ==
          category.toLowerCase().replaceAll(RegExp(r'[,\[\]]'), ''),
    );
    if (morph == null) {
      return MorphFeaturesEnum.Unknown;
    }

    _morphFeatureCache[category] = morph;
    return morph;
  }

  bool get isEligibleForPractice => _eligibleForPractice.contains(this);

  /// the subset of morphological categories that are important to practice for learning the language
  /// by order of importance
  static Set<MorphFeaturesEnum> _eligibleForPractice = {
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
  };

  IconData get fallbackIcon {
    switch (this) {
      case MorphFeaturesEnum.Number:
        // google material 123 icon
        return Icons.format_list_numbered;
      case MorphFeaturesEnum.Gender:
        return Icons.wc;
      case MorphFeaturesEnum.Tense:
        return Icons.access_time;
      case MorphFeaturesEnum.Mood:
        return Icons.mood;
      case MorphFeaturesEnum.Person:
        return Icons.person;
      case MorphFeaturesEnum.Case:
        return Icons.format_list_bulleted;
      case MorphFeaturesEnum.Degree:
        return Icons.trending_up;
      case MorphFeaturesEnum.VerbForm:
        return Icons.text_format;
      case MorphFeaturesEnum.Voice:
        return Icons.record_voice_over;
      case MorphFeaturesEnum.Aspect:
        return Icons.aspect_ratio;
      case MorphFeaturesEnum.PronType:
        return Icons.text_fields;
      case MorphFeaturesEnum.NumType:
        return Icons.format_list_numbered;
      case MorphFeaturesEnum.Poss:
        return Icons.account_balance;
      case MorphFeaturesEnum.Reflex:
        return Icons.refresh;
      case MorphFeaturesEnum.Foreign:
        return Icons.language;
      case MorphFeaturesEnum.NounType:
        return Symbols.abc;
      case MorphFeaturesEnum.Pos:
        return Symbols.toys_and_games;
      case MorphFeaturesEnum.Polarity:
        return Icons.swap_vert;
      case MorphFeaturesEnum.Definite:
        return Icons.check_circle_outline;
      case MorphFeaturesEnum.PrepCase:
        return Icons.location_on_outlined;
      case MorphFeaturesEnum.ConjType:
        return Icons.compare_arrows;
      default:
        return Icons.help_outline;
    }
  }
}
