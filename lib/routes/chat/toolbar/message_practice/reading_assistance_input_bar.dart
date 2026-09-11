import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/message_practice_mode_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_activity_card.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/practice_controller.dart';

const double minContentHeight = 120;

class ReadingAssistanceInputBar extends StatefulWidget {
  final PracticeController controller;
  final PangeaToken? selectedToken;
  final double maxWidth;
  final VoidCallback onClose;

  const ReadingAssistanceInputBar(
    this.controller, {
    required this.maxWidth,
    required this.selectedToken,
    required this.onClose,
    super.key,
  });

  @override
  ReadingAssistanceInputBarState createState() =>
      ReadingAssistanceInputBarState();
}

class ReadingAssistanceInputBarState extends State<ReadingAssistanceInputBar> {
  final ScrollController _scrollController = ScrollController();

  /// Set by the practice card when the current exercise's content can be
  /// flagged as wrong (emoji / meaning); null while it can't.
  final ValueNotifier<VoidCallback?> _flagAction = ValueNotifier(null);

  @override
  void dispose() {
    _scrollController.dispose();
    _flagAction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Column(
          spacing: 4.0,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Material(
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      alignment: Alignment.center,
                      constraints: const BoxConstraints(
                        minHeight: minContentHeight,
                        maxHeight: AppConfig.readingAssistanceInputBarHeight,
                      ),
                      child: Scrollbar(
                        thumbVisibility: true,
                        controller: _scrollController,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: SizedBox(
                            width: widget.maxWidth,
                            child: _ReadingAssistanceBarContent(
                              controller: widget.controller,
                              selectedToken: widget.selectedToken,
                              maxWidth: widget.maxWidth,
                              flagAction: _flagAction,
                              onClose: widget.onClose,
                            ),
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: _flagAction,
                      builder: (context, flagAction, _) {
                        if (flagAction == null) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          top: 0.0,
                          right: 0.0,
                          child: IconButton(
                            color: Theme.of(context).iconTheme.color,
                            iconSize: 20.0,
                            icon: const Icon(Icons.flag_outlined),
                            tooltip: L10n.of(
                              context,
                            ).practiceFeedbackButtonTooltip,
                            onPressed: flagAction,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReadingAssistanceBarContent extends StatelessWidget {
  final PracticeController controller;
  final PangeaToken? selectedToken;
  final double maxWidth;
  final ValueNotifier<VoidCallback?> flagAction;
  final VoidCallback onClose;

  const _ReadingAssistanceBarContent({
    required this.controller,
    required this.selectedToken,
    required this.maxWidth,
    required this.flagAction,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final mode = controller.practiceMode;
    if (controller.pangeaMessageEvent.isAudioMessage == true) {
      return const SizedBox();
    }

    final target = controller.currentTarget;
    final activityCompleted = controller.isCurrentPracticeSessionDone;

    switch (mode) {
      case MessagePracticeMode.noneSelected:
        return controller.isTotallyDone
            ? _AllDoneWidget(onClose: onClose)
            : const Icon(Symbols.fitness_center, size: 60.0);

      case MessagePracticeMode.wordEmoji:
      case MessagePracticeMode.wordMeaning:
      case MessagePracticeMode.listening:
        if (controller.isTotallyDone) {
          return _AllDoneWidget(onClose: onClose);
        }

        if (target == null || activityCompleted) {
          return const Icon(
            Symbols.fitness_center,
            size: 60.0,
            color: AppConfig.goldLight,
          );
        }

        return PracticeActivityCard(
          targetTokensAndActivityType: target,
          controller: controller,
          selectedToken: selectedToken,
          maxWidth: maxWidth,
          flagAction: flagAction,
        );
      case MessagePracticeMode.wordMorph:
        if (controller.isTotallyDone) {
          return _AllDoneWidget(onClose: onClose);
        }
        if (activityCompleted) {
          return const Icon(
            Symbols.fitness_center,
            size: 60.0,
            color: AppConfig.goldLight,
          );
        }

        if (target == null) {
          return const Center(child: Icon(Symbols.fitness_center, size: 60.0));
        }

        return PracticeActivityCard(
          targetTokensAndActivityType: target,
          controller: controller,
          selectedToken: selectedToken,
          maxWidth: maxWidth,
          flagAction: flagAction,
        );
    }
  }
}

class _AllDoneWidget extends StatelessWidget {
  final VoidCallback onClose;

  const _AllDoneWidget({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        Text(
          L10n.of(context).allDone,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
        ElevatedButton(
          onPressed: onClose,
          child: Text(L10n.of(context).continueText),
        ),
      ],
    );
  }
}
