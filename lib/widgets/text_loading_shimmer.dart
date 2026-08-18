import 'package:flutter/material.dart';

import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';

class TextLoadingShimmer extends StatelessWidget {
  final double width;

  /// Final height of the bar, in pixels. An explicit value is used as given;
  /// the default stands in for one line of message text and so grows with the
  /// device text scaler, or the placeholder shrinks away from the text that
  /// replaces it (accessibility.instructions.md, Text scaling).
  final double? height;

  const TextLoadingShimmer({super.key, this.width = 140.0, this.height});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.transparent,
      highlightColor: Theme.of(context).colorScheme.primary.withAlpha(70),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4.0),
          color: Theme.of(context).colorScheme.primary,
        ),
        height:
            height ??
            MediaQuery.textScalerOf(context).scale(AppConfig.messageFontSize),
        width: width,
      ),
    );
  }
}
