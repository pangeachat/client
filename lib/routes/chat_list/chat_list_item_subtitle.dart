import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/activity_tile_body.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat_list/open_roles_indicator.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../utils/matrix_sdk_extensions/matrix_locals.dart';

class ChatListItemSubtitle extends StatelessWidget {
  final Room room;
  final TextStyle style;

  const ChatListItemSubtitle({
    super.key,
    required this.room,
    required this.style,
  });

  /// The subtitle text the row visibly shows, resolved synchronously so
  /// [ChatListItem] can put it in the row's accessible name. Mirrors the
  /// widget branches here and in [ChatListItem]'s subtitle: null where the
  /// subtitle shows no text (the role avatars of a not-yet-started activity),
  /// and the SDK's synchronous fallback body where the rendered preview
  /// resolves asynchronously.
  static String? semanticText(BuildContext context, Room room) {
    final l10n = L10n.of(context);
    if (room.isPendingInvite) return l10n.invited;
    if (room.isSpace && room.membership == Membership.join) {
      return l10n.countChats(room.spaceChildCount);
    }
    final typingText = room.getLocalizedTypingText(context);
    if (typingText.isNotEmpty) return typingText;

    final lastEvent = room.lastEvent;
    if (lastEvent == null) {
      if (room.membership != Membership.invite) return l10n.noMessagesYet;
      return room
              .getState(EventTypes.RoomMember, room.client.userID!)
              ?.content
              .tryGet<String>('reason') ??
          (room.isDirectChat ? l10n.newChatRequest : l10n.inviteChat);
    }

    var withSenderName = true;
    if (room.showActivityChatUI) {
      if (room.hasArchivedActivity) return room.activityPlan?.learningObjective;
      if (!room.isActivityStarted) return null;
      if (room.isActivityFinished) return l10n.activityDone;
      // The ongoing tile's avatar names the sender, so its text must not.
      if (room.isOngoingActiveSession) withSenderName = false;
    }

    if (lastEvent.type == PangeaEventTypes.call) {
      return callPreviewLine(l10n, lastEvent);
    }
    return lastEvent.calcLocalizedBodyFallback(
      MatrixLocals(l10n),
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
      removeMarkdown: true,
      withSenderNamePrefix:
          withSenderName &&
          (!room.isDirectChat || room.directChatMatrixID != lastEvent.senderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (room.showActivityChatUI) {
      // Reference plan may not be hydrated yet; fall back to empty content (the
      // list rebuilds on sync once ActivityPlanRepo fills it in).
      final activity = room.activityPlan;
      if (room.hasArchivedActivity) {
        // Excluded: [semanticText] already carries this into the row's name.
        return ExcludeSemantics(
          child: Text(
            activity?.learningObjective ?? '',
            style: style,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      } else if (!room.isActivityStarted) {
        return FutureBuilder(
          future: room.requestParticipants(
            [Membership.join, Membership.invite, Membership.knock],
            false,
            true,
          ),
          builder: (context, _) {
            return OpenRolesIndicator(
              roles: activity?.roles.values.toList() ?? [],
              assignedRoles: room.assignedRoles?.values.toList() ?? [],
              room: room,
              space: room.courseParent,
            );
          },
        );
      } else if (room.isActivityFinished) {
        return ExcludeSemantics(
          child: Text(
            L10n.of(context).activityDone,
            style: style,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      } else if (room.isOngoingActiveSession) {
        // Both star numbers come from room state, the same pair the map reads.
        // An unhydrated plan leaves no role and so a total of 0, which draws
        // nothing rather than an empty band.
        return ActivityTileBody(
          room: room,
          // One line, like the card's: this tile already carries the most of
          // any state, and a second wrapped line pushed the stars out of reach.
          preview: _LastEventPreview(
            room: room,
            style: style,
            // The avatar beside the text names the sender, so the text must
            // not name them again ("Alice: hi" under Alice's face).
            withSenderName: false,
            maxLines: 1,
          ),
          starsTotal: room.ownRole?.allGoals.length ?? 0,
          starsEarned: room.ownCompletedGoals.length,
          reserveStarSpace: false,
        );
      }
    }

    return ExcludeSemantics(
      child: _LastEventPreview(room: room, style: style),
    );
  }
}

/// The room's last event as the chat list renders it: Pangea display text for
/// a learner message (the same words the chat shows), the SDK's localized body
/// for everything else. Distinct from the map card's preview, which stays on
/// the SDK fallback — resolving display text needs the room's timeline, which
/// a map full of pins must not fetch.
class _LastEventPreview extends StatelessWidget {
  final Room room;
  final TextStyle style;
  final bool withSenderName;
  final int maxLines;

  const _LastEventPreview({
    required this.room,
    required this.style,
    this.withSenderName = true,
    this.maxLines = 2,
  });

  bool _showPangeaContent(Event event) {
    return MatrixState.pangeaController.userController.languagesSet &&
        !event.redacted &&
        event.type == EventTypes.Message &&
        event.messageType == MessageTypes.Text &&
        !(AppSettings.renderHtml.value &&
            !event.redacted &&
            event.isRichMessage);
  }

  Future<PangeaMessageEvent> _pangeaMessageEvent(final Event event) async {
    final Timeline timeline =
        event.room.timeline ?? await event.room.getTimeline();

    return PangeaMessageEvent(
      event: event,
      timeline: timeline,
      ownMessage: event.senderId == event.room.client.userID,
    );
  }

  Widget _text(String data) => Text(
    data,
    style: style,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
  );

  @override
  Widget build(BuildContext context) {
    final event = room.lastEvent;
    if (event == null) return _text(L10n.of(context).emptyChat);

    // The same words the card in the conversation uses, so the list and the
    // conversation agree. Left to the SDK this reads "User sent a pangea.call
    // event".
    if (event.type == PangeaEventTypes.call) {
      // Null when the conversation draws nothing for this call: a send that
      // failed, or a card from somebody who was not on it. Nothing is shown
      // rather than the empty-chat line, which would be a claim about the
      // whole room -- and the room may be full of real messages that simply
      // are not the newest event.
      //
      // Through main's `_text` helper, which is why this cannot simply BE
      // `_text(callPreviewLine(...))`: that takes a non-nullable String, and
      // the preview line became nullable when the call card learned to draw
      // nothing.
      final line = callPreviewLine(L10n.of(context), event);
      if (line == null) return const SizedBox.shrink();
      return _text(line);
    }

    if (!_showPangeaContent(event)) {
      return FutureBuilder(
        future: event.calcLocalizedBody(
          MatrixLocals(L10n.of(context)),
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
          removeMarkdown: true,
          withSenderNamePrefix:
              withSenderName &&
              (!event.room.isDirectChat ||
                  event.room.directChatMatrixID != event.senderId),
        ),
        builder: (context, snapshot) =>
            _text(snapshot.data ?? L10n.of(context).emptyChat),
      );
    }

    return FutureBuilder<PangeaMessageEvent>(
      future: _pangeaMessageEvent(event),
      builder: (context, snapshot) => _text(
        snapshot.data?.messageDisplayText ?? L10n.of(context).emptyChat,
      ),
    );
  }
}
