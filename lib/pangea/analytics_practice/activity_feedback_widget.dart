import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class ActivityFeedback extends StatelessWidget {
  final MultipleChoicePracticeActivityModel activity;
  final SelectedMorphChoice selectedChoice;

  const ActivityFeedback({
    super.key,
    required this.activity,
    required this.selectedChoice,
  });

  @override
  Widget build(BuildContext context) {
    final isWrongAnswer = !activity.multipleChoiceContent.isCorrect(
      selectedChoice.tag,
    );

    if (!isWrongAnswer) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: MorphMeaningWidget(
        feature: selectedChoice.feature,
        tag: selectedChoice.tag,
        blankErrorFeedback: true,
      ),
    );
  }
}
