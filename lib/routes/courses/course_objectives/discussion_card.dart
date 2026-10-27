import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/chat_list/unread_bubble.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A discussion's card (#9647): the activity card, so a discussion sits in
/// the row like any activity, told apart by its "Discussion" mode tag and
/// icon. Two states: plain until the learner joins its chat, then the
/// Ongoing frame and pill reading "Joined". A gold XP badge on the photo
/// once they have earned XP there, counting up; the Chats list's unread
/// bubble when the chat has new messages. No waiting state and no completed
/// stamp.
class DiscussionCard extends StatelessWidget {
  final ActivityPlanModel plan;
  final double width;
  final double height;
  final double? imageHeight;
  final double? fontSize;
  final double? fontSizeSmall;
  final double? iconSize;
  final int xpEarned;
  final bool frameWhenResting;
  final bool selected;

  const DiscussionCard({
    super.key,
    required this.plan,
    required this.width,
    required this.height,
    this.imageHeight,
    this.fontSize,
    this.fontSizeSmall,
    this.iconSize,
    this.xpEarned = 0,
    this.frameWhenResting = false,
    this.selected = false,
  });

  /// The state a discussion's card and pins wear: Ongoing once the learner
  /// is in its chat, else none.
  static ActivityPinState? stateOf(bool joined) =>
      joined ? ActivityPinState.ongoingActive : null;

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    // Joining and unread messages change with every sync.
    return StreamBuilder(
      stream: client.onSync.stream,
      builder: (context, _) {
        final room = client.discussionRoomsFor(plan.activityId).firstOrNull;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            ActivitySuggestionCard(
              activity: plan,
              width: width,
              height: height,
              imageHeight: imageHeight,
              fontSize: fontSize,
              fontSizeSmall: fontSizeSmall,
              iconSize: iconSize,
              pinState: stateOf(room != null),
              stateLabel: room != null
                  ? L10n.of(context).discussionJoined
                  : null,
              stateIcon: Icons.live_help_outlined,
              xpEarned: xpEarned,
              frameWhenResting: frameWhenResting,
              selected: selected,
            ),
            if (room != null)
              Positioned(
                top: -6.0,
                right: -6.0,
                child: UnreadBubble(room: room, borderColor: PinSize.markRing),
              ),
          ],
        );
      },
    );
  }
}
