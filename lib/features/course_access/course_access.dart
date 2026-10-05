import 'package:flutter/material.dart' hide Visibility;

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// Who can find and join a course — joining-courses.instructions.md § Course
/// access. Each setting is a pair of Matrix settings: the course's listing in
/// the room directory that course search reads, and its join rule.
enum CourseAccess {
  public(Visibility.public, JoinRules.public),
  approvalRequired(Visibility.public, JoinRules.knock),
  private(Visibility.private, JoinRules.knock);

  final Visibility visibility;
  final JoinRules joinRule;

  const CourseAccess(this.visibility, this.joinRule);

  /// The setting new courses start on.
  static const CourseAccess initial = CourseAccess.approvalRequired;

  /// The setting this pair matches, or null when it matches none of the three
  /// (e.g. an unlisted course with the `public` join rule).
  static CourseAccess? fromSettings(
    Visibility? visibility,
    JoinRules? joinRule,
  ) => CourseAccess.values.firstWhereOrNull(
    (access) => access.visibility == visibility && access.joinRule == joinRule,
  );

  /// The lock is the one learners see on approval-required courses in the
  /// browse list.
  IconData get icon => switch (this) {
    CourseAccess.public => Icons.public,
    CourseAccess.approvalRequired => Icons.lock_outlined,
    CourseAccess.private => Icons.visibility_off_outlined,
  };

  String label(L10n l10n) => switch (this) {
    CourseAccess.public => l10n.public,
    CourseAccess.approvalRequired => l10n.approvalRequired,
    CourseAccess.private => l10n.private,
  };

  String description(L10n l10n) => switch (this) {
    CourseAccess.public => l10n.courseAccessPublicDesc,
    CourseAccess.approvalRequired => l10n.courseAccessApprovalRequiredDesc,
    CourseAccess.private => l10n.courseAccessPrivateDesc,
  };
}
