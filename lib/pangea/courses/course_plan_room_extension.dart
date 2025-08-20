import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/courses/course_plan_event.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension CoursePlanRoomExtension on Room {
  CoursePlanEvent? get coursePlan {
    final event = getState(PangeaEventTypes.coursePlan);
    if (event == null) return null;
    return CoursePlanEvent.fromJson(event.content);
  }
}
