import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/common/widgets/choice_animation.dart';
import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_choice.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_morph_choice_item.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_controller.dart';

// this widget will handle the content of the input bar when mode == MessageMode.wordMorph

// if initializing, with a selectedToken then we should show an activity if one is available
// in this case, we'll set selectedMorph to the first morph available for the selected token

// if initializing with a selectedMorph then we should show the first activity available for that morph
// if no activity available for that morph, then we should just show the details of the feature and tag

// the details of a morph will allow the user to edit the morphological tag of that feature.

const int numberOfMorphDistractors = 3;

class MessageMorphInputBarContent extends StatefulWidget {
  final PracticeController controller;
  final MorphPracticeActivityModel activity;
  final PangeaToken? selectedToken;
  final double maxWidth;

  const MessageMorphInputBarContent({
    super.key,
    required this.controller,
    required this.activity,
    required this.selectedToken,
    required this.maxWidth,
  });

  @override
  MessageMorphInputBarContentState createState() =>
      MessageMorphInputBarContentState();
}

class MessageMorphInputBarContentState
    extends State<MessageMorphInputBarContent> {
  String? selectedTag;

  PangeaToken get token => widget.activity.tokens.first;
  MorphFeaturesEnum get morph => widget.activity.morphFeature;

  @override
  void didUpdateWidget(covariant MessageMorphInputBarContent oldWidget) {
    final selected = widget.controller.selectedMorph?.morph;
    if (morph != selected || token != oldWidget.selectedToken) {
      setState(() {});
    }
    super.didUpdateWidget(oldWidget);
  }

  TextStyle? textStyle(BuildContext context) => widget.maxWidth > 600
      ? Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)
      : Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.maxWidth > 600
        ? 28.0
        : widget.maxWidth > 600
        ? 24.0
        : 16.0;
    final spacing = widget.maxWidth > 600
        ? 16.0
        : widget.maxWidth > 600
        ? 8.0
        : 4.0;

    return Column(
      spacing: spacing,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: spacing,
          children: [
            MorphIcon(
              morphFeature: morph,
              morphTag: null,
              size: Size(iconSize, iconSize),
              showTooltip: false,
            ),
            Flexible(
              child: Text(
                L10n.of(context).whatIsTheMorphTag(
                  morph.getDisplayCopy(context),
                  token.text.content,
                ),
                style: textStyle(context),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: spacing,
          children: widget.activity.multipleChoiceContent.choices.mapIndexed((
            index,
            choice,
          ) {
            final wasCorrect = widget.controller.wasCorrectChoice(choice);

            return ChoiceAnimationWidget(
              isSelected: selectedTag == choice,
              isCorrect: wasCorrect,
              child: MessageMorphChoiceItem(
                cId: ConstructIdentifier(
                  lemma: choice,
                  type: ConstructTypeEnum.morph,
                  category: morph.name,
                ),
                onTap: () {
                  setState(() => selectedTag = choice);
                  widget.controller.onMatch(
                    token,
                    PracticeChoice(
                      choiceContent: choice,
                      form: ConstructForm(
                        cId: widget.activity.tokens.first.morphIdByFeature(
                          widget.activity.morphFeature,
                        )!,
                        form: token.text.content,
                      ),
                    ),
                  );
                },
                isSelected: selectedTag == choice,
                isGold: wasCorrect,
                shimmer: widget.controller.showChoiceShimmer,
              ),
            );
          }).toList(),
        ),
        if (selectedTag != null)
          Container(
            constraints: BoxConstraints(
              minHeight: widget.maxWidth > 600 ? 20 : 34,
            ),
            alignment: Alignment.center,
            child: MorphMeaningWidget(
              feature: morph,
              tag: selectedTag!,
              style: widget.maxWidth > 600
                  ? Theme.of(context).textTheme.bodyLarge
                  : Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
