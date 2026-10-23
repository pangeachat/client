import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

/// Who is joined to their language's central course (#9591). See
/// joining-courses.instructions.md § The central course.
abstract class CentralCourseRules {
  /// The account Pangea runs central courses from, on [userId]'s homeserver.
  static String supportUserId(String userId) => '@support:${userId.domain}';

  static bool qualifies({
    required UserType? role,
    required String? language,
    required List<String> leftLanguages,
    required bool inTeachersCourse,
  }) =>
      role != UserType.teacher &&
      language != null &&
      !leftLanguages.contains(language) &&
      !inTeachersCourse;

  /// Whether a course with these power levels has an admin other than [self],
  /// [support] and [bot]: a teacher's course. Read from power levels rather
  /// than the member list, which a lazily loaded room may not hold in full.
  static bool hasOtherHumanAdmin(
    Map<String, Object?> powerLevelUsers, {
    required String self,
    required String support,
    required String bot,
  }) => powerLevelUsers.entries.any(
    (entry) =>
        entry.key != self &&
        entry.key != support &&
        entry.key != bot &&
        entry.value is int &&
        (entry.value as int) >= SpaceConstants.powerLevelOfAdmin,
  );

  /// Only the support account's mark counts, as in the Browse catalog, so a
  /// course can't make itself central.
  static bool isCentralMark(
    Map<String, Object?> courseSettings,
    String sender,
    String support,
  ) => courseSettings['central'] == true && sender == support;
}
