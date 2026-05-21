import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/choice_animation.dart';
import 'package:fluffychat/pangea/text_to_speech/tts_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../bot/utils/bot_style.dart';

typedef ChoiceCallback<T> = void Function(T value, int index);

class ChoicesArray<T> extends StatelessWidget {
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
  final Axis direction;

  const ChoicesArray({
    super.key,
    required this.choices,
    required this.onPressed,
    required this.selectedChoiceIndex,
    this.enableAudio = true,
    this.langCode,
    this.onLongPress,
    this.getDisplayCopy,
    this.id,
    this.enabled = true,
    this.direction = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      direction: direction,
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 4.0,
      children: [
        ...choices!.mapIndexed(
          (index, entry) => ChoiceItem<T>(
            onLongPress: onLongPress,
            onPressed: (T value, int index) {
              onPressed(value, index);
              if (enableAudio && langCode != null) {
                TtsController.tryToSpeak(
                  // Display string is used for TTS
                  getDisplayCopy != null
                      ? getDisplayCopy!(value)
                      : value.toString(),
                  targetID: null,
                  langCode: langCode!,
                );
              }
            },
            entry: MapEntry(index, entry),
            isSelected: selectedChoiceIndex == index,
            id: id,
            getDisplayCopy: getDisplayCopy,
            enabled: enabled,
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
