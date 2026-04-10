import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_hint_button_widget.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class ActivityHintSection extends StatelessWidget {
  final MultipleChoicePracticeActivityModel activity;
  final VoidCallback onPressed;
  final bool enabled;
  final bool hintPressed;

  const ActivityHintSection({
    super.key,
    required this.activity,
    required this.onPressed,
    required this.enabled,
    required this.hintPressed,
  });

  @override
  Widget build(BuildContext context) {
    final activity = this.activity;

    return switch (activity) {
      VocabAudioPracticeActivityModel() => Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        constraints: const BoxConstraints(minHeight: 50.0),
        child: HintButton(
          onPressed: onPressed,
          depressed: hintPressed,
          icon: Symbols.text_to_speech,
        ),
      ),
      MorphPracticeActivityModel() => Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        constraints: const BoxConstraints(minHeight: 50.0),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: hintPressed
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: HintButton(
            icon: Icons.lightbulb_outline,
            onPressed: enabled ? onPressed : () {},
            depressed: !enabled,
          ),
          secondChild: MorphMeaningWidget(
            feature: activity.morphFeature,
            tag: activity.multipleChoiceContent.answers.first,
          ),
        ),
      ),
      GrammarErrorPracticeActivityModel() => Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        constraints: const BoxConstraints(minHeight: 50.0),
        child: HintButton(
          icon: Icons.lightbulb_outline,
          onPressed: !enabled ? () {} : onPressed,
          depressed: hintPressed || !enabled,
        ),
      ),
      _ => SizedBox(),
    };
  }
}
