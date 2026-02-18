import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_choice_card_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityChoices extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const ActivityChoices(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.activityState,
      builder: (context, state, _) {
        return switch (state) {
          AsyncLoading<MultipleChoicePracticeActivityModel>() => const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator.adaptive(),
            ),
          ),
          AsyncError<MultipleChoicePracticeActivityModel>(:final error) =>
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                //allow try to reload activity in case of error
                ErrorIndicator(message: error.toString()),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: controller.reloadCurrentActivity,
                  icon: const Icon(Icons.refresh),
                  label: Text(L10n.of(context).tryAgain),
                ),
              ],
            ),
          AsyncLoaded<MultipleChoicePracticeActivityModel>(:final value) =>
            ValueListenableBuilder(
              valueListenable: controller.enableChoicesNotifier,
              builder: (context, enabled, _) {
                final choices = controller.filteredChoices(value);
                final isAudioActivity =
                    value.activityType == ActivityTypeEnum.lemmaAudio;

                if (isAudioActivity) {
                  // For audio activities, use AnimatedSwitcher to fade between choices and example message
                  return ValueListenableBuilder(
                    valueListenable: controller.showingAudioCompletion,
                    builder: (context, showingCompletion, _) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        layoutBuilder: (currentChild, previousChildren) {
                          return Stack(
                            alignment: Alignment.topCenter,
                            children: <Widget>[
                              ...previousChildren,
                              ?currentChild,
                            ],
                          );
                        },
                        child: showingCompletion
                            ? _AudioCompletionWidget(
                                key: const ValueKey('completion'),
                                controller: controller,
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
                                          activity: value,
                                          targetId: controller.choiceTargetId(
                                            choice.choiceId,
                                          ),
                                          choiceId: choice.choiceId,
                                          onPressed: () => controller
                                              .onSelectChoice(choice.choiceId),
                                          cardHeight: 48.0,
                                          controller: controller,
                                          choiceText: choice.choiceText,
                                          choiceEmoji: choice.choiceEmoji,
                                          enabled: enabled,
                                          shrinkWrap: true,
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                      );
                    },
                  );
                }

                return Column(
                  spacing: 8.0,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: choices
                      .map(
                        (choice) => ActivityChoiceCard(
                          activity: value,
                          targetId: controller.choiceTargetId(choice.choiceId),
                          choiceId: choice.choiceId,
                          onPressed: () =>
                              controller.onSelectChoice(choice.choiceId),
                          cardHeight: 60.0,
                          controller: controller,
                          choiceText: choice.choiceText,
                          choiceEmoji: choice.choiceEmoji,
                          enabled: enabled,
                        ),
                      )
                      .toList(),
                );
              },
            ),
          _ => Container(
            constraints: const BoxConstraints(maxHeight: 400.0),
            child: const Center(child: CircularProgressIndicator.adaptive()),
          ),
        };
      },
    );
  }
}

class _AudioCompletionWidget extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _AudioCompletionWidget({super.key, required this.controller});

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
    final exampleMessage = controller.getAudioExampleMessage();

    if (exampleMessage == null || exampleMessage.isEmpty) {
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
            ValueListenableBuilder<bool>(
              valueListenable: controller.hintPressedNotifier,
              builder: (context, showPhonetics, _) => AnimatedSize(
                duration: FluffyThemes.animationDuration,
                alignment: Alignment.topCenter,
                child: showPhonetics
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: PhoneticTranscriptionWidget(
                          text: exampleText,
                          pos: 'other',
                          textLanguage: MatrixState
                              .pangeaController
                              .userController
                              .userL2!,
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
              child: _AudioCompletionTranslation(controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget to show translation for audio completion message
class _AudioCompletionTranslation extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _AudioCompletionTranslation({required this.controller});

  @override
  Widget build(BuildContext context) {
    final state = controller.activityState.value;
    if (state is! AsyncLoaded<MultipleChoicePracticeActivityModel>) {
      return const SizedBox.shrink();
    }

    final activity = state.value;
    if (activity is! VocabAudioPracticeActivityModel) {
      return const SizedBox.shrink();
    }

    final translation = controller.getAudioTranslation(activity.eventId);
    if (translation == null) {
      return const SizedBox.shrink();
    }

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
