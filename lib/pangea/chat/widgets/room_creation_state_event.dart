import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/course_chats/default_chats_room_extension.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';

class RoomCreationStateEvent extends StatefulWidget {
  final Event event;
  const RoomCreationStateEvent({required this.event, super.key});

  @override
  State<RoomCreationStateEvent> createState() => RoomCreationStateEventState();
}

class RoomCreationStateEventState extends State<RoomCreationStateEvent> {
  Event get event => widget.event;
  StreamSubscription? _memberSubscription;

  int get _members =>
      (event.room.summary.mJoinedMemberCount ?? 0) +
      (event.room.summary.mInvitedMemberCount ?? 0);

  @override
  void initState() {
    super.initState();
    _memberSubscription = event.room.client.onRoomState.stream
        .where((u) {
          return u.roomId == event.room.id &&
              u.state.type == EventTypes.RoomMember;
        })
        .listen((_) {
          if (_members > 1) setState(() {});
        });
  }

  @override
  void dispose() {
    _memberSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final matrixLocals = MatrixLocals(l10n);
    final theme = Theme.of(context);
    final roomName = event.room.getLocalizedDisplayname(matrixLocals);
    final defaultChatType = event.room.defaultChatType;

    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Column(
        spacing: 16.0,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 256),
            child: Material(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    Avatar(
                      mxContent: event.room.avatar,
                      name: roomName,
                      size: Avatar.defaultSize * 2,
                      userId: event.room.directChatMatrixID,
                      useRive: true,
                    ),
                    Text(
                      roomName,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${event.originServerTs.localizedTime(context)} | ${l10n.countParticipants((event.room.summary.mJoinedMemberCount ?? 1) + (event.room.summary.mInvitedMemberCount ?? 0))}',
                      style: theme.textTheme.labelSmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (defaultChatType != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12.0),
                constraints: const BoxConstraints(
                  maxWidth: FluffyThemes.columnWidth * 1.5,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer.withAlpha(128),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    defaultChatType.details(l10n),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
          const InstructionsInlineTooltip(
            instructionsEnum: InstructionsEnum.clickMessage,
            padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0),
            animate: false,
          ),
          if (_members <= 1 && InstructionsEnum.clickMessage.isToggledOff)
            const InstructionsInlineTooltip(
              instructionsEnum: InstructionsEnum.emptyChatWarning,
              padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0),
              animate: false,
            ),
        ],
      ),
    );
  }
}
