import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/practice_activity_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_controller.dart';
import 'package:fluffychat/pangea/toolbar/widgets/toolbar_button.dart';
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
                ...MessageMode.practiceModes.map(
                  (m) => ToolbarButton(
                    mode: m,
                    setMode: () => widget.controller.updateToolbarMode(m),
                    isComplete: widget.controller.isPracticeActivityDone(
                      m.associatedActivityType!,
                    ),
                    isSelected: widget.controller.practiceMode == m,
                  ),
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
      case MessageMode.noneSelected:
        return controller.isTotallyDone
            ? const _AllDoneWidget()
            : Text(
                L10n.of(context).choosePracticeMode,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              );

      case MessageMode.wordEmoji:
      case MessageMode.wordMeaning:
      case MessageMode.listening:
        if (controller.isTotallyDone) {
          return const _AllDoneWidget();
        }

        final target = controller.practiceSelection?.getTarget(activityType!);
        if (target == null || activityCompleted) {
          return Text(
            L10n.of(context).practiceActivityCompleted,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          );
        }

        return PracticeActivityCard(
          targetTokensAndActivityType: target,
          controller: controller,
          selectedToken: selectedToken,
          maxWidth: maxWidth,
        );
      case MessageMode.wordMorph:
        if (controller.isTotallyDone) {
          return const _AllDoneWidget();
        }
        if (activityCompleted) {
          return Text(
            L10n.of(context).practiceActivityCompleted,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
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
          return Center(
            child: Text(
              L10n.of(context).selectForGrammar,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
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
