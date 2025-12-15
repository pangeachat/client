import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_summary/progress_bar/animated_progress_bar.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/common/widgets/word_audio_button.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/vocab_practice/animated_choice_card.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_page.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_model.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

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
              ),
            ),
            Text(
              "${controller.completedActivities} / ${controller.availableActivities}",
            ),
          ],
        ),
      ),
      body: MaxWidthBody(
        withScrolling: false,
        padding: const EdgeInsets.all(0.0),
        showBorder: false,
        child: controller.isComplete
            ? _CompletedActivitySessionView(controller)
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
        Text(
          activityType == ActivityTypeEnum.lemmaMeaning
              ? L10n.of(context).selectMeaning
              : L10n.of(context).selectAudio,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
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
                child: _ActivityChoicesWidget(controller, activityType),
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

  const _ActivityChoicesWidget(this.controller, this.activityType);

  @override
  Widget build(BuildContext context) {
    if (controller.activityError != null) {
      return ErrorIndicator(message: controller.activityError!);
    }

    final activity = controller.currentActivity;
    if (controller.isLoadingActivity || activity == null) {
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
        //Constrain the maximum height to prevent excessive spacing
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
              children: choices
                  .map(
                    (choice) => _VocabPracticeChoiceButton(
                      activity: activity,
                      choice: choice,
                      onPressed: () => controller.onSelectChoice(choice),
                      type: activity.activityType,
                      cardHeight: cardHeight,
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class _VocabPracticeChoiceButton extends StatelessWidget {
  final PracticeActivityModel activity;
  final String choice;
  final VoidCallback onPressed;
  final ActivityTypeEnum type;
  final double cardHeight;

  const _VocabPracticeChoiceButton({
    required this.activity,
    required this.choice,
    required this.onPressed,
    required this.type,
    this.cardHeight = 72.0,
  });

  @override
  Widget build(BuildContext context) {
    final transformTargetId =
        'vocab-choice-card-${choice.replaceAll(' ', '_')}';

    return CompositedTransformTarget(
      link: MatrixState.pAnyState.layerLinkAndKey(transformTargetId).link,
      child: type == ActivityTypeEnum.lemmaAudio
          ? _AudioChoiceWidget(
              choice: choice,
              onPressed: onPressed,
              cardHeight: cardHeight,
            )
          : AnimatedChoiceCard(
              key: ValueKey(choice),
              choice: choice,
              onPressed: onPressed,
              isCorrect: activity.multipleChoiceContent!.isCorrect(choice),
              height: cardHeight,
            ),
    );
  }
}

class _AudioChoiceWidget extends StatelessWidget {
  final String choice;
  final VoidCallback onPressed;
  final double cardHeight;

  const _AudioChoiceWidget({
    required this.choice,
    required this.onPressed,
    required this.cardHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: cardHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: WordAudioButton(
              text: choice,
              uniqueID: "vocab_practice_choice_$choice",
              langCode:
                  MatrixState.pangeaController.userController.userL2!.langCode,
            ),
          ),
          TextButton(
            onPressed: onPressed,
            child: Text(L10n.of(context).select),
          ),
        ],
      ),
    );
  }
}

class _CompletedActivitySessionView extends StatelessWidget {
  final VocabPracticeState controller;
  const _CompletedActivitySessionView(this.controller);

  @override
  Widget build(BuildContext context) {
    if (controller.isFinished) {
      return Center(child: Text(L10n.of(context).allDone));
    }

    return Column(
      spacing: 8.0,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(L10n.of(context).congratulations),
        Text(L10n.of(context).yourResult),
        TextButton(
          onPressed: controller.completeActivitySession,
          child: Text(L10n.of(context).addXP),
        ),
        if (controller.canContinueSession)
          TextButton(
            onPressed: controller.continueSession,
            child: Text(L10n.of(context).anotherRound),
          ),
      ],
    );
  }
}

class ChoiceCardPlaceholder extends StatelessWidget {
  final int cardCount;
  const ChoiceCardPlaceholder({super.key, this.cardCount = 3});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double cardHeight = 60;
    const double borderRadius = 16.0;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          cardCount,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Shimmer.fromColors(
              baseColor: theme.colorScheme.primary.withAlpha(20),
              highlightColor: theme.colorScheme.primary.withAlpha(50),
              child: SizedBox(
                width: double.infinity,
                height: cardHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
