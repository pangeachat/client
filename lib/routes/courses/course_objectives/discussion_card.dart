import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/discussions/discussion_standing.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_card_state_pill.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/chat_list/unread_bubble.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/completed_stamp.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A discussion's card (#9647): the activity card in three states. Plain
/// until the learner joins; the Ongoing frame, a "Joined" pill and the
/// chat's unread bubble while they are in it; a gold "Answered" pill once
/// they have ended it.
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

  /// The live state a discussion's card and pins wear: Ongoing while the
  /// learner is in its chat.
  static ActivityPinState? stateOf(DiscussionStanding standing) =>
      standing.joined ? ActivityPinState.ongoingActive : null;

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    return StreamBuilder(
      stream: client.onSync.stream,
      builder: (context, _) {
        final standing = client.discussionStandingFor(plan.activityId);
        final room = standing.activeRoom;
        final l10n = L10n.of(context);
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
              pinState: stateOf(standing),
              statePill: standing.joined
                  ? ActivityCardStatePill(
                      label: l10n.discussionJoined,
                      icon: ActivityMode.discussion.icon,
                    )
                  : standing.answered
                  // The XP badge's gold on its scrim, so what the learner
                  // has done reads as one family of pills.
                  ? ActivityCardStatePill(
                      label: l10n.discussionAnswered,
                      fill: CompletedStamp.scrimOf(theme),
                      onFill: theme.pangea.gold,
                    )
                  : null,
              xpEarned: xpEarned,
              frameWhenResting: frameWhenResting,
              selected: selected,
            ),
            if (room != null)
              Positioned(
                top: -6.0,
                right: -6.0,
                // Rings the bubble off the card it overlaps, in the card's
                // own surface colour.
                child: UnreadBubble(
                  room: room,
                  borderColor: theme.colorScheme.surface,
                ),
              ),
          ],
        );
      },
    );
  }
}
