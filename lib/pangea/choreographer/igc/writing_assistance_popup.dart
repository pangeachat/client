import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/choreographer/igc/writing_asssitance_popup_manager.dart';

class WritingAssistancePopup extends StatefulWidget {
  final WritingAssistancePopupManager controller;
  final Widget child;

  const WritingAssistancePopup(
    this.controller, {
    super.key,
    required this.child,
  });

  @override
  WritingAssistancePopupState createState() => WritingAssistancePopupState();
}

class WritingAssistancePopupState extends State<WritingAssistancePopup> {
  @override
  void dispose() {
    widget.controller.onOverlayClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
