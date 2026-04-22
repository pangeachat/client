import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';

class TutorialTooltipWidget extends StatelessWidget {
  final String text;
  final int currentStep;
  final int totalSteps;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final TextStyle? textStyle;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const TutorialTooltipWidget({
    required this.text,
    required this.currentStep,
    required this.totalSteps,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.textStyle,
    this.iconSize = 32.0,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final background = backgroundColor ?? theme.cardColor;

    final style = textStyle ?? theme.textTheme.bodyMedium;

    final progress = totalSteps > 0 ? currentStep / totalSteps : 0.0;

    return Container(
      padding: padding,
      // decoration: BoxDecoration(color: background, borderRadius: borderRadius),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(width: 2, color: theme.colorScheme.primary),
        borderRadius: const BorderRadius.all(Radius.circular(12.0)),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              spacing: 8.0,
              children: [
                BotFace(width: iconSize, expression: BotExpression.gold),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: Text(
                              text,
                              style: style,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(4.0),
            child: Row(
              children: [
                Text(
                  "$currentStep / $totalSteps",
                  style: theme.textTheme.labelSmall,
                ),
                SizedBox(width: 8.0),
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8.0,
                    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                    color: progress >= 1.0 ? AppConfig.success : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
