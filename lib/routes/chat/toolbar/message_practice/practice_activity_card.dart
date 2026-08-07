import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/card_error_widget.dart';
import 'package:fluffychat/pangea/common/widgets/content_loading_indicator.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_response_dialog.dart';
import 'package:fluffychat/routes/chat/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/message_morph_choice.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_exercise_feedback_dialog.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_match_card.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The wrapper for practice exercise content.
/// Handles the exercises associated with a message,
/// their navigation, and the management of completion records
class PracticeActivityCard extends StatefulWidget {
  final PracticeTarget targetTokensAndActivityType;
  final PracticeController controller;
  final PangeaToken? selectedToken;
  final double maxWidth;

  const PracticeActivityCard({
    super.key,
    required this.targetTokensAndActivityType,
    required this.controller,
    required this.selectedToken,
    required this.maxWidth,
  });

  @override
  PracticeActivityCardState createState() => PracticeActivityCardState();
}

class PracticeActivityCardState extends State<PracticeActivityCard> {
  final ValueNotifier<AsyncState<PracticeExerciseModel>> _activityState =
      ValueNotifier(const AsyncState.loading());

  final _playbackSpeedController = AudioPlaybackSpeedController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchActivity());
  }

  @override
  void didUpdateWidget(PracticeActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetTokensAndActivityType !=
        widget.targetTokensAndActivityType) {
      _fetchActivity();
    }
  }

  @override
  void dispose() {
    _activityState.dispose();
    _playbackSpeedController.dispose();
    super.dispose();
  }

  Future<void> _fetchActivity() async {
    final loadedTarget = widget.targetTokensAndActivityType;
    _activityState.value = const AsyncState.loading();
    if (!MatrixState.pangeaController.userController.languagesSet) {
      _activityState.value = const AsyncState.error("Error fetching activity");
      return;
    }

    final result = await widget.controller.fetchActivityModel(
      widget.targetTokensAndActivityType,
    );

    if (loadedTarget != widget.targetTokensAndActivityType) {
      // Target changed while fetching, discard result
      return;
    }

    if (!mounted) return;

    if (result.isValue) {
      _activityState.value = AsyncState.loaded(result.result!);
    } else {
      _activityState.value = AsyncState.error(
        "Error fetching activity: ${result.asError}",
      );
    }
  }

  Future<void> _onFlagExercise(MatchPracticeExerciseModel activity) async {
    final loadedTarget = widget.targetTokensAndActivityType;
    final outcome = await showDialog<PracticeFeedbackOutcome>(
      context: context,
      builder: (context) => PracticeExerciseFeedbackDialog(
        activity: activity,
        target: loadedTarget,
        controller: widget.controller,
      ),
    );
    if (outcome == null || !mounted) return;

    // Rebuild the exercise from the corrected lemma content — unless the
    // target changed while the dialog was open, in which case the card has
    // already refetched.
    if (loadedTarget == widget.targetTokensAndActivityType) {
      await _fetchActivity();
    }
    if (!mounted) return;

    final unchanged = outcome.prior == outcome.updated;
    await showDialog(
      context: context,
      builder: (context) => FeedbackResponseDialog(
        title: L10n.of(context).practiceFeedbackDialogTitle,
        feedback: unchanged
            ? L10n.of(context).practiceFeedbackUnchanged
            : L10n.of(context).practiceFeedbackUpdated,
      ),
    );
  }

  /// Match cards whose content comes from the lemma dictionary (emoji /
  /// meaning) get a flag button for reporting wrong content. Listening
  /// cards are also match cards, but their content is generated locally,
  /// so there is nothing to report.
  Widget _buildMatchCard(MatchPracticeExerciseModel activity) {
    final card = MatchActivityCard(
      currentActivity: activity,
      controller: widget.controller,
      playbackSpeedController: _playbackSpeedController,
    );

    final flaggable =
        activity is EmojiPracticeExerciseModel ||
        activity is LemmaMeaningPracticeExerciseModel;
    if (!flaggable) return card;

    return Stack(
      children: [
        card,
        Positioned(
          top: 0.0,
          right: 0.0,
          child: IconButton(
            color: Theme.of(context).iconTheme.color,
            iconSize: 20.0,
            icon: const Icon(Icons.flag_outlined),
            tooltip: L10n.of(context).practiceFeedbackButtonTooltip,
            onPressed: () => _onFlagExercise(activity),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _activityState,
      builder: (context, state, _) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            switch (state) {
              AsyncLoading() => const ContentLoadingIndicator(height: 40),
              AsyncError() => CardErrorWidget(
                L10n.of(context).errorFetchingExercise,
              ),
              AsyncLoaded() => switch (state.value) {
                MultipleChoicePracticeExerciseModel() =>
                  MessageMorphInputBarContent(
                    controller: widget.controller,
                    activity: state.value as MorphPracticeExerciseModel,
                    selectedToken: widget.selectedToken,
                    maxWidth: widget.maxWidth,
                  ),
                MatchPracticeExerciseModel() => _buildMatchCard(
                  state.value as MatchPracticeExerciseModel,
                ),
              },
              _ => const SizedBox.shrink(),
            },
          ],
        );
      },
    );
  }
}
