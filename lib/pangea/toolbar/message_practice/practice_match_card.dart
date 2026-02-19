import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/common/widgets/choice_animation.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_choice.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_audio_card.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_practice_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_match_item.dart';

class MatchActivityCard extends StatelessWidget {
  final MatchPracticeActivityModel currentActivity;
  final PracticeController controller;

  const MatchActivityCard({
    super.key,
    required this.currentActivity,
    required this.controller,
  });

  Widget choiceDisplayContent(
    BuildContext context,
    String choice,
    double? fontSize,
  ) {
    switch (currentActivity) {
      case EmojiPracticeActivityModel():
      case LemmaMeaningPracticeActivityModel():
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            choice,
            style: TextStyle(fontSize: fontSize),
            textAlign: TextAlign.center,
          ),
        );
      case WordListeningPracticeActivityModel():
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.volume_up, size: fontSize),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    double fontSize =
        (FluffyThemes.isColumnMode(context)
            ? Theme.of(context).textTheme.titleLarge?.fontSize
            : Theme.of(context).textTheme.titleMedium?.fontSize) ??
        26;

    final mode = controller.practiceMode;
    if (mode == MessagePracticeMode.listening ||
        mode == MessagePracticeMode.wordEmoji) {
      fontSize = fontSize * 1.5;
    }

    final selectedChoice = controller.selectedChoice;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      spacing: 4.0,
      children: [
        if (mode == MessagePracticeMode.listening)
          MessageAudioCard(messageEvent: controller.pangeaMessageEvent),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4.0,
          runSpacing: 4.0,
          children: currentActivity.matchContent.choices.map((
            PracticeChoice cf,
          ) {
            final bool? wasCorrect = controller.wasCorrectMatch(cf);
            return ChoiceAnimationWidget(
              isSelected: selectedChoice == cf,
              isCorrect: wasCorrect,
              child: PracticeMatchItem(
                token: currentActivity.tokens.firstWhereOrNull(
                  (t) => t.vocabConstructID == cf.form.cId,
                ),
                isSelected: selectedChoice == cf,
                isCorrect: wasCorrect,
                constructForm: cf,
                content: choiceDisplayContent(
                  context,
                  cf.choiceContent,
                  fontSize,
                ),
                audioContent:
                    currentActivity is WordListeningPracticeActivityModel
                    ? cf.choiceContent
                    : null,
                controller: controller,
                shimmer: controller.showChoiceShimmer,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
