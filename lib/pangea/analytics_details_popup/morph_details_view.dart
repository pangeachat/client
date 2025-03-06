import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_popup_content.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_identifier.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_level_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/text_loading_shimmer.dart';
import 'package:fluffychat/pangea/lemmas/construct_xp_widget.dart';
import 'package:fluffychat/pangea/morphs/morph_feature_display.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning/morph_info_repo.dart';
import 'package:fluffychat/pangea/morphs/morph_tag_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

class MorphDetailsView extends StatelessWidget {
  final ConstructIdentifier constructId;

  const MorphDetailsView({
    required this.constructId,
    super.key,
  });

  ConstructUses get _construct => constructId.constructUses;
  String get _morphFeature => constructId.category;
  String get _morphTag => constructId.lemma;

  Future<String> _getDefinition(BuildContext context) => MorphInfoRepo.get(
        feature: _construct.category,
        tag: _construct.lemma,
      ).then((value) => value ?? L10n.of(context).meaningNotFound);

  @override
  Widget build(BuildContext context) {
    final Color textColor = Theme.of(context).brightness != Brightness.light
        ? _construct.lemmaCategory.color
        : _construct.lemmaCategory.darkColor;

    return AnalyticsDetailsViewContent(
      title:
          MorphFeatureDisplay(morphFeature: _morphFeature, morphTag: _morphTag),
      subtitle:
          MorphTagDisplay(morphFeature: _morphFeature, textColor: textColor),
      headerContent: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Align(
          alignment: Alignment.topLeft,
          child: FutureBuilder(
            future: _getDefinition(context),
            builder: (
              BuildContext context,
              AsyncSnapshot<String?> snapshot,
            ) {
              if (snapshot.hasData) {
                return RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    children: <TextSpan>[
                      TextSpan(
                        text: L10n.of(context).meaningSectionHeader,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      TextSpan(
                        text: "  ${snapshot.data!}",
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              } else if (snapshot.hasError) {
                return Wrap(
                  children: [
                    Text(
                      L10n.of(context).meaningSectionHeader,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Text(
                      L10n.of(context).meaningNotFound,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                );
              } else {
                return Wrap(
                  children: [
                    Text(
                      L10n.of(context).meaningSectionHeader,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    const TextLoadingShimmer(width: 100),
                  ],
                );
              }
            },
          ),
        ),
      ),
      xpIcon: ConstructXpWidget(id: constructId),
      constructId: constructId,
    );
  }
}
