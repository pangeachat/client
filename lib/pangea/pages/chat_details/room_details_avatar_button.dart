import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix_api_lite/model/event_types.dart';

class RoomDetailsAvatarButton extends StatelessWidget {
  final ChatDetailsController controller;
  const RoomDetailsAvatarButton({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    if (controller.room == null) {
      return const SizedBox();
    }
    return Padding(
      padding: const EdgeInsets.all(32.0),
      // avatar button
      child: Stack(
        children: [
          Material(
            elevation:
                Theme.of(context).appBarTheme.scrolledUnderElevation ?? 4,
            shadowColor: Theme.of(context).appBarTheme.shadowColor,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).dividerColor,
              ),
              borderRadius: BorderRadius.circular(
                Avatar.defaultSize * 2.5,
              ),
            ),
            child: Avatar(
              mxContent: controller.room!.avatar,
              name: controller.room!.getLocalizedDisplayname(),
              size: Avatar.defaultSize * 2.5,
            ),
          ),
          if (!controller.room!.isDirectChat &&
              controller.room!.canChangeStateEvent(
                EventTypes.RoomAvatar,
              ))
            Positioned(
              bottom: 0,
              right: 0,
              child: FloatingActionButton.small(
                onPressed: controller.setAvatarAction,
                heroTag: null,
                child: const Icon(
                  Icons.camera_alt_outlined,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
