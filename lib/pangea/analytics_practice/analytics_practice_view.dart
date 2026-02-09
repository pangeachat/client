import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/audio_player.dart';
import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/game_choice_card.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/grammar_choice_card.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/meaning_choice_card.dart';
import 'package:fluffychat/pangea/analytics_practice/completed_activity_session_view.dart';
import 'package:fluffychat/pangea/analytics_practice/practice_timer_widget.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsPracticeView extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const AnalyticsPracticeView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    const loading = Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator.adaptive(),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Row(
          spacing: 8.0,
          children: [
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: controller.progressNotifier,
                builder: (context, progress, _) {
                  return AnimatedProgressBar(
                    height: 20.0,
                    widthPercent: progress,
                    barColor: Theme.of(context).colorScheme.primary,
                  );
                },
              ),
            ),
            //keep track of state to update timer
            ValueListenableBuilder(
              valueListenable: controller.sessionState,
              builder: (context, state, _) {
                if (state is AsyncLoaded<AnalyticsPracticeSessionModel>) {
                  return PracticeTimerWidget(
                    key: ValueKey(state.value.startedAt),
                    initialSeconds: state.value.state.elapsedSeconds,
                    onTimeUpdate: controller.updateElapsedTime,
                    isRunning: !state.value.isComplete,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: MaxWidthBody(
          withScrolling: false,
          showBorder: false,
          child: ValueListenableBuilder(
            valueListenable: controller.sessionState,
            builder: (context, state, _) {
              return switch (state) {
                AsyncError<AnalyticsPracticeSessionModel>(:final error) =>
                  ErrorIndicator(message: error.toLocalizedString(context)),
                AsyncLoaded<AnalyticsPracticeSessionModel>(:final value) =>
                  value.isComplete
                      ? CompletedActivitySessionView(state.value, controller)
                      : _AnalyticsActivityView(controller),
                _ => loading,
              };
            },
          ),
        ),
      ),
    );
  }
}

class _AnalyticsActivityView extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _AnalyticsActivityView(this.controller);

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    TextStyle? titleStyle = isColumnMode
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.titleMedium;
    titleStyle = titleStyle?.copyWith(fontWeight: FontWeight.bold);

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              //Hints counter bar for grammar activities only
              if (controller.widget.type == ConstructTypeEnum.morph)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _HintsCounterBar(controller: controller),
                ),
              //per-activity instructions, add switch statement once there are more types
              const InstructionsInlineTooltip(
                instructionsEnum: InstructionsEnum.selectMeaning,
                padding: EdgeInsets.symmetric(vertical: 8.0),
              ),
              SizedBox(
                height: 75.0,
                child: ValueListenableBuilder(
                  valueListenable: controller.activityTarget,
                  builder: (context, target, _) {
                    if (target == null) return const SizedBox.shrink();

                    final isAudioActivity =
                        target.target.activityType ==
                        ActivityTypeEnum.lemmaAudio;
                    final isVocabType =
                        controller.widget.type == ConstructTypeEnum.vocab;

                    return Column(
                      children: [
                        Text(
                          isAudioActivity && isVocabType
                              ? L10n.of(context).selectAllWords
                              : target.promptText(context),
                          textAlign: TextAlign.center,
                          style: titleStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isVocabType && !isAudioActivity)
                          PhoneticTranscriptionWidget(
                            text: target
                                .target
                                .tokens
                                .first
                                .vocabConstructID
                                .lemma,
                            textLanguage: MatrixState
                                .pangeaController
                                .userController
                                .userL2!,
                            style: const TextStyle(fontSize: 14.0),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16.0),
              Center(
                child: _AnalyticsPracticeCenterContent(controller: controller),
              ),
              const SizedBox(height: 16.0),
              (controller.widget.type == ConstructTypeEnum.morph)
                  ? Center(child: _HintSection(controller: controller))
                  : const SizedBox.shrink(),
              const SizedBox(height: 16.0),
              _ActivityChoicesWidget(controller),
              const SizedBox(height: 16.0),
              _WrongAnswerFeedback(controller: controller),
            ],
          ),
        ),
        Container(
          alignment: Alignment.bottomCenter,
          child: _AudioContinueButton(controller: controller),
        ),
      ],
    );
  }
}

