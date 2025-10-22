import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/course_plans/courses/course_plan_room_extension.dart';

extension CoursePlanClientExtension on Client {
  Room? getRoomByCourseId(String courseId) {
    for (final room in rooms) {
      if (room.coursePlan?.uuid == courseId) {
        return room;
      }
    }
    return null;
  }
}
