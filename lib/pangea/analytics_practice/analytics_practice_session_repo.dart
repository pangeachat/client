import 'dart:math';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsPracticeSessionRepo {
  static Future<AnalyticsPracticeSessionModel> get(
    ConstructTypeEnum type,
  ) async {
    final r = Random();
    final activityTypes = ActivityTypeEnum.analyticsPracticeTypes(type);

    final types = List.generate(
      AnalyticsPracticeConstants.practiceGroupSize,
      (_) => activityTypes[r.nextInt(activityTypes.length)],
    );

    final List<PracticeTarget> targets = [];

    if (type == ConstructTypeEnum.vocab) {
      final constructs = await _fetchVocab();
      final targetCount = min(constructs.length, types.length);
      targets.addAll([
        for (var i = 0; i < targetCount; i++)
          PracticeTarget(
            tokens: [constructs[i].asToken],
            activityType: types[i],
          ),
      ]);
    } else {
      final morphs = await _fetchMorphs();
      targets.addAll([
        for (final entry in morphs.entries)
          PracticeTarget(
            tokens: [entry.key],
            activityType: types[targets.length],
            morphFeature: entry.value,
          ),
      ]);
    }

    final session = AnalyticsPracticeSessionModel(
      userL1: MatrixState.pangeaController.userController.userL1!.langCode,
      userL2: MatrixState.pangeaController.userController.userL2!.langCode,
      startedAt: DateTime.now(),
      practiceTargets: targets,
    );
    return session;
  }

  static Future<List<ConstructIdentifier>> _fetchVocab() async {
    final constructs = await MatrixState
        .pangeaController.matrixState.analyticsDataService
        .getAggregatedConstructs(ConstructTypeEnum.vocab)
        .then((map) => map.values.toList());

    // sort by last used descending, nulls first
    constructs.sort((a, b) {
      final dateA = a.lastUsed;
      final dateB = b.lastUsed;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return -1;
      if (dateB == null) return 1;
      return dateA.compareTo(dateB);
    });

    final Set<String> seemLemmas = {};
    final targets = <ConstructIdentifier>[];
    for (final construct in constructs) {
      if (seemLemmas.contains(construct.lemma)) continue;
      seemLemmas.add(construct.lemma);
      targets.add(construct.id);
      if (targets.length >= AnalyticsPracticeConstants.practiceGroupSize) {
        break;
      }
    }
    return targets;
  }

  static Future<Map<PangeaToken, MorphFeaturesEnum>> _fetchMorphs() async {
    final constructs = await MatrixState
        .pangeaController.matrixState.analyticsDataService
        .getAggregatedConstructs(ConstructTypeEnum.morph)
        .then((map) => map.values.toList());

    // sort by last used descending, nulls first
    constructs.sort((a, b) {
      final dateA = a.lastUsed;
      final dateB = b.lastUsed;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return -1;
      if (dateB == null) return 1;
      return dateA.compareTo(dateB);
    });

    final targets = <PangeaToken, MorphFeaturesEnum>{};
    final Set<String> seenForms = {};

    for (final entry in constructs) {
      if (targets.length >= AnalyticsPracticeConstants.practiceGroupSize) {
        break;
      }

      final feature = MorphFeaturesEnumExtension.fromString(entry.id.category);
      if (feature == MorphFeaturesEnum.Unknown) {
        continue;
      }

      for (final use in entry.cappedUses) {
        if (targets.length >= AnalyticsPracticeConstants.practiceGroupSize) {
          break;
        }

        if (use.lemma.isEmpty) continue;
        final form = use.form;
        if (seenForms.contains(form) || form == null) {
          continue;
        }

        seenForms.add(form);
        final token = PangeaToken(
          lemma: Lemma(
            text: form,
            saveVocab: true,
            form: form,
          ),
          text: PangeaTokenText.fromString(form),
          pos: 'other',
          morph: {feature: use.lemma},
        );
        targets[token] = feature;
        break;
      }
    }

    return targets;
  }
}
