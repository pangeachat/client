import 'dart:math';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/pangea/practice_activities/practice_choice.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/dotted_border_painter.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_practice_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/morph_selection.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_record_controller.dart';
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

  void _onMatch(PracticeChoice form) {
    controller.onChoiceSelect(null);
    controller.onMatch(token, form);
  }

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
          child = _StandardMatchButton(
            selectedChoice: controller.selectedChoice,
            width: width,
            borderColor: textColor,
            onMatch: (choice) => _onMatch(choice),
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

class _StandardMatchButton extends StatelessWidget {
  final PracticeChoice? selectedChoice;
  final double width;
  final Color borderColor;
  final Function(PracticeChoice choice) onMatch;

  const _StandardMatchButton({
    required this.selectedChoice,
    required this.width,
    required this.borderColor,
    required this.onMatch,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<PracticeChoice>(
      builder: (BuildContext context, accepted, rejected) {
        final double colorAlpha =
            0.3 +
            (selectedChoice != null ? 0.4 : 0.0) +
            (accepted.isNotEmpty ? 0.3 : 0.0);

        final theme = Theme.of(context);
        final borderRadius = BorderRadius.circular(AppConfig.borderRadius - 4);

        return Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: selectedChoice != null
                ? () => onMatch(selectedChoice!)
                : null,
            borderRadius: borderRadius,
            child: CustomPaint(
              painter: DottedBorderPainter(
                color: borderColor.withAlpha((colorAlpha * 255).toInt()),
                borderRadius: borderRadius,
              ),
              child: Shimmer.fromColors(
                enabled: selectedChoice != null,
                baseColor: selectedChoice != null
                    ? AppConfig.gold.withAlpha(20)
                    : Colors.transparent,
                highlightColor: selectedChoice != null
                    ? AppConfig.gold.withAlpha(50)
                    : Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.only(top: 10.0),
                  width: max(width, 24.0),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
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
          message: getGrammarCopy(
            category: morphFeature.toShortString(),
            lemma: morphTag.lemma,
            context: context,
          ),
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
                    morphFeature: morphFeature,
                    morphTag: morphTag.lemma,
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
