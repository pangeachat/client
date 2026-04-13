import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_choices_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_content_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_feedback_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_hint_section_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_hints_progress_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/pangea/analytics_practice/audio_analytics_practice_continue_button_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/insufficient_data_indicator.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

class OngoingAnalyticsPracticeSessionView extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const OngoingAnalyticsPracticeSessionView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final isColumnMode = FluffyThemes.isColumnMode(context);
    TextStyle? titleStyle = isColumnMode
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.titleMedium;
    titleStyle = titleStyle?.copyWith(fontWeight: FontWeight.bold);

    return ValueListenableBuilder(
      valueListenable: controller.practiceExerciseState,
      builder: (context, state, _) {
        final exercise = controller.practiceExercise;
        return Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  ListenableBuilder(
                    listenable: controller.notifier,
                    builder: (context, _) {
                      final enabled =
                          exercise != null &&
                          !controller.notifier.exerciseComplete(exercise);

                      return Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: Icon(Icons.flag_outlined),
                          onPressed: enabled
                              ? () => controller.flagExercise(exercise)
                              : null,
                        ),
                      );
                    },
                  ),
                  //Hints counter bar for grammar activities only
                  if (controller.widget.type == ConstructTypeEnum.morph)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: AnalyticsPracticeExerciseHintsProgress(
                        hintsUsed: controller.session.hintsUsed,
                      ),
                    ),
                  //per-exercise instructions, add switch statement once there are more types
                  if (exercise is VocabMeaningPracticeExerciseModel)
                    const InstructionsInlineTooltip(
                      instructionsEnum: InstructionsEnum.selectMeaning,
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                    ),
                  SizedBox(
                    height: 75.0,
                    child: Builder(
                      builder: (context) {
                        if (exercise == null) {
                          return const SizedBox.shrink();
                        }

                        final isAudioExercise =
                            exercise.exerciseType ==
                            PracticeExerciseTypeEnum.lemmaAudio;
                        final isVocabType =
                            controller.widget.type == ConstructTypeEnum.vocab;

                        final token = exercise.tokens.first;

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isAudioExercise && isVocabType
                                  ? L10n.of(context).selectAllWords
                                  : exercise.practiceTarget.promptText(context),
                              textAlign: TextAlign.center,
                              style: titleStyle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (isVocabType && !isAudioExercise)
                              PhoneticTranscriptionWidget(
                                text: token.vocabConstructID.lemma,
                                pos: token.pos,
                                morph: token.morph.map(
                                  (k, v) => MapEntry(k.name, v),
                                ),
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
                  ListenableBuilder(
                    listenable: controller.notifier,
                    builder: (context, _) {
                      final selectedMorphChoice = controller.notifier
                          .selectedMorphChoice(exercise);
                      return Column(
                        children: [
                          if (exercise != null)
                            Center(
                              child: AnalyticsPracticeExerciseContent(
                                analyticsPracticeExercise: exercise,
                                showHint: controller.notifier.showHint,
                                exampleMessage: controller.exampleMessage,
                                audioFile: controller.data.getAudioFile(
                                  exercise,
                                ),
                                playbackSpeedController:
                                    controller.audioPlaybackSpeedController,
                              ),
                            ),
                          if (exercise != null)
                            AnalyticsPracticeExerciseHintSection(
                              analyticsPracticeExercise: exercise,
                              onPressed: controller.onHintPressed,
                              hintPressed: controller.notifier.showHint,
                              enabled: controller.notifier.enableHintPress(
                                exercise,
                                controller.session.hintsUsed,
                              ),
                            ),
                          switch (state) {
                            AsyncError(error: final error) =>
                              error is InsufficientDataException
                                  ? InsufficientDataIndicator()
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        //allow try to reload exercise in case of error
                                        ErrorIndicator(
                                          message: error.toLocalizedString(
                                            context,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        TextButton.icon(
                                          onPressed: controller.startSession,
                                          icon: const Icon(Icons.refresh),
                                          label: Text(
                                            L10n.of(context).tryAgain,
                                          ),
                                        ),
                                      ],
                                    ),
                            AsyncLoaded(value: final exercise) => Builder(
                              builder: (context) {
                                List<InlineSpan>? audioExampleMessage;
                                String? audioTranslation;

                                if (exercise
                                    is VocabAudioPracticeExerciseModel) {
                                  audioExampleMessage =
                                      exercise.exampleMessage.exampleMessage;
                                  audioTranslation = controller.data
                                      .getAudioTranslation(exercise);
                                }

                                return AnalyticsPracticeExerciseChoices(
                                  analyticsPracticeExercise: exercise,
                                  choices: controller.data.filteredChoices(
                                    exercise,
                                    controller.widget.type,
                                  ),
                                  type: controller.widget.type,
                                  isComplete: controller.notifier
                                      .exerciseComplete(exercise),
                                  showHint: controller.notifier.showHint,
                                  onSelectChoice: controller.onSelectChoice,
                                  audioExampleMessage: audioExampleMessage,
                                  audioTranslation: audioTranslation,
                                );
                              },
                            ),
                            _ => Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator.adaptive(),
                              ),
                            ),
                          },
                          const SizedBox(height: 16.0),
                          if (exercise != null && selectedMorphChoice != null)
                            AnalyticsPracticeExerciseFeedback(
                              analyticsPracticeExercise: exercise,
                              selectedChoice: selectedMorphChoice,
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            if (exercise is VocabAudioPracticeExerciseModel)
              ListenableBuilder(
                listenable: controller.notifier,
                builder: (context, _) => Container(
                  alignment: Alignment.bottomCenter,
                  child: AudioContinueButton(
                    analyticsPracticeExercise: exercise,
                    onContinue: controller.startNextExercise,
                    exerciseComplete: controller.notifier.exerciseComplete(
                      exercise,
                    ),
                    correctAnswers: controller.notifier.correctAnswersSelected(
                      exercise,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
