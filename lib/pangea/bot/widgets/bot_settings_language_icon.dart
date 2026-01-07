import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/bot/utils/bot_room_extension.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_chat_settings_dialog.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';

class BotSettingsLanguageIcon extends StatelessWidget {
  final Room room;

  const BotSettingsLanguageIcon({
    super.key,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    String? langCode = room.botOptions?.targetLanguage;
    if (room.isActivitySession && room.activityPlan != null) {
      langCode = room.activityPlan!.req.targetLanguage;
    }
    if (langCode == null) {
      return const SizedBox();
    }

    langCode = langCode.split('-').first;
    return InkWell(
      borderRadius: BorderRadius.circular(32.0),
      onTap: room.isRoomAdmin
          ? () => BotChatSettingsDialog.show(
                context: context,
                room: room,
              )
          : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          color: Theme.of(context).colorScheme.primaryContainer,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Text(
          langCode,
          style: TextStyle(
            fontSize: 10.0,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
