import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:flutter/material.dart';

class RoomDetailsHeader extends StatelessWidget {
  final ChatDetailsController controller;
  const RoomDetailsHeader({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        controller.room?.nameAndRoomTypeIcon(
              TextStyle(
                fontSize: 20,
                color: Theme.of(context).textTheme.bodyLarge!.color,
              ),
            ) ??
            const SizedBox.shrink(),
        IconButton(
          onPressed: controller.room?.canSendDefaultStates ?? false
              ? controller.setDisplaynameAction
              : null,
          icon: const Icon(Icons.edit),
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ],
    );
  }
}
