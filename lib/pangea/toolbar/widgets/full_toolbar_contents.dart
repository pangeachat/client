import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/widgets/overlay_center_content.dart';
import 'package:fluffychat/pangea/toolbar/widgets/toolbar_button_column.dart';

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
  final double toolbarMaxWidth;

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
          maxWidth: toolbarMaxWidth,
          event: event,
          pangeaMessageEvent: pangeaMessageEvent,
          nextEvent: nextEvent,
          prevEvent: prevEvent,
          overlayController: overlayController,
          chatController: chatController,
          hasReactions: hasReactions,
          shouldShowToolbarButtons: showToolbarButtons,
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

class MeasureOffset extends StatefulWidget {
  final Widget child;
  final ValueChanged<Offset> onChange;

  const MeasureOffset({super.key, required this.child, required this.onChange});

  @override
  MeasureOffsetState createState() => MeasureOffsetState();
}

class MeasureOffsetState extends State<MeasureOffset> {
  Offset? _lastOffset;

  void _updateOffset() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final offset = renderBox.localToGlobal(Offset.zero);
      if (_lastOffset == null || _lastOffset != offset) {
        _lastOffset = offset;
        widget.onChange(offset);
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
