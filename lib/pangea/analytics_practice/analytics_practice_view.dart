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
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

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
    return Column(
      children: [
        //per-activity instructions, add switch statement once there are more types
        const InstructionsInlineTooltip(
          instructionsEnum: InstructionsEnum.selectMeaning,
          padding: EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 24.0,
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ValueListenableBuilder(
                valueListenable: controller.activityTarget,
                builder: (context, target, __) => target != null
                    ? Padding(
                        padding: const EdgeInsets.only(
                          left: 16.0,
                          right: 16.0,
                          top: 16.0,
                        ),
                        child: Column(
                          spacing: 12.0,
                          children: [
                            Text(
                              target.promptText(context),
                              textAlign: TextAlign.center,
                              style: FluffyThemes.isColumnMode(context)
                                  ? Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      )
                                  : Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                            ),
                            if (controller.widget.type ==
                                ConstructTypeEnum.vocab)
                              PhoneticTranscriptionWidget(
                                text: target
                                    .target.tokens.first.vocabConstructID.lemma,
                                textLanguage: MatrixState
                                    .pangeaController.userController.userL2!,
                                style: const TextStyle(fontSize: 14.0),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: _AnalyticsPracticeCenterContent(
                    controller: controller,
                  ),
                ),
              ),
              Expanded(
                child: _ActivityChoicesWidget(controller),
              ),
              //reserve space for grammar category morph meaning to avoid shifting, but only in those questions
              AnimatedBuilder(
                animation: Listenable.merge([
                  controller.activityState,
                  controller.selectedMorphChoice,
                ]),
                builder: (context, _) {
                  final activityState = controller.activityState.value;
                  final selectedChoice = controller.selectedMorphChoice.value;

                  final isGrammarCategory = activityState
                          is AsyncLoaded<MultipleChoicePracticeActivityModel> &&
                      activityState.value.activityType ==
                          ActivityTypeEnum.grammarCategory;

                  if (!isGrammarCategory) {
                    return const SizedBox.shrink();
                  }

                  return ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 80,
                    ),
                    child: selectedChoice == null
                        ? const SizedBox.shrink()
                        : SingleChildScrollView(
                            child: MorphMeaningWidget(
                              feature: selectedChoice.feature,
                              tag: selectedChoice.tag,
                              blankErrorFeedback: true,
                            ),
                          ),
                  );
                },
              ),
            ],
          ),
        ),
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
        ActivityTypeEnum.grammarError => ValueListenableBuilder(
            valueListenable: controller.activityState,
            builder: (context, state, __) => switch (state) {
              AsyncLoaded(
                value: final GrammarErrorPracticeActivityModel activity
              ) =>
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ErrorBlankWidget(
                      activity: activity,
                    ),
                    const SizedBox(height: 12),
                    _GrammarErrorTranslationButton(
                      key: ValueKey(
                        '${activity.eventID}_${activity.errorOffset}_${activity.errorLength}',
                      ),
                      controller: controller,
                    ),
                  ],
                ),
              _ => const SizedBox(),
            },
          ),
        _ => _ExampleMessageWidget(
            controller.getExampleMessage(target!.target),
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

class _ErrorBlankWidget extends StatelessWidget {
  final GrammarErrorPracticeActivityModel activity;

  const _ErrorBlankWidget({
    required this.activity,
  });

  @override
  Widget build(BuildContext context) {
    final text = activity.text;
    final errorOffset = activity.errorOffset;
    final errorLength = activity.errorLength;

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
          children: [
            if (errorOffset > 0)
              TextSpan(text: text.characters.take(errorOffset).toString()),
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
            if (errorOffset + errorLength < text.length)
              TextSpan(
                text:
                    text.characters.skip(errorOffset + errorLength).toString(),
              ),
          ],
        ),
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
            LayoutBuilder(
              builder: (context, constraints) {
                final choices = controller.filteredChoices(value);
                final constrainedHeight =
                    constraints.maxHeight.clamp(0.0, 400.0);
                final cardHeight = (constrainedHeight / (choices.length + 1))
                    .clamp(50.0, 80.0);

                return Column(
                  children: [
                    Expanded(
                      child: Column(
                        spacing: 4.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: choices
                            .map(
                              (choice) => _ChoiceCard(
                                activity: value,
                                targetId:
                                    controller.choiceTargetId(choice.choiceId),
                                choiceId: choice.choiceId,
                                onPressed: () => controller.onSelectChoice(
                                  choice.choiceId,
                                ),
                                cardHeight: cardHeight,
                                choiceText: choice.choiceText,
                                choiceEmoji: choice.choiceEmoji,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
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

class _GrammarErrorTranslationButton extends StatefulWidget {
  final AnalyticsPracticeState controller;

  const _GrammarErrorTranslationButton({
    super.key,
    required this.controller,
  });

  @override
  State<_GrammarErrorTranslationButton> createState() =>
      _GrammarErrorTranslationButtonState();
}

class _GrammarErrorTranslationButtonState
    extends State<_GrammarErrorTranslationButton> {
  Future<String>? _translationFuture;
  bool _showTranslation = false;

  void _toggleTranslation() {
    if (_showTranslation) {
      setState(() {
        _showTranslation = false;
        _translationFuture = null;
      });
    } else {
      setState(() {
        _showTranslation = true;
        _translationFuture = widget.controller.requestTranslation();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: _toggleTranslation,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8.0,
          children: [
            if (_showTranslation)
              Flexible(
                child: FutureBuilder<String>(
                  future: _translationFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
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
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
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
                        child: Text(
                          L10n.of(context).oopsSomethingWentWrong,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryFixed,
                            fontSize: AppConfig.fontSizeFactor *
                                AppConfig.messageFontSize,
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasData) {
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
                        child: Text(
                          snapshot.data!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryFixed,
                            fontSize: AppConfig.fontSizeFactor *
                                AppConfig.messageFontSize,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    return const SizedBox();
                  },
                ),
              ),
            if (!_showTranslation)
              ElevatedButton(
                onPressed: _toggleTranslation,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(8),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
