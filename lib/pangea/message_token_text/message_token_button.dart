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
  MessageTokenButtonState createState() => MessageTokenButtonState();
}

class MessageTokenButtonState extends State<MessageTokenButton> {
  @override
  void didUpdateWidget(covariant MessageTokenButton oldWidget) {
    debugPrint("MessageTokenButton didUpdateWidget");
    if (oldWidget.isVisible != widget.isVisible) {
      setState(() {});
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: widget.isVisible ? 30.0 : 0.0,
      child: widget.isVisible ? widget.content : const SizedBox.shrink(),
    );
  }
}


// import 'package:flutter/material.dart';

// class MessageTokenButton extends StatefulWidget {
//   final Widget content;
//   final bool isVisible;
//   final Animation<double>? contentSizeAnimation;

//   const MessageTokenButton({
//     super.key,
//     required this.content,
//     required this.isVisible,
//     this.contentSizeAnimation,
//   });

//   @override
//   MessageTokenButtonState createState() => MessageTokenButtonState();
// }

// class MessageTokenButtonState extends State<MessageTokenButton> {
//   // @override
//   // void didUpdateWidget(covariant MessageTokenButton oldWidget) {
//   //   if (oldWidget.isVisible != widget.isVisible) {
//   //     setState(() {});
//   //   }
//   //   super.didUpdateWidget(oldWidget);
//   // }

//   @override
//   Widget build(BuildContext context) {
//     if (widget.contentSizeAnimation == null) {
//       return SizedBox(
//         height: widget.isVisible ? 30.0 : 0.0,
//         child: widget.isVisible ? widget.content : const SizedBox.shrink(),
//       );
//     }

//     return Row(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         SizeTransition(
//           sizeFactor: widget.contentSizeAnimation!,
//           child: SizedBox(
//             height: 30.0,
//             child: widget.content,
//           ),
//         ),
//       ],
//     );
//   }
// }

