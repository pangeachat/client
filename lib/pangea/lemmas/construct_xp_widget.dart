import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';

class ConstructXpWidget extends StatelessWidget {
  final ConstructLevelEnum level;
  final int points;
  final Widget icon;

  const ConstructXpWidget({
    super.key,
    required this.level,
    required this.points,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = Theme.of(context).brightness != Brightness.light
        ? level.color(context)
        : level.darkColor(context);

    return Row(
      spacing: 16.0,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        Text(
          "$points XP",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: textColor,
              ),
        ),
      ],
    );
  }
}
