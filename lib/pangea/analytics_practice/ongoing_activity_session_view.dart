import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_choices_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_content_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_feedback_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_hint_section_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_hints_progress_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/analytics_practice/audio_activity_continue_button_widget.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class OngoingActivitySessionView extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const OngoingActivitySessionView(this.controller, {super.key});

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
                  child: ActivityHintsProgress(controller: controller),
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

                    final token = target.target.tokens.first;

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
              const SizedBox(height: 16.0),
              Center(child: ActivityContent(controller: controller)),
              const SizedBox(height: 16.0),
              ValueListenableBuilder(
                valueListenable: controller.activityTarget,
                builder: (context, target, _) =>
                    (controller.widget.type == ConstructTypeEnum.morph ||
                        target?.target.activityType ==
                            ActivityTypeEnum.lemmaAudio)
                    ? Center(child: ActivityHintSection(controller: controller))
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 16.0),
              ActivityChoices(controller),
              const SizedBox(height: 16.0),
              ActivityFeedback(controller: controller),
            ],
          ),
        ),
        Container(
          alignment: Alignment.bottomCenter,
          child: AudioContinueButton(controller: controller),
        ),
      ],
    );
  }
}
