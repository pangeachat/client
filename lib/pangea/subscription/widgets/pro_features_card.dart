import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/subscription/widgets/frame_container.dart';

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
  const ProFeaturesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = theme.brightness == Brightness.light
        ? AppConfig.gold
        : AppConfig.goldLight;

    return FrameContainer(
      title: L10n.of(context).proFeatures,
      frameColor: gold,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.brightness == Brightness.light
          ? theme.colorScheme.onSurface
          : theme.colorScheme.surface,
      child: Column(
        spacing: 12.0,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._ProFeatureInfo.entries(L10n.of(context)).map(
            (e) => RichText(
              text: TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(e.icon, color: gold, size: 20.0),
                    ),
                  ),
                  TextSpan(
                    text: e.text,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
