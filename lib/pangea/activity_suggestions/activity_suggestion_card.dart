import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestion_card_content.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestions_area.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';

class ActivitySuggestionCard extends StatelessWidget {
  final ActivityPlanModel activity;
  final ActivitySuggestionsAreaState controller;
  final VoidCallback onPressed;

  final double width;
  final double height;
  final double padding;

  const ActivitySuggestionCard({
    super.key,
    required this.activity,
    required this.controller,
    required this.onPressed,
    required this.width,
    required this.height,
    required this.padding,
  });

  bool get _isSelected => controller.selectedActivity == activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.all(padding),
      child: PressableButton(
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(24.0),
        color: theme.colorScheme.primary,
        child: AnimatedContainer(
          duration: FluffyThemes.animationDuration,
          height: controller.isEditing && _isSelected
              ? 675
              : _isSelected
                  ? 400
                  : height,
          width: width,
          child: ActivitySuggestionCardContent(
            controller: controller,
            activity: activity,
            width: width,
            height: height,
            padding: padding,
          ),
        ),
      ),
    );
  }
}
