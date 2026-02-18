import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_hint_button_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class ActivityHintSection extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const ActivityHintSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.activityState,
        controller.hintPressedNotifier,
        controller.hintsUsedNotifier,
      ]),
      builder: (context, _) {
        final state = controller.activityState.value;
        if (state is! AsyncLoaded<MultipleChoicePracticeActivityModel>) {
          return const SizedBox.shrink();
        }

        final activity = state.value;
        final hintPressed = controller.hintPressedNotifier.value;
        final hintsUsed = controller.hintsUsedNotifier.value;
        final maxHintsReached = hintsUsed >= AnalyticsPracticeState.maxHints;

        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50.0),
          child: Builder(
            builder: (context) {
              final isAudioActivity =
                  activity.activityType == ActivityTypeEnum.lemmaAudio;

              // For audio activities: toggle hint on/off (no increment, no max hints)
              if (isAudioActivity) {
                return HintButton(
                  onPressed: () => controller.onHintPressed(increment: false),
                  depressed: hintPressed,
                  icon: Symbols.text_to_speech,
                );
              }

              // For grammar category: fade out button and show hint content
              if (activity is MorphPracticeActivityModel) {
                return AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: hintPressed
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: HintButton(
                    icon: Icons.lightbulb_outline,
                    onPressed: maxHintsReached
                        ? () {}
                        : controller.onHintPressed,
                    depressed: maxHintsReached,
                  ),
                  secondChild: MorphMeaningWidget(
                    feature: activity.morphFeature,
                    tag: activity.multipleChoiceContent.answers.first,
                  ),
                );
              }

              // For grammar error: button stays pressed, hint shows in ErrorBlankWidget
              return HintButton(
                icon: Icons.lightbulb_outline,
                onPressed: (hintPressed || maxHintsReached)
                    ? () {}
                    : controller.onHintPressed,
                depressed: hintPressed || maxHintsReached,
              );
            },
          ),
        );
      },
    );
  }
}
