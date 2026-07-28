// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_video_tag.dart';
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
                                    Semantics(
                                      label:
                                          "${L10n.of(context).participants}: ${activity.req.numberOfParticipants}",
                                      child: ExcludeSemantics(
                                        child: Text(
                                          "${activity.req.numberOfParticipants}",
                                          style: labelStyle,
                                        ),
                                      ),
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
              child: _ActivityStateBanner(
                color: stateColor,
                label: pinState!.isOngoing
                    ? L10n.of(context).ongoing
                    : "${L10n.of(context).open} (${openSessions ?? 0})",
                fontSize: fontSizeSmall,
                width: width / 2 + _bannerPoke,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityStateBanner extends StatelessWidget {
  final Color color;
  final String label;
  final double? fontSize;

  /// Fixed banner width so its bookmark (left) edge lands at ~mid-card while the
  /// straight right edge is right-anchored just past the card.
  final double width;

  const _ActivityStateBanner({
    required this.color,
    required this.label,
    required this.width,
    this.fontSize,
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize ?? 11.0,
              fontWeight: FontWeight.w600,
            ),
          ),
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
