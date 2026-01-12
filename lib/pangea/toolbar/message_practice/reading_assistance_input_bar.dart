import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_practice_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_activity_card.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/toolbar_button.dart';
import 'package:fluffychat/widgets/matrix.dart';

const double minContentHeight = 120;

class ReadingAssistanceInputBar extends StatefulWidget {
  final PracticeController controller;
  final PangeaToken? selectedToken;
  final double maxWidth;

  const ReadingAssistanceInputBar(
    this.controller, {
    required this.maxWidth,
    required this.selectedToken,
    super.key,
  });

  @override
  ReadingAssistanceInputBarState createState() =>
      ReadingAssistanceInputBarState();
}

class ReadingAssistanceInputBarState extends State<ReadingAssistanceInputBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
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
            Row(
              spacing: 4.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...MessagePracticeMode.practiceModes.map(
                  (m) {
                    final complete = widget.controller.isPracticeActivityDone(
                      m.associatedActivityType!,
                    );
                    return ToolbarButton(
                      mode: m,
                      setMode: () => widget.controller.updateToolbarMode(m),
                      isComplete: complete,
                      isSelected: widget.controller.practiceMode == m,
                      shimmer: widget.controller.practiceMode ==
                              MessagePracticeMode.noneSelected &&
                          !complete,
                    );
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Material(
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                child: Container(
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
                        ),
                      ),
                    ),
                  ),
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

  const _ReadingAssistanceBarContent({
    required this.controller,
    required this.selectedToken,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final mode = controller.practiceMode;
    if (controller.pangeaMessageEvent.isAudioMessage == true) {
      return const SizedBox();
    }
    final activityType = mode.associatedActivityType;
    final activityCompleted =
        activityType != null && controller.isPracticeActivityDone(activityType);

    switch (mode) {
      case MessagePracticeMode.noneSelected:
        return controller.isTotallyDone
            ? const _AllDoneWidget()
            : const Icon(
                Symbols.fitness_center,
                size: 60.0,
              );

      case MessagePracticeMode.wordEmoji:
      case MessagePracticeMode.wordMeaning:
      case MessagePracticeMode.listening:
        if (controller.isTotallyDone) {
          return const _AllDoneWidget();
        }

        final target = controller.practiceSelection?.getTarget(activityType!);
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
        );
      case MessagePracticeMode.wordMorph:
        if (controller.isTotallyDone) {
          return const _AllDoneWidget();
        }
        if (activityCompleted) {
          return const Icon(
            Symbols.fitness_center,
            size: 60.0,
            color: AppConfig.goldLight,
          );
        }

        PracticeTarget? target;
        if (controller.practiceSelection != null &&
            controller.selectedMorph != null) {
          target = controller.practiceSelection!.getMorphTarget(
            controller.selectedMorph!.token,
            controller.selectedMorph!.morph,
          );
        }

        if (target == null) {
          return const Center(
            child: Icon(
              Symbols.fitness_center,
              size: 60.0,
            ),
          );
        }

        return PracticeActivityCard(
          targetTokensAndActivityType: target,
          controller: controller,
          selectedToken: selectedToken,
          maxWidth: maxWidth,
        );
    }
  }
}

class _AllDoneWidget extends StatelessWidget {
  const _AllDoneWidget();

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
          child: Text(L10n.of(context).continueText),
          onPressed: () {
            MatrixState.pAnyState.closeOverlay();
          },
        ),
      ],
    );
  }
}
