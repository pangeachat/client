import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';

class AnalyticsPracticeExerciseHintsProgress extends StatelessWidget {
  final int hintsUsed;

  const AnalyticsPracticeExerciseHintsProgress({
    super.key,
    required this.hintsUsed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          AnalyticsPracticeConstants.maxHints,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Icon(
              index < hintsUsed ? Icons.lightbulb : Icons.lightbulb_outline,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
