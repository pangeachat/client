import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/routes/chat/chat_details/access/chat_access_settings_controller.dart';
import 'package:fluffychat/routes/chat/chat_details/edit_course/edit_course.dart';
import 'package:fluffychat/routes/chat/chat_details/emotes/settings_emotes.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/permissions/chat_permissions_settings.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';

/// The widget for a management sub-page [name] on [roomId] (a course/space or a
/// room), with the panel's `←` [back] control in place of the widget's own
/// route-pop. Null for an unknown name. Shared by the course card
/// (`course:<page>`) and the room panel (`room:<id>/details/<page>`). [filter]
/// is the invite page's initial contact filter, parsed from the room token's
/// trailing `/<filter>` field by the caller (RoomToken) — see
/// `routing.instructions.md`.
class LeftPanelRoomDetailsSubpage extends StatelessWidget {
  final PanelToken token;
  final Uri currentUri;
  final bool foldedOver;
  final bool isColumnMode;

  final String roomId;
  final String name;
  final String? filter;

  const LeftPanelRoomDetailsSubpage({
    super.key,
    required this.token,
    required this.currentUri,
    required this.foldedOver,
    required this.isColumnMode,
    required this.roomId,
    required this.name,
    this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final back = LeftPanelCloseButton(
      token: token,
      currentUri: currentUri,
      foldedOver: foldedOver,
      isColumnMode: isColumnMode,
    );

    switch (name) {
      case 'edit':
        return EditCourse(roomId: roomId, embeddedCloseButton: back);
      case 'invite':
        return PangeaInvitationSelection(
          roomId: roomId,
          initialFilter: filter != null
              ? InvitationFilter.fromString(filter!)
              : null,
          embeddedCloseButton: back,
        );
      case 'access':
        return ChatAccessSettings(roomId: roomId, embeddedCloseButton: back);
      case 'permissions':
        return ChatPermissionsSettings(
          roomId: roomId,
          embeddedCloseButton: back,
        );
      case 'emotes':
        return EmotesSettings(roomId: roomId, embeddedCloseButton: back);
      case 'addcourse':
        return NewCoursePage(
          route: 'rooms',
          spaceId: roomId,
          embeddedCloseButton: back,
        );
    }

    return SizedBox.shrink();
  }
}
