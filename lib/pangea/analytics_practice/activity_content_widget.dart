import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/events/audio_player.dart';
import 'package:fluffychat/pangea/analytics_practice/activity_example_message_widget.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_page.dart';
import 'package:fluffychat/pangea/analytics_practice/grammar_error_example_widget.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityContent extends StatelessWidget {
  final AnalyticsPracticeState controller;

  const ActivityContent({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.activityTarget,
      builder: (context, target, _) => switch (target?.target.activityType) {
        null => const SizedBox(),
        ActivityTypeEnum.grammarError => SingleChildScrollView(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              controller.activityState,
              controller.hintPressedNotifier,
            ]),
            builder: (context, _) {
              final state = controller.activityState.value;
              if (state is! AsyncLoaded<MultipleChoicePracticeActivityModel>) {
                return const SizedBox();
              }
              final activity = state.value;
              if (activity is! GrammarErrorPracticeActivityModel) {
                return const SizedBox();
              }
              return GrammarErrorExampleWidget(
                key: ValueKey(
                  '${activity.eventID}_${activity.errorOffset}_${activity.errorLength}',
                ),
                activity: activity,
                showTranslation: controller.hintPressedNotifier.value,
              );
            },
          ),
        ),
        ActivityTypeEnum.grammarCategory => Center(
          child: ActivityExampleMessage(controller.getExampleMessage(target!)),
        ),
        ActivityTypeEnum.lemmaAudio => ValueListenableBuilder(
          valueListenable: controller.activityState,
          builder: (context, state, _) => switch (state) {
            AsyncLoaded(
              value: final VocabAudioPracticeActivityModel activity,
            ) =>
              SizedBox(
                height: 60.0,
                child: Center(
                  child: AudioPlayerWidget(
                    null,
                    key: ValueKey('audio_${activity.eventId}'),
                    color: Theme.of(context).colorScheme.primary,
                    linkColor: Theme.of(context).colorScheme.secondary,
                    fontSize:
                        AppSettings.fontSizeFactor.value *
                        AppConfig.messageFontSize,
                    eventId: '${activity.eventId}_practice',
                    roomId: activity.roomId!,
                    senderId: Matrix.of(context).client.userID!,
                    matrixFile: controller.getAudioFile(activity.eventId)!,
                    autoplay: true,
                  ),
                ),
              ),
            _ => const SizedBox(height: 100.0),
          },
        ),
        _ => SizedBox(
          height: 100.0,
          child: Center(
            child: ActivityExampleMessage(
              controller.getExampleMessage(target!),
            ),
          ),
        ),
      },
    );
  }
}
