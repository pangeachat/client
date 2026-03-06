import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class GrammarErrorExampleWidget extends StatelessWidget {
  final GrammarErrorPracticeActivityModel activity;
  final bool showTranslation;

  const GrammarErrorExampleWidget({
    super.key,
    required this.activity,
    required this.showTranslation,
  });

  @override
  Widget build(BuildContext context) {
    final text = activity.text;
    final errorOffset = activity.errorOffset;
    final errorLength = activity.errorLength;

    const maxContextChars = 50;

    final chars = text.characters;
    final totalLength = chars.length;

    // ---------- BEFORE ----------
    int beforeStart = 0;
    bool trimmedBefore = false;

    if (errorOffset > maxContextChars) {
      int desiredStart = errorOffset - maxContextChars;

      // Snap left to nearest whitespace to avoid cutting words
      while (desiredStart > 0 && chars.elementAt(desiredStart) != ' ') {
        desiredStart--;
      }

      beforeStart = desiredStart;
      trimmedBefore = true;
    }

    final before = chars
        .skip(beforeStart)
        .take(errorOffset - beforeStart)
        .toString();

    // ---------- AFTER ----------
    int afterEnd = totalLength;
    bool trimmedAfter = false;

    final errorEnd = errorOffset + errorLength;
    final afterChars = totalLength - errorEnd;

    if (afterChars > maxContextChars) {
      int desiredEnd = errorEnd + maxContextChars;

      // Snap right to nearest whitespace
      while (desiredEnd < totalLength && chars.elementAt(desiredEnd) != ' ') {
        desiredEnd++;
      }

      afterEnd = desiredEnd;
      trimmedAfter = true;
    }

    final after = chars.skip(errorEnd).take(afterEnd - errorEnd).toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Colors.white.withAlpha(180),
          ThemeData.dark().colorScheme.primary,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            text: TextSpan(
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryFixed,
                fontSize:
                    AppSettings.fontSizeFactor.value *
                    AppConfig.messageFontSize,
              ),
              children: [
                if (trimmedBefore) const TextSpan(text: '…'),
                if (before.isNotEmpty) TextSpan(text: before),
                WidgetSpan(
                  child: Container(
                    height: 4.0,
                    width: (errorLength * 8).toDouble(),
                    padding: const EdgeInsets.only(bottom: 2.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (after.isNotEmpty) TextSpan(text: after),
                if (trimmedAfter) const TextSpan(text: '…'),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: showTranslation
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        activity.translation,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryFixed,
                          fontSize:
                              AppSettings.fontSizeFactor.value *
                              AppConfig.messageFontSize,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
