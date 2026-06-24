import 'package:flutter/material.dart';

class TopOverlayWidget extends StatelessWidget {
  final Widget child;

  const TopOverlayWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Positioned(top: 0, right: 0, left: 0, child: child);
  }
}
