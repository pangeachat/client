import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/vocab_practice/choice_cards/audio_choice_card.dart';
import 'package:fluffychat/pangea/vocab_practice/choice_cards/game_choice_card.dart';
import 'package:fluffychat/pangea/vocab_practice/choice_cards/meaning_choice_card.dart';
import 'package:fluffychat/pangea/vocab_practice/completed_activity_session_view.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_page.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_model.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_timer_widget.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';

class VocabPracticeView extends StatelessWidget {
  final VocabPracticeState controller;

  const VocabPracticeView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          spacing: 8.0,
          children: [
            Expanded(
              child: AnimatedProgressBar(
                height: 20.0,
                widthPercent: controller.progress,
                barColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            //keep track of state to update timer
            ValueListenableBuilder(
              valueListenable: controller.sessionLoader.state,
              builder: (context, state, __) {
                if (state is AsyncLoaded<VocabPracticeSessionModel>) {
                  return VocabTimerWidget(
                    key: ValueKey(state.value.startedAt),
                    initialSeconds: state.value.elapsedSeconds,
                    onTimeUpdate: controller.updateElapsedTime,
                    isRunning: !controller.isComplete,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
      body: MaxWidthBody(
        withScrolling: false,
        padding: const EdgeInsets.all(0.0),
        showBorder: false,
        child: controller.isComplete
            ? CompletedActivitySessionView(controller)
            : _OngoingActivitySessionView(controller),
      ),
    );
  }
}

class _OngoingActivitySessionView extends StatelessWidget {
  final VocabPracticeState controller;
  const _OngoingActivitySessionView(this.controller);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.sessionLoader.state,
      builder: (context, state, __) {
        return switch (state) {
          AsyncError<VocabPracticeSessionModel>(:final error) =>
            ErrorIndicator(message: error.toString()),
          AsyncLoaded<VocabPracticeSessionModel>(:final value) =>
            value.currentConstructId != null &&
                    value.currentActivityType != null
                ? _VocabActivityView(
                    value.currentConstructId!,
                    value.currentActivityType!,
                    controller,
                  )
                : const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  ),
          _ => const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
        };
      },
    );
  }
}

class _VocabActivityView extends StatelessWidget {
  final ConstructIdentifier constructId;
  final ActivityTypeEnum activityType;
  final VocabPracticeState controller;

  const _VocabActivityView(
    this.constructId,
    this.activityType,
    this.controller,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        //per-activity instructions, add switch statement once there are more types
        const InstructionsInlineTooltip(
          instructionsEnum: InstructionsEnum.selectMeaning,
          padding: EdgeInsets.symmetric(horizontal: 16.0),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  constructId.lemma,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              _ExampleMessageWidget(controller, constructId),
              Flexible(
                child: _ActivityChoicesWidget(
                  controller,
                  activityType,
                  constructId,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExampleMessageWidget extends StatelessWidget {
  final VocabPracticeState controller;
  final ConstructIdentifier constructId;

  const _ExampleMessageWidget(this.controller, this.constructId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InlineSpan>?>(
      future: controller.getExampleMessage(constructId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox();
        }

        return Padding(
          //styling like sent message bubble
          padding: const EdgeInsets.all(16.0),
          child: Container(
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
                  fontSize:
                      AppConfig.fontSizeFactor * AppConfig.messageFontSize,
                ),
                children: snapshot.data!,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActivityChoicesWidget extends StatelessWidget {
  final VocabPracticeState controller;
  final ActivityTypeEnum activityType;
  final ConstructIdentifier constructId;

  const _ActivityChoicesWidget(
    this.controller,
    this.activityType,
    this.constructId,
  );

  @override
  Widget build(BuildContext context) {
    if (controller.activityError != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          //allow try to reload activity in case of error
          ErrorIndicator(message: controller.activityError!),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: controller.loadActivity,
            icon: const Icon(Icons.refresh),
            label: Text(L10n.of(context).tryAgain),
          ),
        ],
      );
    }

    final activity = controller.currentActivity;
    if (controller.isLoadingActivity ||
        activity == null ||
        (activity.activityType == ActivityTypeEnum.lemmaMeaning &&
            controller.isLoadingLemmaInfo)) {
      return Container(
        constraints: const BoxConstraints(maxHeight: 400.0),
        child: const Center(
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }

    final choices = activity.multipleChoiceContent!.choices.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        //Constrain max height to keep choices together on large screens, and allow shrinking to fit on smaller screens
        final constrainedHeight = constraints.maxHeight.clamp(0.0, 400.0);
        final cardHeight =
            (constrainedHeight / (choices.length + 1)).clamp(50.0, 80.0);

        return Container(
          constraints: const BoxConstraints(maxHeight: 400.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: choices.map((choiceId) {
                final bool isEnabled = !controller.isAwaitingNextActivity;
                return _buildChoiceCard(
                  activity: activity,
                  choiceId: choiceId,
                  cardHeight: cardHeight,
                  isEnabled: isEnabled,
                  onPressed: () =>
                      controller.onSelectChoice(constructId, choiceId),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChoiceCard({
    required activity,
    required String choiceId,
    required double cardHeight,
    required bool isEnabled,
    required VoidCallback onPressed,
  }) {
    final isCorrect = activity.multipleChoiceContent!.isCorrect(choiceId);

    switch (activity.activityType) {
      case ActivityTypeEnum.lemmaMeaning:
        return MeaningChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_meaning_$choiceId',
          ),
          choiceId: choiceId,
          displayText: controller.getChoiceText(choiceId),
          emoji: controller.getChoiceEmoji(choiceId),
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: isEnabled,
        );

      case ActivityTypeEnum.lemmaAudio:
        return AudioChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_audio_$choiceId',
          ),
          text: choiceId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: isEnabled,
        );

      default:
        return GameChoiceCard(
          key: ValueKey(
            '${constructId.string}_${activityType.name}_basic_$choiceId',
          ),
          shouldFlip: false,
          transformId: choiceId,
          onPressed: onPressed,
          isCorrect: isCorrect,
          height: cardHeight,
          isEnabled: isEnabled,
          child: Text(controller.getChoiceText(choiceId)),
        );
    }
  }
}
