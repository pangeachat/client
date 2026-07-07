import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/routes/chat/chat_details/access/chat_access_settings_controller.dart';
import 'package:fluffychat/routes/chat/chat_details/edit_course/edit_course.dart';
import 'package:fluffychat/routes/chat/chat_details/emotes/settings_emotes.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/permissions/chat_permissions_settings.dart';
import 'package:fluffychat/routes/courses/own/selected_course_page.dart';

/// The widget for a management sub-page [name] on [roomId] (a course/space or a
/// room), with the panel's `←` [closeButton] control in place of the widget's own
/// route-pop. Null for an unknown name. Shared by the course card
/// (`course:<page>`) and the room panel (`room:<id>/details/<page>`). [filter]
/// is the invite page's initial contact filter, parsed from the room token's
/// trailing `/<filter>` field by the caller (RoomToken) — see
/// `routing.instructions.md`.
class LeftPanelRoomDetailsSubpage extends StatelessWidget {
  final String roomId;
  final String? name;
  final String? filter;
  final String? courseId;
  final Widget closeButton;

  const LeftPanelRoomDetailsSubpage({
    super.key,
    required this.roomId,
    required this.name,
    required this.closeButton,
    this.filter,
    this.courseId,
  });

  @override
  Widget build(BuildContext context) {
    switch (name?.split('/').first) {
      case 'edit':
        return EditCourse(roomId: roomId, embeddedCloseButton: closeButton);
      case 'invite':
        return PangeaInvitationSelection(
          roomId: roomId,
          initialFilter: InvitationFilter.fromNullableString(filter),
          embeddedCloseButton: closeButton,
        );
      case 'access':
        return ChatAccessSettings(
          roomId: roomId,
          embeddedCloseButton: closeButton,
        );
      case 'permissions':
        return ChatPermissionsSettings(
          roomId: roomId,
          embeddedCloseButton: closeButton,
        );
      case 'emotes':
        return EmotesSettings(roomId: roomId, embeddedCloseButton: closeButton);
      case 'addcourse':
        final courseId = this.courseId;
        if (courseId != null) {
          return SelectedCourse(
            courseId,
            SelectedCourseMode.addToSpace,
            spaceId: roomId,
          );
        }
        return NewCoursePage(
          route: 'rooms',
          spaceId: roomId,
          embeddedCloseButton: closeButton,
        );
    }

    return SizedBox.shrink();
  }
}
