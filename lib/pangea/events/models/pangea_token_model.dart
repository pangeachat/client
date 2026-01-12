import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_repo.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_morph_choice.dart';
import '../../common/constants/model_keys.dart';
import '../../lemmas/lemma.dart';

class PangeaToken {
  PangeaTokenText text;

  //TODO - make this a string and move save_vocab to this class
  // clients have been able to handle null lemmas for 12 months so this is safe
  Lemma lemma;

  /// [pos] ex "VERB" - part of speech of the token
  /// https://universaldependencies.org/u/pos/
  String pos;

  /// [_morph] ex {} - morphological features of the token
  /// https://universaldependencies.org/u/feat/
  final Map<MorphFeaturesEnum, String> _morph;

  PangeaToken({
    required this.text,
    required this.lemma,
    required this.pos,
    required Map<MorphFeaturesEnum, String> morph,
  }) : _morph = morph;

  @override
  bool operator ==(Object other) {
    if (other is PangeaToken) {
      return other.text.content == text.content &&
          other.text.offset == text.offset;
    }
    return false;
  }

  @override
  int get hashCode => text.content.hashCode ^ text.offset.hashCode;

  /// [morph] - morphological features of the token
  /// includes the part of speech if it is not already included
  /// https://universaldependencies.org/u/feat/
  Map<MorphFeaturesEnum, String> get morph {
    if (_morph.keys.contains(MorphFeaturesEnum.Pos)) {
      return _morph;
    }
    final morphWithPos = Map<MorphFeaturesEnum, String>.from(_morph);
    morphWithPos[MorphFeaturesEnum.Pos] = pos;
    return morphWithPos;
  }

  static Lemma _getLemmas(String text, dynamic json) {
    if (json != null) {
      // July 24, 2024 - we're changing from a list to a single lemma and this is for backwards compatibility
      // previously sent tokens have lists of lemmas
      if (json is Iterable) {
        return json
                .map<Lemma>(
                  (e) => Lemma.fromJson(e as Map<String, dynamic>),
                )
                .toList()
                .cast<Lemma>()
                .firstOrNull ??
            Lemma(text: text, saveVocab: false, form: text);
      } else {
        return Lemma.fromJson(json);
      }
    } else {
      // earlier still, we didn't have lemmas so this is for really old tokens
      return Lemma(text: text, saveVocab: false, form: text);
    }
  }

  factory PangeaToken.fromJson(Map<String, dynamic> json) {
    final PangeaTokenText text =
        PangeaTokenText.fromJson(json[_textKey] as Map<String, dynamic>);
    final morph = json['morph'] != null
        ? (json['morph'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(
              MorphFeaturesEnumExtension.fromString(key),
              value as String,
            ),
          )
        : <MorphFeaturesEnum, String>{};
    return PangeaToken(
      text: text,
      lemma: _getLemmas(text.content, json[_lemmaKey]),
      pos: morph[MorphFeaturesEnum.Pos] ?? '',
      morph: morph,
    );
  }

  static const String _textKey = "text";
  static const String _lemmaKey = ModelKey.lemma;

  Map<String, dynamic> toJson() => {
        _textKey: text.toJson(),
        _lemmaKey: [lemma.toJson()],
        'morph': morph.map(
          (key, value) => MapEntry(key.name, value),
        ),
      };

  /// alias for the offset
  int get start => text.offset;

  /// alias for the end of the token ie offset + length
  int get end => text.offset + text.length;

  /// Given a [type] and [metadata], returns a [OneConstructUse] for this lemma
  OneConstructUse _toVocabUse(
    ConstructUseTypeEnum type,
    ConstructUseMetaData metadata,
    int xp,
  ) {
    return OneConstructUse(
      useType: type,
      lemma: lemma.text,
      form: text.content,
      constructType: ConstructTypeEnum.vocab,
      metadata: metadata,
      category: pos,
      xp: xp,
    );
  }

  List<OneConstructUse> allUses(
    ConstructUseTypeEnum type,
    ConstructUseMetaData metadata,
    int xp,
  ) {
    final List<OneConstructUse> uses = [];
    if (!lemma.saveVocab) return uses;

    uses.add(_toVocabUse(type, metadata, xp));
    for (final morphFeature in morph.keys) {
      uses.add(
        OneConstructUse(
          useType: type,
          lemma: morph[morphFeature]!,
          form: text.content,
          constructType: ConstructTypeEnum.morph,
          metadata: metadata,
          category: morphFeature,
          xp: xp,
        ),
      );
    }

    return uses;
  }

  /// Safely get morph tag for a given feature without regard for case
  String? getMorphTag(MorphFeaturesEnum feature) {
    // if the morph contains the feature, return it
    if (morph.containsKey(feature)) return morph[feature];

    return null;
  }

  ConstructIdentifier? morphIdByFeature(MorphFeaturesEnum feature) {
    final tag = getMorphTag(feature);
    if (tag == null) return null;
    return ConstructIdentifier(
      lemma: tag,
      type: ConstructTypeEnum.morph,
      category: feature.name,
    );
  }

  ConstructIdentifier get vocabConstructID => ConstructIdentifier(
        lemma: lemma.text,
        type: ConstructTypeEnum.vocab,
        category: pos,
      );

  ConstructForm get vocabForm =>
      ConstructForm(form: text.content, cId: vocabConstructID);

  Set<String> morphActivityDistractors(
    MorphFeaturesEnum morphFeature,
    String morphTag,
  ) {
    final List<String> allTags =
        MorphsRepo.cached.getDisplayTags(morphFeature.name);

    final List<String> possibleDistractors = allTags
        .where(
          (tag) => tag.toLowerCase() != morphTag.toLowerCase() && tag != "X",
        )
        .toList();

    possibleDistractors.shuffle();
    return possibleDistractors.take(numberOfMorphDistractors).toSet();
  }

  List<ConstructIdentifier> get morphsBasicallyEligibleForPracticeByPriority =>
      MorphFeaturesEnumExtension.eligibleForPractice.where((f) {
        return morph.containsKey(f);
      }).map((f) {
        return ConstructIdentifier(
          lemma: getMorphTag(f)!,
          type: ConstructTypeEnum.morph,
          category: f.name,
        );
      }).toList();

  bool eligibleForPractice(ActivityTypeEnum activityType) {
    switch (activityType) {
      case ActivityTypeEnum.emoji:
        return lemma.saveVocab && vocabConstructID.isContentWord;
      default:
        return lemma.saveVocab;
    }
  }

  String get uniqueId => "${text.content}::${text.offset}";
}
