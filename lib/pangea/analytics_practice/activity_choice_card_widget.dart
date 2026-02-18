import 'package:flutter/widgets.dart';

import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/audio_choice_card.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/game_choice_card.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/grammar_choice_card.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/meaning_choice_card.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityChoiceCard extends StatelessWidget {
  final MultipleChoicePracticeActivityModel activity;
  final String choiceId;
  final String targetId;
  final VoidCallback onPressed;
  final double cardHeight;
  final AnalyticsPracticeState controller;

  final String choiceText;
  final String? choiceEmoji;
  final bool enabled;
  final bool shrinkWrap;

  const ActivityChoiceCard({
    super.key,
    required this.activity,
    required this.choiceId,
    required this.targetId,
    required this.onPressed,
    required this.cardHeight,
    required this.controller,
    required this.choiceText,
    required this.choiceEmoji,
    this.enabled = true,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrect = activity.multipleChoiceContent.isCorrect(choiceId);
    final activityType = activity.activityType;
    final constructId = activity.tokens.first.vocabConstructID;

    switch (activity.activityType) {
      case ActivityTypeEnum.lemmaMeaning:
        return MeaningChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_meaning_$choiceId',
          ),
          choiceId: choiceId,
          targetId: targetId,
          displayText: choiceText,
          emoji: choiceEmoji,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
        );

      case ActivityTypeEnum.lemmaAudio:
        return ValueListenableBuilder<bool>(
          valueListenable: controller.hintPressedNotifier,
          builder: (context, showPhonetics, _) => AudioChoiceCard(
            key: ValueKey(
              '${constructId.string}_${activityType.name}_audio_$choiceId',
            ),
            choiceId: choiceId,
            targetId: targetId,
            displayText: choiceText,
            textLanguage: MatrixState.pangeaController.userController.userL2!,
            onPressed: onPressed,
            isCorrect: isCorrect,
            isEnabled: enabled,
            showPhoneticTranscription: showPhonetics,
          ),
        );

      case ActivityTypeEnum.grammarCategory:
        return GrammarChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_grammar_$choiceId',
          ),
          choiceId: choiceId,
          targetId: targetId,
          feature: (activity as MorphPracticeActivityModel).morphFeature,
          tag: choiceText,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          enabled: enabled,
        );

      case ActivityTypeEnum.grammarError:
        final activity = this.activity as GrammarErrorPracticeActivityModel;
        return GameChoiceCard(
          key: ValueKey(
            '${activity.errorLength}_${activity.errorOffset}_${activity.eventID}_${activityType.name}_grammar_error_$choiceId',
          ),
          shouldFlip: false,
          targetId: targetId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
          child: Text(choiceText),
        );

      default:
        return GameChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_basic_$choiceId',
          ),
          shouldFlip: false,
          targetId: targetId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
          child: Text(choiceText),
        );
    }
  }
}
