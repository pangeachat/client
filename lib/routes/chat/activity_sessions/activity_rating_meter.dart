import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The activity plan page's rating indicator, top-right of the header per the
/// #7194/#7993 designs: a NEW pill while the activity has fewer than
/// [kNewRatingThreshold] ratings, then a pill carrying a thumbs-up icon and the
/// up-percentage, tinted between the scheme's error container (all thumbs down)
/// and its primary container (all thumbs up) — light red to light purple under
/// the default seed. The thumb — not a ring or dial — is what reads as "share of
/// thumbs up" (#8088): a ring at 0% looked like an empty progress meter rather
/// than an all-negative rating. This is the ONLY surface that shows the
/// badge/meter — map pins and cards carry neither (the rating enters the map
/// solely as a score term; world-map.instructions.md).
class ActivityRatingMeter extends StatelessWidget {
  /// Up-fraction 0..1, null when the read path didn't carry it.
  final double? average;
  final int? count;

  const ActivityRatingMeter({super.key, this.average, this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isNewActivity(count)) {
      return Tooltip(
        message: L10n.of(context).newActivityBadge,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppConfig.primaryColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            L10n.of(context).newActivityBadge,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    final clamped = (average ?? 0.0).clamp(0.0, 1.0);
    final percent = (clamped * 100).round();

    // The tint runs across a matched pair of scheme roles, so the pill and its
    // contents stay contrasting at both ends and under either brightness.
    final colors = theme.colorScheme;
    final background = Color.lerp(
      colors.errorContainer,
      colors.primaryContainer,
      clamped,
    )!;
    final foreground = Color.lerp(
      colors.onErrorContainer,
      colors.onPrimaryContainer,
      clamped,
    )!;

    return Tooltip(
      message: L10n.of(context).activityRatingMeterLabel(percent, count!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4.0,
          children: [
            Icon(Icons.thumb_up_outlined, size: 16.0, color: foreground),
            Text(
              "$percent%",
              style: theme.textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
