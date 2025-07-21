import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_positioner.dart';
import 'package:fluffychat/pangea/toolbar/widgets/overlay_center_content.dart';

class MagicFloatingMessage extends StatefulWidget {
  final MessageSelectionPositionerState controller;
  const MagicFloatingMessage({
    super.key,
    required this.controller,
  });

  @override
  State<MagicFloatingMessage> createState() => MagicFloatingMessageState();
}

class MagicFloatingMessageState extends State<MagicFloatingMessage>
    with TickerProviderStateMixin {
  AnimationController? _animationController;
  Animation<Offset>? animation;

  bool get _hasScroll {
    if (widget.controller.mediaQuery == null) {
      return false;
    }

    return widget.controller.contentHeight >
        widget.controller.mediaQuery!.size.height -
            widget.controller.mediaQuery!.padding.top -
            widget.controller.mediaQuery!.padding.bottom;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mediaQuery = widget.controller.mediaQuery;
      final contentHeight = widget.controller.contentHeight;
      if (mediaQuery != null) {
        final spaceAboveContent = (mediaQuery.size.height -
                mediaQuery.padding.top -
                mediaQuery.padding.bottom -
                contentHeight) /
            2;

        final startOffset = Offset(
          widget.controller.ownMessage
              ? widget.controller.messageRightOffset!
              : widget.controller.messageLeftOffset!,
          widget.controller.originalMessageOffset.dy - mediaQuery.padding.top,
        );

        final endOffset = Offset(
          startOffset.dx,
          _hasScroll
              ? AppConfig.toolbarMenuHeight +
                  widget.controller.reactionsHeight +
                  4.0
              : spaceAboveContent,
        );

        _animationController = AnimationController(
          vsync: this,
          duration: widget.controller.transitionAnimationDuration,
        );

        animation = Tween<Offset>(
          begin: startOffset,
          end: endOffset,
        ).animate(
          CurvedAnimation(
            parent: _animationController!,
            curve: FluffyThemes.animationCurve,
          ),
        );

        _animationController!.forward().then((_) {
          widget.controller.onFinishedAnimating();
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_animationController == null || animation == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: animation!,
      builder: (context, child) {
        return Positioned(
          top: _hasScroll ? null : animation!.value.dy,
          bottom: _hasScroll ? animation!.value.dy : null,
          left: widget.controller.ownMessage ? null : animation!.value.dx,
          right: widget.controller.ownMessage ? animation!.value.dx : null,
          child: OverlayCenterContent(
            event: widget.controller.widget.event,
            messageHeight: widget.controller.originalMessageSize.height,
            messageWidth:
                widget.controller.widget.overlayController.showingExtraContent
                    ? max(widget.controller.originalMessageSize.width, 150)
                    : widget.controller.originalMessageSize.width,
            overlayController: widget.controller.widget.overlayController,
            chatController: widget.controller.widget.chatController,
            nextEvent: widget.controller.widget.nextEvent,
            prevEvent: widget.controller.widget.prevEvent,
            hasReactions: widget.controller.hasReactions,
            readingAssistanceMode: widget.controller.readingAssistanceMode,
            isTransitionAnimation: true,
          ),
        );
      },
    );
  }
}
