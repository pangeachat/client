import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';

class _ProFeatureInfo {
  final IconData icon;
  final String text;

  const _ProFeatureInfo({required this.icon, required this.text});

  static List<_ProFeatureInfo> entries(L10n l10n) => [
    _ProFeatureInfo(
      icon: Icons.volume_up_outlined,
      text: l10n.pronunciationTools,
    ),
    _ProFeatureInfo(icon: Icons.mic_outlined, text: l10n.audioTranscription),
    _ProFeatureInfo(icon: Icons.mood, text: l10n.visualLearnerSupport),
    _ProFeatureInfo(
      icon: Icons.edit_outlined,
      text: l10n.instantWritingTranslation,
    ),
    _ProFeatureInfo(
      icon: Icons.lightbulb_outline,
      text: l10n.personalizedPracticeExercises,
    ),
    _ProFeatureInfo(icon: Icons.star_outline, text: l10n.vocabularyFlashcards),
  ];
}

class ProFeaturesCard extends StatelessWidget {
  final double borderWidth;
  final Color? frameColor;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry titlePadding;

  const ProFeaturesCard({
    super.key,
    this.borderWidth = 3.0,
    this.frameColor,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius = 24.0,
    this.padding = const EdgeInsets.all(24),
    this.titlePadding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 12,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = theme.brightness == Brightness.light
        ? AppConfig.gold
        : AppConfig.goldLight;

    return Semantics(
      label: L10n.of(context).featuresIncludeLabel,
      container: true,
      child: FrameContainer(
        title: L10n.of(context).proFeatures,
        frameColor: frameColor ?? gold,
        borderWidth: borderWidth,
        padding: padding,
        titlePadding: titlePadding,
        backgroundColor: backgroundColor ?? theme.colorScheme.surface,
        foregroundColor:
            foregroundColor ??
            (theme.brightness == Brightness.light
                ? theme.colorScheme.onSurface
                : theme.colorScheme.surface),
        child: Column(
          spacing: 12.0,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._ProFeatureInfo.entries(L10n.of(context)).map(
              (e) => Row(
                spacing: 8.0,
                children: [
                  Icon(e.icon, color: gold, size: 20.0),
                  Expanded(
                    child: Semantics(
                      container: true,
                      child: Text(
                        e.text,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
