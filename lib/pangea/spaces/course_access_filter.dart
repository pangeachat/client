import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';

/// The browse list's access filter pills (#9358): how a public course is
/// joined. The catalog does not filter by join rule, so each filter narrows
/// the pages the list has fetched.
enum CourseAccessFilter {
  all,

  /// Anyone can join straight away (join rule `public`).
  public,

  /// The learner asks to join and an admin lets them in (join rule `knock`).
  restricted;

  String label(L10n l10n) => switch (this) {
    CourseAccessFilter.all => l10n.all,
    CourseAccessFilter.public => l10n.public,
    CourseAccessFilter.restricted => l10n.approvalRequired,
  };

  String tooltip(L10n l10n) => switch (this) {
    CourseAccessFilter.all => l10n.allCoursesFilterTooltip,
    CourseAccessFilter.public => l10n.publicCoursesFilterTooltip,
    CourseAccessFilter.restricted => l10n.restrictedCoursesFilterTooltip,
  };

  /// A published course with any other join rule shows under [all] only.
  bool includes(PublicCoursesChunk course) => switch (this) {
    CourseAccessFilter.all => true,
    CourseAccessFilter.public => course.room.joinRule == JoinRules.public.name,
    CourseAccessFilter.restricted =>
      course.room.joinRule == JoinRules.knock.name,
  };

  static CourseAccessFilter? fromName(String name) =>
      CourseAccessFilter.values.asNameMap()[name];
}
