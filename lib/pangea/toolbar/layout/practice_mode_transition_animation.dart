import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/toolbar/layout/message_selection_positioner.dart';
import 'package:fluffychat/pangea/toolbar/layout/overlay_center_content.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PracticeModeTransitionAnimation extends StatefulWidget {
  final String targetId;
  final MessageSelectionPositionerState controller;
  const PracticeModeTransitionAnimation({
    super.key,
    required this.targetId,
    required this.controller,
  });

  @override
  State<PracticeModeTransitionAnimation> createState() =>
      PracticeModeTransitionAnimationState();
}

class PracticeModeTransitionAnimationState
    extends State<PracticeModeTransitionAnimation>
    with SingleTickerProviderStateMixin {
  AnimationController? _animationController;
  Animation<Offset>? _offsetAnimation;
  Animation<Size>? _sizeAnimation;

  RenderBox? get _centerMessageRenderBox {
    try {
      return MatrixState.pAnyState.getRenderBox(widget.targetId);
    } catch (e) {
      return null;
    }
  }

  Offset? get _centerMessageOffset {
    final renderBox = _centerMessageRenderBox;
    if (renderBox == null) {
      return null;
    }
    return renderBox.localToGlobal(Offset.zero);
  }

  Size? get _centerMessageSize {
    final renderBox = _centerMessageRenderBox;
    if (renderBox == null) {
      return null;
    }
    return renderBox.size;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isRtl = widget.controller.isRtl;
      final columnWidth = isRtl ? 0 : widget.controller.columnWidth;

      final startOffset = Offset(
        widget.controller.ownMessage
            ? widget.controller.messageRightOffset!
            : widget.controller.messageLeftOffset!,
        widget.controller.overlayMessageOffset!.dy,
      );

      final endOffset = Offset(
        _centerMessageOffset!.dx - columnWidth,
        _centerMessageOffset!.dy,
      );

      _animationController = AnimationController(
        vsync: this,
        duration: widget.controller.transitionAnimationDuration,
      );

      _offsetAnimation = Tween<Offset>(
        begin: startOffset,
        end: endOffset,
      ).animate(
        CurvedAnimation(
          parent: _animationController!,
          curve: FluffyThemes.animationCurve,
        ),
      );

      final startSize = Size(
        widget.controller.originalMessageSize.width,
        widget.controller.originalMessageSize.height,
      );

      _sizeAnimation = Tween<Size>(
        begin: startSize,
        end: _centerMessageSize!,
      ).animate(
        CurvedAnimation(
          parent: _animationController!,
          curve: FluffyThemes.animationCurve,
        ),
      );

      widget.controller.onStartedTransition();
      setState(() {});

      _animationController!.forward().then((_) {
        widget.controller.onFinishedTransition();
      });
    });
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller.finishedTransition,
      child: _offsetAnimation == null
          ? const SizedBox()
          : AnimatedBuilder(
              animation: _offsetAnimation!,
              builder: (context, child) {
                return Positioned(
                  top: _offsetAnimation!.value.dy,
                  left: widget.controller.ownMessage
                      ? null
                      : _offsetAnimation!.value.dx,
                  right: widget.controller.ownMessage
                      ? _offsetAnimation!.value.dx
                      : null,
                  child: OverlayCenterContent(
                    event: widget.controller.widget.event,
                    overlayController:
                        widget.controller.widget.overlayController,
                    chatController: widget.controller.widget.chatController,
                    nextEvent: widget.controller.widget.nextEvent,
                    prevEvent: widget.controller.widget.prevEvent,
                    hasReactions: widget.controller.hasReactions,
                    sizeAnimation: _sizeAnimation,
                    readingAssistanceMode:
                        widget.controller.readingAssistanceMode,
                    overlayKey:
                        "overlay_transition_message_${widget.controller.widget.event.eventId}",
                    reactionsWidth: widget.controller.reactionNotifier,
                  ),
                );
              },
            ),
      builder: (context, finished, child) {
        if (finished || _offsetAnimation == null) {
          return const SizedBox();
        }
        return child!;
      },
    );
  }
}

class CenteredMessage extends StatelessWidget {
  final MessageSelectionPositionerState controller;

  const CenteredMessage({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller.finishedTransition,
      builder: (context, finished, __) {
        return Opacity(
          opacity: finished ? 1.0 : 0.0,
          child: GestureDetector(
            onTap: controller.widget.chatController.clearSelectedEvents,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width:
                        controller.screenSize!.width - controller.columnWidth,
                    height: 20.0,
                  ),
                  OverlayCenterContent(
                    event: controller.widget.event,
                    overlayController: controller.widget.overlayController,
                    chatController: controller.widget.chatController,
                    nextEvent: controller.widget.nextEvent,
                    prevEvent: controller.widget.prevEvent,
                    hasReactions: controller.hasReactions,
                    overlayKey:
                        "overlay_center_message_${controller.widget.event.eventId}",
                    readingAssistanceMode: controller.readingAssistanceMode,
                    reactionsWidth: controller.reactionNotifier,
                  ),
                  const SizedBox(
                    height: AppConfig.readingAssistanceInputBarHeight + 60.0,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
