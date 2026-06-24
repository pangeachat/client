import 'package:flutter/material.dart';

class CenteredOverlayWidget extends StatelessWidget {
  final Widget child;

  const CenteredOverlayWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Positioned(top: 0, right: 0, left: 0, bottom: 0, child: child);
  }
}
