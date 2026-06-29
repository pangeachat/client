import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/morph_features_and_tags.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_download_button.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MorphAnalyticsListView extends StatelessWidget {
  final ConstructAnalyticsViewState controller;

  const MorphAnalyticsListView({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    final l2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    return Column(
      children: [
        if (kIsWeb)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [DownloadAnalyticsButton()],
          ),
        Expanded(
          child: CustomScrollView(
            key: const PageStorageKey<String>('morph-analytics'),
            slivers: [
              const SliverToBoxAdapter(
                child: InstructionsInlineTooltip(
                  instructionsEnum: InstructionsEnum.morphAnalyticsList,
                ),
              ),

              if (!InstructionsEnum.morphAnalyticsList.isToggledOff)
                const SliverToBoxAdapter(child: SizedBox(height: 16.0)),

              // Morph feature boxes
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final feature = controller.morphs.features[index];
                  return feature.tags.isNotEmpty && l2 != null
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: MorphFeatureBox(
                            featureTags: feature,
                            language: l2,
                          ),
                        )
                      : const SizedBox.shrink();
                }, childCount: controller.morphs.features.length),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 75.0)),
            ],
          ),
        ),
      ],
    );
  }
}

class MorphFeatureBox extends StatelessWidget {
  final MorphFeatureTags featureTags;
  final String language;

  const MorphFeatureBox({
    super.key,
    required this.featureTags,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final feature = featureTags.feature;
    final tags = featureTags.tags;

    final featureEnum = MorphFeaturesEnum.fromString(feature.value);
    final analyticsService = Matrix.of(context).analyticsDataService;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 16.0,
            children: [
              SizedBox(
                height: 30.0,
                width: 30.0,
                child: MorphIcon(feature: featureEnum),
              ),
              Flexible(
                child: Text(
                  feature.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16.0,
                  runSpacing: 16.0,
                  children: tags.map((morphTag) {
                    final id = ConstructIdentifier(
                      lemma: morphTag.value,
                      type: ConstructTypeEnum.morph,
                      category: feature.value,
                    );

                    return FutureBuilder(
                      future: analyticsService.getConstructUse(id, language),
                      builder: (context, snapshot) => MorphTagChip(
                        feature: featureEnum,
                        tag: morphTag,
                        constructAnalytics: snapshot.data,
                        onTap: () {
                          AnalyticsNavigationUtil.navigateToAnalytics(
                            context: context,
                            view: ProgressIndicatorEnum.morphsUsed,
                            construct: id,
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MorphTagChip extends StatelessWidget {
  final MorphFeaturesEnum feature;
  final GrammarTag tag;
  final ConstructUses? constructAnalytics;
  final VoidCallback? onTap;

  const MorphTagChip({
    super.key,
    required this.feature,
    required this.tag,
    required this.constructAnalytics,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlocked =
        constructAnalytics != null && constructAnalytics!.numTotalUses > 0 ||
        Matrix.of(context).client.userID == Environment.supportUserId;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        onTap: onTap,
        child: Opacity(
          opacity: unlocked ? 1.0 : 0.3,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32.0),
              gradient: unlocked
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: <Color>[
                        constructAnalytics?.lemmaCategory.color(context) ??
                            ConstructLevelEnum.seeds.color(context),
                        Colors.transparent,
                      ],
                    )
                  : null,
              color: unlocked ? null : theme.disabledColor,
            ),
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8.0,
              children: [
                unlocked
                    ? Container(
                        width: 28.0,
                        height: 28.0,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withAlpha(180),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: MorphIcon(
                          feature: feature,
                          tag: tag.value,
                          size: Size(16.0, 16.0),
                        ),
                      )
                    : SizedBox(
                        height: 28.0,
                        width: 28.0,
                        child: Icon(Icons.lock, color: Colors.white),
                      ),

                Flexible(
                  child: Text(
                    tag.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