class _AnalyticsPracticeCenterContent extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _AnalyticsPracticeCenterContent({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.activityTarget,
      builder: (context, target, _) => switch (target?.target.activityType) {
        null => const SizedBox(),
        ActivityTypeEnum.grammarError => SingleChildScrollView(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              controller.activityState,
              controller.hintPressedNotifier,
            ]),
            builder: (context, _) {
              final state = controller.activityState.value;
              if (state is! AsyncLoaded<MultipleChoicePracticeActivityModel>) {
                return const SizedBox();
              }
              final activity = state.value;
              if (activity is! GrammarErrorPracticeActivityModel) {
                return const SizedBox();
              }
              return _ErrorBlankWidget(
                key: ValueKey(
                  '${activity.eventID}_${activity.errorOffset}_${activity.errorLength}',
                ),
                activity: activity,
                showTranslation: controller.hintPressedNotifier.value,
              );
            },
          ),
        ),
        ActivityTypeEnum.grammarCategory => Center(
          child: _ExampleMessageWidget(controller.getExampleMessage(target!)),
        ),
        ActivityTypeEnum.lemmaAudio => ValueListenableBuilder(
          valueListenable: controller.activityState,
          builder: (context, state, _) => switch (state) {
            AsyncLoaded(
              value: final VocabAudioPracticeActivityModel activity,
            ) =>
              SizedBox(
                height: 100.0,
                child: Center(
                  child: AudioPlayerWidget(
                    null,
                    color: Theme.of(context).colorScheme.primary,
                    linkColor: Theme.of(context).colorScheme.secondary,
                    fontSize:
                        AppSettings.fontSizeFactor.value *
                        AppConfig.messageFontSize,
                    eventId: '${activity.eventId}_practice',
                    roomId: activity.roomId!,
                    senderId: Matrix.of(context).client.userID!,
                    matrixFile: controller.getAudioFile(activity.eventId)!,
                    autoplay: true,
                  ),
                ),
              ),
            _ => const SizedBox(height: 100.0),
          },
        ),
        _ => SizedBox(
          height: 100.0,
          child: Center(
            child: _ExampleMessageWidget(controller.getExampleMessage(target!)),
          ),
        ),
      },
    );
  }
}

class _AudioCompletionWidget extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _AudioCompletionWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final exampleMessage = controller.getAudioExampleMessage();

    if (exampleMessage == null || exampleMessage.isEmpty) {
      return const SizedBox(height: 100.0);
    }

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
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryFixed,
              fontSize:
                  AppSettings.fontSizeFactor.value * AppConfig.messageFontSize,
            ),
            children: exampleMessage,
          ),
        ),
      ),
    );
  }
}

class _ExampleMessageWidget extends StatelessWidget {
  final Future<List<InlineSpan>?> future;

  const _ExampleMessageWidget(this.future);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InlineSpan>?>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              Colors.white.withAlpha(180),
              ThemeData.dark().colorScheme.primary,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryFixed,
                fontSize:
                    AppSettings.fontSizeFactor.value *
                    AppConfig.messageFontSize,
              ),
              children: snapshot.data!,
            ),
          ),
        );
      },
    );
  }
}

class _HintsCounterBar extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _HintsCounterBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.hintsUsedNotifier,
      builder: (context, hintsUsed, _) {
        return Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              AnalyticsPracticeState.maxHints,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Icon(
                  index < hintsUsed ? Icons.lightbulb : Icons.lightbulb_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HintSection extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _HintSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.activityState,
        controller.hintPressedNotifier,
        controller.hintsUsedNotifier,
      ]),
      builder: (context, _) {
        final state = controller.activityState.value;
        if (state is! AsyncLoaded<MultipleChoicePracticeActivityModel>) {
          return const SizedBox.shrink();
        }

        final activity = state.value;
        final hintPressed = controller.hintPressedNotifier.value;
        final hintsUsed = controller.hintsUsedNotifier.value;
        final maxHintsReached = hintsUsed >= AnalyticsPracticeState.maxHints;

        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50.0),
          child: Builder(
            builder: (context) {
              // For grammar category: fade out button and show hint content
              if (activity is MorphPracticeActivityModel) {
                return AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: hintPressed
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: HintButton(
                    onPressed: maxHintsReached
                        ? () {}
                        : controller.onHintPressed,
                    depressed: maxHintsReached,
                  ),
                  secondChild: MorphMeaningWidget(
                    feature: activity.morphFeature,
                    tag: activity.multipleChoiceContent.answers.first,
                  ),
                );
              }

              // For grammar error: button stays pressed, hint shows in ErrorBlankWidget
              return HintButton(
                onPressed: (hintPressed || maxHintsReached)
                    ? () {}
                    : controller.onHintPressed,
                depressed: hintPressed || maxHintsReached,
              );
            },
          ),
        );
      },
    );
  }
}

