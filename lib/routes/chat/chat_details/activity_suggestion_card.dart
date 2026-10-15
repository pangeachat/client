// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/activity_participant_row.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_video_tag.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/completed_stamp.dart';
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
  final List<String> participants;
  final int openSlots;

  /// The activity's live map-pin state, or null for a plain card. Drawn as a
  /// frame in the pin's state hue with a corner tab naming it, so the card
  /// matches the map's pins: Ongoing (dark purple) or Open/joinable (green).
  /// See [ActivityPinState].
  final ActivityPinState? pinState;

  /// How many times the learner has finished this activity. Above zero the
  /// card wears the completed stamp (a double ring with a check) in its
  /// top-right corner — the same mark as on the map — with "×N" past one. It
  /// sits beside a live [pinState], never instead of it (#9420 prototype).
  final int timesCompleted;

  /// The photo's height; null keeps it square (width × width). The map's
  /// activity cards squash it so the card reads squarer.
  final double? imageHeight;

  static const double _frameWidth = 3.0;

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
    this.timesCompleted = 0,
    this.imageHeight,
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

    // Match the map's state pins: a frame and a corner tab in the pin's state
    // hue. The info section keeps the plain card surface and ink.
    final stateColor = pinState?.bodyColor(context);
    final onState = pinState?.onBodyColor(context);

    // Shared style for the mode + participant-count labels
    final labelStyle = fontSizeSmall != null
        ? TextStyle(fontSize: fontSizeSmall)
        : theme.textTheme.labelSmall;

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
                      if (imageHeight == null)
                        ImageByUrl(
                          imageUrl: heroUrl,
                          width: width,
                          borderRadius: const BorderRadius.all(Radius.zero),
                          replacement: SizedBox(height: width),
                        )
                      else
                        SizedBox(
                          width: width,
                          height: imageHeight,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: ImageByUrl(
                              imageUrl: heroUrl,
                              width: width,
                              borderRadius: const BorderRadius.all(Radius.zero),
                              replacement: SizedBox(
                                width: width,
                                height: width,
                              ),
                            ),
                          ),
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
                    child: Container(
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
                              style: TextStyle(fontSize: fontSize),
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
          // The live state as a frame around the whole card.
          if (stateColor != null)
            IgnorePointer(
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: stateColor, width: _frameWidth),
                ),
              ),
            ),
          // ...and named in a tab in its top-left corner, with the Waiting
          // state's roster just under it, on the photo with no bar behind it.
          if (pinState != null && stateColor != null)
            Positioned(
              top: 0,
              left: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(maxWidth: width * 0.75),
                    padding: const EdgeInsets.fromLTRB(8.0, 3.0, 9.0, 4.0),
                    decoration: BoxDecoration(
                      color: stateColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12.0),
                        bottomRight: Radius.circular(10.0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The shared status glyph, matching the map pin.
                        Icon(
                          pinState!.icon,
                          size: (fontSizeSmall ?? 11.0) + 3.0,
                          color: onState,
                        ),
                        const SizedBox(width: 4.0),
                        Flexible(
                          child: Text(
                            _stateLabel(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: onState,
                              fontSize: fontSizeSmall ?? 11.0,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pinState == ActivityPinState.ongoingPending &&
                      (participants.isNotEmpty || openSlots > 0))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6.0, 4.0, 0, 0),
                      child: ActivityParticipantRow(
                        icon: null,
                        accent: stateColor,
                        participants: participants,
                        openSlots: openSlots,
                        avatarSize: (width / 8).clamp(14.0, 24.0),
                      ),
                    ),
                ],
              ),
            ),
          if (timesCompleted > 0)
            Positioned(
              top: 5.0,
              right: 5.0,
              child: CompletedStamp(
                size: (width / 6).clamp(22.0, 32.0),
                times: timesCompleted,
              ),
            ),
        ],
      ),
    );
  }

  String _stateLabel(BuildContext context) => switch (pinState!) {
    ActivityPinState.ongoingActive => L10n.of(context).ongoing,
    ActivityPinState.ongoingPending => L10n.of(context).mapStatusWaiting,
    _ =>
      openSessions == null
          ? L10n.of(context).open
          : "${L10n.of(context).open} ($openSessions)",
  };
}
