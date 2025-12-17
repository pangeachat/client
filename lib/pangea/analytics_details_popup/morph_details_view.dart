import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_usage_content.dart';
import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/lemmas/construct_xp_widget.dart';
import 'package:fluffychat/pangea/morphs/morph_feature_display.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_tag_display.dart';

class MorphDetailsView extends StatelessWidget {
  final ConstructIdentifier constructId;

  const MorphDetailsView({
    required this.constructId,
    super.key,
  });

  MorphFeaturesEnum get _morphFeature =>
      MorphFeaturesEnumExtension.fromString(constructId.category);
  String get _morphTag => constructId.lemma;

  @override
  Widget build(BuildContext context) {
    final construct = constructId.constructUses;
    final Color textColor = Theme.of(context).brightness != Brightness.light
        ? construct.lemmaCategory.color(context)
        : construct.lemmaCategory.darkColor(context);

    return SingleChildScrollView(
      child: Column(
        spacing: 16.0,
        children: [
          MorphTagDisplay(
            morphFeature: _morphFeature,
            morphTag: _morphTag,
            textColor: textColor,
          ),
          MorphFeatureDisplay(morphFeature: _morphFeature),
          MorphMeaningWidget(
            feature: _morphFeature,
            tag: _morphTag,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const Divider(),
          Row(
            spacing: 16.0,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstructXpWidget(id: constructId),
              Text(
                "${construct.points} XP",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: textColor,
                    ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: AnalyticsDetailsUsageContent(
              construct: construct,
            ),
          ),
        ],
      ),
    );
  }
}
