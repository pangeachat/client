import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/extensions/unread_rooms_client_extension.dart';
import 'package:fluffychat/pangea/spaces/course_role_filter.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_extension.dart';

abstract class AddCourseTileContent {
  String title(L10n l10n);

  Uri? get imageUrl => null;

  int? get members => null;

  String? get courseId => null;

  /// The joined/previewed course space, where the tile has one — lets the info
  /// chips read the same quest outline the course itself does.
  String? get courseRoomId => null;

  /// The course space behind this tile, for the tile chrome that needs the
  /// live room rather than a snapshot of it — currently the knock badge, which
  /// watches the member list. Null for tiles with no room yet (public-course
  /// previews, course-plan suggestions), which skip that chrome entirely.
  Room? get space => null;

  bool get isKnock => false;

  bool? get invited => null;

  /// The viewer administers this joined course — its tile carries the Admin
  /// label (#9207).
  bool get isAdmin => false;

  Future<Event?>? get unreadCoursePingEvent => null;

  List<Room>? get unreadRooms => null;

  String? get expandedContent => null;
}

class RoomAddCourseTileContent extends AddCourseTileContent {
  @override
  final Room space;

  /// The client-wide [UnreadRoomsClientExtension.unreadRooms], read once for
  /// the whole list.
  final List<Room> clientUnreadRooms;

  RoomAddCourseTileContent(this.space, this.clientUnreadRooms);

  @override
  String title(_) => space.getLocalizedDisplayname();

  @override
  Uri? get imageUrl => space.avatar;

  @override
  int? get members => space.summary.mJoinedMemberCount ?? 1;

  @override
  bool get invited => space.membership == Membership.invite;

  @override
  bool get isAdmin => CourseRoleFilter.teaching.includes(space);

  @override
  Future<Event?>? get unreadCoursePingEvent => space.unreadCoursePingEvent;

  @override
  List<Room> get unreadRooms => space.spaceChildrenAmong(clientUnreadRooms);

  @override
  String? get courseId => space.coursePlan?.uuid;

  @override
  String? get courseRoomId => space.id;
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

  @override
  String? get expandedContent => preview.room.topic;
}

class CoursePlanAddCourseTileContent extends AddCourseTileContent {
  final CoursePlanModel course;
  CoursePlanAddCourseTileContent(this.course);

  @override
  String title(_) => course.title;

  @override
  Uri? get imageUrl => course.imageUrl;

  @override
  String? get courseId => course.uuid;

  @override
  String? get expandedContent => course.description;
}

class CombinedAddCourseTileContent extends AddCourseTileContent {
  final String _title;
  final Uri? _imageUrl;
  final int? _members;
  final String? _courseId;
  final bool _isKnock;
  final String? _expandedContent;

  CombinedAddCourseTileContent({
    required String title,
    Uri? imageUrl,
    int? members,
    String? courseId,
    bool isKnock = false,
    String? expandedContent,
  }) : _title = title,
       _imageUrl = imageUrl,
       _members = members,
       _courseId = courseId,
       _isKnock = isKnock,
       _expandedContent = expandedContent;

  @override
  String title(_) => _title;

  @override
  Uri? get imageUrl => _imageUrl;

  @override
  int? get members => _members;

  @override
  String? get courseId => _courseId;

  @override
  bool get isKnock => _isKnock;

  @override
  String? get expandedContent => _expandedContent;
}
