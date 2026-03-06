import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/audio_player.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_example_message_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/grammar_error_example_widget.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_audio_card.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityContent extends StatelessWidget {
  final MultipleChoicePracticeActivityModel activity;

  final bool showHint;
  final Future<List<InlineSpan>?> exampleMessage;
  final PangeaAudioFile? audioFile;

  const ActivityContent({
    super.key,
    required this.activity,
    required this.showHint,
    required this.exampleMessage,
    this.audioFile,
  });

  @override
  Widget build(BuildContext context) {
    final activity = this.activity;

    return switch (activity) {
      GrammarErrorPracticeActivityModel() => SingleChildScrollView(
        child: GrammarErrorExampleWidget(
          key: ValueKey(
            '${activity.eventID}_${activity.errorOffset}_${activity.errorLength}',
          ),
          activity: activity,
          showTranslation: showHint,
        ),
      ),
      MorphCategoryPracticeActivityModel() => Center(
        child: ActivityExampleMessage(exampleMessage),
      ),
      VocabAudioPracticeActivityModel() => SizedBox(
        height: 60.0,
        child: Center(
          child: AudioPlayerWidget(
            null,
            key: ValueKey('audio_${activity.eventId}'),
            color: Theme.of(context).colorScheme.primary,
            linkColor: Theme.of(context).colorScheme.secondary,
            fontSize:
                AppSettings.fontSizeFactor.value * AppConfig.messageFontSize,
            eventId: '${activity.eventId}_practice',
            roomId: activity.roomId!,
            senderId: Matrix.of(context).client.userID!,
            matrixFile: audioFile,
            autoplay: true,
          ),
        ),
      ),
      _ => SizedBox(
        height: 100.0,
        child: Center(child: ActivityExampleMessage(exampleMessage)),
      ),
    };
  }
}
