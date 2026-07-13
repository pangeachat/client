import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_response_dialog.dart';
import 'package:fluffychat/pangea/morphs/grammar_construct_example.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning_widget.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/analytics_details_usage_content.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/construct_xp_progress_bar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MorphDetailsView extends StatefulWidget {
  final ConstructIdentifier constructId;

  const MorphDetailsView({required this.constructId, super.key});

  @override
  State<MorphDetailsView> createState() => _MorphDetailsViewState();
}

class _MorphDetailsViewState extends State<MorphDetailsView> {
  /// Bumped after a feedback regen so the meaning content remounts and
  /// re-reads the (now updated) grammar constructs cache.
  int _regenCount = 0;

  ConstructIdentifier get constructId => widget.constructId;

  /// The flag flow (#6839): collect feedback, send it to the choreographer
  /// (which regenerates the feature's meaning bundle in place — choreo
  /// #2548), then remount the meaning content to show the corrected copy.
  Future<void> _flagMeaning(String feature) async {
    final l10n = L10n.of(context);
    await showDialog(
      context: context,
      builder: (dialogContext) => FeedbackDialog(
        title: l10n.grammarFeedbackDialogTitle,
        onSubmit: (feedback) async {
          Navigator.of(dialogContext).pop();
          final result = await showFutureLoadingDialog(
            context: context,
            future: () => GrammarConstructsProvider.submitTagFeedback(
              feature: feature,
              feedback: feedback,
            ),
          );
          if (!mounted || result.isError) return;
          setState(() => _regenCount++);
          await showDialog(
            context: context,
            builder: (context) => FeedbackResponseDialog(
              title: l10n.grammarFeedbackDialogTitle,
              feedback: L10n.of(context).grammarFeedbackSubmittedDesc,
            ),
          );
        },
      ),
    );
  }

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
          child: Stack(
            children: [
              Column(
                key: ValueKey('morph-details-$_regenCount'),
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
              // Flag in the top right, like the vocab word card (#6839).
              Positioned(
                top: 0.0,
                right: 0.0,
                child: IconButton(
                  color: Theme.of(context).iconTheme.color,
                  icon: const Icon(Icons.flag_outlined),
                  tooltip: L10n.of(context).reportGrammarIssueTooltip,
                  onPressed: () => _flagMeaning(feature),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
