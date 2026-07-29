import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// Compact aggregate-rating meter for an activity (issue #7194): a small ring
/// filled to the up-fraction with the percentage beside it, tinted between
/// light red (all thumbs down) and light purple (all thumbs up) per Ava's
/// design. Callers hide it while there are no ratings; it renders nothing for
/// a zero count so no surface ever shows a meaningless 0%.
class ActivityRatingMeter extends StatelessWidget {
  /// Up-fraction 0..1.
  final double average;
  final int count;

  const ActivityRatingMeter({
    super.key,
    required this.average,
    required this.count,
  });

  static const Color _downColor = Color(0xFFEFB8B8); // light red
  static const Color _upColor = AppConfig.primaryColorLight; // light purple

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final clamped = average.clamp(0.0, 1.0);
    final percent = (clamped * 100).round();
    final color = Color.lerp(_downColor, _upColor, clamped)!;

    return Tooltip(
      message: L10n.of(context).activityRatingMeterLabel(percent, count),
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
