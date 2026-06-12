import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';

extension OnboardingClientExtension on Client {
  Future<String> getCourseIdByRoomId(String roomId) async {
    Room? room = getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      try {
        await waitForRoomInSync(roomId).timeout(Duration(seconds: 10));
      } catch (e) {
        if (e is! TimeoutException) rethrow;
      }
    }

    room = getRoomById(roomId);
    if (room?.coursePlan == null) {
      throw "Room not found or doesn't contain course";
    }

    return room!.coursePlan!.uuid;
  }
}
