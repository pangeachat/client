import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/course_role_groups.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';

extension SpacesClientExtension on Client {
  Future<String> createPangeaSpace({
    required String name,
    String? topic,
    Visibility visibility = Visibility.private,
    JoinRules joinRules = JoinRules.public,
    String? avatarUrl,
    List<StateEvent>? initialState,
    int spaceChild = 50,
  }) async => createPangeaRoom(
    createRoom(
      creationContent: {'type': RoomCreationTypes.mSpace},
      visibility: visibility,
      name: name.trim(),
      topic: topic?.trim(),
      initialState: [
        await generateCustomJoinRules(joinRules),
        if (avatarUrl != null)
          StateEvent(type: EventTypes.RoomAvatar, content: {'url': avatarUrl}),
        if (initialState != null) ...initialState,
      ],
      powerLevelContentOverride: RoomDefaults.defaultSpacePowerLevelsContent(
        spaceChild: spaceChild,
      ),
    ),
  );

  /// The learner's joined courses, in [rooms]' own recency order.
  List<Room> get joinedCourses =>
      rooms.where((r) => r.isSpace && r.membership == Membership.join).toList();

  /// The learner's courses they are joined to OR invited to — what the Courses
  /// hub lists and sizes itself on.
  List<Room> get courses => rooms
      .where(
        (r) =>
            r.isSpace &&
            (r.membership == Membership.join ||
                r.membership == Membership.invite),
      )
      .toList();

  /// In the nav rail and courses tab, prioritize invited courses,
  /// then sort alphebetically by title
  List<Room> sortedCourses(L10n l10n) => courses
    ..sort((a, b) {
      if (a.membership == Membership.join &&
          b.membership == Membership.invite) {
        return 1;
      }
      if (b.membership == Membership.join &&
          a.membership == Membership.invite) {
        return -1;
      }
      return a
          .getLocalizedDisplayname(MatrixLocals(l10n))
          .toLowerCase()
          .compareTo(
            b.getLocalizedDisplayname(MatrixLocals(l10n)).toLowerCase(),
          );
    });

  /// [sortedCourses] split by the learner's role in each course — the model
  /// the Courses hub, the nav rail and the mobile sheet's height estimate all
  /// read (#8425). Partitioning the sorted list keeps each group alphabetical.
  CourseRoleGroups coursesByRole(L10n l10n) {
    final invited = <Room>[];
    final teaching = <Room>[];
    final learning = <Room>[];
    for (final course in sortedCourses(l10n)) {
      if (course.membership == Membership.invite) {
        invited.add(course);
      } else if (course.isRoomAdmin) {
        teaching.add(course);
      } else {
        learning.add(course);
      }
    }
    return CourseRoleGroups(
      invited: invited,
      teaching: teaching,
      learning: learning,
    );
  }
}
