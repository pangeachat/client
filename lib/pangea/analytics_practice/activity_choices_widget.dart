import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_choice_card_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_data_service.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_ui_controller.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityChoices extends StatelessWidget {
  final MultipleChoicePracticeActivityModel activity;
  final List<AnalyticsPracticeChoice> choices;
  final ConstructTypeEnum type;

  final bool isComplete;
  final bool showHint;
  final Function(String) onSelectChoice;

  final List<InlineSpan>? audioExampleMessage;
  final String? audioTranslation;

  const ActivityChoices({
    super.key,
    required this.activity,
    required this.choices,
    required this.type,
    required this.isComplete,
    required this.showHint,
    required this.onSelectChoice,
    this.audioExampleMessage,
    this.audioTranslation,
  });

  @override
  Widget build(BuildContext context) {
    final isAudioActivity =
        activity.activityType == ActivityTypeEnum.lemmaAudio;

    if (isAudioActivity) {
      Padding(
        key: const ValueKey('choices'),
        padding: const EdgeInsets.all(16.0),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8.0,
          runSpacing: 8.0,
          children: choices
              .map(
                (choice) => ActivityChoiceCard(
                  activity: activity,
                  targetId: AnalyticsPracticeUiController.getChoiceTargetId(
                    choice.choiceId,
                    type,
                  ),
                  choiceId: choice.choiceId,
                  onPressed: () => onSelectChoice(choice.choiceId),
                  cardHeight: 48.0,
                  showHint: showHint,
                  choiceText: choice.choiceText,
                  choiceEmoji: choice.choiceEmoji,
                  enabled: !isComplete,
                  shrinkWrap: true,
                ),
              )
              .toList(),
        ),
      );
    }

    if (isAudioActivity) {
      // For audio activities, use AnimatedSwitcher to fade between choices and example message
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: isComplete
            ? _AudioCompletionWidget(
                key: const ValueKey('completion'),
                showHint: showHint,
                exampleMessage: audioExampleMessage ?? [],
                translation: audioTranslation ?? "",
              )
            : Padding(
                key: const ValueKey('choices'),
                padding: const EdgeInsets.all(16.0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: choices
                      .map(
                        (choice) => ActivityChoiceCard(
                          activity: activity,
                          targetId:
                              AnalyticsPracticeUiController.getChoiceTargetId(
                                choice.choiceId,
                                type,
                              ),
                          choiceId: choice.choiceId,
                          onPressed: () => onSelectChoice(choice.choiceId),
                          cardHeight: 48.0,
                          showHint: showHint,
                          choiceText: choice.choiceText,
                          choiceEmoji: choice.choiceEmoji,
                          enabled: !isComplete,
                          shrinkWrap: true,
                        ),
                      )
                      .toList(),
                ),
              ),
      );
    }

    return Column(
      spacing: 8.0,
      mainAxisAlignment: MainAxisAlignment.center,
      children: choices
          .map(
            (choice) => ActivityChoiceCard(
              activity: activity,
              targetId: AnalyticsPracticeUiController.getChoiceTargetId(
                choice.choiceId,
                type,
              ),
              choiceId: choice.choiceId,
              onPressed: () => onSelectChoice(choice.choiceId),
              cardHeight: 60.0,
              showHint: showHint,
              choiceText: choice.choiceText,
              choiceEmoji: choice.choiceEmoji,
              enabled: !isComplete,
            ),
          )
          .toList(),
    );
  }
}

class _AudioCompletionWidget extends StatelessWidget {
  final List<InlineSpan> exampleMessage;
  final String translation;
  final bool showHint;

  const _AudioCompletionWidget({
    super.key,
    required this.exampleMessage,
    required this.translation,
    required this.showHint,
  });

  String _extractTextFromSpans(List<InlineSpan> spans) {
    final buffer = StringBuffer();
    for (final span in spans) {
      if (span is TextSpan && span.text != null) {
        buffer.write(span.text);
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (exampleMessage.isEmpty) {
      return const SizedBox(height: 100.0);
    }

    final exampleText = _extractTextFromSpans(exampleMessage);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
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
            AnimatedSize(
              duration: FluffyThemes.animationDuration,
              alignment: Alignment.topCenter,
              child: showHint
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: PhoneticTranscriptionWidget(
                        text: exampleText,
                        pos: 'other',
                        textLanguage:
                            MatrixState.pangeaController.userController.userL2!,
                        textOnly: true,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryFixed.withValues(alpha: 0.7),
                          fontSize:
                              (AppSettings.fontSizeFactor.value *
                                  AppConfig.messageFontSize) *
                              0.85,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Main example message
            RichText(
              text: TextSpan(
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryFixed,
                  fontSize:
                      AppSettings.fontSizeFactor.value *
                      AppConfig.messageFontSize,
                ),
                children: exampleMessage,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _AudioCompletionTranslation(translation: translation),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget to show translation for audio completion message
class _AudioCompletionTranslation extends StatelessWidget {
  final String translation;

  const _AudioCompletionTranslation({required this.translation});

  @override
  Widget build(BuildContext context) {
    return Text(
      translation,
      style: TextStyle(
        color: Theme.of(
          context,
        ).colorScheme.onPrimaryFixed.withValues(alpha: 0.8),
        fontSize:
            (AppSettings.fontSizeFactor.value * AppConfig.messageFontSize) *
            0.9,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
