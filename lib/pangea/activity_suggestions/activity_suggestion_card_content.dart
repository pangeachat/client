import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestion_edit_card.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestion_selected_card.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestions_area.dart';

class ActivitySuggestionCardContent extends StatelessWidget {
  final ActivitySuggestionsAreaState controller;
  final ActivityPlanModel activity;
  final double width;
  final double height;
  final double padding;

  const ActivitySuggestionCardContent({
    super.key,
    required this.controller,
    required this.activity,
    required this.width,
    required this.height,
    required this.padding,
  });

  bool get _isSelected => controller.selectedActivity == activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24.0),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              height: 100,
              width: width,
              decoration: BoxDecoration(
                image: activity.imageURL != null
                    ? DecorationImage(
                        image: controller.avatar == null || !_isSelected
                            ? NetworkImage(activity.imageURL!)
                            : MemoryImage(controller.avatar!)
                                as ImageProvider<Object>,
                      )
                    : null,
                borderRadius: BorderRadius.circular(24.0),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: 12.0,
                  left: 12.0,
                  right: 12.0,
                  bottom: 12.0,
                ),
                child: controller.isEditing && _isSelected
                    ? ActivitySuggestionEditCard(
                        activity: activity,
                        controller: controller,
                      )
                    : ActivitySuggestionSelectedCard(
                        activity: activity,
                        isSelected: _isSelected,
                        controller: controller,
                      ),
              ),
            ),
          ],
        ),
        if (controller.isEditing && _isSelected)
          Positioned(
            top: 75.0,
            child: InkWell(
              borderRadius: BorderRadius.circular(90),
              onTap: controller.selectPhoto,
              child: const CircleAvatar(
                radius: 16.0,
                child: Icon(
                  Icons.add_a_photo_outlined,
                  size: 16.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
