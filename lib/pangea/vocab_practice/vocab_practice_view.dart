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
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator.adaptive(),
                  ),
          _ => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator.adaptive(),
            )
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(32.0, 16.0, 32.0, 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            activityType == ActivityTypeEnum.lemmaMeaning
                ? L10n.of(context).selectMeaning
                : L10n.of(context).selectAudio,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.titleLarge!.fontSize!,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    constructId.lemma,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize:
                          Theme.of(context).textTheme.titleLarge!.fontSize! *
                              1.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FutureBuilder<List<InlineSpan>?>(
                  future: controller.getExampleMessage(constructId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data == null) {
                      return const SizedBox();
                    }

                    return Align(
                      alignment: Alignment.center,
                      child: Padding(
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
                            borderRadius: const BorderRadius.all(
                              Radius.circular(16),
                            ),
                          ),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryFixed,
                                fontSize: AppConfig.fontSizeFactor *
                                    AppConfig.messageFontSize,
                              ),
                              children: snapshot.data!,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    if (controller.activityError != null) {
                      return ErrorIndicator(
                        message: controller.activityError!,
                      );
                    }

                    final activity = controller.currentActivity;

                    if (controller.isLoadingActivity || activity == null) {
                      return const ChoiceCardPlaceholder();
                    }

                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...activity.multipleChoiceContent!.choices.map(
                            (c) => _VocabPracticeChoiceButton(
                              activity: activity,
                              choice: c,
                              onPressed: () {
                                controller.onSelectChoice(c);
                              },
                              type: activity.activityType,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VocabPracticeChoiceButton extends StatelessWidget {
  final PracticeActivityModel activity;
  final String choice;
  final VoidCallback onPressed;
  final ActivityTypeEnum type;

  const _VocabPracticeChoiceButton({
    required this.activity,
    required this.choice,
    required this.onPressed,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    if (type == ActivityTypeEnum.lemmaAudio) {
      return Row(
        spacing: 8.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          WordAudioButton(
            text: choice,
            uniqueID: "vocab_practice_choice_$choice",
            langCode:
                MatrixState.pangeaController.userController.userL2!.langCode,
          ),
          TextButton(
            onPressed: onPressed,
            child: Text(L10n.of(context).select),
          ),
        ],
      );
    }

    final String transformTargetId =
        'vocab-choice-card-${choice.replaceAll(' ', '_')}';
    return CompositedTransformTarget(
      link: MatrixState.pAnyState.layerLinkAndKey(transformTargetId).link,
      child: AnimatedChoiceCard(
        key: ValueKey(choice), //prevents flipped card persistence
        choice: choice,
        onPressed: onPressed,
        isCorrect: activity.multipleChoiceContent!.isCorrect(choice),
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
