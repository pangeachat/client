import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/discussions/discussion_extensions.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/chat_list/unread_bubble.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/completed_stamp.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/config/pangea_colors.dart';

/// A discussion's card (#9647): the activity card, so a discussion sits in
/// the row like any activity, told apart by its "Discussion" mode tag and
/// icon. Three states: plain until the learner joins its chat; the Ongoing
/// frame and a "Joined" pill while they are in it; plain with a gold
/// "Answered" pill once they have said they are done. A gold XP badge on the
/// photo once they have earned XP there, counting up, the Answered pill in
/// its colours; the Chats list's unread
/// bubble only while they are in it. No waiting state and no completed stamp.
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
        final room = client.activeDiscussionRoomFor(plan.activityId);
        final answered = client.hasAnsweredDiscussion(plan.activityId);
        final theme = Theme.of(context);
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
                  : answered
                  ? L10n.of(context).discussionAnswered
                  : null,
              stateIcon: answered ? null : ActivityMode.discussion.icon,
              // The XP badge's look: gold on its scrim, so what the learner
              // has done reads as one family of pills.
              stateColors: answered
                  ? (fill: CompletedStamp.scrimOf(theme), on: theme.pangea.gold)
                  : null,
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
