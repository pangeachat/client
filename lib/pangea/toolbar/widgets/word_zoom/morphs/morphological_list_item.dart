import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/pangea/analytics_details_popup/analytics_details_popup.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/pangea/morphs/morph_categories_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/word_zoom_activity_button.dart';

class MorphologicalListItem extends StatelessWidget {
  final String morphFeature;
  final String morphTag;
  final String wordForm;
  final MessageOverlayController overlayController;

  const MorphologicalListItem({
    required this.morphFeature,
    required this.morphTag,
    required this.overlayController,
    required this.wordForm,
    super.key,
  });

  bool get shouldDoActivity => ConstructIdentifier(
        lemma: morphTag,
        type: ConstructTypeEnum.morph,
        category: morphFeature,
      ).isActivityProbablyLevelAppropriate(ActivityTypeEnum.morphId, wordForm);

  bool get isSelected => overlayController.toolbarMode == MessageMode.wordMorph;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: WordZoomActivityButton(
        icon: shouldDoActivity
            ? const Icon(Symbols.toys_and_games)
            : MorphIcon(morphFeature: morphFeature, morphTag: morphTag),
        isSelected: isSelected,
        onPressed: shouldDoActivity
            ? () => overlayController.updateToolbarMode(MessageMode.wordMorph)
            : () => (feature) => showDialog<AnalyticsPopupWrapper>(
                  context: context,
                  builder: (context) => AnalyticsPopupWrapper(
                    constructZoom: ConstructIdentifier(
                      lemma: morphTag,
                      type: ConstructTypeEnum.morph,
                      category: feature,
                    ),
                    view: ConstructTypeEnum.vocab,
                  ),
                ),
        tooltip: shouldDoActivity
            ? getMorphologicalCategoryCopy(
                morphFeature,
                context,
              )
            : getGrammarCopy(
                category: morphFeature,
                lemma: morphTag,
                context: context,
              ),
        opacity: isSelected
            ? 1
            : shouldDoActivity
                ? 0.4
                : 1,
      ),
    );
  }
}