class _WrongAnswerFeedback extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _WrongAnswerFeedback({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.activityState,
        controller.selectedMorphChoice,
      ]),
      builder: (context, _) {
        final activityState = controller.activityState.value;
        final selectedChoice = controller.selectedMorphChoice.value;

        if (activityState
                is! AsyncLoaded<MultipleChoicePracticeActivityModel> ||
            selectedChoice == null) {
          return const SizedBox.shrink();
        }

        final activity = activityState.value;
        final isWrongAnswer = !activity.multipleChoiceContent.isCorrect(
          selectedChoice.tag,
        );

        if (!isWrongAnswer) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: MorphMeaningWidget(
            feature: selectedChoice.feature,
            tag: selectedChoice.tag,
            blankErrorFeedback: true,
          ),
        );
      },
    );
  }
}

class _ErrorBlankWidget extends StatelessWidget {
  final GrammarErrorPracticeActivityModel activity;
  final bool showTranslation;

  const _ErrorBlankWidget({
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

class HintButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool depressed;

  const HintButton({
    required this.onPressed,
    required this.depressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return PressableButton(
      borderRadius: BorderRadius.circular(20),
      color: Theme.of(context).colorScheme.primaryContainer,
      onPressed: onPressed,
      depressed: depressed,
      playSound: true,
      colorFactor: 0.3,
      builder: (context, depressed, shadowColor) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 40.0,
            width: 40.0,
            decoration: BoxDecoration(
              color: depressed
                  ? shadowColor
                  : Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
          ),
          const Icon(Icons.lightbulb_outline, size: 20),
        ],
      ),
    );
  }
}

class _ActivityChoicesWidget extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _ActivityChoicesWidget(this.controller);

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
                                        (choice) => _ChoiceCard(
                                          activity: value,
                                          targetId: controller.choiceTargetId(
                                            choice.choiceId,
                                          ),
                                          choiceId: choice.choiceId,
                                          onPressed: () => controller
                                              .onSelectChoice(choice.choiceId),
                                          cardHeight: 48.0,
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
                        (choice) => _ChoiceCard(
                          activity: value,
                          targetId: controller.choiceTargetId(choice.choiceId),
                          choiceId: choice.choiceId,
                          onPressed: () =>
                              controller.onSelectChoice(choice.choiceId),
                          cardHeight: 60.0,
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

class _AudioContinueButton extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _AudioContinueButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.activityState,
      builder: (context, state, _) {
        // Only show for audio activities
        if (state is! AsyncLoaded<MultipleChoicePracticeActivityModel>) {
          return const SizedBox.shrink();
        }

        final activity = state.value;
        if (activity.activityType != ActivityTypeEnum.lemmaAudio) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder(
          valueListenable: controller.showingAudioCompletion,
          builder: (context, showingCompletion, _) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: showingCompletion
                    ? controller.onAudioContinuePressed
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48.0,
                    vertical: 16.0,
                  ),
                ),
                child: Text(
                  L10n.of(context).continueText,
                  style: const TextStyle(fontSize: 18.0),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final MultipleChoicePracticeActivityModel activity;
  final String choiceId;
  final String targetId;
  final VoidCallback onPressed;
  final double cardHeight;

  final String choiceText;
  final String? choiceEmoji;
  final bool enabled;
  final bool shrinkWrap;

  const _ChoiceCard({
    required this.activity,
    required this.choiceId,
    required this.targetId,
    required this.onPressed,
    required this.cardHeight,
    required this.choiceText,
    required this.choiceEmoji,
    this.enabled = true,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrect = activity.multipleChoiceContent.isCorrect(choiceId);
    final activityType = activity.activityType;
    final constructId = activity.tokens.first.vocabConstructID;

    switch (activity.activityType) {
      case ActivityTypeEnum.lemmaMeaning:
        return MeaningChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_meaning_$choiceId',
          ),
          choiceId: choiceId,
          targetId: targetId,
          displayText: choiceText,
          emoji: choiceEmoji,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
        );

      case ActivityTypeEnum.lemmaAudio:
        return GameChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_audio_$choiceId',
          ),
          shouldFlip: false,
          targetId: targetId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
          shrinkWrap: shrinkWrap,
          child: Text(choiceText, textAlign: TextAlign.center),
        );

      case ActivityTypeEnum.grammarCategory:
        return GrammarChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_grammar_$choiceId',
          ),
          choiceId: choiceId,
          targetId: targetId,
          feature: (activity as MorphPracticeActivityModel).morphFeature,
          tag: choiceText,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          enabled: enabled,
        );

      case ActivityTypeEnum.grammarError:
        final activity = this.activity as GrammarErrorPracticeActivityModel;
        return GameChoiceCard(
          key: ValueKey(
            '${activity.errorLength}_${activity.errorOffset}_${activity.eventID}_${activityType.name}_grammar_error_$choiceId',
          ),
          shouldFlip: false,
          targetId: targetId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
          child: Text(choiceText),
        );

      default:
        return GameChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_basic_$choiceId',
          ),
          shouldFlip: false,
          targetId: targetId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
          child: Text(choiceText),
        );
    }
  }
}
