import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_emoji_picker.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_chat/activity_role_tooltip.dart';
import 'package:fluffychat/pangea/chat/widgets/pangea_chat_input_row.dart';
import 'package:fluffychat/pangea/choreographer/it/it_bar.dart';
import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  final ChatController controller;
  final double padding;

  const ChatInputBar({
    required this.controller,
    required this.padding,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ActivityRoleTooltip(
          room: controller.room,
          hide: controller.choreographer.itController.open,
        ),
        ITBar(choreographer: controller.choreographer),
        if (!controller.obscureText) ReplyDisplay(controller),
        PangeaChatInputRow(
          controller: controller,
        ),
        ChatEmojiPicker(controller),
      ],
    );
  }
}
