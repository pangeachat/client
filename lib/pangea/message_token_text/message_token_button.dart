import 'package:flutter/material.dart';

class MessageTokenButton extends StatefulWidget {
  final Widget content;
  final bool isVisible;

  const MessageTokenButton({
    super.key,
    required this.content,
    required this.isVisible,
  });

  @override
  _MessageTokenButtonState createState() => _MessageTokenButtonState();
}

class _MessageTokenButtonState extends State<MessageTokenButton> {
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: widget.isVisible ? 30.0 : 0.0,
      width: widget.isVisible ? null : 0.0,
      child: widget.isVisible ? widget.content : const SizedBox.shrink(),
    );
  }
}
