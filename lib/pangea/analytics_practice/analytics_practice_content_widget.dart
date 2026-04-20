import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/audio_player.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_message_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/grammar_error_example_widget.dart';
import 'package:fluffychat/pangea/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_audio_card.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsPracticeExerciseContent extends StatelessWidget {
  final MultipleChoicePracticeExerciseModel analyticsPracticeExercise;

  final bool showHint;
  final Future<List<InlineSpan>?> exampleMessage;
  final PangeaAudioFile? audioFile;
  final AudioPlaybackSpeedController playbackSpeedController;

  const AnalyticsPracticeExerciseContent({
    super.key,
    required this.analyticsPracticeExercise,
    required this.showHint,
    required this.exampleMessage,
    required this.playbackSpeedController,
    this.audioFile,
  });

  @override
  Widget build(BuildContext context) {
    final exercise = analyticsPracticeExercise;

    return switch (exercise) {
      GrammarErrorPracticeExerciseModel() => SingleChildScrollView(
        child: GrammarErrorExampleWidget(
          key: ValueKey(
            '${exercise.eventID}_${exercise.errorOffset}_${exercise.errorLength}',
          ),
          analyticsPracticeExercise: exercise,
          showTranslation: showHint,
        ),
      ),
      MorphCategoryPracticeExerciseModel() => Center(
        child: AnalyticsPracticeExerciseExampleMessage(exampleMessage),
      ),
      VocabAudioPracticeExerciseModel() => SizedBox(
        height: 60.0,
        child: Center(
          child: AudioPlayerWidget(
            null,
            key: ValueKey('audio_${exercise.eventId}'),
            color: Theme.of(context).colorScheme.primary,
            linkColor: Theme.of(context).colorScheme.secondary,
            fontSize:
                AppSettings.fontSizeFactor.value * AppConfig.messageFontSize,
            eventId: '${exercise.eventId}_practice',
            roomId: exercise.roomId!,
            senderId: Matrix.of(context).client.userID!,
            matrixFile: audioFile,
            autoplay: true,
            playbackSpeedController: playbackSpeedController,
          ),
        ),
      ),
      _ => SizedBox(
        height: 100.0,
        child: Center(
          child: AnalyticsPracticeExerciseExampleMessage(exampleMessage),
        ),
      ),
    };
  }
}
