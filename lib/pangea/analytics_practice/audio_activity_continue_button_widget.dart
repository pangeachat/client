import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';

class AudioContinueButton extends StatelessWidget {
  final VocabAudioPracticeActivityModel activity;

  final bool activityComplete;
  final int correctAnswers;

  final VoidCallback onContinue;

  const AudioContinueButton({
    super.key,
    required this.activity,
    required this.onContinue,
    required this.activityComplete,
    required this.correctAnswers,
  });

  @override
  Widget build(BuildContext context) {
    final activity = this.activity;

    final totalAnswers = activity.multipleChoiceContent.answers.length;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8.0,
        children: [
          // Progress ovals row
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  totalAnswers,
                  (index) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Container(
                        height: 16.0,
                        decoration: BoxDecoration(
                          color: index < correctAnswers
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Continue button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: activityComplete ? onContinue : null,
              child: Text(
                L10n.of(context).continueText,
                style: const TextStyle(fontSize: 16.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
