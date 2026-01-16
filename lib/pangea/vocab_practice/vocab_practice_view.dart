import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/vocab_practice/choice_cards/audio_choice_card.dart';
import 'package:fluffychat/pangea/vocab_practice/choice_cards/game_choice_card.dart';
import 'package:fluffychat/pangea/vocab_practice/choice_cards/meaning_choice_card.dart';
import 'package:fluffychat/pangea/vocab_practice/completed_activity_session_view.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_page.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_model.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_timer_widget.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class VocabPracticeView extends StatelessWidget {
  final VocabPracticeState controller;

  const VocabPracticeView(this.controller, {super.key});

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
                if (state is AsyncLoaded<VocabPracticeSessionModel>) {
                  return VocabTimerWidget(
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
          horizontal: 16.0,
          vertical: 24.0,
        ),
        child: MaxWidthBody(
          withScrolling: false,
          showBorder: false,
          child: ValueListenableBuilder(
            valueListenable: controller.sessionState,
            builder: (context, state, __) {
              return switch (state) {
                AsyncError<VocabPracticeSessionModel>(:final error) =>
                  ErrorIndicator(message: error.toString()),
                AsyncLoaded<VocabPracticeSessionModel>(:final value) =>
                  value.isComplete
                      ? CompletedActivitySessionView(state.value, controller)
                      : _VocabActivityView(controller),
                _ => loading,
              };
            },
          ),
        ),
      ),
    );
  }
}

class _VocabActivityView extends StatelessWidget {
  final VocabPracticeState controller;

  const _VocabActivityView(
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
            spacing: 16.0,
            children: [
              Expanded(
                flex: 1,
                child: ValueListenableBuilder(
                  valueListenable: controller.activityConstructId,
                  builder: (context, constructId, __) => constructId != null
                      ? Column(
                          spacing: 12.0,
                          children: [
                            Text(
                              constructId.lemma,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            PhoneticTranscriptionWidget(
                              text: constructId.lemma,
                              textLanguage: MatrixState
                                  .pangeaController.userController.userL2!,
                              style: const TextStyle(fontSize: 14.0),
                            ),
                          ],
                        )
                      : const SizedBox(),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: ValueListenableBuilder(
                    valueListenable: controller.activityConstructId,
                    builder: (context, constructId, __) => constructId != null
                        ? _ExampleMessageWidget(
                            controller.getExampleMessage(constructId),
                          )
                        : const SizedBox(),
                  ),
                ),
              ),
              Expanded(
                flex: 6,
                child: _ActivityChoicesWidget(controller),
              ),
            ],
          ),
        ),
      ],
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

class _ActivityChoicesWidget extends StatelessWidget {
  final VocabPracticeState controller;

  const _ActivityChoicesWidget(
    this.controller,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.activityState,
      builder: (context, state, __) {
        return switch (state) {
          AsyncLoading<PracticeActivityModel>() => const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
          AsyncError<PracticeActivityModel>(:final error) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                //allow try to reload activity in case of error
                ErrorIndicator(message: error.toString()),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: controller.reloadSession,
                  icon: const Icon(Icons.refresh),
                  label: Text(L10n.of(context).tryAgain),
                ),
              ],
            ),
          AsyncLoaded<PracticeActivityModel>(:final value) => LayoutBuilder(
              builder: (context, constraints) {
                final choices = controller.filteredChoices(
                  value.practiceTarget,
                  value.multipleChoiceContent!,
                );
                final constrainedHeight =
                    constraints.maxHeight.clamp(0.0, 400.0);
                final cardHeight = (constrainedHeight / (choices.length + 1))
                    .clamp(50.0, 80.0);

                return Container(
                  constraints: const BoxConstraints(maxHeight: 400.0),
                  child: Column(
                    spacing: 4.0,
                    mainAxisSize: MainAxisSize.min,
                    children: choices
                        .map(
                          (choice) => _ChoiceCard(
                            activity: value,
                            targetId:
                                controller.choiceTargetId(choice.choiceId),
                            choiceId: choice.choiceId,
                            onPressed: () => controller.onSelectChoice(
                              value.targetTokens.first.vocabConstructID,
                              choice.choiceId,
                            ),
                            cardHeight: cardHeight,
                            choiceText: choice.choiceText,
                            choiceEmoji: choice.choiceEmoji,
                          ),
                        )
                        .toList(),
                  ),
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
  final PracticeActivityModel activity;
  final String choiceId;
  final String targetId;
  final VoidCallback onPressed;
  final double cardHeight;

  final String choiceText;
  final String? choiceEmoji;

  const _ChoiceCard({
    required this.activity,
    required this.choiceId,
    required this.targetId,
    required this.onPressed,
    required this.cardHeight,
    required this.choiceText,
    required this.choiceEmoji,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrect = activity.multipleChoiceContent!.isCorrect(choiceId);
    final activityType = activity.activityType;
    final constructId = activity.targetTokens.first.vocabConstructID;

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
          child: Text(choiceText),
        );
    }
  }
}
