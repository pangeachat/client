import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/pangea/analytics_summary/progress_indicators_enum.dart';
import '../../bot/utils/bot_style.dart';
import '../../common/utils/error_handler.dart';
import '../controllers/it_controller.dart';
import 'choice_array.dart';

class TranslationFeedback extends StatelessWidget {
  final ITController controller;
  const TranslationFeedback({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    try {
      final int vocabCount = controller.choreographer.altTranslator
          .countVocabularyWordsFromSteps();
      final int grammarCount = controller.choreographer.altTranslator
          .countGrammarConstructsFromSteps();
      final feedbackText =
          controller.choreographer.altTranslator.getDefaultFeedback(context);

      return ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 150,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (controller
                  .choreographer.altTranslator.showTranslationFeedback)
                Column(
                  children: [
                    // Star rating
                    SizedBox(
                      height: 40,
                      child: controller.choreographer.altTranslator
                          .buildStarRating(context),
                    ),
                    const SizedBox(height: 8),

                    if (vocabCount > 0 || grammarCount > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (vocabCount > 0) ...[
                            Icon(
                              Symbols.dictionary,
                              color: ProgressIndicatorEnum.wordsUsed
                                  .color(context),
                              size: 24,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "+$vocabCount",
                              style: TextStyle(
                                color: ProgressIndicatorEnum.wordsUsed
                                    .color(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                          if (vocabCount > 0 && grammarCount > 0)
                            const SizedBox(width: 16),
                          if (grammarCount > 0) ...[
                            Icon(
                              Symbols.toys_and_games,
                              color: ProgressIndicatorEnum.morphsUsed
                                  .color(context),
                              size: 24,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "+$grammarCount",
                              style: TextStyle(
                                color: ProgressIndicatorEnum.morphsUsed
                                    .color(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Text(
                          feedbackText,
                          textAlign: TextAlign.center,
                          style: BotStyle.text(context),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 6),
              if (controller
                  .choreographer.altTranslator.showAlternativeTranslations)
                AlternativeTranslations(controller: controller),
            ],
          ),
        ),
      );
    } catch (err, stack) {
      debugPrint("Error in TranslationFeedback: $err");
      ErrorHandler.logError(
        e: err,
        s: stack,
        data: {},
      );

      // Fallback to a simple message if anything goes wrong
      return const Center(child: Text("Nice job!"));
    }
  }
}

class AlternativeTranslations extends StatelessWidget {
  const AlternativeTranslations({
    super.key,
    required this.controller,
  });

  final ITController controller;

  @override
  Widget build(BuildContext context) {
    return ChoicesArray(
      originalSpan: controller.sourceText ?? "dummy",
      isLoading:
          controller.choreographer.altTranslator.loadingAlternativeTranslations,
      // choices: controller.choreographer.altTranslator.similarityResponse.scores
      choices: [
        Choice(text: controller.choreographer.altTranslator.translations.first),
      ],
      // choices: controller.choreographer.altTranslator.translations,
      onPressed: (String value, int index) {
        controller.choreographer.onSelectAlternativeTranslation(
          controller.choreographer.altTranslator.translations[index],
        );
      },
      selectedChoiceIndex: null,
      tts: null,
    );
  }
}
