// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_video_tag.dart';
import 'package:fluffychat/routes/world/activity_participant_row.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class ActivitySuggestionCard extends StatelessWidget {
  final ActivityPlanModel activity;
  final double width;
  final double height;

  final double? fontSize;
  final double? fontSizeSmall;
  final double? iconSize;

  /// The count shown as "Open (N)" when [pinState] is the joinable state.
  final int? openSessions;
  final int starsEarned;

  /// The live roster drawn in the Waiting ([ActivityPinState.ongoingPending])
  /// state's participant bar
  final List<LargeCardParticipant> participants;
  final int openSlots;

  /// The activity's live map-pin state, or null for a plain card. Drives the
  /// colour-state fill + bookmark banner so the card matches the map's pins:
  /// Ongoing (dark purple) or Open/joinable (green). See [ActivityPinState].
  final ActivityPinState? pinState;

  /// How far the banner's straight right edge pokes past the card's right edge.
  static const double _bannerPoke = 8.0;

  const ActivitySuggestionCard({
    super.key,
    required this.activity,
    required this.width,
    required this.height,
    this.fontSize,
    this.fontSizeSmall,
    this.iconSize,
    this.openSessions,
    this.starsEarned = 0,
    this.pinState,
    this.participants = const [],
    this.openSlots = 0,
  });

  // One player's earnable stars — uniform across roles by generation, min
  // across roles for older plans (see ActivityPlanModel.earnableStars).
  int get _starsTotal => activity.earnableStars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hero = activity.heroBlock;
    final heroIsVideo = hero != null && (hero.isVideo || hero.isYoutube);
    final heroDisplayUrl = hero?.displayUrl(width);
    final heroUrl = heroDisplayUrl != null
        ? Uri.tryParse(heroDisplayUrl)
        : activity.imageURL;

    // Match the map's state pins: a colour-state fill on the info section + a
    // bookmark banner, both in the pin's state hue
    final stateColor = pinState?.color;
    final onState = stateColor != null ? Colors.white : null;

    // Shared style for the mode + participant-count labels
    final labelStyle = fontSizeSmall != null
        ? TextStyle(fontSize: fontSizeSmall, color: onState)
        : theme.textTheme.labelSmall?.copyWith(color: onState);

    return SizedBox(
      height: height,
      width: width,
      child: Stack(
        // The banner peeks past the card's top-right corner, so it must not be clipped
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12.0),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ImageByUrl(
                        imageUrl: heroUrl,
                        width: width,
                        borderRadius: const BorderRadius.all(Radius.zero),
                        replacement: SizedBox(height: width),
                      ),
                      // A video tag, not a play badge: tapping the card opens the
                      // activity (where the video plays), so a play glyph here would
                      // mislead. See #7543.
                      if (heroIsVideo)
                        Positioned(
                          left: 6.0,
                          bottom: 6.0,
                          child: ActivityMediaVideoTag(
                            size: (iconSize ?? 12.0) * 1.4,
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    // The colour-state fill for Ongoing / Open; null (transparent,
                    // surfaceContainer shows through) for a plain card.
                    child: Container(
                      color: stateColor,
                      padding: const EdgeInsets.symmetric(
                        vertical: 2.0,
                        horizontal: 4.0,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Fixed-height card: cap the title and let it yield space
                          // (Flexible) so the star row and participant/mode row below
                          // can't be pushed past the card's bottom edge and clipped by
                          // the ClipRRect when a long title wraps (#7675).
                          Flexible(
                            child: Text(
                              activity.title,
                              style: TextStyle(
                                fontSize: fontSize,
                                color: onState,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_starsTotal > 0)
                            ActivityStarRow(
                              total: _starsTotal,
                              earned: starsEarned.clamp(0, _starsTotal),
                              iconSize: 12,
                              condensed: _starsTotal > 7,
                              emptyColor: onState,
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 8.0,
                            children: [
                              if (activity.req.mode.isNotEmpty)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Text(
                                      activity.req.mode,
                                      style: labelStyle,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: 4.0,
                                  children: [
                                    Icon(
                                      Icons.group_outlined,
                                      size: iconSize ?? 12.0,
                                      color: onState,
                                    ),
                                    Text(
                                      "${activity.req.numberOfParticipants}",
                                      style: labelStyle,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (pinState != null && stateColor != null)
            Positioned(
              top: 8.0,
              right: -_bannerPoke,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _ActivityStateBanner(
                    color: stateColor,
                    width: width / 2 + _bannerPoke,
                    child: Text(
                      _stateLabel(context),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSizeSmall ?? 11.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (pinState == ActivityPinState.ongoingPending &&
                      (participants.isNotEmpty || openSlots > 0))
                    _WaitingParticipantBar(
                      color: stateColor,
                      cardWidth: width,
                      participants: participants,
                      openSlots: openSlots,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _stateLabel(BuildContext context) => switch (pinState!) {
    ActivityPinState.ongoingActive => L10n.of(context).ongoing,
    ActivityPinState.ongoingPending => L10n.of(context).mapStatusWaiting,
    _ => "${L10n.of(context).open} (${openSessions ?? 0})",
  };
}

/// The second bookmark bar for the Waiting state. Sizes each avatar down so a
/// full roster (up to [ActivityParticipantRow.defaultMaxVisible] seats) fits
/// within the card's width
class _WaitingParticipantBar extends StatelessWidget {
  final Color color;

  /// The width of the card this bar hangs off, used to size the avatars down.
  final double cardWidth;

  final List<LargeCardParticipant> participants;
  final int openSlots;

  const _WaitingParticipantBar({
    required this.color,
    required this.cardWidth,
    required this.participants,
    required this.openSlots,
  });

  @override
  Widget build(BuildContext context) {
    final visible = (participants.length + openSlots).clamp(
      1,
      ActivityParticipantRow.defaultMaxVisible,
    );
    // The bar's inner padding (matches _ActivityStateBanner) plus the 4px gap
    // the row leaves after each circle.
    const hPadding = 16.0 + 10.0;
    const gapPerAvatar = 4.0;
    const leftInset = 16.0;
    final barMaxWidth =
        cardWidth + ActivitySuggestionCard._bannerPoke - leftInset;
    final avail = barMaxWidth - hPadding - visible * gapPerAvatar;
    final avatarSize = (avail / visible).clamp(10.0, 28.0);
    final barWidth = hPadding + visible * (avatarSize + gapPerAvatar);

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: _ActivityStateBanner(
        color: color,
        width: barWidth,
        child: ActivityParticipantRow(
          icon: null,
          accent: Colors.white,
          participants: participants,
          openSlots: openSlots,
          avatarSize: avatarSize,
        ),
      ),
    );
  }
}

class _ActivityStateBanner extends StatelessWidget {
  final Color color;
  final Widget child;

  /// Fixed banner width so its bookmark (left) edge lands at ~mid-card while the
  /// straight right edge is right-anchored just past the card.
  final double width;

  const _ActivityStateBanner({
    required this.color,
    required this.child,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    // PhysicalShape clips to the bookmark path AND casts a soft elevation
    // shadow that follows it.
    return PhysicalShape(
      clipper: const _BookmarkBannerClipper(),
      clipBehavior: Clip.antiAlias,
      color: color,
      elevation: 3.0,
      child: SizedBox(
        width: width,
        child: Padding(
          // Extra left padding clears the bookmark notch.
          padding: const EdgeInsets.fromLTRB(16.0, 3.0, 10.0, 3.0),
          child: child,
        ),
      ),
    );
  }
}

class _BookmarkBannerClipper extends CustomClipper<Path> {
  const _BookmarkBannerClipper();

  /// How far the middle of the left edge caves in toward the text.
  static const double _notch = 7.0;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, 0) // top-left tip
      ..lineTo(w, 0) // top edge
      ..lineTo(w, h) // right edge
      ..lineTo(0, h) // bottom-left tip
      ..lineTo(_notch, h / 2) // cave in to the mid-height notch
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
