import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_details_popup/morph_meaning_widget.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/analytics_practice/choice_cards/audio_choice_card.dart';
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
                builder: (context, progress, __) {
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
              builder: (context, state, __) {
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
        padding: const EdgeInsets.symmetric(
          horizontal: 8.0,
        ),
        child: MaxWidthBody(
          withScrolling: false,
          showBorder: false,
          child: ValueListenableBuilder(
            valueListenable: controller.sessionState,
            builder: (context, state, __) {
              return switch (state) {
                AsyncError<AnalyticsPracticeSessionModel>(:final error) =>
                  ErrorIndicator(
                    message: error.toLocalizedString(context),
                  ),
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

  const _AnalyticsActivityView(
    this.controller,
  );

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    TextStyle? titleStyle = isColumnMode
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.titleMedium;
    titleStyle = titleStyle?.copyWith(fontWeight: FontWeight.bold);

    return ListView(
      children: [
        //per-activity instructions, add switch statement once there are more types
        const InstructionsInlineTooltip(
          instructionsEnum: InstructionsEnum.selectMeaning,
          padding: EdgeInsets.symmetric(
            vertical: 8.0,
          ),
        ),
        SizedBox(
          height: 75.0,
          child: ValueListenableBuilder(
            valueListenable: controller.activityTarget,
            builder: (context, target, __) => target != null
                ? Column(
                    children: [
                      Text(
                        target.promptText(context),
                        textAlign: TextAlign.center,
                        style: titleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (controller.widget.type == ConstructTypeEnum.vocab)
                        PhoneticTranscriptionWidget(
                          text:
                              target.target.tokens.first.vocabConstructID.lemma,
                          textLanguage: MatrixState
                              .pangeaController.userController.userL2!,
                          style: const TextStyle(fontSize: 14.0),
                        ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 16.0),
        Center(
          child: _AnalyticsPracticeCenterContent(controller: controller),
        ),
        const SizedBox(height: 16.0),
        _ActivityChoicesWidget(controller),
        const SizedBox(height: 16.0),
        _WrongAnswerFeedback(controller: controller),
      ],
    );
  }
}

class _AnalyticsPracticeCenterContent extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _AnalyticsPracticeCenterContent({
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.activityTarget,
      builder: (context, target, __) => switch (target?.target.activityType) {
        null => const SizedBox(),
        ActivityTypeEnum.grammarError => SizedBox(
            height: 160.0,
            child: SingleChildScrollView(
              child: ValueListenableBuilder(
                valueListenable: controller.activityState,
                builder: (context, state, __) => switch (state) {
                  AsyncLoaded(
                    value: final GrammarErrorPracticeActivityModel activity
                  ) =>
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ErrorBlankWidget(
                          key: ValueKey(
                            '${activity.eventID}_${activity.errorOffset}_${activity.errorLength}',
                          ),
                          activity: activity,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  _ => const SizedBox(),
                },
              ),
            ),
          ),
        ActivityTypeEnum.grammarCategory => Center(
            child: Column(
              children: [
                _CorrectAnswerHint(controller: controller),
                _ExampleMessageWidget(
                  controller.getExampleMessage(target!),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder(
                  valueListenable: controller.hintPressedNotifier,
                  builder: (context, hintPressed, __) {
                    return HintButton(
                      depressed: hintPressed,
                      onPressed: controller.onHintPressed,
                    );
                  },
                ),
              ],
            ),
          ),
        _ => SizedBox(
            height: 100.0,
            child: Center(
              child: _ExampleMessageWidget(
                controller.getExampleMessage(target!),
              ),
            ),
          ),
      },
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
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
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
                fontSize: AppConfig.fontSizeFactor * AppConfig.messageFontSize,
              ),
              children: snapshot.data!,
            ),
          ),
        );
      },
    );
  }
}

class _CorrectAnswerHint extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _CorrectAnswerHint({
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.hintPressedNotifier,
      builder: (context, hintPressed, __) {
        if (!hintPressed) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder(
          valueListenable: controller.activityState,
          builder: (context, state, __) {
            if (state is! AsyncLoaded<MultipleChoicePracticeActivityModel>) {
              return const SizedBox.shrink();
            }

            final activity = state.value;
            if (activity is! MorphPracticeActivityModel) {
              return const SizedBox.shrink();
            }

            final correctAnswerTag =
                activity.multipleChoiceContent.answers.first;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: MorphMeaningWidget(
                feature: activity.morphFeature,
                tag: correctAnswerTag,
              ),
            );
          },
        );
      },
    );
  }
}

class _WrongAnswerFeedback extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _WrongAnswerFeedback({
    required this.controller,
  });

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
        final isWrongAnswer =
            !activity.multipleChoiceContent.isCorrect(selectedChoice.tag);

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

class _ErrorBlankWidget extends StatefulWidget {
  final GrammarErrorPracticeActivityModel activity;

  const _ErrorBlankWidget({
    super.key,
    required this.activity,
  });

  @override
  State<_ErrorBlankWidget> createState() => _ErrorBlankWidgetState();
}

class _ErrorBlankWidgetState extends State<_ErrorBlankWidget> {
  late final String translation = widget.activity.translation;
  bool _showTranslation = false;

  void _toggleTranslation() {
    setState(() {
      _showTranslation = !_showTranslation;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.activity.text;
    final errorOffset = widget.activity.errorOffset;
    final errorLength = widget.activity.errorLength;

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

    final before =
        chars.skip(beforeStart).take(errorOffset - beforeStart).toString();

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

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              Colors.white.withAlpha(180),
              ThemeData.dark().colorScheme.primary,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryFixed,
                    fontSize:
                        AppConfig.fontSizeFactor * AppConfig.messageFontSize,
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
              const SizedBox(height: 8),
              _showTranslation
                  ? Text(
                      translation,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryFixed,
                        fontSize: AppConfig.fontSizeFactor *
                            AppConfig.messageFontSize,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.left,
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
        const SizedBox(height: 8),
        HintButton(depressed: _showTranslation, onPressed: _toggleTranslation),
      ],
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
          const Icon(
            Icons.lightbulb_outline,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _ActivityChoicesWidget extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const _ActivityChoicesWidget(
    this.controller,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.activityState,
      builder: (context, state, __) {
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
              builder: (context, enabled, __) {
                final choices = controller.filteredChoices(value);
                return Column(
                  spacing: 8.0,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: choices
                      .map(
                        (choice) => _ChoiceCard(
                          activity: value,
                          targetId: controller.choiceTargetId(choice.choiceId),
                          choiceId: choice.choiceId,
                          onPressed: () => controller.onSelectChoice(
                            choice.choiceId,
                          ),
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
              child: const Center(
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
        };
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

  const _ChoiceCard({
    required this.activity,
    required this.choiceId,
    required this.targetId,
    required this.onPressed,
    required this.cardHeight,
    required this.choiceText,
    required this.choiceEmoji,
    this.enabled = true,
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
        return AudioChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_audio_$choiceId',
          ),
          text: choiceId,
          targetId: targetId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: enabled,
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
