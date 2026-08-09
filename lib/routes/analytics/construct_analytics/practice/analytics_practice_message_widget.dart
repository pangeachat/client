import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';

class AnalyticsPracticeExerciseExampleMessage extends StatelessWidget {
  final Future<List<InlineSpan>?> future;

  const AnalyticsPracticeExerciseExampleMessage(this.future, {super.key});

  @override
  Widget build(BuildContext context) {
    final textStyle = FluffyThemes.isColumnMode(context)
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.titleSmall;

    return FutureBuilder<List<InlineSpan>?>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: RichText(
            text: TextSpan(
              style: textStyle?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              children: snapshot.data!,
            ),
          ),
        );
      },
    );
  }
}
