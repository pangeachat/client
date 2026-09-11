import 'dart:math';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/dotted_border_painter.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/message_practice_mode_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/morph_selection.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_record_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_choice.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/hover_builder.dart';

const double tokenButtonHeight = 40.0;
const double tokenButtonDefaultFontSize = 10;
const int maxEmojisPerLemma = 1;

class TokenPracticeButton extends StatelessWidget {
  final PracticeController controller;
  final PangeaToken token;
  final TextStyle textStyle;
  final double width;
  final Color textColor;

  const TokenPracticeButton({
    super.key,
    required this.controller,
    required this.token,
    required this.textStyle,
    required this.width,
    required this.textColor,
  });

  TextStyle get _emojiStyle => TextStyle(
    fontSize: (textStyle.fontSize ?? tokenButtonDefaultFontSize) + 4,
  );

  PracticeTarget? get _activity => controller.practiceTargetForToken(token);

  bool get isActivityCompleteOrNullForToken {
    if (_activity == null) return true;
    return PracticeRecordController.isCompleteByToken(_activity!, token);
  }

  bool get _isEmpty => controller.isPracticeButtonEmpty(token);

  bool get _isSelected =>
      controller.selectedMorph?.token == token &&
      controller.selectedMorph?.morph == _activity?.morphFeature;

  void _onMatch(PracticeExerciseChoice form) => controller.onMatch(token, form);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final practiceMode = controller.practiceMode;

        Widget child;
        if (isActivityCompleteOrNullForToken || _activity == null) {
          child = _NoActivityContentButton(
            practiceMode: practiceMode,
            token: token,
            target: _activity,
            emojiStyle: _emojiStyle,
            width: tokenButtonHeight,
          );
        } else if (practiceMode == MessagePracticeMode.wordMorph) {
          child = _MorphMatchButton(
            active: _isSelected,
            textColor: textColor,
            width: tokenButtonHeight,
            onTap: () => controller.updatePracticeMorph(
              MorphSelection(token, _activity!.morphFeature!),
            ),
            shimmer:
                controller.selectedMorph == null &&
                _activity != null &&
                !PracticeRecordController.hasAnyCorrectChoices(_activity!),
          );
        } else {
          final selectedSlotToken = controller.selectedSlotToken;
          child = _StandardMatchButton(
            isSelected: selectedSlotToken == token,
            isDimmed: selectedSlotToken != null && selectedSlotToken != token,
            shimmer: controller.showSlotShimmer,
            width: width,
            borderColor: textColor,
            onSelect: () => controller.onSlotSelect(token),
            onMatch: _onMatch,
          );
        }

        return AnimatedSize(
          duration: const Duration(
            milliseconds: AppConfig.overlayAnimationDuration,
          ),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: _isEmpty
              ? const SizedBox()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4.0),
                    SizedBox(height: tokenButtonHeight, child: child),
                  ],
                ),
        );
      },
    );
  }
}

/// A blank under one word. Tapping it makes that word the exercise's target,
/// which is what brings the tray's answers up; it stays a drop target so a
/// dragged answer still lands.
class _StandardMatchButton extends StatelessWidget {
  final bool isSelected;
  final bool isDimmed;
  final bool shimmer;
  final double width;
  final Color borderColor;
  final VoidCallback onSelect;
  final Function(PracticeExerciseChoice choice) onMatch;

  const _StandardMatchButton({
    required this.isSelected,
    required this.isDimmed,
    required this.shimmer,
    required this.width,
    required this.borderColor,
    required this.onSelect,
    required this.onMatch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<PracticeExerciseChoice>(
      builder: (BuildContext context, accepted, rejected) {
        final bool highlighted = isSelected || accepted.isNotEmpty;
        final double colorAlpha = highlighted
            ? 1.0
            : isDimmed
            ? 0.15
            : 0.3;

        final borderRadius = BorderRadius.circular(AppConfig.borderRadius - 4);

        return Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onSelect,
            borderRadius: borderRadius,
            // A foreground painter: the blank's fill is opaque, so a border
            // painted behind it only showed the half of the stroke that spilled
            // outside the box.
            child: CustomPaint(
              foregroundPainter: DottedBorderPainter(
                color: (highlighted ? theme.colorScheme.primary : borderColor)
                    .withAlpha((colorAlpha * 255).toInt()),
                borderRadius: borderRadius,
              ),
              child: ShimmerBackground(
                enabled: shimmer,
                // Without this the pulse defaults to the standard corner
                // radius and bulges past the blank's own, tighter outline.
                borderRadius: borderRadius,
                child: Container(
                  padding: const EdgeInsets.only(top: 10.0),
                  width: max(width, 24.0),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: highlighted
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surface,
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      onAcceptWithDetails: (details) => onMatch(details.data),
    );
  }
}

class _MorphMatchButton extends StatelessWidget {
  final Function()? onTap;
  final bool active;
  final Color textColor;
  final bool shimmer;
  final double width;

  const _MorphMatchButton({
    required this.active,
    required this.textColor,
    required this.width,
    this.shimmer = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: HoverBuilder(
        builder: (context, hovered) {
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius - 4),
            child: ShimmerBackground(
              enabled: shimmer,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius - 4),
              child: SizedBox(
                width: width,
                child: Center(
                  child: Opacity(
                    opacity: active ? 1.0 : 0.6,
                    child: AnimatedScale(
                      scale: hovered || active ? 1.25 : 1.0,
                      duration: FluffyThemes.animationDuration,
                      curve: FluffyThemes.animationCurve,
                      child: Icon(
                        Symbols.toys_and_games,
                        color: textColor,
                        size: 24.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NoActivityContentButton extends StatelessWidget {
  final MessagePracticeMode practiceMode;
  final PangeaToken token;
  final PracticeTarget? target;
  final TextStyle emojiStyle;
  final double width;

  const _NoActivityContentButton({
    required this.practiceMode,
    required this.token,
    required this.target,
    required this.emojiStyle,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    if (practiceMode == MessagePracticeMode.wordEmoji) {
      String? displayEmoji = token.vocabConstructID.userSetEmoji;
      if (target != null) {
        displayEmoji =
            PracticeRecordController.correctResponse(target!, token)?.text ??
            displayEmoji;
      }
      return Text(displayEmoji ?? '', style: emojiStyle);
    }
    if (practiceMode == MessagePracticeMode.wordMorph && target != null) {
      final morphFeature = target!.morphFeature!;
      final morphTag = token.morphIdByFeature(morphFeature);
      if (morphTag != null) {
        return Tooltip(
          message:
              GrammarConstructsProvider.getTagTitle(
                feature: morphFeature.name,
                tag: morphTag.lemma,
              ) ??
              morphTag.lemma,
          child: SizedBox(
            width: width,
            child: Center(
              child: CircleAvatar(
                radius: width / 2,
                backgroundColor:
                    Theme.of(context).brightness != Brightness.light
                    ? Theme.of(context).colorScheme.surface.withAlpha(100)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: MorphIcon(
                    feature: morphFeature,
                    tag: morphTag.lemma,
                    size: Size.fromWidth(width - 8.0),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return const SizedBox();
  }
}
