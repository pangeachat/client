import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pangea/enum/message_mode_enum.dart';
import 'package:fluffychat/pangea/matrix_event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/widgets/chat/message_activity_controller.dart';
import 'package:fluffychat/pangea/widgets/chat/message_text_selection.dart';
import 'package:fluffychat/pangea/widgets/chat/message_toolbar.dart';
import 'package:fluffychat/pangea/widgets/chat/overlay_footer.dart';
import 'package:fluffychat/pangea/widgets/chat/overlay_header.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class MessageSelectionOverlay extends StatefulWidget {
  final ChatController controller;
  final Event event;
  final Event? nextEvent;
  final Event? prevEvent;
  final PangeaMessageEvent pangeaMessageEvent;
  final MessageMode? initialMode;
  final MessageTextSelection textSelection;

  const MessageSelectionOverlay({
    required this.controller,
    required this.event,
    required this.pangeaMessageEvent,
    required this.textSelection,
    this.initialMode,
    this.nextEvent,
    this.prevEvent,
    super.key,
  });

  @override
  MessageSelectionOverlayState createState() => MessageSelectionOverlayState();
}

class MessageSelectionOverlayState extends State<MessageSelectionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  Animation<double>? _overlayPositionAnimation;
  late MessageActivityController activityController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: FluffyThemes.animationDuration,
    );

    activityController = MessageActivityController(
      controller: this,
      pangeaMessageEvent: widget.pangeaMessageEvent,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (messageSize == null || messageOffset == null) {
      return;
    }

    // position the overlay directly over the underlying message
    final headerBottomOffset = screenHeight - headerHeight;
    final footerBottomOffset = footerHeight;
    final currentBottomOffset =
        screenHeight - messageOffset!.dy - messageSize!.height;

    final bool hasHeaderOverflow =
        messageOffset!.dy < (AppConfig.toolbarMaxHeight + headerHeight);
    final bool hasFooterOverflow = footerHeight > currentBottomOffset;

    if (!hasHeaderOverflow && !hasFooterOverflow) return;

    double scrollOffset = 0;
    double animationEndOffset = 0;

    final midpoint = (headerBottomOffset + footerBottomOffset) / 2;

    // if the overlay would have a footer overflow for this message,
    // check if shifting the overlay up could cause a header overflow
    final bottomOffsetDifference = footerHeight - currentBottomOffset;
    final newTopOffset = messageOffset!.dy - bottomOffsetDifference;
    final bool upshiftCausesHeaderOverflow = hasFooterOverflow &&
        newTopOffset < (headerHeight + AppConfig.toolbarMaxHeight);

    if (hasHeaderOverflow || upshiftCausesHeaderOverflow) {
      animationEndOffset = midpoint - messageSize!.height;
      final totalTopOffset =
          animationEndOffset + messageSize!.height + AppConfig.toolbarMaxHeight;
      final remainingSpace = screenHeight - totalTopOffset;
      if (remainingSpace < headerHeight) {
        // the overlay could run over the header, so it needs to be shifted down
        animationEndOffset -= (headerHeight - remainingSpace);
      }
      scrollOffset = animationEndOffset - currentBottomOffset;
    } else if (hasFooterOverflow) {
      scrollOffset = footerHeight - currentBottomOffset;
      animationEndOffset = footerHeight;
    }

    _overlayPositionAnimation = Tween<double>(
      begin: currentBottomOffset,
      end: animationEndOffset,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: FluffyThemes.animationCurve,
      ),
    );

    widget.controller.scrollController.animateTo(
      widget.controller.scrollController.offset - scrollOffset,
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  RenderBox? get messageRenderBox => MatrixState.pAnyState.getRenderBox(
        widget.event.eventId,
      );

  Size? get messageSize => messageRenderBox?.size;
  Offset? get messageOffset => messageRenderBox?.localToGlobal(Offset.zero);

  // height of the reply/forward bar + the reaction picker + contextual padding
  double get footerHeight =>
      48 + 56 + (FluffyThemes.isColumnMode(context) ? 16.0 : 8.0);

  double get headerHeight =>
      (Theme.of(context).appBarTheme.toolbarHeight ?? 56) +
      MediaQuery.of(context).padding.top;

  double get screenHeight => MediaQuery.of(context).size.height;

  @override
  Widget build(BuildContext context) {
    final bool showDetails = (Matrix.of(context)
                .store
                .getBool(SettingKeys.displayChatDetailsColumn) ??
            false) &&
        FluffyThemes.isThreeColumnMode(context) &&
        widget.controller.room.membership == Membership.join;

    final overlayMessage = ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: FluffyThemes.columnWidth * 2.5,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: widget.pangeaMessageEvent.ownMessage
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: widget.pangeaMessageEvent.ownMessage
                        ? 0
                        : Avatar.defaultSize + 16,
                    right: widget.pangeaMessageEvent.ownMessage ? 8 : 0,
                  ),
                  child: MessageToolbar(
                    pangeaMessageEvent: widget.pangeaMessageEvent,
                    controller: widget.controller,
                    textSelection: widget.textSelection,
                    initialMode: widget.initialMode,
                  ),
                ),
              ],
            ),
            Message(
              widget.event,
              onSwipe: () => {},
              onInfoTab: (_) => {},
              onAvatarTab: (_) => {},
              scrollToEventId: (_) => {},
              onSelect: (_) => {},
              immersionMode: widget.controller.choreographer.immersionMode,
              controller: widget.controller,
              timeline: widget.controller.timeline!,
              isOverlay: true,
              animateIn: false,
              nextEvent: widget.nextEvent,
              previousEvent: widget.prevEvent,
            ),
          ],
        ),
      ),
    );

    final positionedOverlayMessage = _overlayPositionAnimation == null
        ? Positioned(
            left: 0,
            right: showDetails ? FluffyThemes.columnWidth : 0,
            bottom: screenHeight - messageOffset!.dy - messageSize!.height,
            child: Align(
              alignment: Alignment.center,
              child: overlayMessage,
            ),
          )
        : AnimatedBuilder(
            animation: _overlayPositionAnimation!,
            builder: (context, child) {
              return Positioned(
                left: 0,
                right: showDetails ? FluffyThemes.columnWidth : 0,
                bottom: _overlayPositionAnimation!.value,
                child: Align(
                  alignment: Alignment.center,
                  child: overlayMessage,
                ),
              );
            },
          );

    return Padding(
      padding: EdgeInsets.only(
        left: FluffyThemes.isColumnMode(context) ? 8.0 : 0.0,
        right: FluffyThemes.isColumnMode(context) ? 8.0 : 0.0,
      ),
      child: Stack(
        children: [
          positionedOverlayMessage,
          Align(
            alignment: Alignment.bottomCenter,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OverlayFooter(controller: widget.controller),
                    ],
                  ),
                ),
                if (showDetails)
                  const SizedBox(
                    width: FluffyThemes.columnWidth,
                  ),
              ],
            ),
          ),
          Material(
            child: OverlayHeader(controller: widget.controller),
          ),
        ],
      ),
    );
  }
}
