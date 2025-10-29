import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/choreographer/constants/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choregrapher_user_settings_extension.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_state_extension.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_ui_extension.dart';
import 'package:fluffychat/pangea/choreographer/models/it_step.dart';
import 'package:fluffychat/pangea/choreographer/repo/full_text_translation_request_model.dart';
import 'package:fluffychat/pangea/choreographer/widgets/igc/word_data_card.dart';
import 'package:fluffychat/pangea/choreographer/widgets/it_feedback_card.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/learning_settings/pages/settings_learning.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../common/utils/overlay.dart';
import 'choice_array.dart';

class ITBar extends StatefulWidget {
  final Choreographer choreographer;
  const ITBar({super.key, required this.choreographer});

  @override
  ITBarState createState() => ITBarState();
}

class ITBarState extends State<ITBar> with SingleTickerProviderStateMixin {
  bool showedClickInstruction = false;
  late AnimationController _controller;
  late Animation<double> _animation;
  bool wasOpen = false;

  @override
  void initState() {
    super.initState();

    // Rebuild the widget each time there's an update from choreo.
    widget.choreographer.addListener(() {
      if (widget.choreographer.isITOpen != wasOpen) {
        widget.choreographer.isITOpen
            ? _controller.forward()
            : _controller.reverse();
      }
      wasOpen = widget.choreographer.isITOpen;
      setState(() {});
    });

    wasOpen = widget.choreographer.isITOpen;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    // Start in the correct state
    widget.choreographer.isITOpen
        ? _controller.forward()
        : _controller.reverse();
  }

  bool get showITInstructionsTooltip {
    final toggledOff = InstructionsEnum.clickBestOption.isToggledOff;
    if (!toggledOff) {
      setState(() => showedClickInstruction = true);
    }
    return !toggledOff;
  }

  bool get showTranslationsChoicesTooltip {
    return !showedClickInstruction &&
        !showITInstructionsTooltip &&
        !widget.choreographer.isFetching &&
        !widget.choreographer.isEditingSourceText &&
        !widget.choreographer.isITDone &&
        widget.choreographer.itStepContinuances?.isNotEmpty == true;
  }

