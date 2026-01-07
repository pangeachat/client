import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class StatCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final String achievementText;
  final Widget child;
  final bool isAchievement;

  const StatCard({
    required this.icon,
    required this.text,
    required this.achievementText,
    required this.child,
    this.isAchievement = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isAchievement
        ? Color.alphaBlend(
            Theme.of(context).colorScheme.surface.withAlpha(170),
            AppConfig.goldLight,
          )
        : colorScheme.surfaceContainer;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                icon,
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (isAchievement) ...[
                const Spacer(),
                Text(
                  achievementText,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
