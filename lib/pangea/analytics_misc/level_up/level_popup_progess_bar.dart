import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';

class LevelPopupProgressBar extends StatefulWidget {
  final double height;
  final Duration duration;

  const LevelPopupProgressBar({
    required this.height,
    required this.duration,
    super.key,
  });

  @override
  LevelPopupProgressBarState createState() => LevelPopupProgressBarState();
}

class LevelPopupProgressBarState extends State<LevelPopupProgressBar> {
  double width = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        width = 1.0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedProgressBar(
      height: widget.height,
      widthPercent: width,
      duration: widget.duration,
    );
  }
}
