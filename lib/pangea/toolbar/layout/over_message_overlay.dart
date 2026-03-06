import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/toolbar/layout/message_selection_positioner.dart';
import 'package:fluffychat/pangea/toolbar/layout/overlay_center_content.dart';
import 'package:fluffychat/pangea/toolbar/layout/reading_assistance_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/pangea/toolbar/word_card/word_card_switcher.dart';
import 'package:fluffychat/widgets/matrix.dart';

class OverMessageOverlay extends StatelessWidget {
  final MessageSelectionPositionerState controller;
  const OverMessageOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: controller.messageAlignment,
      child: Padding(
        padding: EdgeInsets.only(
          left: controller.messageLeftOffset ?? 0.0,
          right: controller.messageRightOffset ?? 0.0,
        ),
        child: GestureDetector(
          onTap: controller.widget.chatController.clearSelectedEvents,
          child: SingleChildScrollView(
            controller: controller.scrollController,
            child: Column(
              crossAxisAlignment: controller.messageColumnAlignment,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!controller.shouldScroll) ...[
                  WordCardSwitcher(controller: controller),
                  const SizedBox(height: 4.0),
                ] else
                  AnimatedContainer(
                    duration: FluffyThemes.animationDuration,
                    height: controller.overheadContentHeight,
                  ),
                CompositedTransformTarget(
                  link: MatrixState.pAnyState
                      .layerLinkAndKey(
                        'overlay_message_${controller.widget.event.eventId}',
                      )
                      .link,
                  child: ValueListenableBuilder(
                    valueListenable:
                        controller.widget.overlayController.selectedMode,
                    builder: (context, mode, _) {
                      return OverlayCenterContent(
                        event: controller.widget.event,
                        messageHeight: mode != SelectMode.emoji
                            ? controller.originalMessageSize.height
                            : null,
                        messageWidth:
                            controller
                                .widget
                                .overlayController
                                .selectModeController
                                .isShowingExtraContent
                            ? max(controller.originalMessageSize.width, 150)
                            : controller.originalMessageSize.width,
                        overlayController: controller.widget.overlayController,
                        chatController: controller.widget.chatController,
                        nextEvent: controller.widget.nextEvent,
                        prevEvent: controller.widget.prevEvent,
                        hasReactions: controller.hasReactions,
                        isTransitionAnimation: true,
                        readingAssistanceMode: controller.readingAssistanceMode,
                        overlayKey:
                            'overlay_message_${controller.widget.event.eventId}',
                        reactionsWidth: controller.reactionNotifier,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4.0),
                SelectModeButtons(
                  controller: controller.widget.chatController,
                  overlayController: controller.widget.overlayController,
                  launchPractice: () => controller.launchPractice(
                    ReadingAssistanceMode.practiceMode,
                  ),
                ),
                AnimatedContainer(
                  duration: FluffyThemes.animationDuration,
                  height: max(0, controller.spaceBelowContent),
                  width:
                      controller.screenSize!.width -
                      controller.columnWidth -
                      (controller.showDetails ? FluffyThemes.columnWidth : 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
