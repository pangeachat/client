import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The activity plan page's rating indicator, top-right of the header per the
/// #7194/#7993 designs: a NEW pill while the activity has fewer than
/// [kNewRatingThreshold] ratings, then a small ring filled to the up-fraction
/// with the percentage beside it, tinted between light red (all thumbs down)
/// and light purple (all thumbs up). This is the ONLY surface that shows the
/// badge/meter — map pins and cards carry neither (the rating enters the map
/// solely as a score term; world-map.instructions.md).
class ActivityRatingMeter extends StatelessWidget {
  /// Up-fraction 0..1, null when the read path didn't carry it.
  final double? average;
  final int? count;

  const ActivityRatingMeter({super.key, this.average, this.count});

  static const Color _downColor = Color(0xFFEFB8B8); // light red
  static const Color _upColor = AppConfig.primaryColorLight; // light purple

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
    final color = Color.lerp(_downColor, _upColor, clamped)!;

    return Tooltip(
      message: L10n.of(context).activityRatingMeterLabel(percent, count!),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4.0,
        children: [
          SizedBox(
            height: 18.0,
            width: 18.0,
            child: CircularProgressIndicator(
              value: clamped,
              strokeWidth: 3.0,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          Text("$percent%", style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
