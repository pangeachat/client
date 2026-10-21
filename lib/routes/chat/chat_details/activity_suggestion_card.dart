// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/activity_participant_row.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_video_tag.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_selection.dart';
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

  /// The live roster drawn in the Waiting ([ActivityPinState.ongoingPending])
  /// state's participant bar
  final List<String> participants;
  final int openSlots;

  /// The activity's live map-pin state, or null for a plain card. Drawn as a
  /// thin frame in the pin's state hue with a pill on the photo naming it, so
  /// the card matches the map's pins: Ongoing (purple) or Open (green).
  /// See [ActivityPinState].
  final ActivityPinState? pinState;

  /// How many times the learner has finished this activity. Above zero the
  /// photo wears the completed coin with its XP (or "×N" past one) in its
  /// bottom-right corner — the same mark as on the map. It sits beside a live
  /// [pinState], never instead of it.
  final int timesCompleted;

  /// The learner's total XP from every finished session of this activity,
  /// shown on the completed stamp in place of its "×N" (#9559). The card
  /// carries no goal row: goals pay XP every session, so the activity's
  /// headline is the XP it has given, and the goals live in the session.
  final int xpEarned;

  /// Outline a card with no live state in the not-started pin's colour —
  /// the map's cards, which float over the tiles and would otherwise melt
  /// into them (#9559). Off on the course page and the activity panel, where
  /// a resting card stays plain.
  final bool frameWhenResting;

  /// The map's focused card: its frame darkens slightly, the selected look
  /// it shares with the map's pins ([WorldMapSelection]).
  final bool selected;

  /// A coursemate pinged the course to fill this activity's open session:
  /// the live-state pill shows the ping's bell in place of its state glyph.
  final bool pinged;

  /// The photo's height; null keeps it square (width × width). The map's
  /// activity cards squash it so the card reads squarer.
  final double? imageHeight;

  static const double _frameWidth = 2.0;

  const ActivitySuggestionCard({
    super.key,
    required this.activity,
    required this.width,
    required this.height,
    this.fontSize,
    this.fontSizeSmall,
    this.iconSize,
    this.openSessions,
    this.pinState,
    this.participants = const [],
    this.openSlots = 0,
    this.timesCompleted = 0,
    this.xpEarned = 0,
    this.pinged = false,
    this.frameWhenResting = false,
    this.selected = false,
    this.imageHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hero = activity.heroBlock;
    final heroIsVideo = hero != null && (hero.isVideo || hero.isYoutube);
    final heroDisplayUrl = hero?.displayUrl(width);
    final heroUrl = heroDisplayUrl != null
        ? Uri.tryParse(heroDisplayUrl)
        : activity.imageURL;

    // The card body stays calm (#9559): the badges ride the photo as one
    // family of pills — what is live top-left, what the learner earned
    // bottom-right — and only a live card adds a thin frame in its state's
    // hue, matching the map's pins.
    final stateColor = pinState?.bodyColor(context);
    final onState = pinState?.onBodyColor(context);
    final restingFrame =
        stateColor ??
        (frameWhenResting
            ? ActivityPinState.available.bodyColor(context)
            : null);
    final frameColor = selected && restingFrame != null
        ? WorldMapSelection.darken(restingFrame)
        : restingFrame;

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
                      // What the learner has done here, bottom-right on the
                      // photo: the corners above belong to the live state and
                      // the map's close button, and the bottom-left to the
                      // video tag.
                      if (timesCompleted > 0)
                        Positioned(
                          right: 6.0,
                          bottom: 6.0,
                          child: CompletedStamp(
                            size: (width / 8).clamp(14.0, 18.0),
                            times: timesCompleted,
                            xp: xpEarned,
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
          // The live state as a thin frame around the whole card — or, where
          // asked, the not-started pin's colour on a resting one.
          if (frameColor != null)
            IgnorePointer(
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: frameColor, width: _frameWidth),
                ),
              ),
            ),
          // ...and named in a pill at the photo's top-left, with the Waiting
          // state's roster just under it.
          if (pinState != null && stateColor != null)
            Positioned(
              top: 6.0,
              left: 6.0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    // Room on the right for the map card's close button.
                    constraints: BoxConstraints(maxWidth: width * 0.7),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      6.0,
                      2.0,
                      8.0,
                      2.0,
                    ),
                    decoration: BoxDecoration(
                      color: stateColor,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(999.0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The shared status glyph, matching the map pin —
                        // or the ping's bell, folded into the pill so a card
                        // carries one badge for what is live (#9559).
                        Icon(
                          pinged
                              ? Icons.notifications_outlined
                              : pinState!.icon,
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
