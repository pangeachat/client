import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';

/// The Courses hub's role filter pills (#9207). Each filter narrows the one
/// activity-ordered course list; none regroups it.
enum CourseRoleFilter {
  all,

  /// Joined courses the learner administers (`isRoomAdmin`, power level ≥
  /// 100). There is no separate teacher role; admin is the signal.
  teaching,

  /// Every other joined course.
  learning;

  String label(L10n l10n) => switch (this) {
    CourseRoleFilter.all => l10n.all,
    CourseRoleFilter.teaching => l10n.courseSectionTeaching,
    CourseRoleFilter.learning => l10n.courseSectionLearning,
  };

  String tooltip(L10n l10n) => switch (this) {
    CourseRoleFilter.all => l10n.allCoursesFilterTooltip,
    CourseRoleFilter.teaching => l10n.teachingCoursesFilterTooltip,
    CourseRoleFilter.learning => l10n.learningCoursesFilterTooltip,
  };

  /// A pending invite shows under [all] only: power levels aren't part of
  /// stripped invite state, so its role is unknown until join.
  bool includes(Room course) => switch (this) {
    CourseRoleFilter.all => true,
    CourseRoleFilter.teaching =>
      course.membership == Membership.join && course.isRoomAdmin,
    CourseRoleFilter.learning =>
      course.membership == Membership.join && !course.isRoomAdmin,
  };

  /// Whether the hub shows the pills: only when the learner holds both roles.
  /// A pure learner (most users) or a pure teacher has nothing to filter.
  static bool appliesTo(Iterable<Room> courses) =>
      courses.any(CourseRoleFilter.teaching.includes) &&
      courses.any(CourseRoleFilter.learning.includes);
}
