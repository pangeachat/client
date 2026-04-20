import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_type_enum.dart';

/// Picks which tokens to do activities on and what types of activities to do
/// Caches result so that we don't have to recompute it
/// Most importantly, we can't do this in the state of a message widget because the state is disposed of and recreated
/// If we decided that the first token should have a hidden word listening, we need to remember that
/// Otherwise, the user might leave the chat, return, and see a different word hidden

class PracticeTarget {
  /// this is the tokens involved in the exercise
  /// for most, this will be a single token
  final List<PangeaToken> tokens;

  /// this is the type of exercise to do on the tokens
  final PracticeExerciseTypeEnum exerciseType;

  /// this is only defined for morphId exercises
  final MorphFeaturesEnum? morphFeature;

  PracticeTarget({
    required this.tokens,
    required this.exerciseType,
    this.morphFeature,
  }) {
    if (PracticeExerciseTypeEnum.morphId == exerciseType &&
        morphFeature == null) {
      throw Exception("morphFeature must be defined for morphId activities");
    }
  }

  String promptText(BuildContext context) {
    switch (exerciseType) {
      case PracticeExerciseTypeEnum.grammarCategory:
        return L10n.of(context).whatIsTheMorphTag(
          morphFeature!.getDisplayCopy(context),
          tokens.first.text.content,
        );
      case PracticeExerciseTypeEnum.grammarError:
        return L10n.of(context).fillInBlank;
      default:
        return tokens.first.vocabConstructID.lemma;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PracticeTarget &&
        listEquals(other.tokens, tokens) &&
        other.exerciseType == exerciseType &&
        other.morphFeature == morphFeature;
  }

  @override
  int get hashCode =>
      tokens.hashCode ^ exerciseType.hashCode ^ morphFeature.hashCode;

  static PracticeTarget fromJson(Map<String, dynamic> json) {
    final type = PracticeExerciseTypeEnum.values.firstWhereOrNull(
      (v) => json['activityType'] == v.name,
    );
    if (type == null) {
      throw Exception(
        "PracticeExerciseTypeEnum ${json['activityType']} not found in enum",
      );
    }

    return PracticeTarget(
      tokens: (json[ModelKey.tokens] as List)
          .map((e) => PangeaToken.fromJson(e))
          .toList(),
      exerciseType: type,
      morphFeature: json['morphFeature'] == null
          ? null
          : MorphFeaturesEnumExtension.fromString(json['morphFeature']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ModelKey.tokens: tokens.map((e) => e.toJson()).toList(),
      'activityType': exerciseType.name,
      'morphFeature': morphFeature?.name,
    };
  }

  //unique condensed deterministic key for local storage
  String get storageKey {
    return tokens.map((e) => e.text.content).join() +
        exerciseType.name +
        (morphFeature?.name ?? "");
  }

  ConstructIdentifier targetTokenConstructID(PangeaToken token) {
    final defaultID = token.vocabConstructID;
    final ConstructIdentifier? cId = morphFeature == null
        ? defaultID
        : token.morphIdByFeature(morphFeature!);
    return cId ?? defaultID;
  }
}
