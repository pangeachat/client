import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class ActivityStarRow extends StatelessWidget {
  final int total;
  final int earned;
  final double iconSize;
  final bool condensed;

  const ActivityStarRow({
    super.key,
    required this.total,
    required this.earned,
    this.iconSize = 16,
    this.condensed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final filled = earned.clamp(0, total);
    if (condensed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2.0,
        children: [
          Text("$filled/$total", style: TextStyle(fontSize: iconSize)),
          Icon(Icons.star, size: iconSize, color: AppConfig.gold),
        ],
      );
    }
    return Wrap(
      spacing: 2.0,
      runSpacing: 2.0,
      children: List.generate(
        total,
        (i) => Icon(
          i < filled ? Icons.star : Icons.star_border,
          size: iconSize,
          color: i < filled ? AppConfig.gold : AppConfig.grayText,
        ),
      ),
    );
  }
}
