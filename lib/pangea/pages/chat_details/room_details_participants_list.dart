import 'package:fluffychat/pages/chat_details/participant_list_item.dart';
import 'package:fluffychat/pangea/widgets/common/bot_face_svg.dart';
import 'package:fluffychat/pangea/widgets/conversation_bot/conversation_bot_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class RoomDetailsParticipantsList extends StatefulWidget {
  final Room room;
  const RoomDetailsParticipantsList({super.key, required this.room});

  @override
  RoomDetailsParticipantsListState createState() =>
      RoomDetailsParticipantsListState();
}

class RoomDetailsParticipantsListState
    extends State<RoomDetailsParticipantsList> {
  bool isOpen = true;

  List<User> get participants => widget.room.getParticipants();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                L10n.of(context)!.participants,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Stack(
                    children: [
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: IconButton(
                          icon: const BotFace(
                            width: 24.0,
                            expression: BotExpression.idle,
                          ),
                          onPressed: () => showDialog<ConversationBotSettings>(
                            context: context,
                            builder: (context) => ConversationBotSettings(
                              room: widget.room,
                              startOpen: true,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 16,
                            width: 16,
                            color: Colors.white,
                            child: const Icon(
                              Icons.add,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Stack(
                    children: [
                      SizedBox(
                        height: 40,
                        width: 40,
                        child: IconButton(
                          icon: Icon(
                            Icons.person,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () =>
                              context.go("/rooms/${widget.room.id}/invite"),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 16,
                            width: 16,
                            color: Colors.white,
                            child: const Icon(
                              Icons.add,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            foregroundColor: Theme.of(context).textTheme.bodyLarge!.color,
            child: const Icon(Icons.person_outline),
          ),
          trailing: Icon(
            isOpen
                ? Icons.keyboard_arrow_down_outlined
                : Icons.keyboard_arrow_right_outlined,
          ),
          onTap: () {
            setState(() => isOpen = !isOpen);
          },
        ),
        if (isOpen)
          Container(
            constraints: const BoxConstraints(
              maxHeight: 200,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: participants.length,
              itemBuilder: (context, index) => ParticipantListItem(
                participants[index],
              ),
            ),
          ),
      ],
    );
  }
}
