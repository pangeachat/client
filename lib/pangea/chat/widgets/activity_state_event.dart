import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/chat/events/state_message.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';

class ActivityStateEvent extends StatelessWidget {
  final Event event;
  const ActivityStateEvent({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    try {
      final activity = ActivityPlanModel.fromJson(event.content);
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 24.0,
          vertical: 16.0,
        ),
        child: Text(activity.markdown),
      );
    } catch (e) {
      return StateMessage(event);
    }
  }
}