  final double iconDimension = 36;
  final double iconSize = 20;

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _animation,
      axis: Axis.vertical,
      axisAlignment: -1.0,
      child: CompositedTransformTarget(
        link: widget.choreographer.itBarLinkAndKey.link,
        child: Column(
          spacing: 8.0,
          children: [
            if (showITInstructionsTooltip)
              const InstructionsInlineTooltip(
                instructionsEnum: InstructionsEnum.clickBestOption,
                animate: false,
              ),
            if (showTranslationsChoicesTooltip)
              const InstructionsInlineTooltip(
                instructionsEnum: InstructionsEnum.translationChoices,
                animate: false,
              ),
            Container(
              key: widget.choreographer.itBarLinkAndKey.key,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                color: Theme.of(context).colorScheme.surfaceContainer,
              ),
              padding: const EdgeInsets.all(3),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (widget.choreographer.isEditingSourceText)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 20,
                                right: 10,
                                top: 10,
                              ),
                              child: TextField(
                                controller: TextEditingController(
                                  text: widget.choreographer.sourceText,
                                ),
                                autofocus: true,
                                enableSuggestions: false,
                                maxLines: null,
                                textInputAction: TextInputAction.send,
                                onSubmitted:
                                    widget.choreographer.submitSourceTextEdits,
                                obscureText: false,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                        if (!widget.choreographer.isEditingSourceText &&
                            widget.choreographer.sourceText != null)
                          SizedBox(
                            width: iconDimension,
                            height: iconDimension,
                            child: IconButton(
                              iconSize: iconSize,
                              color: Theme.of(context).colorScheme.primary,
                              onPressed: () => widget.choreographer
                                  .setEditingSourceText(true),
                              icon: const Icon(Icons.edit_outlined),
                              // iconSize: 20,
                            ),
                          ),
                        if (!widget.choreographer.isEditingSourceText)
                          SizedBox(
                            width: iconDimension,
                            height: iconDimension,
                            child: IconButton(
                              iconSize: iconSize,
                              color: Theme.of(context).colorScheme.primary,
                              icon: const Icon(Icons.settings_outlined),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (c) => const SettingsLearning(),
                                barrierDismissible: false,
                              ),
                            ),
                          ),
                        SizedBox(
                          width: iconDimension,
                          height: iconDimension,
                          child: IconButton(
                            iconSize: iconSize,
                            color: Theme.of(context).colorScheme.primary,
                            icon: const Icon(Icons.close_outlined),
                            onPressed: () {
                              widget.choreographer.isEditingSourceText
                                  ? widget.choreographer
                                      .setEditingSourceText(false)
                                  : widget.choreographer.closeIT();
                            },
                          ),
                        ),
                      ],
                    ),
                    if (!widget.choreographer.isEditingSourceText)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: !widget.choreographer.isITOpen
                            ? const SizedBox()
                            : widget.choreographer.sourceText != null
                                ? Text(
                                    widget.choreographer.sourceText!,
                                    textAlign: TextAlign.center,
                                  )
                                : const LinearProgressIndicator(),
                      ),
                    const SizedBox(height: 8.0),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      constraints: const BoxConstraints(minHeight: 80),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        child: Center(
                          child: widget.choreographer.errorService.isError
                              ? ITError(choreographer: widget.choreographer)
                              : widget.choreographer.isITDone
                                  ? const SizedBox()
                                  : ITChoices(
                                      choreographer: widget.choreographer,
                                    ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ITChoices extends StatelessWidget {
  final Choreographer choreographer;
  const ITChoices({
    super.key,
    required this.choreographer,
  });

  void showCard(
    BuildContext context,
    int index, [
    Color? borderColor,
    String? choiceFeedback,
  ]) {
    if (choreographer.itStepContinuances == null) {
      ErrorHandler.logError(
        m: "currentITStep is null in showCard",
        s: StackTrace.current,
        data: {
          "index": index,
        },
      );
      return;
    }

    final text = choreographer.itStepContinuances![index].text;
    choreographer.chatController.inputFocus.unfocus();
    MatrixState.pAnyState.closeOverlay("it_feedback_card");
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: choiceFeedback == null
          ? WordDataCard(
              word: text,
              wordLang: choreographer.l2LangCode!,
              fullText: choreographer.sourceText ?? choreographer.currentText,
              fullTextLang: choreographer.sourceText != null
                  ? choreographer.l1LangCode!
                  : choreographer.l2LangCode!,
              choiceFeedback: choiceFeedback,
            )
          : ITFeedbackCard(
              req: FullTextTranslationRequestModel(
                text: text,
                tgtLang: choreographer.l2LangCode!,
                userL1: choreographer.l1LangCode!,
                userL2: choreographer.l2LangCode!,
              ),
              choiceFeedback: choiceFeedback,
            ),
      maxHeight: 300,
      maxWidth: 300,
      borderColor: borderColor,
      transformTargetId: choreographer.itBarTransformTargetKey,
      isScrollable: choiceFeedback == null,
      overlayKey: "it_feedback_card",
      ignorePointer: true,
    );
  }

  void selectContinuance(int index, BuildContext context) {
    MatrixState.pAnyState.closeOverlay("it_feedback_card");
    Continuance continuance;
    try {
      continuance = choreographer.onSelectContinuance(index);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        level: SentryLevel.warning,
        data: {
          "index": index,
        },
      );
      choreographer.closeIT();
      return;
    }

    if (continuance.level == 1) {
      Future.delayed(
        const Duration(milliseconds: 500),
        () {
          try {
            choreographer.onAcceptContinuance(index);
          } catch (e, s) {
            ErrorHandler.logError(
              e: e,
              s: s,
              level: SentryLevel.warning,
              data: {
                "index": index,
              },
            );
            choreographer.closeIT();
            return;
          }
        },
      );
    } else {
      showCard(
        context,
        index,
        continuance.level == 2 ? ChoreoConstants.yellow : ChoreoConstants.red,
        continuance.feedbackText(context),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      if (choreographer.isEditingSourceText) {
        return const SizedBox();
      }
      if (choreographer.itStepContinuances == null) {
        return choreographer.isITOpen
            ? CircularProgressIndicator(
                strokeWidth: 2.0,
                color: Theme.of(context).colorScheme.primary,
              )
            : const SizedBox();
      }
      return ChoicesArray(
        id: Object.hashAll(choreographer.itStepContinuances!).toString(),
        isLoading: choreographer.isFetching ||
            choreographer.itStepContinuances == null,
        choices: choreographer.itStepContinuances!.map((e) {
          debugPrint("WAS CLICKED: ${e.wasClicked}");
          try {
            return Choice(
              text: e.text.trim(),
              color: e.color,
              isGold: e.description == "best",
            );
          } catch (e) {
            debugger(when: kDebugMode);
            return Choice(text: "error", color: Colors.red);
          }
        }).toList(),
        onPressed: (value, index) => selectContinuance(index, context),
        onLongPress: (value, index) => showCard(context, index),
        selectedChoiceIndex: null,
        langCode:
            choreographer.pangeaController.languageController.activeL2Code(),
      );
    } catch (e) {
      debugger(when: kDebugMode);
      return const SizedBox();
    }
  }
}

class ITError extends StatelessWidget {
  final Choreographer choreographer;
  const ITError({
    super.key,
    required this.choreographer,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        spacing: 8.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          ErrorIndicator(
            message: L10n.of(context).translationError,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          IconButton(
            onPressed: choreographer.closeIT,
            icon: const Icon(
              Icons.close,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
