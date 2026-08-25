import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/listening_exposure_declaration.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_tts_listening_probe.dart';
import 'package:fluffychat/features/overlay/layer_link_and_key.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/routes/chat/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_choice.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PracticeMatchItem extends StatefulWidget {
  final Widget content;
  final PangeaToken? token;
  final PracticeExerciseChoice constructForm;
  final String? audioContent;
  final PracticeController controller;
  final bool? isCorrect;
  final bool isSelected;
  final bool shimmer;
  final AudioPlaybackSpeedController playbackSpeedController;

  const PracticeMatchItem({
    super.key,
    required this.content,
    required this.token,
    required this.constructForm,
    required this.isCorrect,
    required this.isSelected,
    this.audioContent,
    required this.controller,
    this.shimmer = false,
    required this.playbackSpeedController,
  });

  @override
  PracticeMatchItemState createState() => PracticeMatchItemState();
}

class PracticeMatchItemState extends State<PracticeMatchItem> {
  bool _isHovered = false;
  bool _isPlaying = false;

  bool get isSelected => widget.isSelected;

  bool? get isCorrect => widget.isCorrect;

  String get _targetId =>
      "practice-choice-item-${widget.constructForm.choiceContent}";

  LayerLinkAndKey get _target =>
      MatrixState.pAnyState.layerLinkAndKey(_targetId);

  Future<void> play() async {
    if (widget.audioContent == null) {
      return;
    }

    if (_isPlaying) {
      await TtsController.stop(
        text: widget.audioContent!,
        langCode:
            MatrixState.pangeaController.userController.userL2Code ?? 'en',
        pos: widget.token?.pos,
        morph: widget.token?.morph.map((k, v) => MapEntry(k.name, v)),
      );
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    } else {
      if (mounted) {
        setState(() => _isPlaying = true);
      }
      try {
        final l2 = MatrixState.pangeaController.userController.userL2Code;
        if (l2 != null) {
          await TtsController.tryToSpeak(
            widget.audioContent!,
            context: context,
            targetID: _targetId,
            langCode: l2,
            useCase: TtsUseCase.choices,
            pos: widget.token?.pos,
            morph: widget.token?.morph.map((k, v) => MapEntry(k.name, v)),
            speed: widget.playbackSpeedController.playbackSpeed.value,
            // Listening category 6 (#104): audio a DRILL played — a match
            // item's play button, deliberate and repeatable.
            //
            // The room comes from the exercise's own message. A fresh probe per
            // call: it holds a running measurement.
            listening: DosageTtsListeningProbe(
              category: DosageListeningCategory.practiceAudio,
              roomId: widget.controller.pangeaMessageEvent.room.id,
              userId: () =>
                  widget.controller.pangeaMessageEvent.room.client.userID,
              accessToken: () =>
                  widget.controller.pangeaMessageEvent.room.client.accessToken,
            ),
            exposure: widget.token == null
                ? const ListeningExposureDeclaration.exempt(
                    "match item has no token to attribute the lemma to",
                  )
                : ListeningExposureDeclaration.ofTokens([
                    widget.token!,
                  ], langCode: l2),
          );
        }
      } catch (e, s) {
        debugger(when: kDebugMode);
        ErrorHandler.logError(e: e, s: s, data: {"text": widget.audioContent});
      } finally {
        if (mounted) {
          setState(() => _isPlaying = false);
        }
      }
    }
  }

  Color color(BuildContext context) {
    if (isCorrect != null) {
      return isCorrect! ? AppConfig.success : AppConfig.warning;
    }

    if (isSelected) {
      return Theme.of(context).colorScheme.primaryContainer;
    }

    if (_isHovered) {
      return Theme.of(context).colorScheme.primaryContainer;
    }

    return Theme.of(context).colorScheme.surface;
  }

  @override
  didUpdateWidget(PracticeMatchItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected != widget.isSelected ||
        oldWidget.isCorrect != widget.isCorrect) {
      setState(() {});
    }
  }

  void onTap() {
    play();
    if (isCorrect == null || !isCorrect! || widget.token == null) {
      widget.controller.onChoiceSelect(widget.constructForm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final content = CompositedTransformTarget(
      link: target.link,
      child: Row(
        key: target.key,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                color: color(context).withAlpha((0.4 * 255).toInt()),
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                border: isSelected
                    ? Border.all(color: color(context).withAlpha(255), width: 2)
                    : Border.all(color: Colors.transparent, width: 2),
              ),
              child: widget.content,
            ),
          ),
        ],
      ),
    );

    // Disable feedback and dragging when the answer is correct to prevent unnecessary interactions
    if (isCorrect == true) {
      return content;
    }

    return Draggable<PracticeExerciseChoice>(
      data: widget.constructForm,
      feedback: Material(type: MaterialType.transparency, child: content),
      onDragStarted: onTap,
      child: InkWell(
        onHover: (isHovered) => setState(() => _isHovered = isHovered),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        onTap: onTap,
        child: ShimmerBackground(enabled: widget.shimmer, child: content),
      ),
    );
  }
}
