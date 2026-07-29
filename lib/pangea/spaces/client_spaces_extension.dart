import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
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

  /// In the nav rail and courses tab, prioritize invited courses,
  /// then sort alphebetically by title
  List<Room> sortedCourses(L10n l10n) =>
      rooms
          .where(
            (r) =>
                r.isSpace &&
                (r.membership == Membership.join ||
                    r.membership == Membership.invite),
          )
          .toList()
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
}
