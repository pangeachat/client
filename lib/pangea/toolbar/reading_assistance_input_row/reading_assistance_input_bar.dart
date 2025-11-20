import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_activity/practice_activity_card.dart';
import 'package:fluffychat/pangea/toolbar/widgets/practice_mode_buttons.dart';
import 'package:fluffychat/widgets/matrix.dart';

const double minContentHeight = 120;

class ReadingAssistanceInputBar extends StatefulWidget {
  final MessageOverlayController overlayController;

  const ReadingAssistanceInputBar(
    this.overlayController, {
    super.key,
  });

  @override
  ReadingAssistanceInputBarState createState() =>
      ReadingAssistanceInputBarState();
}

class ReadingAssistanceInputBarState extends State<ReadingAssistanceInputBar> {
  final ScrollController _scrollController = ScrollController();
  MessageOverlayController get overlayController => widget.overlayController;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget barContent(BuildContext context) {
    Widget? content;
    final target = overlayController.toolbarMode.associatedActivityType != null
        ? overlayController.practiceSelection?.getSelection(
            overlayController.toolbarMode.associatedActivityType!,
            overlayController.selectedMorph?.token,
            overlayController.selectedMorph?.morph,
          )
        : null;

    if (overlayController.pangeaMessageEvent.isAudioMessage == true) {
      return const SizedBox();
      // return ReactionsPicker(controller);
    } else {
      final activityType = overlayController.toolbarMode.associatedActivityType;
      final activityCompleted = activityType != null &&
          overlayController.isPracticeActivityDone(activityType);

      switch (overlayController.toolbarMode) {
        case MessageMode.messageSpeechToText:
        case MessageMode.practiceActivity:
        case MessageMode.wordZoom:
        case MessageMode.noneSelected:
        case MessageMode.messageMeaning:
          content = overlayController.isTotallyDone
              ? const AllDoneWidget()
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
          if (overlayController.isTotallyDone) {
            content = const AllDoneWidget();
          } else if (target == null || activityCompleted) {
            content = Text(
              L10n.of(context).practiceActivityCompleted,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            );
          } else {
            content = PracticeActivityCard(
              targetTokensAndActivityType: target,
              overlayController: overlayController,
            );
          }
        case MessageMode.wordMorph:
          if (overlayController.isTotallyDone) {
            content = const AllDoneWidget();
          } else if (activityCompleted) {
            content = Text(
              L10n.of(context).practiceActivityCompleted,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            );
          } else if (target != null) {
            content = PracticeActivityCard(
              targetTokensAndActivityType: target,
              overlayController: overlayController,
            );
          } else {
            content = Center(
              child: Text(
                L10n.of(context).selectForGrammar,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            );
          }
      }
    }

    return content;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PracticeModeButtons(
          overlayController: overlayController,
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
                    width: overlayController.maxWidth,
                    child: barContent(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AllDoneWidget extends StatelessWidget {
  const AllDoneWidget({
    super.key,
  });

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
