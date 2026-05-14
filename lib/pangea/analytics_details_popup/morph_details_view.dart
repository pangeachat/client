import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_usage_content.dart';
import 'package:fluffychat/pangea/analytics_details_popup/construct_xp_progress_bar.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/morph_feature_display.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/morphs/morph_tag_display.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MorphDetailsView extends StatelessWidget {
  final ConstructIdentifier constructId;

  const MorphDetailsView({required this.constructId, super.key});

  @override
  Widget build(BuildContext context) {
    final l2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    final feature = GrammarConstructsProvider.getFeature(
      feature: constructId.category,
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
              MorphTagDisplay(
                feature: constructId.category,
                tag: constructId.lemma,
                textColor: textColor,
              ),
              if (feature != null) MorphFeatureDisplay(feature: feature),
              MorphMeaningWidget(
                feature: constructId.category,
                tag: constructId.lemma,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
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
