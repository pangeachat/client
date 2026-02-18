import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';

class ActivityHintsProgress extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const ActivityHintsProgress({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.hintsUsedNotifier,
      builder: (context, hintsUsed, _) {
        return Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              AnalyticsPracticeState.maxHints,
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
      },
    );
  }
}
