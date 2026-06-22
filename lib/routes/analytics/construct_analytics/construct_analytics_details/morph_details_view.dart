import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/pangea/morphs/grammar_construct_example.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning_widget.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/analytics_details_usage_content.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/construct_xp_progress_bar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MorphDetailsView extends StatelessWidget {
  final ConstructIdentifier constructId;

  const MorphDetailsView({required this.constructId, super.key});

  @override
  Widget build(BuildContext context) {
    final l2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    final tag = constructId.lemma;
    final feature = constructId.category;

    final featureEnum = MorphFeaturesEnum.fromString(feature);

    final localizedTag = GrammarConstructsProvider.getTag(
      feature: feature,
      tag: tag,
    );

    final localizedFeature = GrammarConstructsProvider.getFeature(
      feature: feature,
    );

    return FutureBuilder(
      future: l2 != null
          ? Matrix.of(
              context,
            ).analyticsDataService.getConstructUse(constructId, l2)
          : Future.value(
              ConstructUses(
                uses: [],
                lemma: constructId.lemma,
                category: constructId.category,
                constructType: constructId.type,
              ),
            ),
      builder: (context, snapshot) {
        final construct = snapshot.data;
        final level = construct?.lemmaCategory ?? ConstructLevelEnum.seeds;
        final Color textColor = Theme.of(context).brightness != Brightness.light
            ? level.color(context)
            : level.darkColor(context);

        return MaxWidthBody(
          maxWidth: 600.0,
          showBorder: false,
          child: Column(
            spacing: 16.0,
            children: [
              if (localizedTag != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 32.0,
                      height: 32.0,
                      child: MorphIcon(feature: featureEnum, tag: tag),
                    ),
                    const SizedBox(width: 10.0),
                    Text(
                      localizedTag.title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: textColor),
                    ),
                  ],
                ),
              if (localizedFeature != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24.0,
                      height: 24.0,
                      child: MorphIcon(feature: featureEnum),
                    ),
                    const SizedBox(width: 10.0),
                    Text(
                      localizedFeature.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              MorphMeaningWidget(
                feature: feature,
                tag: tag,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (localizedTag != null)
                GrammarConstructExample(tag: localizedTag),
              const Divider(),
              if (construct != null) ...[
                ConstructXPProgressBar(construct: construct.id),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: AnalyticsDetailsUsageContent(construct: construct),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
