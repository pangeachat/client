import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/choreographer/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/it/completed_it_step_model.dart';
import 'package:fluffychat/pangea/choreographer/it/it_feedback_card.dart';
import 'package:fluffychat/pangea/choreographer/it/word_data_card.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/learning_settings/settings_learning.dart';
import 'package:fluffychat/pangea/translation/full_text_translation_request_model.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../common/utils/overlay.dart';
import '../../common/widgets/choice_array.dart';

class ITBar extends StatefulWidget {
  final Choreographer choreographer;
  const ITBar({
    super.key,
    required this.choreographer,
  });

  @override
  ITBarState createState() => ITBarState();
}

class ITBarState extends State<ITBar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final TextEditingController _sourceTextController = TextEditingController();

  Timer? _successTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _openListener();
    _open.addListener(_openListener);
  }

  @override
  void dispose() {
    _controller.dispose();
    _sourceTextController.dispose();
    _successTimer?.cancel();
    _open.removeListener(_openListener);
    super.dispose();
  }

  FullTextTranslationRequestModel _translationRequest(String text) =>
      FullTextTranslationRequestModel(
        text: text,
        tgtLang: MatrixState.pangeaController.userController.userL1!.langCode,
        userL1: MatrixState.pangeaController.userController.userL1!.langCode,
        userL2: MatrixState.pangeaController.userController.userL2!.langCode,
      );

  void _openListener() {
    if (!mounted) return;

    final nextText = _sourceText.value ?? widget.choreographer.currentText;
    if (_sourceTextController.text != nextText) {
      _sourceTextController.text = nextText;
    }

    if (_open.value) {
      setState(() => _visible = true);
      _controller.forward();
    } else {
      _controller.reverse().then((value) {
        if (!mounted) return;
        setState(() => _visible = false);
      });
    }
  }

  ValueNotifier<String?> get _sourceText =>
      widget.choreographer.itController.sourceText;
  ValueNotifier<bool> get _open => widget.choreographer.itController.open;

  void _showFeedbackCard(
    ContinuanceModel continuance, [
    Color? borderColor,
    bool selected = false,
  ]) {
    final text = continuance.text;
    MatrixState.pAnyState.closeOverlay("it_feedback_card");
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: selected
          ? WordDataCard(
              word: text,
              langCode:
                  MatrixState.pangeaController.userController.userL2!.langCode,
              fullText: _sourceText.value ?? widget.choreographer.currentText,
            )
          : ITFeedbackCard(_translationRequest(text)),
      maxHeight: 300,
      maxWidth: 300,
      borderColor: borderColor,
      transformTargetId: 'it_bar',
      isScrollable: false,
      overlayKey: "it_feedback_card",
      ignorePointer: true,
    );
  }

  void _selectContinuance(int index) {
    MatrixState.pAnyState.closeOverlay("it_feedback_card");
    ContinuanceModel continuance;
    try {
      continuance = widget.choreographer.itController.selectContinuance(index);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        level: SentryLevel.warning,
        data: {
          "index": index,
        },
      );
      widget.choreographer.itController.closeIT();
      return;
    }

    if (continuance.level == 1) {
      _onCorrectSelection(index);
    } else {
      _showFeedbackCard(
        continuance,
        continuance.level == 2 ? ChoreoConstants.yellow : ChoreoConstants.red,
        true,
      );
    }
  }

  void _onCorrectSelection(int index) {
    _successTimer?.cancel();
    _successTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      try {
        widget.choreographer.itController.acceptContinuance(index);
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          level: SentryLevel.warning,
          data: {
            "index": index,
          },
        );
        widget.choreographer.itController.closeIT();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => SizeTransition(
        sizeFactor: _animation,
        axisAlignment: -1.0,
        child: child,
      ),
      child: CompositedTransformTarget(
        link: MatrixState.pAnyState.layerLinkAndKey('it_bar').link,
        child: Container(
          key: MatrixState.pAnyState.layerLinkAndKey('it_bar').key,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            color: Theme.of(context).colorScheme.surfaceContainer,
          ),
          padding: const EdgeInsets.all(12.0),
          child: Column(
            spacing: 12.0,
            children: [
              _ITBarHeader(
                onClose: () =>
                    widget.choreographer.itController.closeIT(dismiss: true),
                setEditing:
                    widget.choreographer.itController.setEditingSourceText,
                editing: widget.choreographer.itController.editing,
                progress: widget.choreographer.itController.progress,
                sourceTextController: _sourceTextController,
                sourceText: _sourceText,
                onSubmitEdits: (_) {
                  widget.choreographer.itController.submitSourceTextEdits(
                    _sourceTextController.text,
                  );
                },
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                constraints: const BoxConstraints(minHeight: 80),
                child: Center(
                  child: widget.choreographer.errorService.isError
                      ? Row(
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
                              onPressed:
                                  widget.choreographer.itController.closeIT,
                              icon: const Icon(
                                Icons.close,
                                size: 20,
                              ),
                            ),
                          ],
                        )
                      : ValueListenableBuilder(
                          valueListenable:
                              widget.choreographer.itController.currentITStep,
                          builder: (context, step, __) {
                            return step == null
                                ? CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  )
                                : _ITChoices(
                                    continuances: step.continuances,
                                    onPressed: _selectContinuance,
                                    onLongPressed: _showFeedbackCard,
                                  );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ITBarHeader extends StatelessWidget {
  final VoidCallback onClose;
  final Function(String) onSubmitEdits;
  final Function(bool) setEditing;

  final ValueNotifier<bool> editing;
  final ValueNotifier<double> progress;
  final TextEditingController sourceTextController;
  final ValueNotifier<String?> sourceText;

  const _ITBarHeader({
    required this.onClose,
    required this.setEditing,
    required this.editing,
    required this.progress,
    required this.onSubmitEdits,
    required this.sourceTextController,
    required this.sourceText,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: editing,
      builder: (context, isEditing, __) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: isEditing
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Row(
                spacing: 12.0,
                children: [
                  Expanded(
                    child: TextField(
                      controller: sourceTextController,
                      autofocus: true,
                      enableSuggestions: false,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: onSubmitEdits,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    color: Theme.of(context).colorScheme.primary,
                    icon: const Icon(Icons.close_outlined),
                    onPressed: () => setEditing(false),
                  ),
                ],
              ),
              secondChild: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                      child: ValueListenableBuilder(
                        valueListenable: progress,
                        builder: (context, value, __) => AnimatedProgressBar(
                          height: 20.0,
                          widthPercent: value,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          barColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withAlpha(180),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () => setEditing(true),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    color: Theme.of(context).colorScheme.primary,
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (c) => const SettingsLearning(),
                      barrierDismissible: false,
                    ),
                  ),
                  IconButton(
                    color: Theme.of(context).colorScheme.primary,
                    icon: const Icon(Icons.close_outlined),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            isEditing
                ? const SizedBox(height: 24.0)
                : ValueListenableBuilder(
                    valueListenable: sourceText,
                    builder: (context, text, __) {
                      return Container(
                        padding: const EdgeInsets.only(top: 8.0),
                        constraints: const BoxConstraints(minHeight: 24.0),
                        child: sourceText.value != null
                            ? Text(
                                sourceText.value!,
                                textAlign: TextAlign.center,
                              )
                            : const SizedBox(),
                      );
                    },
                  ),
          ],
        );
      },
    );
  }
}

class _ITChoices extends StatelessWidget {
  final List<ContinuanceModel> continuances;
  final Function(int) onPressed;
  final Function(ContinuanceModel) onLongPressed;

  const _ITChoices({
    required this.continuances,
    required this.onPressed,
    required this.onLongPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ChoicesArray(
      id: Object.hashAll(continuances).toString(),
      isLoading: false,
      choices: [
        ...continuances.map(
          (e) => Choice(
            text: e.text.trim(),
            color: e.color,
            isGold: e.description == "best",
          ),
        ),
      ],
      onPressed: (value, index) => onPressed(index),
      onLongPress: (value, index) => onLongPressed(continuances[index]),
      selectedChoiceIndex: null,
      langCode: MatrixState.pangeaController.userController.userL2Code!,
    );
  }
}
