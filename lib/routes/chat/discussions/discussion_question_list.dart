import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

/// A discussion's questions, numbered, in the block at the top of its chat
/// (#9647): what the group talks about, easier to deeper.
class DiscussionQuestionList extends StatelessWidget {
  final List<String> questions;

  const DiscussionQuestionList({super.key, required this.questions});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: AppConfig.messageFontSize);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8.0,
      children: [
        for (var i = 0; i < questions.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8.0,
            children: [
              Text(
                '${i + 1}.',
                style: style.copyWith(fontWeight: FontWeight.bold),
              ),
              Expanded(child: Text(questions[i], style: style)),
            ],
          ),
      ],
    );
  }
}
