import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/listening_exposure_declaration.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_tts_listening_probe.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/choice_animation.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_use_case.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../../features/bot/utils/bot_style.dart';

typedef ChoiceCallback<T> = void Function(T value, int index);

class ChoicesArray<T> extends StatefulWidget {
  final List<Choice<T>>? choices;
  final ChoiceCallback<T> onPressed;
  final ChoiceCallback<T>? onLongPress;
  final int? selectedChoiceIndex;

  final bool enableAudio;

  /// language code for the TTS
  final String? langCode;

  /// Used to uniquely identify the keys for choices, in cases where multiple
  /// choices could have identical text, like in back-to-back practice exercises.
  final String? id;

  final String Function(T)? getDisplayCopy;
  final bool enabled;

  /// The room the choices belong to, for the listening measurement below.
  ///
  /// REQUIRED, and deliberately so. This widget is generic and shared, and it
  /// has no room of its own — only its caller knows one. A room a caller may
  /// omit is a room a caller will omit, and the emit would then have to invent
  /// one or go dark, which is how the gap this closes opened in the first
  /// place. Both current callers have a room in hand; a third that does not
  /// belongs in the same conversation as the roomless surfaces, not behind a
  /// default here.
  final String roomId;

  /// When true, a single tap on a choice only plays it; selecting it takes a
  /// second tap on the SAME choice within [kDoubleTapTimeout].
  ///
  /// Writing assistance's Listen First mode, and only its. A learner who knows
  /// a language by ear cannot tell the choices apart on sight, and hearing one
  /// used to cost them the answer. Every other caller leaves this false and
  /// keeps the shipped behaviour, where a tap selects.
  final bool listenFirstMode;

  const ChoicesArray({
    super.key,
    required this.choices,
    required this.onPressed,
    required this.selectedChoiceIndex,
    required this.roomId,
    this.enableAudio = true,
    this.langCode,
    this.onLongPress,
    this.getDisplayCopy,
    this.id,
    this.enabled = true,
    this.listenFirstMode = false,
  });

  @override
  State<ChoicesArray<T>> createState() => _ChoicesArrayState<T>();
}

class _ChoicesArrayState<T> extends State<ChoicesArray<T>> {
  /// The choice a Listen First tap has played and left waiting for the second
  /// tap that selects it, cleared when [kDoubleTapTimeout] runs out.
  int? _armedIndex;
  Timer? _armTimer;

  @override
  void didUpdateWidget(covariant ChoicesArray<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Leaving the mode, or moving to another match's choices, must not leave a
    // choice armed: the next tap would select without the learner having heard
    // this one, which is the surprise the mode exists to remove.
    if (!widget.listenFirstMode || oldWidget.id != widget.id) _disarm();
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  void _disarm() {
    _armTimer?.cancel();
    _armTimer = null;
    _armedIndex = null;
  }

  void _speak(T value) {
    if (!widget.enableAudio || widget.langCode == null) return;
    TtsController.tryToSpeak(
      // Display string is used for TTS
      widget.getDisplayCopy != null
          ? widget.getDisplayCopy!(value)
          : value.toString(),
      targetID: null,
      langCode: widget.langCode!,
      useCase: TtsUseCase.choices,
      // Listening category 6 (#104): audio a DRILL played — a
      // tapped answer choice spoken back to the learner.
      //
      // The category is a constant here, but the ROOM cannot be:
      // this widget serves writing assistance and the activity
      // orchestrator, so it is threaded in by whichever caller
      // built it. The identity is read live rather than captured —
      // an account switch mid-playback must not post under a stale
      // one. A fresh probe per call: it holds a running
      // measurement.
      // A choice is spoken as raw text: this widget serves
      // writing assistance and the activity orchestrator and is
      // handed strings, not tokens, so there is no construct to
      // file the hearing under. Deriving a lemma from the surface
      // form would file it under the wrong word, which is worse
      // than not recording it.
      exposure: const ListeningExposureDeclaration.exempt(
        "choice text is not resolved to a construct here",
      ),
      listening: DosageTtsListeningProbe(
        category: DosageListeningCategory.practiceAudio,
        roomId: widget.roomId,
        userId: () => MatrixState.pangeaController.matrixState.client.userID,
        accessToken: () =>
            MatrixState.pangeaController.matrixState.client.accessToken,
      ),
    );
  }

  /// A tap on choice [index].
  ///
  /// Outside Listen First this is unchanged: select, and play. Inside it the
  /// first tap only plays, and a second tap on the same choice within the
  /// double-tap window selects it without replaying over the audio the first
  /// tap started.
  void _onTap(T value, int index) {
    if (!widget.listenFirstMode) {
      widget.onPressed(value, index);
      _speak(value);
      return;
    }

    if (_armedIndex == index) {
      _disarm();
      widget.onPressed(value, index);
      return;
    }

    _speak(value);
    _armTimer?.cancel();
    _armedIndex = index;
    _armTimer = Timer(kDoubleTapTimeout, () => _armedIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 4.0,
      children: [
        ...widget.choices!.mapIndexed(
          (index, entry) => ChoiceItem<T>(
            onLongPress: widget.onLongPress,
            onPressed: _onTap,
            entry: MapEntry(index, entry),
            isSelected: widget.selectedChoiceIndex == index,
            id: widget.id,
            getDisplayCopy: widget.getDisplayCopy,
            enabled: widget.enabled,
          ),
        ),
      ],
    );
  }
}

class Choice<T> {
  Choice({this.color, required this.value, this.isGold = false});

  final Color? color;
  final T value;
  final bool isGold;
}

class ChoiceItem<T> extends StatelessWidget {
  final MapEntry<int, Choice<T>> entry;
  final ChoiceCallback<T>? onLongPress;
  final ChoiceCallback<T> onPressed;
  final bool isSelected;
  final String? id;
  final String Function(T)? getDisplayCopy;
  final double? fontSize;
  final bool enabled;

  const ChoiceItem({
    super.key,
    required this.onLongPress,
    required this.onPressed,
    required this.entry,
    required this.isSelected,
    required this.id,
    this.getDisplayCopy,
    this.fontSize,
    this.enabled = true,
  });

  String get _displayText => getDisplayCopy != null
      ? getDisplayCopy!(entry.value.value)
      : entry.value.value.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: onLongPress != null ? L10n.of(context).holdForInfo : "",
      waitDuration: onLongPress != null
          ? const Duration(milliseconds: 500)
          : const Duration(days: 1),
      child: CompositedTransformTarget(
        link: MatrixState.pAnyState.layerLinkAndKey("$_displayText$id").link,
        child: ChoiceAnimationWidget(
          isSelected: isSelected,
          isCorrect: entry.value.isGold,
          key: MatrixState.pAnyState.layerLinkAndKey("$_displayText$id").key,
          child: Container(
            margin: const EdgeInsets.all(2),
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                backgroundColor:
                    entry.value.color?.withAlpha(50) ??
                    theme.colorScheme.primary.withAlpha(10),
                textStyle: BotStyle.text(context),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: isSelected
                        ? entry.value.color ?? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 2.0,
                  ),
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                ),
              ),
              onLongPress: onLongPress != null && enabled
                  ? () => onLongPress!(entry.value.value, entry.key)
                  : null,
              onPressed: enabled
                  ? () => onPressed(entry.value.value, entry.key)
                  : null,
              child: Text(
                _displayText,
                style: BotStyle.text(context).copyWith(fontSize: fontSize),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
