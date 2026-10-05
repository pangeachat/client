import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_access/course_access.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';

extension CourseAccessRoomExtension on Room {
  /// The course's current setting; null when its pair matches none of the
  /// three. The directory listing is not room state, so it is fetched.
  Future<CourseAccess?> fetchCourseAccess() async => CourseAccess.fromSettings(
    await client.getRoomVisibilityOnDirectory(id),
    joinRules,
  );

  /// Applies [access]. The join rule goes through [setCustomJoinRules] so the
  /// course keeps its join code.
  Future<void> setCourseAccess(CourseAccess access) async {
    await client.setRoomVisibilityOnDirectory(
      id,
      visibility: access.visibility,
    );
    if (joinRules != access.joinRule) {
      await setCustomJoinRules(access.joinRule);
    }
  }
}
