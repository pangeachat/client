// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_video_tag.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class ActivitySuggestionCard extends StatelessWidget {
  final ActivityPlanModel activity;
  final double width;
  final double height;

  final double? fontSize;
  final double? fontSizeSmall;
  final double? iconSize;

  final int? openSessions;
  final int starsEarned;

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
    return SizedBox(
      height: height,
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Container(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2.0,
                    horizontal: 4.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.title,
                        style: TextStyle(fontSize: fontSize),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
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
                                  style: fontSizeSmall != null
                                      ? TextStyle(fontSize: fontSizeSmall)
                                      : theme.textTheme.labelSmall,
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
                                Text(
                                  "${activity.req.numberOfParticipants}",
                                  style: fontSizeSmall != null
                                      ? TextStyle(fontSize: fontSizeSmall)
                                      : theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          if (openSessions != null && openSessions! > 0)
                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 4.0,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline,
                                    size: iconSize ?? 12.0,
                                  ),
                                  Text(
                                    "$openSessions",
                                    style: fontSizeSmall != null
                                        ? TextStyle(fontSize: fontSizeSmall)
                                        : theme.textTheme.labelSmall,
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
    );
  }
}
