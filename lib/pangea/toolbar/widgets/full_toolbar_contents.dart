import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/overlay_center_content.dart';
import 'package:fluffychat/pangea/toolbar/widgets/toolbar_button_column.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class FullToolbarContents extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? prevEvent;
  final PangeaMessageEvent? pangeaMessageEvent;

  final MessageOverlayController overlayController;
  final ChatController chatController;
  final bool showToolbarButtons;
  final bool hasReactions;
  final double messageHeight;
  final double messageWidth;
  final Animation<Size>? sizeAnimation;
  // final Animation<double>? contentSizeAnimation;
  final void Function(RenderBox) onChangeSize;

  final double toolbarMaxWidth;
  final bool isVisible;

  const FullToolbarContents({
    required this.event,
    required this.messageHeight,
    required this.messageWidth,
    required this.toolbarMaxWidth,
    required this.overlayController,
    required this.chatController,
    required this.pangeaMessageEvent,
    required this.nextEvent,
    required this.prevEvent,
    required this.showToolbarButtons,
    required this.hasReactions,
    required this.onChangeSize,
    this.sizeAnimation,
    // this.contentSizeAnimation,
    this.isVisible = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: event.senderId == event.room.client.userID
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        OverlayCenterContent(
          messageHeight: messageHeight,
          messageWidth: messageWidth,
          onChangeSize: onChangeSize,
          maxWidth: toolbarMaxWidth,
          event: event,
          pangeaMessageEvent: pangeaMessageEvent,
          nextEvent: nextEvent,
          prevEvent: prevEvent,
          overlayController: overlayController,
          chatController: chatController,
          hasReactions: hasReactions,
          shouldShowToolbarButtons: showToolbarButtons,
          sizeAnimation: sizeAnimation,
          isVisible: isVisible,
          // contentSizeAnimation: contentSizeAnimation,
        ),
        ToolbarButtonRow(
          event: event,
          overlayController: overlayController,
          shouldShowToolbarButtons: showToolbarButtons,
        ),
      ],
    );
  }
}

class MeasureRenderBox extends StatefulWidget {
  final Widget child;
  final ValueChanged<RenderBox> onChange;

  const MeasureRenderBox({
    super.key,
    required this.child,
    required this.onChange,
  });

  @override
  MeasureRenderBoxState createState() => MeasureRenderBoxState();
}

class MeasureRenderBoxState extends State<MeasureRenderBox> {
  Offset? _lastOffset;
  Size? _lastSize;

  void _updateOffset() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final offset = renderBox.localToGlobal(Offset.zero);
      if (_lastOffset == null ||
          _lastOffset != offset ||
          _lastSize == null ||
          _lastSize != renderBox.size) {
        _lastOffset = offset;
        _lastSize = renderBox.size;
        widget.onChange(renderBox);
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOffset());
    return widget.child;
  }
}
