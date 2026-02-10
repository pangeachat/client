import 'package:flutter/material.dart';

import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';

class TextLoadingShimmer extends StatelessWidget {
  final double width;
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
            (AppConfig.messageFontSize * AppSettings.fontSizeFactor.value),
        width: width,
      ),
    );
  }
}
