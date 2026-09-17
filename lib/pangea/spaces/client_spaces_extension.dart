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

  /// In the nav rail and courses tab: invited courses first, then joined
  /// courses by recent activity ([ChildrenAndParentsRoomExtension.spaceActivityTime]).
  /// Invites carry no activity, so they — and activity ties — sort by title.
  List<Room> sortedCourses(L10n l10n) {
    final courses = rooms
        .where(
          (r) =>
              r.isSpace &&
              (r.membership == Membership.join ||
                  r.membership == Membership.invite),
        )
        .toList();
    // Resolved once per course rather than per comparison: activity walks the
    // client's rooms, and the rail re-sorts on every sync.
    final activityTimes = {
      for (final course in courses)
        if (course.membership == Membership.join)
          course.id: course.spaceActivityTime,
    };
    final titles = {
      for (final course in courses)
        course.id: course
            .getLocalizedDisplayname(MatrixLocals(l10n))
            .toLowerCase(),
    };
    return courses..sort((a, b) {
      final aInvited = a.membership == Membership.invite;
      if (aInvited != (b.membership == Membership.invite)) {
        return aInvited ? -1 : 1;
      }
      if (!aInvited) {
        final byActivity = activityTimes[b.id]!.compareTo(activityTimes[a.id]!);
        if (byActivity != 0) return byActivity;
      }
      return titles[a.id]!.compareTo(titles[b.id]!);
    });
  }

  /// [sortedCourses] split by the learner's role in each course — the model
  /// the Courses hub, the nav rail and the mobile sheet's height estimate all
  /// read (#8425). Partitioning the sorted list keeps each group in that order.
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
