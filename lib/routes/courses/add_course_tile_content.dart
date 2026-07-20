import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';

abstract class AddCourseTileContent {
  String title(L10n l10n);

  Uri? get imageUrl => null;

  int? get members => null;

  String? get courseId => null;

  bool get isKnock => false;
}

class RoomAddCourseTileContent extends AddCourseTileContent {
  final Room space;
  RoomAddCourseTileContent(this.space);

  @override
  String title(_) => space.getLocalizedDisplayname();

  @override
  Uri? get imageUrl => space.avatar;

  @override
  int? get members => space.summary.mJoinedMemberCount ?? 1;

  @override
  String? get courseId => space.coursePlan?.uuid;
}

class PreviewAddCourseTileContent extends AddCourseTileContent {
  final PublicCoursesChunk preview;
  PreviewAddCourseTileContent(this.preview);

  @override
  String title(L10n l10n) =>
      preview.room.name ?? preview.room.canonicalAlias ?? l10n.course;

  @override
  Uri? get imageUrl => preview.room.avatarUrl;

  @override
  int? get members => preview.room.numJoinedMembers;

  @override
  String? get courseId => preview.courseId;

  @override
  bool get isKnock => preview.room.joinRule == JoinRules.knock.name;
}

class CoursePlanAddCourseTileContent extends AddCourseTileContent {
  final CoursePlanModel course;
  CoursePlanAddCourseTileContent(this.course);

  @override
  String title(_) => course.title;

  @override
  String? get courseId => course.uuid;
}
