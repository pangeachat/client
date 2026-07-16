import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

class GrammarErrorExampleWidget extends StatelessWidget {
  final GrammarErrorPracticeExerciseModel analyticsPracticeExercise;
  final bool showTranslation;

  const GrammarErrorExampleWidget({
    super.key,
    required this.analyticsPracticeExercise,
    required this.showTranslation,
  });

  /// The sentence split around the blanked error span, as (before, after) plus
  /// whether either side was context-trimmed. Grapheme-based (matching
  /// [SpanData.errorSpan]), so the blank aligns exactly with
  /// `text.characters[errorOffset .. errorOffset + errorLength)` — the true
  /// error word once the offsets index the right base string (#7360). Pure and
  /// static so the alignment is unit-testable without pumping the widget.
  @visibleForTesting
  static ({String before, String after, bool trimmedBefore, bool trimmedAfter})
  splitAroundBlank(
    String text,
    int errorOffset,
    int errorLength, {
    int maxContextChars = 50,
  }) {
    final chars = text.characters;
    final totalLength = chars.length;

    int beforeStart = 0;
    bool trimmedBefore = false;
    if (errorOffset > maxContextChars) {
      int desiredStart = errorOffset - maxContextChars;
      // Snap left to nearest whitespace to avoid cutting words.
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

    int afterEnd = totalLength;
    bool trimmedAfter = false;
    final errorEnd = errorOffset + errorLength;
    if (totalLength - errorEnd > maxContextChars) {
      int desiredEnd = errorEnd + maxContextChars;
      // Snap right to nearest whitespace.
      while (desiredEnd < totalLength && chars.elementAt(desiredEnd) != ' ') {
        desiredEnd++;
      }
      afterEnd = desiredEnd;
      trimmedAfter = true;
    }
    final after = chars.skip(errorEnd).take(afterEnd - errorEnd).toString();

    return (
      before: before,
      after: after,
      trimmedBefore: trimmedBefore,
      trimmedAfter: trimmedAfter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final errorLength = analyticsPracticeExercise.errorLength;

    final split = splitAroundBlank(
      analyticsPracticeExercise.text,
      analyticsPracticeExercise.errorOffset,
      errorLength,
    );
    final before = split.before;
    final after = split.after;
    final trimmedBefore = split.trimmedBefore;
    final trimmedAfter = split.trimmedAfter;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            text: TextSpan(
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
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
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withAlpha(200),
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
                        analyticsPracticeExercise.translation,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
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
