import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_popup.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/pangea/user/client_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class MorphAnalyticsListView extends StatelessWidget {
  final void Function(ConstructIdentifier) onConstructZoom;
  final AnalyticsPopupWrapperState controller;

  const MorphAnalyticsListView({
    required this.onConstructZoom,
    required this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // spacing: 16.0,
        children: [
          // Add your text widget here
          const InstructionsInlineTooltip(
            instructionsEnum: InstructionsEnum.morphAnalyticsList,
          ),
          Expanded(
            child: ListView.builder(
              key: const PageStorageKey<String>('morph-analytics'),
              itemCount: controller.features.length,
              itemBuilder: (context, index) {
                final feature = controller.features[index];
                return feature.displayTags.isNotEmpty
                    ? MorphFeatureBox(
                        morphFeature: feature.feature,
                        allTags: controller.morphs
                            .getDisplayTags(feature.feature)
                            .map((tag) => tag.toLowerCase())
                            .toSet(),
                        onConstructZoom: onConstructZoom,
                      )
                    : const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MorphFeatureBox extends StatelessWidget {
  final String morphFeature;
  final Set<String> allTags;
  final void Function(ConstructIdentifier) onConstructZoom;

  const MorphFeatureBox({
    super.key,
    required this.morphFeature,
    required this.allTags,
    required this.onConstructZoom,
  });

  MorphFeaturesEnum get feature =>
      MorphFeaturesEnumExtension.fromString(morphFeature);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppConfig.primaryColorLight
              : AppConfig.primaryColor,
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
                child: MorphIcon(morphFeature: feature, morphTag: null),
              ),
              Text(
                feature.getDisplayCopy(context),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
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
                  children: allTags
                      .map(
                        (morphTag) {
                          final id = ConstructIdentifier(
                            lemma: morphTag,
                            type: ConstructTypeEnum.morph,
                            category: morphFeature,
                          );

                          final analytics = MatrixState.pangeaController
                                  .getAnalytics.constructListModel
                                  .getConstructUses(id) ??
                              ConstructUses(
                                lemma: morphTag,
                                constructType: ConstructTypeEnum.morph,
                                category: morphFeature,
                                uses: [],
                              );

                          return MorphTagChip(
                            morphFeature: morphFeature,
                            morphTag: morphTag,
                            constructAnalytics: analytics,
                            onTap: analytics.points > 0
                                ? () => onConstructZoom(id)
                                : null,
                          );
                        },
                      )
                      .sortedBy<num>(
                        (chip) => chip.constructAnalytics.points,
                      )
                      .reversed
                      .toList(),
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
  final String morphFeature;
  final String morphTag;
  final ConstructUses constructAnalytics;
  final VoidCallback? onTap;

  const MorphTagChip({
    super.key,
    required this.morphFeature,
    required this.morphTag,
    required this.constructAnalytics,
    this.onTap,
  });

  MorphFeaturesEnum get feature =>
      MorphFeaturesEnumExtension.fromString(morphFeature);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      onTap: onTap,
      child: Opacity(
        opacity: constructAnalytics.points > 0 ? 1.0 : 0.3,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            gradient: constructAnalytics.points > 0
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[
                      Colors.transparent,
                      constructAnalytics.lemmaCategory.color,
                    ],
                  )
                : null,
            color: constructAnalytics.points > 0 ? null : theme.disabledColor,
          ),
          padding: const EdgeInsets.symmetric(
            vertical: 4.0,
            horizontal: 8.0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8.0,
            children: [
              SizedBox(
                width: 28.0,
                height: 28.0,
                child: constructAnalytics.points > 0 ||
                        Matrix.of(context).client.isSupportAccount
                    ? MorphIcon(
                        morphFeature: feature,
                        morphTag: morphTag,
                      )
                    : const Icon(
                        Icons.lock,
                        color: Colors.white,
                      ),
              ),
              Text(
                getGrammarCopy(
                      category: morphFeature,
                      lemma: morphTag,
                      context: context,
                    ) ??
                    morphTag,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
