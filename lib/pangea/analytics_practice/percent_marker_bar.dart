import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

// A progress bar with a rounded marker indicating a percentage position

class PercentMarkerBar extends StatelessWidget {
  final double height;
  final double widthPercent;
  final double markerWidth;
  final Color markerColor;
  final Color? backgroundColor;

  const PercentMarkerBar({
    required this.height,
    required this.widthPercent,
    this.markerWidth = 10.0,
    this.markerColor = AppConfig.goldLight,
    this.backgroundColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final halfMarker = markerWidth / 2;

        // Calculate the center position of the marker
        final targetPosition = totalWidth * widthPercent.clamp(0.0, 1.0);

        // Calculate the start position, clamping to keep marker within bounds
        final markerStart = (targetPosition - halfMarker).clamp(
          0.0,
          totalWidth - markerWidth,
        );

        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Background bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                height: height,
                width: constraints.maxWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  color:
                      backgroundColor ??
                      Theme.of(context).colorScheme.secondaryContainer,
                ),
              ),
            ),
            // Marker circle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                margin: EdgeInsets.only(left: markerStart),
                height: height,
                width: markerWidth,
                decoration: BoxDecoration(
                  color: markerColor,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
