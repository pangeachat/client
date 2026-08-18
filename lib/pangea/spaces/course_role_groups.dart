import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// Which of the learner's course groups a section shows (#8425).
enum CourseRoleGroup {
  /// Pending course invites. Role is unknown until join — power levels
  /// aren't part of stripped invite state — so invites are their own group.
  invited,

  /// Joined courses the learner administers (`isRoomAdmin`, power level ≥
  /// 100). There is no separate teacher role; admin is the signal.
  teaching,

  /// Every other joined course.
  learning;

  String title(L10n l10n) => switch (this) {
    CourseRoleGroup.invited => l10n.invited,
    CourseRoleGroup.teaching => l10n.courseSectionTeaching,
    CourseRoleGroup.learning => l10n.courseSectionLearning,
  };
}

/// One non-empty group of courses, in display order.
class CourseRoleSection {
  final CourseRoleGroup group;
  final List<Room> rooms;

  const CourseRoleSection(this.group, this.rooms);
}

/// The learner's courses split by their role in each — the model behind the
/// Courses hub's sections and the nav rail's grouped order (#8425).
///
/// Each group keeps the alphabetical (localized display name) order of the
/// underlying sorted course list.
class CourseRoleGroups {
  final List<Room> invited;
  final List<Room> teaching;
  final List<Room> learning;

  const CourseRoleGroups({
    required this.invited,
    required this.teaching,
    required this.learning,
  });

  /// Whether the split is worth showing: only when the learner holds BOTH
  /// roles. A pure learner (most users) or a pure teacher gets the flat list
  /// they have today — no section headers, no rail dividers.
  bool get isGrouped => teaching.isNotEmpty && learning.isNotEmpty;

  /// The non-empty groups in display order: invited, teaching, learning.
  List<CourseRoleSection> get sections => [
    if (invited.isNotEmpty) CourseRoleSection(CourseRoleGroup.invited, invited),
    if (teaching.isNotEmpty)
      CourseRoleSection(CourseRoleGroup.teaching, teaching),
    if (learning.isNotEmpty)
      CourseRoleSection(CourseRoleGroup.learning, learning),
  ];

  /// Every course in display order. When [isGrouped] is false this is exactly
  /// the pre-#8425 order (invites first, then joined courses alphabetically).
  List<Room> get ordered => [...invited, ...teaching, ...learning];

  int get courseCount => invited.length + teaching.length + learning.length;

  /// How many section headers the hub renders: one per non-empty group when
  /// grouped, none otherwise. The mobile sheet's content-fit height counts
  /// these rows.
  int get sectionCount => isGrouped ? sections.length : 0;
}
